import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/profile/domain/models/current_user_profile.dart';
import 'package:mattermost_flutter/src/features/profile/presentation/profile_page.dart';
import 'package:mattermost_flutter/src/features/profile/presentation/profile_strings.dart';
import 'package:mattermost_flutter/src/features/profile/presentation/widgets/profile_navigation_avatar.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';
import 'package:mattermost_flutter/src/ui/users/widgets/user_avatar_image.dart';

enum _ProfileMenuAction {
  customStatus,
  online,
  away,
  doNotDisturb,
  offline,
  profile,
  logout,
}

Future<void> showProfileAvatarMenu({
  required BuildContext context,
  required WidgetRef ref,
  required VoidCallback onProfile,
  required Future<void> Function() onLogout,
  bool bottomNavigation = false,
}) async {
  final RenderBox anchor = context.findRenderObject()! as RenderBox;
  final RenderBox overlay =
      Overlay.of(context).context.findRenderObject()! as RenderBox;
  final Offset origin = anchor.localToGlobal(Offset.zero, ancestor: overlay);
  final Rect rect = bottomNavigation
      ? Rect.fromLTWH(
          origin.dx + anchor.size.width * .75,
          origin.dy,
          anchor.size.width * .25,
          anchor.size.height,
        )
      : origin & anchor.size;
  final profileState = ref.read(currentUserProfileProvider);
  final CurrentUserProfile? profile = profileState.value?.profile;
  final bool canUpdate =
      profile != null &&
      profileState.value?.updateStatus is! OperationInProgress;
  final _ProfileMenuAction? action = await showMenu<_ProfileMenuAction>(
    context: context,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    popUpAnimationStyle: AnimationStyle.noAnimation,
    constraints: BoxConstraints(maxWidth: bottomNavigation ? 320 : 340),
    items: <PopupMenuEntry<_ProfileMenuAction>>[
      PopupMenuItem<_ProfileMenuAction>(
        key: const ValueKey<String>('profile-avatar-menu'),
        enabled: false,
        height: 72,
        child: profile == null
            ? Text(
                profileState.hasError
                    ? ProfileStrings.loadFailed
                    : ProfileStrings.loading,
              )
            : Row(
                children: <Widget>[
                  UserAvatarImage(
                    userId: profile.user.id,
                    displayName: profile.user.fullName,
                    profileImageUpdatedAt: profile.user.profileImageUpdatedAt,
                    radius: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          profile.user.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '@${profile.user.handle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<_ProfileMenuAction>(
        key: ValueKey<String>('profile-menu-custom-status'),
        value: _ProfileMenuAction.customStatus,
        enabled: canUpdate,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.add_reaction_outlined),
          title: Text(ProfileStrings.setCustomStatus),
        ),
      ),
      const PopupMenuDivider(),
      for (final UserPresence presence in UserPresence.values)
        PopupMenuItem<_ProfileMenuAction>(
          key: ValueKey<String>('profile-menu-${presence.name}'),
          enabled: canUpdate,
          value: switch (presence) {
            UserPresence.online => _ProfileMenuAction.online,
            UserPresence.away => _ProfileMenuAction.away,
            UserPresence.doNotDisturb => _ProfileMenuAction.doNotDisturb,
            UserPresence.offline => _ProfileMenuAction.offline,
          },
          child: Semantics(
            selected: profile?.availability.presence == presence,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.circle,
                color: presenceColor(context, presence),
                size: 20,
              ),
              title: Text(ProfileStrings.presence(presence)),
              trailing: profile?.availability.presence == presence
                  ? const Icon(Icons.check, size: 20)
                  : null,
            ),
          ),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem<_ProfileMenuAction>(
        key: ValueKey<String>('profile-menu-profile'),
        value: _ProfileMenuAction.profile,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.person_outline),
          title: Text(ProfileStrings.title),
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem<_ProfileMenuAction>(
        key: ValueKey<String>('profile-menu-logout'),
        value: _ProfileMenuAction.logout,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.logout),
          title: Text(ProfileStrings.logout),
        ),
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _ProfileMenuAction.profile:
      onProfile();
    case _ProfileMenuAction.logout:
      await onLogout();
    case _ProfileMenuAction.customStatus:
      final QuickCustomStatus? status = await _editCustomStatus(
        context,
        profile,
      );
      if (status == null || !context.mounted) return;
      await ref
          .read(currentUserProfileProvider.notifier)
          .setQuickCustomStatus(status);
      if (context.mounted) _showUpdateFailure(context, ref);
    case _ProfileMenuAction.online ||
        _ProfileMenuAction.away ||
        _ProfileMenuAction.doNotDisturb ||
        _ProfileMenuAction.offline:
      final UserPresence presence = switch (action) {
        _ProfileMenuAction.online => UserPresence.online,
        _ProfileMenuAction.away => UserPresence.away,
        _ProfileMenuAction.doNotDisturb => UserPresence.doNotDisturb,
        _ => UserPresence.offline,
      };
      AvailabilityExpiry? expiry;
      if (presence == UserPresence.doNotDisturb) {
        expiry = await showAvailabilityExpirySheet(context);
        if (expiry == null || !context.mounted) return;
      }
      await ref
          .read(currentUserProfileProvider.notifier)
          .setAvailability(presence, expiry: expiry);
      if (context.mounted) _showUpdateFailure(context, ref);
  }
}

void _showUpdateFailure(BuildContext context, WidgetRef ref) {
  if (ref.read(currentUserProfileProvider).value?.updateStatus
      is OperationFailed) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text(ProfileStrings.updateFailed)),
      );
  }
}

Future<QuickCustomStatus?> _editCustomStatus(
  BuildContext context,
  CurrentUserProfile? profile,
) async {
  String statusText = profile?.customStatus?.text ?? '';
  CustomStatusDuration duration = CustomStatusDuration.oneHour;
  final QuickCustomStatus? result = await showDialog<QuickCustomStatus>(
    context: context,
    builder: (BuildContext context) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) => AlertDialog(
        title: const Text(ProfileStrings.setCustomStatus),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextFormField(
              key: const ValueKey<String>('custom-status-text'),
              initialValue: statusText,
              autofocus: true,
              maxLines: 2,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: ProfileStrings.statusText,
              ),
              onChanged: (String value) => setState(() => statusText = value),
            ),
            DropdownButtonFormField<CustomStatusDuration>(
              initialValue: duration,
              decoration: const InputDecoration(
                labelText: ProfileStrings.clearAfter,
              ),
              items: CustomStatusDuration.values
                  .map(
                    (CustomStatusDuration value) =>
                        DropdownMenuItem<CustomStatusDuration>(
                          value: value,
                          child: Text(ProfileStrings.customDuration(value)),
                        ),
                  )
                  .toList(growable: false),
              onChanged: (CustomStatusDuration? value) {
                if (value != null) setState(() => duration = value);
              },
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(ProfileStrings.cancel),
          ),
          FilledButton(
            key: const ValueKey<String>('custom-status-save'),
            onPressed: statusText.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(
                    QuickCustomStatus(
                      emoji: profile?.customStatus?.emoji ?? 'speech_balloon',
                      text: statusText.trim(),
                      duration: duration,
                    ),
                  ),
            child: const Text(ProfileStrings.save),
          ),
        ],
      ),
    ),
  );
  return result;
}
