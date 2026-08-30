import 'package:drift/drift.dart';
import 'package:mattermost_flutter/src/data/database/open_database_stub.dart'
    if (dart.library.io) 'package:mattermost_flutter/src/data/database/open_database_native.dart'
    if (dart.library.js_interop) 'package:mattermost_flutter/src/data/database/open_database_web.dart'
    as platform;

QueryExecutor openDatabaseConnection() => platform.openDatabaseConnection();
