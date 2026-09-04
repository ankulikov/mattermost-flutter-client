import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';

abstract class PostponedRepository {
  const PostponedRepository();

  Future<PostponedReferencesSnapshot> load({required AuthSession session});

  Future<void> save({
    required AuthSession session,
    required List<PostponedReference> references,
  });

  Future<void> remove({
    required AuthSession session,
    required List<PostponedReference> references,
  });
}
