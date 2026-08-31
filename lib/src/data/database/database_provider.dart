import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/data/database/app_database.dart' as db;

final Provider<db.AppDatabase> appDatabaseProvider = Provider<db.AppDatabase>((
  Ref ref,
) {
  final db.AppDatabase database = db.AppDatabase.open();
  ref.onDispose(() => unawaited(database.close()));
  return database;
});
