import 'package:flutter/material.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/config.dart';
import 'core/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LocalStore.open();
  registerDependencies(
    client: ApiClient(baseUrl: AppConfig.apiBase, store: HiveTokenStore(store)),
    store: store,
  );
  runApp(const TaskFlowApp());
}
