import 'dart:collection';

/// Content-free post identifiers individually dismissed from an unread channel.
final class ViewedChannelPostsSnapshot {
  ViewedChannelPostsSnapshot(Map<String, Iterable<String>> postIdsByChannelId)
    : postIdsByChannelId =
          UnmodifiableMapView<String, Set<String>>(<String, Set<String>>{
            for (final MapEntry(:key, :value) in postIdsByChannelId.entries)
              key: Set<String>.unmodifiable(value),
          });

  final Map<String, Set<String>> postIdsByChannelId;

  Set<String> forChannel(String channelId) =>
      postIdsByChannelId[channelId] ?? const <String>{};
}
