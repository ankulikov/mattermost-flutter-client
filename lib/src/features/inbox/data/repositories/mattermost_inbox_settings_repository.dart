import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_settings.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_settings_repository.dart';

/// Mattermost-preference implementation of the client-owned Inbox settings.
///
/// This repository intentionally owns exactly one value per active user. It
/// does not use the `postponed_messages` category and does not read or write
/// desktop notification preferences. Mattermost's 100-entry batch limit is
/// therefore never approached by this settings document.
final class MattermostInboxSettingsRepository extends InboxSettingsRepository {
  MattermostInboxSettingsRepository({required MattermostApi api}) : _api = api;

  static const String category = 'mattermost_flutter_inbox';
  static const String name = 'settings';
  static const int _maxSettingsJsonCharacters = 64 * 1024;

  final MattermostApi _api;

  @override
  Future<InboxSettingsSnapshot> load({required AuthSession session}) async {
    final List<MattermostPreferenceDto> preferences;
    try {
      preferences = await _api.getPreferencesByCategory(
        userId: session.userId,
        category: category,
      );
    } on DioException catch (error) {
      if (_isMissingCategory(error)) {
        return const InboxSettingsSnapshot.defaults();
      }
      rethrow;
    }

    MattermostPreferenceDto? settingsPreference;
    for (final MattermostPreferenceDto preference in preferences) {
      if (preference.userId == session.userId &&
          preference.category == category &&
          preference.name == name) {
        settingsPreference = preference;
      }
    }
    if (settingsPreference == null) {
      return const InboxSettingsSnapshot.defaults();
    }
    return _parse(settingsPreference.value);
  }

  @override
  Future<void> save({
    required AuthSession session,
    required InboxSettings settings,
  }) {
    return _api.savePreferences(
      userId: session.userId,
      preferences: <MattermostPreferenceDto>[
        MattermostPreferenceDto(
          userId: session.userId,
          category: category,
          name: name,
          value: jsonEncode(_toJson(settings)),
        ),
      ],
    );
  }

  static InboxSettingsSnapshot _parse(String value) {
    // Preferences are server-provided. Inbox owns a deliberately small
    // settings document, so reject oversized values before synchronous JSON
    // parsing can monopolize the UI isolate.
    if (value.length > _maxSettingsJsonCharacters) {
      return const InboxSettingsSnapshot(
        settings: InboxSettings.defaults,
        state: InboxSettingsLoadState.malformed,
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return const InboxSettingsSnapshot(
        settings: InboxSettings.defaults,
        state: InboxSettingsLoadState.malformed,
      );
    }
    final Map<String, Object?>? root = _asObjectMap(decoded);
    if (root == null) {
      return const InboxSettingsSnapshot(
        settings: InboxSettings.defaults,
        state: InboxSettingsLoadState.malformed,
      );
    }

    final Object? version = root['v'];
    if (version is int && version != InboxSettings.currentVersion) {
      return const InboxSettingsSnapshot(
        settings: InboxSettings.defaults,
        state: InboxSettingsLoadState.unsupportedVersion,
      );
    }
    if (version != InboxSettings.currentVersion) {
      return const InboxSettingsSnapshot(
        settings: InboxSettings.defaults,
        state: InboxSettingsLoadState.malformed,
      );
    }

    var hasMalformedKnownValue = false;
    final _ParsedValue<bool> enabled = _bool(root, 'enabled', true);
    hasMalformedKnownValue |= enabled.wasMalformed;

    final _ParsedSources sources = _parseSources(root['sources']);
    hasMalformedKnownValue |= sources.wasMalformed;
    final _ParsedPostponed postponed = _parsePostponed(root['postponed']);
    hasMalformedKnownValue |= postponed.wasMalformed;
    final _ParsedDirectGrouping directGrouping = _parseDirectGrouping(
      root['direct_grouping'],
    );
    hasMalformedKnownValue |= directGrouping.wasMalformed;
    final _ParsedInAppNotification inAppNotification = _parseInAppNotification(
      root['in_app_notification'],
    );
    hasMalformedKnownValue |= inAppNotification.wasMalformed;

    return InboxSettingsSnapshot(
      settings: InboxSettings(
        enabled: enabled.value,
        sources: sources.value,
        postponed: postponed.value,
        directGrouping: directGrouping.value,
        inAppNotification: inAppNotification.value,
        additionalFields: _additionalFields(root, _rootKnownFields),
      ),
      state: hasMalformedKnownValue
          ? InboxSettingsLoadState.malformed
          : InboxSettingsLoadState.parsed,
    );
  }

  static _ParsedSources _parseSources(Object? raw) {
    if (raw == null) return const _ParsedSources(InboxSourceSettings());
    final Map<String, Object?>? value = _asObjectMap(raw);
    if (value == null) return const _ParsedSources(InboxSourceSettings(), true);

    var malformed = false;
    final _ParsedValue<bool> directMessages = _bool(
      value,
      'direct_messages',
      true,
    );
    final _ParsedValue<bool> groupMessages = _bool(
      value,
      'group_messages',
      true,
    );
    final _ParsedValue<bool> mentions = _bool(value, 'mentions', true);
    final _ParsedValue<bool> followedThreads = _bool(
      value,
      'followed_threads',
      true,
    );
    final _ParsedValue<bool> allActivity = _bool(value, 'all_activity', true);
    malformed =
        directMessages.wasMalformed ||
        groupMessages.wasMalformed ||
        mentions.wasMalformed ||
        followedThreads.wasMalformed ||
        allActivity.wasMalformed;

    final Object? rawAutomations = value['automations'];
    final InboxAutomationVisibility automations = switch (rawAutomations) {
      null => InboxAutomationVisibility.separate,
      'include' => InboxAutomationVisibility.include,
      'exclude' => InboxAutomationVisibility.exclude,
      'separate' => InboxAutomationVisibility.separate,
      _ => InboxAutomationVisibility.separate,
    };
    malformed |=
        rawAutomations != null &&
        rawAutomations != 'include' &&
        rawAutomations != 'exclude' &&
        rawAutomations != 'separate';

    return _ParsedSources(
      InboxSourceSettings(
        directMessages: directMessages.value,
        groupMessages: groupMessages.value,
        mentions: mentions.value,
        followedThreads: followedThreads.value,
        allActivity: allActivity.value,
        automations: automations,
        additionalFields: _additionalFields(value, _sourceKnownFields),
      ),
      malformed,
    );
  }

  static _ParsedPostponed _parsePostponed(Object? raw) {
    if (raw == null) return const _ParsedPostponed(InboxPostponedSettings());
    final Map<String, Object?>? value = _asObjectMap(raw);
    if (value == null) {
      return const _ParsedPostponed(InboxPostponedSettings(), true);
    }

    final _ParsedValue<bool> reactivateOnMention = _bool(
      value,
      'reactivate_on_mention',
      true,
    );
    final _ParsedValue<bool> removeOnOpen = _bool(
      value,
      'remove_on_open',
      false,
    );
    return _ParsedPostponed(
      InboxPostponedSettings(
        reactivateOnMention: reactivateOnMention.value,
        removeOnOpen: removeOnOpen.value,
        additionalFields: _additionalFields(value, _postponedKnownFields),
      ),
      reactivateOnMention.wasMalformed || removeOnOpen.wasMalformed,
    );
  }

  static _ParsedDirectGrouping _parseDirectGrouping(Object? raw) {
    if (raw == null) {
      return const _ParsedDirectGrouping(InboxDirectGroupingSettings());
    }
    final Map<String, Object?>? value = _asObjectMap(raw);
    if (value == null) {
      return const _ParsedDirectGrouping(InboxDirectGroupingSettings(), true);
    }

    final Object? rawMode = value['mode'];
    final InboxDirectGroupingMode mode = switch (rawMode) {
      null => InboxDirectGroupingMode.consecutive,
      'none' => InboxDirectGroupingMode.none,
      'consecutive' => InboxDirectGroupingMode.consecutive,
      'conversation' => InboxDirectGroupingMode.conversation,
      _ => InboxDirectGroupingMode.consecutive,
    };
    final bool malformedMode =
        rawMode != null &&
        rawMode != 'none' &&
        rawMode != 'consecutive' &&
        rawMode != 'conversation';

    final Object? rawWindow = value['window_seconds'];
    final bool validWindow =
        rawWindow is int &&
        rawWindow >= InboxDirectGroupingSettings.minWindowSeconds &&
        rawWindow <= InboxDirectGroupingSettings.maxWindowSeconds;
    final int windowSeconds = rawWindow == null
        ? InboxDirectGroupingSettings.defaultWindowSeconds
        : validWindow
        ? rawWindow
        : InboxDirectGroupingSettings.defaultWindowSeconds;

    return _ParsedDirectGrouping(
      InboxDirectGroupingSettings(
        mode: mode,
        windowSeconds: windowSeconds,
        additionalFields: _additionalFields(value, _directGroupingKnownFields),
      ),
      malformedMode || (rawWindow != null && !validWindow),
    );
  }

  static _ParsedInAppNotification _parseInAppNotification(Object? raw) {
    if (raw == null) {
      return const _ParsedInAppNotification(InboxInAppNotificationSettings());
    }
    final Map<String, Object?>? value = _asObjectMap(raw);
    if (value == null) {
      return const _ParsedInAppNotification(
        InboxInAppNotificationSettings(),
        true,
      );
    }
    final _ParsedValue<bool> showMessagePreview = _bool(
      value,
      'show_message_preview',
      false,
    );
    return _ParsedInAppNotification(
      InboxInAppNotificationSettings(
        showMessagePreview: showMessagePreview.value,
        additionalFields: _additionalFields(
          value,
          _inAppNotificationKnownFields,
        ),
      ),
      showMessagePreview.wasMalformed,
    );
  }

  static Map<String, Object?> _toJson(InboxSettings settings) {
    final Map<String, Object?> root = _copyMap(settings.additionalFields);
    root['v'] = InboxSettings.currentVersion;
    root['enabled'] = settings.enabled;
    root['sources'] = _sourceJson(settings.sources);
    root['postponed'] = _postponedJson(settings.postponed);
    root['direct_grouping'] = _directGroupingJson(settings.directGrouping);
    root['in_app_notification'] = _inAppNotificationJson(
      settings.inAppNotification,
    );
    return root;
  }

  static Map<String, Object?> _sourceJson(InboxSourceSettings settings) {
    final Map<String, Object?> value = _copyMap(settings.additionalFields);
    value['direct_messages'] = settings.directMessages;
    value['group_messages'] = settings.groupMessages;
    value['mentions'] = settings.mentions;
    value['followed_threads'] = settings.followedThreads;
    value['all_activity'] = settings.allActivity;
    value['automations'] = settings.automations.name;
    return value;
  }

  static Map<String, Object?> _postponedJson(InboxPostponedSettings settings) {
    final Map<String, Object?> value = _copyMap(settings.additionalFields);
    value['reactivate_on_mention'] = settings.reactivateOnMention;
    value['remove_on_open'] = settings.removeOnOpen;
    return value;
  }

  static Map<String, Object?> _directGroupingJson(
    InboxDirectGroupingSettings settings,
  ) {
    final Map<String, Object?> value = _copyMap(settings.additionalFields);
    value['mode'] = settings.mode.name;
    value['window_seconds'] = settings.windowSeconds;
    return value;
  }

  static Map<String, Object?> _inAppNotificationJson(
    InboxInAppNotificationSettings settings,
  ) {
    final Map<String, Object?> value = _copyMap(settings.additionalFields);
    value['show_message_preview'] = settings.showMessagePreview;
    return value;
  }

  static _ParsedValue<bool> _bool(
    Map<String, Object?> value,
    String key,
    bool defaultValue,
  ) {
    final Object? raw = value[key];
    if (raw == null) return _ParsedValue<bool>(defaultValue);
    if (raw is bool) return _ParsedValue<bool>(raw);
    return _ParsedValue<bool>(defaultValue, true);
  }

  static Map<String, Object?>? _asObjectMap(Object? value) {
    if (value is! Map<Object?, Object?>) return null;
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is! String) return null;
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static Map<String, Object?> _additionalFields(
    Map<String, Object?> fields,
    Set<String> knownFields,
  ) {
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<String, Object?> entry in fields.entries) {
      if (!knownFields.contains(entry.key)) {
        result[entry.key] = _copyJsonValue(entry.value);
      }
    }
    return result;
  }

  static Map<String, Object?> _copyMap(Map<String, Object?> fields) =>
      fields.map(
        (String key, Object? value) =>
            MapEntry<String, Object?>(key, _copyJsonValue(value)),
      );

  static Object? _copyJsonValue(Object? value) {
    if (value is String || value is num || value is bool || value == null) {
      return value;
    }
    if (value is List<Object?>) {
      return value.map<Object?>(_copyJsonValue).toList(growable: false);
    }
    if (value is Map<Object?, Object?>) {
      final Map<String, Object?>? map = _asObjectMap(value);
      if (map == null) return null;
      return _copyMap(map);
    }
    return null;
  }

  static bool _isMissingCategory(DioException error) {
    if (error.response?.statusCode != 404) return false;
    final Object? data = error.response?.data;
    return data is Map<Object?, Object?> &&
        data['id'] == 'api.preference.preferences_category.get.app_error';
  }

  static const Set<String> _rootKnownFields = <String>{
    'v',
    'enabled',
    'sources',
    'postponed',
    'direct_grouping',
    'in_app_notification',
  };
  static const Set<String> _sourceKnownFields = <String>{
    'direct_messages',
    'group_messages',
    'mentions',
    'followed_threads',
    'all_activity',
    'automations',
  };
  static const Set<String> _postponedKnownFields = <String>{
    'reactivate_on_mention',
    'remove_on_open',
  };
  static const Set<String> _directGroupingKnownFields = <String>{
    'mode',
    'window_seconds',
  };
  static const Set<String> _inAppNotificationKnownFields = <String>{
    'show_message_preview',
  };
}

final class _ParsedValue<T> {
  const _ParsedValue(this.value, [this.wasMalformed = false]);

  final T value;
  final bool wasMalformed;
}

final class _ParsedSources {
  const _ParsedSources(this.value, [this.wasMalformed = false]);

  final InboxSourceSettings value;
  final bool wasMalformed;
}

final class _ParsedPostponed {
  const _ParsedPostponed(this.value, [this.wasMalformed = false]);

  final InboxPostponedSettings value;
  final bool wasMalformed;
}

final class _ParsedDirectGrouping {
  const _ParsedDirectGrouping(this.value, [this.wasMalformed = false]);

  final InboxDirectGroupingSettings value;
  final bool wasMalformed;
}

final class _ParsedInAppNotification {
  const _ParsedInAppNotification(this.value, [this.wasMalformed = false]);

  final InboxInAppNotificationSettings value;
  final bool wasMalformed;
}
