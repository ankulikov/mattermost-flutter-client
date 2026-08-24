import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

QueryExecutor openDatabaseConnection() => LazyDatabase(() async {
  final Directory directory = await getApplicationSupportDirectory();
  final File file = File(path.join(directory.path, 'mattermost.sqlite'));
  return NativeDatabase.createInBackground(file);
});
