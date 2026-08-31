import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/models/user_avatar.dart';
import 'package:mattermost_flutter/src/ui/core/widgets/avatar_initials.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';
import 'package:mattermost_flutter/src/ui/users/user_profile_strings.dart';

typedef OpenDirectMessage = Future<void> Function(UserProfile profile);

Future<void> showUserProfileCard(
  BuildContext context, {
  required String userId,
  required OpenDirectMessage onMessage,
}) => showDialog<void>(
  context: context,
  builder: (BuildContext context) =>
      UserProfileCard(userId: userId, onMessage: onMessage),
);

class UserProfileCard extends ConsumerStatefulWidget {
  const UserProfileCard({
    required this.userId,
    required this.onMessage,
    super.key,
  });

  final String userId;
  final OpenDirectMessage onMessage;

  @override
  ConsumerState<UserProfileCard> createState() => _UserProfileCardState();
}

class _UserProfileCardState extends ConsumerState<UserProfileCard> {
  bool _openingMessage = false;
  bool _messageFailed = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<UserProfile> profile = ref.watch(
      userProfileProvider(widget.userId),
    );
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                tooltip: UserProfileStrings.close,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            Flexible(
              child: profile.when(
                loading: () => const _ProfileLoading(),
                error: (Object _, StackTrace _) => _ProfileError(
                  onRetry: () =>
                      ref.invalidate(userProfileProvider(widget.userId)),
                ),
                data: _buildProfile,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfile(UserProfile profile) {
    final bool isCurrentUser = ref.watch(
      authSessionProvider.select((session) => session?.userId == profile.id),
    );
    final double horizontalPadding = MediaQuery.sizeOf(context).width < 400
        ? 16
        : 28;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(child: _ProfileAvatar(profile: profile)),
          const SizedBox(height: 16),
          Text(
            profile.fullName,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '@${profile.handle}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Center(child: _PresenceBadge(presence: profile.presence)),
          const SizedBox(height: 24),
          _ProfileField(
            icon: Icons.work_outline,
            label: UserProfileStrings.position,
            value: _shown(profile.position),
          ),
          const SizedBox(height: 14),
          _ProfileField(
            icon: Icons.email_outlined,
            label: UserProfileStrings.email,
            value: _shown(profile.email),
            selectable: profile.email.isNotEmpty,
          ),
          if (_messageFailed) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              UserProfileStrings.messageFailed,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (!isCurrentUser) ...<Widget>[
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _openingMessage ? null : () => _openMessage(profile),
              child: _openingMessage
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(UserProfileStrings.message),
            ),
          ],
        ],
      ),
    );
  }

  String _shown(String value) =>
      value.trim().isEmpty ? UserProfileStrings.unavailable : value.trim();

  Future<void> _openMessage(UserProfile profile) async {
    setState(() {
      _openingMessage = true;
      _messageFailed = false;
    });
    try {
      await widget.onMessage(profile);
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() {
        _openingMessage = false;
        _messageFailed = true;
      });
    }
  }
}

class _ProfileAvatar extends ConsumerWidget {
  const _ProfileAvatar({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<UserAvatar?> avatar = ref.watch(
      userAvatarProvider((
        userId: profile.id,
        profileImageUpdatedAt: profile.profileImageUpdatedAt,
      )),
    );
    const double diameter = 112;
    final Widget fallback = CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
      child: Text(
        avatarInitials(profile.fullName),
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
    return Semantics(
      image: true,
      label: profile.fullName,
      child: SizedBox.square(
        dimension: diameter,
        child: ClipOval(
          child: avatar.when(
            data: (UserAvatar? value) => value == null
                ? fallback
                : _ProfileImage(bytes: value.bytes, fallback: fallback),
            loading: () => fallback,
            error: (Object _, StackTrace _) => fallback,
          ),
        ),
      ),
    );
  }
}

class _ProfileImage extends StatelessWidget {
  const _ProfileImage({required this.bytes, required this.fallback});

  final Uint8List bytes;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => Image.memory(
    bytes,
    fit: BoxFit.cover,
    cacheWidth: (112 * MediaQuery.devicePixelRatioOf(context)).ceil(),
    gaplessPlayback: true,
    excludeFromSemantics: true,
    errorBuilder: (BuildContext context, Object _, StackTrace? _) => fallback,
  );
}

class _PresenceBadge extends StatelessWidget {
  const _PresenceBadge({required this.presence});

  final UserPresence presence;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (presence) {
      UserPresence.online => Colors.green,
      UserPresence.away => Colors.amber.shade700,
      UserPresence.doNotDisturb => Colors.red,
      UserPresence.offline => Theme.of(context).colorScheme.outline,
    };
    return Semantics(
      label: UserProfileStrings.presence(presence),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(UserProfileStrings.presence(presence)),
        ],
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.icon,
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Icon(icon, size: 22),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 2),
            if (selectable) SelectableText(value) else Text(value),
          ],
        ),
      ),
    ],
  );
}

class _ProfileLoading extends StatelessWidget {
  const _ProfileLoading();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(64),
    child: Center(
      child: Semantics(
        label: UserProfileStrings.loading,
        child: const CircularProgressIndicator(),
      ),
    ),
  );
}

class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 16, 28, 40),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(UserProfileStrings.loadFailed, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: onRetry,
          child: const Text(UserProfileStrings.retry),
        ),
      ],
    ),
  );
}
