import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';

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

/// A one-shot request for the shell to present the selected channel.
///
/// Selecting a channel can happen outside the sidebar, for example after the
/// Message action on a user card. The shell owns the compact channel/list
/// transition, so the request deliberately stays separate from selection.
final NotifierProvider<ChannelPresentationController, bool>
channelPresentationProvider =
    NotifierProvider<ChannelPresentationController, bool>(
      ChannelPresentationController.new,
    );

final class ChannelPresentationController extends Notifier<bool> {
  @override
  bool build() => false;

  void showSelectedChannel() => state = true;

  void markPresented() => state = false;
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
