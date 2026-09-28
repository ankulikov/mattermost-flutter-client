import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_settings.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_settings_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_controller.dart';

/// Volatile form state for the client-owned Inbox preference.
///
/// Desktop notification settings intentionally are not represented here: the
/// settings form cannot broaden, duplicate, or edit Mattermost's authoritative
/// desktop policy.
final class InboxSettingsViewState {
  const InboxSettingsViewState({
    required this.snapshot,
    this.saveStatus = const OperationStatus.idle(),
  });

  final InboxSettingsSnapshot snapshot;
  final OperationStatus saveStatus;

  InboxSettings get settings => snapshot.settings;

  InboxSettingsViewState copyWith({
    InboxSettingsSnapshot? snapshot,
    OperationStatus? saveStatus,
  }) => InboxSettingsViewState(
    snapshot: snapshot ?? this.snapshot,
    saveStatus: saveStatus ?? this.saveStatus,
  );
}

/// Screen-scoped controller for the non-secret Inbox settings document.
///
/// The controller accepts only the domain repository contract. A new load or
/// save cancels the previous request scope and stale completions never replace
/// the current form state.
final class InboxSettingsController
    extends AsyncNotifier<InboxSettingsViewState> {
  InboxSettingsController(
    this._sessionProvider,
    this._repositoryProvider, {
    AsyncNotifierProvider<InboxSessionController, InboxSessionViewState>?
    inboxSessionProvider,
  }) : _inboxSessionProvider = inboxSessionProvider;

  final Provider<AuthSession?> _sessionProvider;
  final Provider<InboxSettingsRepository> _repositoryProvider;
  final AsyncNotifierProvider<InboxSessionController, InboxSessionViewState>?
  _inboxSessionProvider;
  RequestCancellation? _loadCancellation;
  RequestCancellation? _saveCancellation;
  var _generation = 0;
  var _disposed = false;

  @override
  Future<InboxSettingsViewState> build() async {
    _disposed = false;
    final int generation = ++_generation;
    _loadCancellation?.cancel('Inbox settings load superseded');
    final RequestCancellation cancellation = RequestCancellation();
    _loadCancellation = cancellation;
    ref.onDispose(() {
      _disposed = true;
      cancellation.cancel('Inbox settings page disposed');
      _saveCancellation?.cancel('Inbox settings page disposed');
    });

    final AuthSession? session = ref.watch(_sessionProvider);
    if (session == null) throw StateError('No active Inbox settings session');
    final InboxSettingsSnapshot snapshot = await cancellation.run(
      () => ref.watch(_repositoryProvider).load(session: session),
    );
    if (!_isCurrent(cancellation, generation)) {
      throw const RequestCancelledException('Inbox settings load superseded');
    }
    return InboxSettingsViewState(snapshot: snapshot);
  }

  void retry() => ref.invalidateSelf();

  void setEnabled(bool value) => _replaceSettings(
    (InboxSettings settings) => InboxSettings(
      enabled: value,
      sources: settings.sources,
      postponed: settings.postponed,
      directGrouping: settings.directGrouping,
      inAppNotification: settings.inAppNotification,
      additionalFields: settings.additionalFields,
    ),
  );

  void setDirectMessages(bool value) => _replaceSources(
    (InboxSourceSettings sources) => InboxSourceSettings(
      directMessages: value,
      groupMessages: sources.groupMessages,
      mentions: sources.mentions,
      followedThreads: sources.followedThreads,
      allActivity: sources.allActivity,
      automations: sources.automations,
      additionalFields: sources.additionalFields,
    ),
  );

  void setGroupMessages(bool value) => _replaceSources(
    (InboxSourceSettings sources) => InboxSourceSettings(
      directMessages: sources.directMessages,
      groupMessages: value,
      mentions: sources.mentions,
      followedThreads: sources.followedThreads,
      allActivity: sources.allActivity,
      automations: sources.automations,
      additionalFields: sources.additionalFields,
    ),
  );

  void setMentions(bool value) => _replaceSources(
    (InboxSourceSettings sources) => InboxSourceSettings(
      directMessages: sources.directMessages,
      groupMessages: sources.groupMessages,
      mentions: value,
      followedThreads: sources.followedThreads,
      allActivity: sources.allActivity,
      automations: sources.automations,
      additionalFields: sources.additionalFields,
    ),
  );

  void setFollowedThreads(bool value) => _replaceSources(
    (InboxSourceSettings sources) => InboxSourceSettings(
      directMessages: sources.directMessages,
      groupMessages: sources.groupMessages,
      mentions: sources.mentions,
      followedThreads: value,
      allActivity: sources.allActivity,
      automations: sources.automations,
      additionalFields: sources.additionalFields,
    ),
  );

  void setAllActivity(bool value) => _replaceSources(
    (InboxSourceSettings sources) => InboxSourceSettings(
      directMessages: sources.directMessages,
      groupMessages: sources.groupMessages,
      mentions: sources.mentions,
      followedThreads: sources.followedThreads,
      allActivity: value,
      automations: sources.automations,
      additionalFields: sources.additionalFields,
    ),
  );

  void setAutomations(InboxAutomationVisibility value) => _replaceSources(
    (InboxSourceSettings sources) => InboxSourceSettings(
      directMessages: sources.directMessages,
      groupMessages: sources.groupMessages,
      mentions: sources.mentions,
      followedThreads: sources.followedThreads,
      allActivity: sources.allActivity,
      automations: value,
      additionalFields: sources.additionalFields,
    ),
  );

  void setReactivateOnMention(bool value) => _replaceSettings(
    (InboxSettings settings) => InboxSettings(
      enabled: settings.enabled,
      sources: settings.sources,
      postponed: InboxPostponedSettings(
        reactivateOnMention: value,
        removeOnOpen: settings.postponed.removeOnOpen,
        additionalFields: settings.postponed.additionalFields,
      ),
      directGrouping: settings.directGrouping,
      inAppNotification: settings.inAppNotification,
      additionalFields: settings.additionalFields,
    ),
  );

  void setRemoveOnOpen(bool value) => _replaceSettings(
    (InboxSettings settings) => InboxSettings(
      enabled: settings.enabled,
      sources: settings.sources,
      postponed: InboxPostponedSettings(
        reactivateOnMention: settings.postponed.reactivateOnMention,
        removeOnOpen: value,
        additionalFields: settings.postponed.additionalFields,
      ),
      directGrouping: settings.directGrouping,
      inAppNotification: settings.inAppNotification,
      additionalFields: settings.additionalFields,
    ),
  );

  void setDirectGroupingMode(InboxDirectGroupingMode value) => _replaceSettings(
    (InboxSettings settings) => InboxSettings(
      enabled: settings.enabled,
      sources: settings.sources,
      postponed: settings.postponed,
      directGrouping: InboxDirectGroupingSettings(
        mode: value,
        windowSeconds: settings.directGrouping.windowSeconds,
        additionalFields: settings.directGrouping.additionalFields,
      ),
      inAppNotification: settings.inAppNotification,
      additionalFields: settings.additionalFields,
    ),
  );

  void setShowMessagePreview(bool value) => _replaceSettings(
    (InboxSettings settings) => InboxSettings(
      enabled: settings.enabled,
      sources: settings.sources,
      postponed: settings.postponed,
      directGrouping: settings.directGrouping,
      inAppNotification: InboxInAppNotificationSettings(
        showMessagePreview: value,
        additionalFields: settings.inAppNotification.additionalFields,
      ),
      additionalFields: settings.additionalFields,
    ),
  );

  Future<void> save() async {
    final InboxSettingsViewState? current = state.value;
    final AuthSession? session = ref.read(_sessionProvider);
    if (current == null || session == null || _disposed) return;

    final int generation = ++_generation;
    _saveCancellation?.cancel('Inbox settings save superseded');
    final RequestCancellation cancellation = RequestCancellation();
    _saveCancellation = cancellation;
    state = AsyncData(
      current.copyWith(saveStatus: const OperationStatus.inProgress()),
    );
    try {
      await cancellation.run(
        () => ref
            .read(_repositoryProvider)
            .save(session: session, settings: current.settings),
      );
      if (!_isCurrent(cancellation, generation)) return;
      final AsyncNotifierProvider<
        InboxSessionController,
        InboxSessionViewState
      >?
      inboxSessionProvider = _inboxSessionProvider;
      if (inboxSessionProvider != null) {
        ref
            .read(inboxSessionProvider.notifier)
            .setShowMessagePreview(
              current.settings.inAppNotification.showMessagePreview,
            );
      }
      state = AsyncData(
        current.copyWith(saveStatus: const OperationStatus.idle()),
      );
    } on Object catch (error) {
      if (!_isCurrent(cancellation, generation) ||
          error is RequestCancelledException) {
        return;
      }
      state = AsyncData(
        current.copyWith(saveStatus: OperationStatus.failed(error)),
      );
    }
  }

  void _replaceSources(
    InboxSourceSettings Function(InboxSourceSettings sources) replace,
  ) => _replaceSettings(
    (InboxSettings settings) => InboxSettings(
      enabled: settings.enabled,
      sources: replace(settings.sources),
      postponed: settings.postponed,
      directGrouping: settings.directGrouping,
      inAppNotification: settings.inAppNotification,
      additionalFields: settings.additionalFields,
    ),
  );

  void _replaceSettings(
    InboxSettings Function(InboxSettings settings) replace,
  ) {
    final InboxSettingsViewState? current = state.value;
    if (current == null || current.saveStatus is OperationInProgress) return;
    state = AsyncData(
      current.copyWith(
        snapshot: InboxSettingsSnapshot(
          settings: replace(current.settings),
          state: current.snapshot.state,
        ),
        saveStatus: const OperationStatus.idle(),
      ),
    );
  }

  bool _isCurrent(RequestCancellation cancellation, int generation) =>
      !_disposed &&
      generation == _generation &&
      (identical(_loadCancellation, cancellation) ||
          identical(_saveCancellation, cancellation));
}
