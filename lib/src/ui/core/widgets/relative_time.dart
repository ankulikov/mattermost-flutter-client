import 'package:flutter/material.dart';
import 'package:mattermost_flutter/src/ui/threads/followed_threads_strings.dart';

String formatFollowedThreadLastReplyTime({
  required DateTime lastReplyAt,
  required DateTime now,
  required MaterialLocalizations localizations,
}) {
  final Duration elapsed = now.toLocal().difference(lastReplyAt.toLocal());
  final int minutes = elapsed.isNegative ? 0 : elapsed.inMinutes;
  if (minutes == 0) return FollowedThreadsStrings.now;
  if (minutes < 60) return FollowedThreadsStrings.minutesAgo(minutes);

  final int hours = elapsed.inHours;
  if (hours < 24) return FollowedThreadsStrings.hoursAgo(hours);

  return localizations.formatMediumDate(lastReplyAt.toLocal());
}
