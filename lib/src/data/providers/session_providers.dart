import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/data/api/active_mattermost_api.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/session/active_account_context.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';

/// Owns the current account transport for the lifetime of the provider scope.
///
/// It is deliberately data-owned: no presentation controller participates in
/// constructing, replacing, or closing the API client.
final Provider<ActiveAccountContext> activeAccountContextProvider =
    Provider<ActiveAccountContext>((Ref ref) {
      final ActiveAccountContext context = ActiveAccountContext(
        onChanged: () => ref.invalidate(activeMattermostApiProvider),
      );
      ref.onDispose(context.dispose);
      return context;
    });

final Provider<ActiveMattermostApi> activeMattermostApiSourceProvider =
    Provider<ActiveMattermostApi>(
      (Ref ref) => ref.watch(activeAccountContextProvider),
    );

/// Authenticated raw transport. Cache and entity policy belong to repositories.
final Provider<MattermostApi> activeMattermostApiProvider =
    Provider<MattermostApi>((Ref ref) {
      final AuthSession? session = ref.watch(
        activeAccountContextProvider.select(
          (ActiveAccountContext context) => context.session,
        ),
      );
      final MattermostApi? api = ref
          .watch(activeMattermostApiSourceProvider)
          .api;
      if (session == null || api == null) {
        throw StateError('No API client for the active Mattermost account');
      }
      return api;
    });
