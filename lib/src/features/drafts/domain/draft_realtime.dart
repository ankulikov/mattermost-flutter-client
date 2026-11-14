import 'package:mattermost_flutter/src/domain/models/auth_session.dart';

enum DraftRealtimeChange { drafts, preferences, recovery }

abstract interface class DraftRealtime {
  Stream<DraftRealtimeChange> watch(AuthSession session);
}
