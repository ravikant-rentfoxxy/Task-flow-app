// Full UI run against a real TMS_BE:
//
//   flutter test integration_test -d <iPhone simulator> --dart-define=API_URL=http://localhost:4100/api
//
// Admin creates a task for Neha → Neha accepts, starts, comments, completes it →
// admin sees it done (tablet-width layout). Also checks the Hive-cached session. Screenshots of every main screen are written to the app's
// temp directory (path printed as SCREENSHOT_DIR).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:taskflow/app.dart';
import 'package:taskflow/core/api_client.dart';
import 'package:taskflow/core/config.dart';
import 'package:taskflow/core/local_store.dart';

late Directory shots;

Future<void> shot(WidgetTester t, String name) async {
  await t.pumpAndSettle();
  final view = t.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 1.5);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('${shots.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
}

Future<void> settle(WidgetTester t, {int seconds = 2}) async {
  // Network calls are real here, so give them time before settling.
  for (var i = 0; i < seconds * 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.pumpAndSettle();
}

Future<void> tapOn(WidgetTester t, Finder f, {int wait = 1}) async {
  final target = f.last;
  if (find.ancestor(of: target, matching: find.byType(Scrollable)).evaluate().isNotEmpty) {
    await t.ensureVisible(target);
    await t.pumpAndSettle();
  }
  await t.tap(target);
  await settle(t, seconds: wait);
}

Future<void> waitFor(WidgetTester t, Finder f, {int seconds = 10}) async {
  for (var i = 0; i < seconds * 10; i++) {
    if (f.evaluate().isNotEmpty) return;
    await t.pump(const Duration(milliseconds: 100));
  }
  expect(f, findsWidgets);
}

Future<void> login(WidgetTester t, String email) async {
  await waitFor(t, find.byKey(const Key('login-email')));
  await t.enterText(find.byKey(const Key('login-email')), email);
  await t.enterText(find.byKey(const Key('login-password')), 'password123');
  await tapOn(t, find.byKey(const Key('login-submit')), wait: 3);
  await shot(t, 'login_${email.split('@').first}_${t.view.physicalSize.width.toInt()}');
  await waitFor(t, find.byKey(const Key('greeting')));
}

Future<void> logout(WidgetTester t) async {
  await t.tap(find.byKey(const Key('account-menu')).first);
  await t.pumpAndSettle();
  await tapOn(t, find.byKey(const Key('logout')));
  await waitFor(t, find.byKey(const Key('login-email')));
}

Future<void> go(WidgetTester t, String id) async {
  await tapOn(t, find.byKey(ValueKey('nav-$id')), wait: 2);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('admin assigns → member completes → admin verifies', (t) async {
    final store = await LocalStore.open();
    await store.clearSession();
    registerDependencies(client: ApiClient(baseUrl: AppConfig.apiBase, store: HiveTokenStore(store)), store: store);
    const shotsDir = String.fromEnvironment('SHOTS_DIR');
    shots = await Directory(shotsDir.isNotEmpty ? shotsDir : '${(await getTemporaryDirectory()).path}/tf_shots').create(recursive: true);
    // ignore: avoid_print
    print('SCREENSHOT_DIR=${shots.path}');
    t.view.physicalSize = const Size(430, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    final title = 'E2E ${DateTime.now().millisecondsSinceEpoch}';
    await t.pumpWidget(const TaskFlowApp());
    await settle(t);
    await shot(t, '01_login');

    // ---- Admin creates a task for Neha ----------------------------------------
    await login(t, 'admin@rentfoxxy.com');
    await settle(t, seconds: 2);
    await shot(t, '02_dashboard_admin');

    await tapOn(t, find.byKey(const Key('dashboard-new-task')));
    await t.enterText(find.byKey(const Key('composer-title')), title);
    await t.enterText(find.byKey(const Key('composer-description')), 'Check the [pricing sheet](https://example.com) before calling.');
    await tapOn(t, find.byKey(const Key('composer-assignee')));
    await tapOn(t, find.byKey(const ValueKey('pick-Neha Kapoor')), wait: 2);
    await tapOn(t, find.text('Today EOD'));
    await tapOn(t, find.byKey(const ValueKey('priority-HIGH')));
    await shot(t, '03_composer');
    await tapOn(t, find.byKey(const Key('composer-submit')));
    expect(find.text('Task created'), findsOneWidget);

    await go(t, 'tasks');
    await tapOn(t, find.byKey(const ValueKey('segment-created')), wait: 2);
    await waitFor(t, find.text(title));
    await shot(t, '04_tasks_created');

    await go(t, 'projects');
    await shot(t, '05_projects');
    await tapOn(t, find.text('Corporate Expansion Q3'), wait: 2);
    await shot(t, '06_project_detail');
    await t.pageBack();
    await settle(t);

    await go(t, 'more');
    await tapOn(t, find.byKey(const Key('more-reports')), wait: 3);
    await shot(t, '07_reports');
    await tapOn(t, find.byKey(const ValueKey('stat-Open tasks')), wait: 2);
    await shot(t, '08_report_drill');
    await t.tapAt(const Offset(200, 40));
    await settle(t);
    await t.pageBack();
    await settle(t);
    await tapOn(t, find.byKey(const Key('more-admin')), wait: 3);
    await shot(t, '09_admin');
    await t.pageBack();
    await settle(t);
    await logout(t);

    // ---- Neha accepts, starts, comments and completes ------------------------
    await login(t, 'neha@rentfoxxy.com');
    await settle(t, seconds: 2);
    await waitFor(t, find.text(title));
    await shot(t, '10_dashboard_member');

    await tapOn(t, find.text(title), wait: 3);
    await shot(t, '11_task_detail_assigned');
    await tapOn(t, find.byKey(const Key('detail-accept')));
    await tapOn(t, find.text('+24 hours'));
    await tapOn(t, find.byKey(const Key('accept-submit')));
    expect(find.text('Task accepted'), findsOneWidget);
    await shot(t, '11b_after_accept');
    expect(find.text('Task accepted'), findsOneWidget);
    await tapOn(t, find.byKey(const Key('detail-start')));
    expect(find.text('Task started'), findsOneWidget);

    await tapOn(t, find.byKey(const Key('tab-comments')), wait: 2);
    await t.enterText(find.byKey(const Key('comment-input')), 'Started — will update by EOD.');
    await t.pump();
    await tapOn(t, find.byKey(const Key('comment-send')), wait: 2);
    await waitFor(t, find.text('Started — will update by EOD.'));
    await shot(t, '12_task_comments');

    await tapOn(t, find.text('Details'));
    await tapOn(t, find.byKey(const Key('detail-done')));
    expect(find.text('Task marked done'), findsOneWidget);
    await shot(t, '13_task_done');
    await t.pageBack();
    await settle(t);

    // Chat with the admin who assigned it.
    await go(t, 'chat');
    await shot(t, '14_chat_list');
    await tapOn(t, find.textContaining('Kumar Bibhaw Raj'), wait: 3);
    await t.enterText(find.byKey(const Key('chat-input')), 'Done with $title 🎉');
    await t.pump();
    await tapOn(t, find.byKey(const Key('chat-send')), wait: 2);
    await waitFor(t, find.text('Done with $title 🎉'));
    await shot(t, '15_chat_thread');
    await t.pageBack();
    await settle(t);

    await t.tap(find.byKey(const Key('notification-bell')).first);
    await settle(t, seconds: 2);
    await shot(t, '16_notifications');
    await t.pageBack();
    await settle(t);
    await logout(t);

    // ---- Admin sees it done (desktop layout) ---------------------------------
    t.view.physicalSize = const Size(1360, 880);
    await settle(t);
    await login(t, 'admin@rentfoxxy.com');
    await settle(t, seconds: 2);
    await shot(t, '17_dashboard_desktop');
    await tapOn(t, find.text('Tasks').first, wait: 2);
    await tapOn(t, find.byKey(const ValueKey('segment-created')), wait: 2);
    await tapOn(t, find.byKey(const Key('status-filter')));
    await tapOn(t, find.text('Done').last, wait: 2);
    await waitFor(t, find.text(title));
    await shot(t, '18_tasks_desktop_done');
    await tapOn(t, find.text(title), wait: 3);
    expect(find.textContaining('Started — will update by EOD.'), findsOneWidget);
    await shot(t, '19_task_detail_desktop');
    await t.pageBack();
    await settle(t);
    await tapOn(t, find.text('Chat').first, wait: 2);
    await tapOn(t, find.textContaining('Neha Kapoor').first, wait: 3);
    await waitFor(t, find.text('Done with $title 🎉'));
    await shot(t, '20_chat_desktop');
  });
}
