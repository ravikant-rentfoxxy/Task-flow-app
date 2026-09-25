import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'core/api_client.dart';
import 'core/local_store.dart';
import 'data/taskflow_api.dart';
import 'features/auth/login_screen.dart';
import 'features/shell/home_shell.dart';
import 'state/auth_controller.dart';
import 'state/chat_unread_controller.dart';
import 'state/realtime_controller.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';

/// Registers the app's services and controllers with GetX.
/// Tests pass their own [ApiClient] (fake Dio adapter) and [RealtimeController].
void registerDependencies({
  required ApiClient client,
  LocalStore? store,
  RealtimeController? realtime,
  Duration pollInterval = const Duration(seconds: 30),
}) {
  Get.reset();
  final api = Get.put(TaskFlowApi(client), permanent: true);
  Get.put(AuthController(api, store: store, pollInterval: pollInterval), permanent: true);
  Get.put(realtime ?? RealtimeController(), permanent: true);
  Get.put(ChatUnreadController(store: store), permanent: true).load();
}

class TaskFlowApp extends StatefulWidget {
  const TaskFlowApp({super.key});

  @override
  State<TaskFlowApp> createState() => _TaskFlowAppState();
}

class _TaskFlowAppState extends State<TaskFlowApp> {
  @override
  void initState() {
    super.initState();
    Get.find<AuthController>().init();
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'TaskFlow',
      debugShowCheckedModeBanner: false,
      theme: TF.theme(),
      themeMode: ThemeMode.light,
      scaffoldMessengerKey: messengerKey,
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    return Obx(() => AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: switch (auth.status) {
            AuthStatus.unknown => const Scaffold(key: ValueKey('splash'), body: Center(child: CircularProgressIndicator())),
            AuthStatus.signedOut => const LoginScreen(key: ValueKey('login')),
            AuthStatus.signedIn => const HomeShell(key: ValueKey('home')),
          },
        ));
  }
}
