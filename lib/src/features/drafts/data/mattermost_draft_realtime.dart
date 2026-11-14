import 'package:mattermost_flutter/src/data/realtime/session_realtime_service.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft_realtime.dart';

final class MattermostDraftRealtime implements DraftRealtime {
  MattermostDraftRealtime(this._realtime);
  final SessionRealtimeService _realtime;

  @override
  Stream<DraftRealtimeChange> watch(AuthSession session) => _realtime
      .watch(
        session: session,
        subscription: const SessionRealtimeSubscription(
          eventNames: {
            'draft_created',
            'draft_updated',
            'draft_deleted',
            'preference_changed',
            'preferences_changed',
            'preferences_deleted',
          },
        ),
      )
      .where(
        (signal) =>
            signal is SessionRealtimeEventReceived ||
            signal is SessionRealtimeRecoveryRequired,
      )
      .map((signal) {
        if (signal is SessionRealtimeRecoveryRequired) {
          return DraftRealtimeChange.recovery;
        }
        final event = (signal as SessionRealtimeEventReceived).event;
        return event.name.startsWith('preference')
            ? DraftRealtimeChange.preferences
            : DraftRealtimeChange.drafts;
      });
}
