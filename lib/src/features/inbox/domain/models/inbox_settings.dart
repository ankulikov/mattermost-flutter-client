/// Automation visibility preference for the client-side Inbox projection.
///
/// This setting can only narrow the locally displayed projection. It never
/// changes Mattermost desktop notification eligibility.
enum InboxAutomationVisibility { include, exclude, separate }

/// Grouping preference for direct-message Inbox items.
enum InboxDirectGroupingMode { none, consecutive, conversation }

/// The source toggles owned by the client Inbox preference.
final class InboxSourceSettings {
  const InboxSourceSettings({
    this.directMessages = true,
    this.groupMessages = true,
    this.mentions = true,
    this.followedThreads = true,
    this.allActivity = true,
    this.automations = InboxAutomationVisibility.separate,
    this.additionalFields = const <String, Object?>{},
  });

  final bool directMessages;
  final bool groupMessages;
  final bool mentions;
  final bool followedThreads;
  final bool allActivity;
  final InboxAutomationVisibility automations;

  /// Forward-compatible JSON values not yet understood by this client.
  ///
  /// They are opaque to domain policies and are emitted unchanged by the data
  /// mapper when this v1 settings document is saved again.
  final Map<String, Object?> additionalFields;
}

/// Settings for the durable, content-free Postponed queue.
final class InboxPostponedSettings {
  const InboxPostponedSettings({
    this.reactivateOnMention = true,
    this.removeOnOpen = false,
    this.additionalFields = const <String, Object?>{},
  });

  final bool reactivateOnMention;
  final bool removeOnOpen;
  final Map<String, Object?> additionalFields;
}

/// Bounded direct-message grouping settings.
final class InboxDirectGroupingSettings {
  const InboxDirectGroupingSettings({
    this.mode = InboxDirectGroupingMode.consecutive,
    this.windowSeconds = defaultWindowSeconds,
    this.additionalFields = const <String, Object?>{},
  });

  static const int defaultWindowSeconds = 120;
  static const int minWindowSeconds = 1;
  static const int maxWindowSeconds = 3600;

  final InboxDirectGroupingMode mode;
  final int windowSeconds;
  final Map<String, Object?> additionalFields;
}

/// Product privacy controls for foreground Inbox notifications.
///
/// This setting never changes Inbox membership or Mattermost notification
/// policy. It only decides whether a transient foreground notification may
/// include server-provided message text.
final class InboxInAppNotificationSettings {
  const InboxInAppNotificationSettings({
    this.showMessagePreview = false,
    this.additionalFields = const <String, Object?>{},
  });

  /// Defaults to false so foreground notifications do not disclose message
  /// content unless the user explicitly opts in.
  final bool showMessagePreview;
  final Map<String, Object?> additionalFields;
}

/// Non-secret client settings that may narrow the Inbox projection.
///
/// Mattermost desktop notification preferences remain authoritative. This
/// model deliberately has no fields for desktop, push, email, server URLs,
/// users, channels, or message content.
final class InboxSettings {
  const InboxSettings({
    this.enabled = true,
    this.sources = const InboxSourceSettings(),
    this.postponed = const InboxPostponedSettings(),
    this.directGrouping = const InboxDirectGroupingSettings(),
    this.inAppNotification = const InboxInAppNotificationSettings(),
    this.additionalFields = const <String, Object?>{},
  });

  static const int currentVersion = 1;

  static const InboxSettings defaults = InboxSettings();

  final bool enabled;
  final InboxSourceSettings sources;
  final InboxPostponedSettings postponed;
  final InboxDirectGroupingSettings directGrouping;
  final InboxInAppNotificationSettings inAppNotification;

  /// Opaque v1 JSON fields retained for forward-compatible round trips.
  ///
  /// Known invalid fields are not retained: they fall back to the corresponding
  /// safe default. This prevents an invalid future value from becoming active
  /// after a subsequent save.
  final Map<String, Object?> additionalFields;
}

/// Whether a settings document was usable for the current client version.
enum InboxSettingsLoadState { defaults, parsed, malformed, unsupportedVersion }

/// A settings read together with content-free parser status.
///
/// [state] is intentionally diagnostic-only: it contains neither the raw
/// preference nor any user-provided values, so presentation can communicate a
/// fallback without exposing preference contents.
final class InboxSettingsSnapshot {
  const InboxSettingsSnapshot({
    required this.settings,
    this.state = InboxSettingsLoadState.defaults,
  });

  const InboxSettingsSnapshot.defaults()
    : settings = InboxSettings.defaults,
      state = InboxSettingsLoadState.defaults;

  final InboxSettings settings;
  final InboxSettingsLoadState state;
}
