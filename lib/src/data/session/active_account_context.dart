import 'package:mattermost_flutter/src/data/api/active_mattermost_api.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';

/// Atomically owns the authenticated account snapshot and its closeable
/// transport. UI observes [session] through providers but never constructs API
/// clients or receives credentials.
final class ActiveAccountContext implements ActiveMattermostApi {
  ActiveAccountContext({void Function()? onChanged}) : _onChanged = onChanged;

  MattermostApiClient? _client;
  AuthSession? _session;
  final void Function()? _onChanged;

  AuthSession? get session => _session;

  @override
  MattermostApi? get api => _client?.api;

  void activate({
    required MattermostApiClient client,
    required AuthSession session,
  }) {
    final MattermostApiClient? previous = _client;
    _client = client;
    _session = session;
    previous?.close();
    _onChanged?.call();
  }

  void deactivate() {
    final MattermostApiClient? previous = _client;
    _client = null;
    _session = null;
    previous?.close();
    _onChanged?.call();
  }

  void dispose() => deactivate();
}
