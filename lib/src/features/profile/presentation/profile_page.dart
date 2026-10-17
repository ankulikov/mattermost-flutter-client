import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/profile/domain/models/current_user_profile.dart';
import 'package:mattermost_flutter/src/features/profile/presentation/current_user_profile_controller.dart';
import 'package:mattermost_flutter/src/features/profile/presentation/display_settings_page.dart';
import 'package:mattermost_flutter/src/features/profile/presentation/profile_strings.dart';
import 'package:mattermost_flutter/src/features/profile/presentation/widgets/profile_navigation_avatar.dart';
import 'package:mattermost_flutter/src/features/updates/presentation/app_update_page.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';
import 'package:mattermost_flutter/src/ui/users/widgets/user_avatar_image.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({required this.onLogout, super.key});

  final Future<void> Function() onLogout;

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  bool _loggingOut = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserProfileProvider, (previous, next) {
      final bool failed = next.value?.updateStatus is OperationFailed;
      if (failed && previous?.value?.updateStatus is! OperationFailed) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text(ProfileStrings.updateFailed)),
          );
      }
    });
    final AsyncValue<CurrentUserProfileViewState> state = ref.watch(
      currentUserProfileProvider,
    );
    return state.when(
      loading: () => const _ProfileLoading(),
      error: (Object _, StackTrace _) => _ProfileError(
        onRetry: () => ref.invalidate(currentUserProfileProvider),
      ),
      data: (CurrentUserProfileViewState value) => _ProfileBody(
        state: value,
        onAvailabilitySelected: _selectAvailability,
        onCustomStatusSelected: (QuickCustomStatus status) => unawaited(
          ref
              .read(currentUserProfileProvider.notifier)
              .setQuickCustomStatus(status),
        ),
        onClearCustomStatus: () => unawaited(
          ref.read(currentUserProfileProvider.notifier).clearCustomStatus(),
        ),
        onDisplaySettings: () => unawaited(
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => const DisplaySettingsPage(),
            ),
          ),
        ),
        onAppUpdates: () => unawaited(
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => const AppUpdatePage(),
            ),
          ),
        ),
        onLogout: _loggingOut ? null : () => unawaited(_logout()),
        isLoggingOut: _loggingOut,
      ),
    );
  }

  Future<void> _selectAvailability(UserPresence presence) async {
    AvailabilityExpiry? expiry;
    if (presence == UserPresence.doNotDisturb) {
      expiry = await showModalBottomSheet<AvailabilityExpiry>(
        context: context,
        showDragHandle: true,
        builder: (BuildContext context) => const _AvailabilityExpirySheet(),
      );
      if (expiry == null || !mounted) return;
    }
    await ref
        .read(currentUserProfileProvider.notifier)
        .setAvailability(presence, expiry: expiry);
  }

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    try {
      await widget.onLogout();
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({
    required this.state,
    required this.onAvailabilitySelected,
    required this.onCustomStatusSelected,
    required this.onClearCustomStatus,
    required this.onDisplaySettings,
    required this.onAppUpdates,
    required this.onLogout,
    required this.isLoggingOut,
  });

  final CurrentUserProfileViewState state;
  final ValueChanged<UserPresence> onAvailabilitySelected;
  final ValueChanged<QuickCustomStatus> onCustomStatusSelected;
  final VoidCallback onClearCustomStatus;
  final VoidCallback onDisplaySettings;
  final VoidCallback onAppUpdates;
  final VoidCallback? onLogout;
  final bool isLoggingOut;

  static const List<QuickCustomStatus> quickStatuses = <QuickCustomStatus>[
    QuickCustomStatus(
      emoji: 'calendar',
      text: ProfileStrings.inAMeeting,
      duration: CustomStatusDuration.oneHour,
    ),
    QuickCustomStatus(
      emoji: 'hamburger',
      text: ProfileStrings.outForLunch,
      duration: CustomStatusDuration.oneHour,
    ),
    QuickCustomStatus(
      emoji: 'bus',
      text: ProfileStrings.commuting,
      duration: CustomStatusDuration.oneHour,
    ),
    QuickCustomStatus(
      emoji: 'palm_tree',
      text: ProfileStrings.dayOff,
      duration: CustomStatusDuration.oneDay,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final CurrentUserProfile profile = state.profile;
    return Stack(
      children: <Widget>[
        CustomScrollView(
          key: const ValueKey<String>('profile-scroll-view'),
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _ProfileHeader(
                          profile: profile,
                          onClearCustomStatus:
                              state.updateStatus is OperationInProgress
                              ? null
                              : onClearCustomStatus,
                        ),
                        const SizedBox(height: 32),
                        Text(
                          ProfileStrings.availability,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        _AvailabilityChoices(
                          selected: profile.availability.presence,
                          enabled: state.updateStatus is! OperationInProgress,
                          onSelected: onAvailabilitySelected,
                        ),
                        const SizedBox(height: 28),
                        Text(
                          ProfileStrings.customStatus,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        _QuickStatusChoices(
                          statuses: quickStatuses,
                          currentStatus: profile.customStatus,
                          enabled: state.updateStatus is! OperationInProgress,
                          onSelected: onCustomStatusSelected,
                        ),
                        const SizedBox(height: 32),
                        _SettingsMenu(
                          onDisplaySettings: onDisplaySettings,
                          onAppUpdates: onAppUpdates,
                          onLogout: onLogout,
                          isLoggingOut: isLoggingOut,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (state.updateStatus is OperationInProgress)
          const PositionedDirectional(
            top: 0,
            start: 0,
            end: 0,
            child: LinearProgressIndicator(
              key: ValueKey<String>('profile-update-progress'),
            ),
          ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.onClearCustomStatus,
  });

  final CurrentUserProfile profile;
  final VoidCallback? onClearCustomStatus;

  @override
  Widget build(BuildContext context) {
    final CustomStatus? customStatus = profile.customStatus;
    return Column(
      children: <Widget>[
        Semantics(
          image: true,
          label: profile.user.fullName,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              UserAvatarImage(
                userId: profile.user.id,
                displayName: profile.user.fullName,
                profileImageUpdatedAt: profile.user.profileImageUpdatedAt,
                radius: 64,
              ),
              PositionedDirectional(
                end: 3,
                bottom: 3,
                child: Container(
                  key: const ValueKey<String>('profile-header-presence'),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: presenceColor(
                      context,
                      profile.availability.presence,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          profile.user.fullName,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          '@${profile.user.handle}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          ProfileStrings.presence(profile.availability.presence),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        if (profile.availability.expiresAt case final DateTime expiresAt)
          Text(
            _untilLabel(context, expiresAt),
            key: const ValueKey<String>('availability-expiry'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        if (customStatus != null) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_emojiGlyph(customStatus.emoji)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  customStatus.text,
                  key: const ValueKey<String>('current-custom-status'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: ProfileStrings.clearCustomStatus,
                visualDensity: VisualDensity.compact,
                onPressed: onClearCustomStatus,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          if (customStatus.expiresAt case final DateTime expiresAt)
            Text(
              _untilLabel(context, expiresAt),
              key: const ValueKey<String>('custom-status-expiry'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ],
    );
  }
}

class _AvailabilityChoices extends StatelessWidget {
  const _AvailabilityChoices({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final UserPresence selected;
  final bool enabled;
  final ValueChanged<UserPresence> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      const double gap = 8;
      final double itemWidth = (constraints.maxWidth - (gap * 3)) / 4;
      final bool useShortDndLabel = constraints.maxWidth < 500;
      return Wrap(
        spacing: gap,
        children: UserPresence.values
            .map(
              (UserPresence presence) => SizedBox(
                width: itemWidth,
                child: _AvailabilityButton(
                  buttonKey: ValueKey<String>('availability-${presence.name}'),
                  presence: presence,
                  selected: selected == presence,
                  label:
                      useShortDndLabel && presence == UserPresence.doNotDisturb
                      ? ProfileStrings.doNotDisturbShort
                      : ProfileStrings.presence(presence),
                  onPressed: enabled ? () => onSelected(presence) : null,
                ),
              ),
            )
            .toList(growable: false),
      );
    },
  );
}

class _QuickStatusChoices extends StatelessWidget {
  const _QuickStatusChoices({
    required this.statuses,
    required this.currentStatus,
    required this.enabled,
    required this.onSelected,
  });

  final List<QuickCustomStatus> statuses;
  final CustomStatus? currentStatus;
  final bool enabled;
  final ValueChanged<QuickCustomStatus> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final double itemWidth = constraints.maxWidth < 620
          ? (constraints.maxWidth - 10) / 2
          : (constraints.maxWidth - 30) / 4;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: statuses
            .map((QuickCustomStatus status) {
              final bool selected = currentStatus?.matches(status) ?? false;
              return SizedBox(
                width: itemWidth,
                child: FilterChip(
                  key: ValueKey<String>('quick-status-${status.emoji}'),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: enabled ? (bool _) => onSelected(status) : null,
                  label: SizedBox(
                    width: double.infinity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          _emojiGlyph(status.emoji),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(status.text, textAlign: TextAlign.center),
                        Text(
                          ProfileStrings.customDuration(status.duration),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            })
            .toList(growable: false),
      );
    },
  );
}

class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu({
    required this.onDisplaySettings,
    required this.onAppUpdates,
    required this.onLogout,
    required this.isLoggingOut,
  });

  final VoidCallback onDisplaySettings;
  final VoidCallback onAppUpdates;
  final VoidCallback? onLogout;
  final bool isLoggingOut;

  @override
  Widget build(BuildContext context) {
    final Color dangerColor = Theme.of(context).colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Card.outlined(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              const _SettingsTile(
                icon: Icons.person_outline,
                label: ProfileStrings.profileSettings,
              ),
              const Divider(height: 1),
              const _SettingsTile(
                icon: Icons.lock_outline,
                label: ProfileStrings.security,
              ),
              const Divider(height: 1),
              const _SettingsTile(
                icon: Icons.notifications_outlined,
                label: ProfileStrings.notifications,
              ),
              const Divider(height: 1),
              _SettingsTile(
                tileKey: const ValueKey<String>('profile-display-settings'),
                icon: Icons.visibility_outlined,
                label: ProfileStrings.display,
                onTap: onDisplaySettings,
              ),
              const Divider(height: 1),
              _SettingsTile(
                tileKey: const ValueKey<String>('profile-app-updates'),
                icon: Icons.system_update_alt,
                label: ProfileStrings.appUpdates,
                onTap: onAppUpdates,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card.outlined(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          color: Theme.of(context).colorScheme.errorContainer,
          child: ListTile(
            key: const ValueKey<String>('profile-logout'),
            enabled: onLogout != null,
            onTap: onLogout,
            iconColor: dangerColor,
            textColor: dangerColor,
            leading: const Icon(Icons.logout),
            title: const Text(ProfileStrings.logout),
            trailing: isLoggingOut
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      color: dangerColor,
                      strokeWidth: 2,
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    this.tileKey,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Key? tileKey;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    key: tileKey,
    enabled: onTap != null,
    onTap: onTap,
    leading: Icon(icon),
    title: Text(label),
    trailing: const Icon(Icons.chevron_right),
  );
}

class _PresenceDot extends StatelessWidget {
  const _PresenceDot({required this.presence});

  final UserPresence presence;

  @override
  Widget build(BuildContext context) => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      color: presence == UserPresence.offline
          ? Colors.transparent
          : presenceColor(context, presence),
      shape: BoxShape.circle,
      border: Border.all(color: presenceColor(context, presence), width: 2),
    ),
  );
}

class _AvailabilityButton extends StatelessWidget {
  const _AvailabilityButton({
    required this.presence,
    required this.selected,
    required this.label,
    required this.onPressed,
    required this.buttonKey,
  });

  final UserPresence presence;
  final bool selected;
  final String label;
  final VoidCallback? onPressed;
  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final RoundedRectangleBorder shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: selected ? colors.primary : colors.outline),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: ProfileStrings.presence(presence),
      child: Material(
        color: selected ? colors.secondaryContainer : colors.surface,
        shape: shape,
        child: InkWell(
          key: buttonKey,
          onTap: onPressed,
          customBorder: shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _PresenceDot(presence: presence),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvailabilityExpirySheet extends StatelessWidget {
  const _AvailabilityExpirySheet();

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
            child: Text(
              ProfileStrings.clearAfter,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final AvailabilityExpiry expiry in AvailabilityExpiry.values)
            ListTile(
              key: ValueKey<String>('availability-expiry-${expiry.name}'),
              leading: Icon(_expiryIcon(expiry)),
              title: Text(ProfileStrings.expiry(expiry)),
              onTap: () => Navigator.of(context).pop(expiry),
            ),
        ],
      ),
    ),
  );
}

class _ProfileLoading extends StatelessWidget {
  const _ProfileLoading();

  @override
  Widget build(BuildContext context) => const Center(
    child: CircularProgressIndicator(semanticsLabel: ProfileStrings.loading),
  );
}

class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(ProfileStrings.loadFailed, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text(ProfileStrings.retry),
          ),
        ],
      ),
    ),
  );
}

String _untilLabel(BuildContext context, DateTime expiresAt) {
  final DateTime local = expiresAt.toLocal();
  final MaterialLocalizations localizations = MaterialLocalizations.of(context);
  final String time = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
  );
  final DateTime now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return ProfileStrings.untilTime(time);
  }
  return ProfileStrings.untilDateTime(
    localizations.formatShortDate(local),
    time,
  );
}

IconData _expiryIcon(AvailabilityExpiry expiry) => switch (expiry) {
  AvailabilityExpiry.thirtyMinutes => Icons.timer_outlined,
  AvailabilityExpiry.oneHour => Icons.schedule,
  AvailabilityExpiry.tomorrowMorning => Icons.wb_sunny_outlined,
  AvailabilityExpiry.unlimited => Icons.all_inclusive,
};

String _emojiGlyph(String emoji) => switch (emoji) {
  'calendar' => '📅',
  'hamburger' => '🍔',
  'bus' => '🚌',
  'palm_tree' => '🌴',
  _ => '💬',
};
