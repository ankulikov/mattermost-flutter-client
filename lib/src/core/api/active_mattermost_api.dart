import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';

/// Read-only view of the API owned by the active authenticated account.
abstract interface class ActiveMattermostApi {
  MattermostApi? get api;
}
