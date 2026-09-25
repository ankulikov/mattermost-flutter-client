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

/// The mutually-exclusive destinations owned by the application shell.
enum ShellDestination { channels, inbox, search, profile }

final NotifierProvider<ShellDestinationController, ShellDestination>
shellDestinationProvider =
    NotifierProvider<ShellDestinationController, ShellDestination>(
      ShellDestinationController.new,
    );

final class ShellDestinationController extends Notifier<ShellDestination> {
  @override
  ShellDestination build() => ShellDestination.channels;

  void select(ShellDestination destination) => state = destination;
}

/// A one-shot request for Search.  The screen itself owns consumption so a
/// rebuild cannot accidentally overwrite a draft the user has started.
final NotifierProvider<SearchLaunchIntentController, Object?>
searchLaunchIntentProvider =
    NotifierProvider<SearchLaunchIntentController, Object?>(
      SearchLaunchIntentController.new,
    );

final class SearchLaunchIntentController extends Notifier<Object?> {
  @override
  Object? build() => null;

  void launch(Object intent) => state = intent;
}
