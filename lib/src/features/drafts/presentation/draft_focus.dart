import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A one-shot channel composer focus request issued by the Drafts Edit action.
final class DraftFocusRequest extends Notifier<String?> {
  @override
  String? build() => null;

  void request(String channelId) => state = channelId;
  void clear(String channelId) {
    if (state == channelId) state = null;
  }
}

final NotifierProvider<DraftFocusRequest, String?> draftFocusRequestProvider =
    NotifierProvider<DraftFocusRequest, String?>(DraftFocusRequest.new);
