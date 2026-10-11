import 'package:mattermost_flutter/src/domain/models/user.dart';

final class ChannelMember {
  const ChannelMember({required this.user, this.isChannelAdmin = false});

  final UserSummary user;
  final bool isChannelAdmin;
}

final class ChannelMembersPage {
  const ChannelMembersPage({
    this.members = const <ChannelMember>[],
    this.hasMore = false,
  });

  final List<ChannelMember> members;
  final bool hasMore;
}
