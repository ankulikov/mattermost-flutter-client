import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';

final NotifierProvider<SelectedChannelController, SidebarChannel?>
selectedChannelProvider =
    NotifierProvider<SelectedChannelController, SidebarChannel?>(
      SelectedChannelController.new,
    );

final class SelectedChannelController extends Notifier<SidebarChannel?> {
  @override
  SidebarChannel? build() => null;

  void select(SidebarChannel channel) => state = channel;

  void clear() => state = null;
}

final NotifierProvider<ThreadsDestinationController, bool>
threadsDestinationProvider =
    NotifierProvider<ThreadsDestinationController, bool>(
      ThreadsDestinationController.new,
    );

final class ThreadsDestinationController extends Notifier<bool> {
  @override
  bool build() => false;

  void select() => state = true;

  void clear() => state = false;
}
