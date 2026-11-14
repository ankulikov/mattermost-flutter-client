import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft_realtime.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft_repository.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft_sync_preference.dart';

/// A destination uniquely identifies a channel or thread draft within a session.
final class DraftKey {
  const DraftKey({required this.channelId, this.rootId});
  final String channelId;
  final String? rootId;

  @override
  bool operator ==(Object other) =>
      other is DraftKey &&
      channelId == other.channelId &&
      (rootId ?? '') == (other.rootId ?? '');
  @override
  int get hashCode => Object.hash(channelId, rootId ?? '');
}

final class DraftEntry {
  const DraftEntry({
    required this.draft,
    this.dirty = false,
    this.saving = false,
    this.error,
    this.cleanupPending = false,
  });
  final Draft draft;
  final bool dirty;
  final bool saving;
  final Object? error;

  final bool cleanupPending;
}

enum DraftSyncStatus { unknown, enabled, disabled, unsupported, failed }

final class DraftsState {
  const DraftsState({
    this.entries = const {},
    this.loading = false,
    this.error,
    this.loadedTeams = const {},
    this.teamKeys = const {},
    this.syncStatus = DraftSyncStatus.unknown,
  });
  final Map<DraftKey, DraftEntry> entries;
  final bool loading;
  final Object? error;
  final Set<String> loadedTeams;
  final Map<String, Set<DraftKey>> teamKeys;
  final DraftSyncStatus syncStatus;

  DraftsState copyWith({
    Map<DraftKey, DraftEntry>? entries,
    bool? loading,
    Object? error,
    Set<String>? loadedTeams,
    Map<String, Set<DraftKey>>? teamKeys,
    DraftSyncStatus? syncStatus,
  }) => DraftsState(
    entries: entries ?? this.entries,
    loading: loading ?? this.loading,
    error: error,
    loadedTeams: loadedTeams ?? this.loadedTeams,
    teamKeys: teamKeys ?? this.teamKeys,
    syncStatus: syncStatus ?? this.syncStatus,
  );
}

/// Session-owned in-memory projection. Operations for each destination are serialized.
final class DraftsController extends Notifier<DraftsState>
    with WidgetsBindingObserver {
  DraftsController(
    this._sessionProvider,
    this._repositoryProvider, [
    this._realtimeProvider,
    this._preferenceProvider,
  ]);
  final Provider<AuthSession?> _sessionProvider;
  final Provider<DraftRepository> _repositoryProvider;
  final Provider<DraftRealtime>? _realtimeProvider;
  final Provider<DraftSyncPreference>? _preferenceProvider;
  DraftSyncPreference? _preference;
  AuthSession? _session;
  Future<bool>? _preferenceLoad;
  // Cancelled in the provider's disposal callback.
  // ignore: cancel_subscriptions
  StreamSubscription<DraftRealtimeChange>? _realtimeSubscription;
  int _preferenceRevision = 0;
  Timer? _refreshTimer;
  final Map<DraftKey, Timer> _timers = {};
  final Map<DraftKey, Future<void>> _operations = {};
  final Map<DraftKey, int> _versions = {};
  final Map<DraftKey, Completer<void>> _changes = {};
  final Random _random = Random();
  final Map<String, Future<void>> _loads = {};
  DraftRepository? _repository;
  int _generation = 0;

  @override
  DraftsState build() {
    final session = ref.watch(_sessionProvider);
    _session = session;
    _repository = session == null ? null : ref.watch(_repositoryProvider);
    _preference = session == null || _preferenceProvider == null
        ? null
        : ref.watch(_preferenceProvider);
    _generation++;
    if (session != null && _realtimeProvider != null) {
      _realtimeSubscription = ref
          .watch(_realtimeProvider)
          .watch(session)
          .listen((change) {
            if (change != DraftRealtimeChange.drafts) {
              _preferenceRevision++;
              _preferenceLoad = null;
              if (state.syncStatus != DraftSyncStatus.unsupported) {
                state = state.copyWith(syncStatus: DraftSyncStatus.unknown);
              }
            }
            _refreshTimer?.cancel();
            _refreshTimer = Timer(const Duration(milliseconds: 300), () {
              for (final teamId in state.loadedTeams.toList()) {
                unawaited(_refreshAfterLoad(teamId));
              }
            });
          }, onError: (Object _) {});
    }
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _refreshTimer?.cancel();
      final subscription = _realtimeSubscription;
      _realtimeSubscription = null;
      if (subscription != null) unawaited(subscription.cancel());
      _generation++;
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
      _operations.clear();
      _versions.clear();
      for (final change in _changes.values) {
        if (!change.isCompleted) change.complete();
      }
      _changes.clear();
      _loads.clear();
      _preferenceLoad = null;
    });
    return const DraftsState();
  }

  Future<bool> _syncAllowed() async {
    if (state.syncStatus == DraftSyncStatus.unsupported ||
        state.syncStatus == DraftSyncStatus.disabled) {
      return false;
    }
    if (state.syncStatus == DraftSyncStatus.enabled) return true;
    final preference = _preference;
    final session = _session;
    if (preference == null || session == null) return true;
    final generation = _generation;
    final revision = _preferenceRevision;
    try {
      final enabled = await (_preferenceLoad ??= preference.isEnabled(
        session.userId,
      ));
      if (generation != _generation || revision != _preferenceRevision) {
        return false;
      }
      state = state.copyWith(
        syncStatus: enabled
            ? DraftSyncStatus.enabled
            : DraftSyncStatus.disabled,
      );
      return enabled;
    } catch (error) {
      if (generation == _generation && revision == _preferenceRevision) {
        state = state.copyWith(
          syncStatus: DraftSyncStatus.failed,
          error: error,
        );
      }
      return false;
    } finally {
      if (generation == _generation && revision == _preferenceRevision) {
        _preferenceLoad = null;
      }
    }
  }

  void _recordUnsupported(Object error) {
    if (error is DraftSyncException && error.unsupported) {
      state = state.copyWith(
        syncStatus: DraftSyncStatus.unsupported,
        error: error,
      );
    }
  }

  Future<void> _refreshAfterLoad(String teamId) async {
    final generation = _generation;
    await _loads[teamId];
    if (generation == _generation) await loadTeam(teamId, refresh: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      for (final key in this.state.entries.keys.toList()) {
        unawaited(flush(key));
      }
    } else if (state == AppLifecycleState.resumed) {
      for (final teamId in this.state.loadedTeams.toList()) {
        unawaited(loadTeam(teamId, refresh: true));
      }
    }
  }

  Future<void> loadTeam(String teamId, {bool refresh = false}) {
    final repository = _repository;
    if (repository == null) return Future.value();
    if (!refresh && state.loadedTeams.contains(teamId)) return Future.value();
    return _loads.putIfAbsent(teamId, () {
      final generation = _generation;
      final versions = Map<DraftKey, int>.of(_versions);
      state = state.copyWith(loading: true);
      final future =
          (() async {
                if (!await _syncAllowed()) return null;
                return repository.listTeamDrafts(teamId);
              })()
              .then((drafts) {
                if (generation != _generation) return;
                if (drafts == null) {
                  state = state.copyWith(loading: false, error: state.error);
                  return;
                }
                final entries = Map<DraftKey, DraftEntry>.of(state.entries);
                final keys = <DraftKey>{};
                for (final draft in drafts) {
                  final key = DraftKey(
                    channelId: draft.channelId,
                    rootId: draft.rootId,
                  );
                  keys.add(key);
                  final current = entries[key];
                  if ((versions[key] ?? 0) == (_versions[key] ?? 0) &&
                      !(current?.dirty ?? false)) {
                    entries[key] = DraftEntry(draft: draft);
                  }
                }
                // Remove absent clean entries only if no other loaded team references them.
                final oldKeys = state.teamKeys[teamId] ?? <DraftKey>{};
                for (final key in oldKeys.difference(keys)) {
                  final shared = state.teamKeys.entries.any(
                    (e) => e.key != teamId && e.value.contains(key),
                  );
                  if (!shared &&
                      !(entries[key]?.dirty ?? false) &&
                      (versions[key] ?? 0) == (_versions[key] ?? 0)) {
                    entries.remove(key);
                  }
                }
                state = state.copyWith(
                  entries: entries,
                  loading: false,
                  loadedTeams: {...state.loadedTeams, teamId},
                  teamKeys: {...state.teamKeys, teamId: keys},
                );
              })
              .catchError((Object error) {
                if (generation == _generation) {
                  state = state.copyWith(loading: false, error: error);
                  _recordUnsupported(error);
                }
              })
              .whenComplete(() {
                _loads.remove(teamId);
              });
      return future;
    });
  }

  void update(Draft draft) {
    final key = DraftKey(channelId: draft.channelId, rootId: draft.rootId);
    _advanceVersion(key);
    state = state.copyWith(
      entries: {
        ...state.entries,
        key: DraftEntry(draft: draft, dirty: true),
      },
    );
    _timers.remove(key)?.cancel();
    // Empty-message attachment drafts cannot be represented by the API.
    if (draft.message.isEmpty && draft.fileIds.isNotEmpty) return;
    _timers[key] = Timer(const Duration(seconds: 5), () {
      unawaited(flush(key));
    });
  }

  Future<void> flush(DraftKey key) {
    _timers.remove(key)?.cancel();
    return _enqueue(key, () async {
      final repository = _repository;
      if (repository == null) return;
      if (_loads.isNotEmpty) await Future.wait(_loads.values.toList());
      if (!await _syncAllowed()) return;
      final entry = state.entries[key];
      if (entry == null ||
          !entry.dirty ||
          entry.cleanupPending ||
          (entry.draft.message.isEmpty && entry.draft.fileIds.isNotEmpty)) {
        return;
      }
      final version = _versions[key] ?? 0;
      final generation = _generation;
      state = state.copyWith(
        entries: {
          ...state.entries,
          key: DraftEntry(draft: entry.draft, dirty: true, saving: true),
        },
      );
      try {
        final saved = entry.draft.message.isEmpty
            ? null
            : await _withRetry(
                key,
                version,
                generation,
                () => repository.saveDraft(entry.draft),
              );
        if (entry.draft.message.isEmpty) {
          await _withRetry(
            key,
            version,
            generation,
            () => repository.deleteDraft(
              channelId: key.channelId,
              rootId: key.rootId,
            ),
          );
        }
        if (generation != _generation || version != _versions[key]) return;
        final entries = Map<DraftKey, DraftEntry>.of(state.entries);
        if (saved == null) {
          entries.remove(key);
        } else {
          entries[key] = DraftEntry(draft: saved);
        }
        state = state.copyWith(entries: entries);
      } catch (error) {
        if (generation == _generation && version == _versions[key]) {
          _recordUnsupported(error);
          state = state.copyWith(
            entries: {
              ...state.entries,
              key: DraftEntry(draft: entry.draft, dirty: true, error: error),
            },
          );
        }
      }
    });
  }

  Future<void> delete(DraftKey key) {
    _timers.remove(key)?.cancel();
    _advanceVersion(key);
    final version = _versions[key];
    final generation = _generation;
    final existing = state.entries[key];
    return _enqueue(key, () async {
      final repository = _repository;
      if (repository == null) return;
      final allowed = await _syncAllowed();
      if (generation != _generation || version != _versions[key]) return;
      if (!allowed) {
        if (state.syncStatus == DraftSyncStatus.disabled ||
            state.syncStatus == DraftSyncStatus.unsupported) {
          final entries = Map<DraftKey, DraftEntry>.of(state.entries)
            ..remove(key);
          state = state.copyWith(entries: entries);
        }
        return;
      }
      try {
        await _withRetry(
          key,
          version ?? 0,
          generation,
          () => repository.deleteDraft(
            channelId: key.channelId,
            rootId: key.rootId,
          ),
        );
        if (generation != _generation || version != _versions[key]) return;
        final entries = Map<DraftKey, DraftEntry>.of(state.entries)
          ..remove(key);
        state = state.copyWith(entries: entries);
      } catch (error) {
        if (generation == _generation &&
            version == _versions[key] &&
            existing != null) {
          _recordUnsupported(error);
          state = state.copyWith(
            entries: {
              ...state.entries,
              key: DraftEntry(draft: existing.draft, dirty: true, error: error),
            },
          );
        }
      }
    });
  }

  /// Delete only the version that was sent; newer local edits remain queued.
  Future<bool> deleteIfUnchanged(DraftKey key, Draft expected) async {
    final current = state.entries[key];
    if (current == null || !_sameContent(current.draft, expected)) return false;
    _timers.remove(key)?.cancel();
    final version = _versions[key] ?? 0;
    final generation = _generation;
    var succeeded = false;
    await _enqueue(key, () async {
      if (version != (_versions[key] ?? 0) || _repository == null) return;
      final allowed = await _syncAllowed();
      if (generation != _generation || version != (_versions[key] ?? 0)) return;
      if (!allowed) {
        if (state.syncStatus == DraftSyncStatus.disabled ||
            state.syncStatus == DraftSyncStatus.unsupported) {
          final entries = Map<DraftKey, DraftEntry>.of(state.entries)
            ..remove(key);
          state = state.copyWith(entries: entries);
          succeeded = true;
        }
        return;
      }
      try {
        await _withRetry(
          key,
          version,
          generation,
          () => _repository!.deleteDraft(
            channelId: key.channelId,
            rootId: key.rootId,
          ),
        );
        if (generation != _generation) return;
        succeeded = true;
        if (version == (_versions[key] ?? 0)) {
          final entries = Map<DraftKey, DraftEntry>.of(state.entries)
            ..remove(key);
          state = state.copyWith(entries: entries);
        }
      } catch (error) {
        if (generation == _generation && version == (_versions[key] ?? 0)) {
          _recordUnsupported(error);
          state = state.copyWith(
            entries: {
              ...state.entries,
              key: DraftEntry(
                draft: current.draft,
                dirty: true,
                error: error,
                cleanupPending: true,
              ),
            },
          );
        }
      }
    });
    return succeeded;
  }

  bool _sameContent(Draft a, Draft b) =>
      a.message == b.message &&
      a.fileIds.length == b.fileIds.length &&
      List.generate(
        a.fileIds.length,
        (i) => a.fileIds[i] == b.fileIds[i],
      ).every((equal) => equal);

  void _advanceVersion(DraftKey key) {
    _versions[key] = (_versions[key] ?? 0) + 1;
    final change = _changes.remove(key);
    if (change != null && !change.isCompleted) change.complete();
  }

  Future<T> _withRetry<T>(
    DraftKey key,
    int version,
    int generation,
    Future<T> Function() action,
  ) async {
    for (var attempt = 0; ; attempt++) {
      if (generation != _generation || version != (_versions[key] ?? 0)) {
        throw const _DraftOperationSuperseded();
      }
      try {
        return await action();
      } on DraftSyncException catch (error) {
        if (!error.retryable || attempt >= 2) rethrow;
        final delay =
            error.retryAfter ??
            Duration(milliseconds: (500 << attempt) + _random.nextInt(250));
        final change = _changes.putIfAbsent(key, Completer<void>.new);
        await Future.any<void>([Future<void>.delayed(delay), change.future]);
      }
    }
  }

  Future<void> _enqueue(DraftKey key, Future<void> Function() operation) {
    final generation = _generation;
    final previous = _operations[key] ?? Future<void>.value();
    final next = previous.then((_) async {
      if (generation != _generation) return;
      await operation();
    });
    _operations[key] = next;
    return next.whenComplete(() {
      if (identical(_operations[key], next)) _operations.remove(key);
    });
  }
}

final class _DraftOperationSuperseded implements Exception {
  const _DraftOperationSuperseded();
}
