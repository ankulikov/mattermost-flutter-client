import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/app/app.dart';

void bootstrapMattermostApp() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MattermostApp()));
}
