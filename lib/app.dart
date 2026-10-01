import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'core/api_client.dart';
import 'core/local_store.dart';
import 'data/taskflow_api.dart';
import 'features/auth/login_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/splash/splash_screen.dart';
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
      title: 'Work Plus',
      debugShowCheckedModeBanner: false,
      theme: TF.theme(),
      themeMode: ThemeMode.light,
      scaffoldMessengerKey: messengerKey,
      home: const _AuthGate(),
    );
  }
}

/// Splash until the session is restored and the intro has played, then login or home.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  /// Long enough for the splash intro animation to finish.
  static const minSplash = Duration(milliseconds: 1600);

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _introDone = false;
  late final Timer _timer = Timer(_AuthGate.minSplash, () {
    if (mounted) setState(() => _introDone = true);
  });

  @override
  void initState() {
    super.initState();
    _timer; // start the minimum splash time
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    return Obx(() {
      final status = auth.status; // read first so Obx always subscribes
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: !_introDone || status == AuthStatus.unknown
            ? const SplashScreen(key: ValueKey('splash'))
            : status == AuthStatus.signedIn
                ? const HomeShell(key: ValueKey('home'))
                : const LoginScreen(key: ValueKey('login')),
      );
    });
  }
}
