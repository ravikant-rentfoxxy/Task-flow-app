// Renders App Store screenshots of the real UI with dummy data, on a simulator
// (real iOS fonts and device size):
//
//   flutter test integration_test/store_screens_test.dart -d "iPhone 17 Pro Max"
//   flutter test integration_test/store_screens_test.dart -d "iPad Pro 13-inch (M5)"
//
// PNGs go to --dart-define=STORE_SHOTS=<dir> (else the app's temp directory).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:taskflow/app.dart';
import 'package:taskflow/core/api_client.dart';
import 'package:taskflow/features/shell/home_shell.dart';

import '../test/support/fake_adapter.dart';
import '../test/support/fake_backend.dart';

DateTime _at(int h, [int m = 0]) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, h, m);
}

/// [FakeBackend] filled with presentable dummy people, tasks and chats.
class DemoBackend extends FakeBackend {
  DemoBackend() : super(role: 'MANAGER', userId: 1) {
    users
      ..clear()
      ..addAll([
        _u(1, 'Alex Morgan', 'MANAGER'),
        _u(2, 'Emma Wilson', 'MEMBER'),
        _u(3, 'Daniel Brooks', 'MEMBER'),
        _u(4, 'Sophia Turner', 'MEMBER'),
        _u(5, 'Michael Chen', 'MEMBER'),
        _u(6, 'Olivia Park', 'MEMBER'),
      ]);
    teams
      ..clear()
      ..add({'id': 1, 'name': 'Design Team', 'manager_id': 1, 'manager_name': 'Alex Morgan', 'member_count': 6});
    types
      ..clear()
      ..add({'id': 1, 'team_id': 1, 'name': 'Design Review', 'is_active': true, 'team_name': 'Design Team', 'used_count': 8});
    tasks
      ..clear()
      ..addAll([
        _t(1, 'Review homepage hero copy', 'ASSIGNED', 'URGENT', creator: 2, due: _at(17)),
        _t(2, 'Approve Q4 campaign budget', 'ASSIGNED', 'HIGH', creator: 5, due: _at(18, 30)),
        _t(3, 'Finalize onboarding plan for client portal', 'IN_PROGRESS', 'HIGH', due: _at(19), comments: 3, subtasks: 4, subDone: 2),
        _t(4, 'Prepare Q4 sales report', 'IN_PROGRESS', 'NORMAL', due: _at(19), comments: 1),
        _t(5, 'Update brand guidelines deck', 'ACKNOWLEDGED', 'NORMAL', due: DateTime.now().add(const Duration(days: 2)), comments: 2),
        _t(6, 'Plan team offsite agenda', 'IN_PROGRESS', 'LOW', due: DateTime.now().add(const Duration(days: 4))),
        _t(7, 'Wireframes for mobile checkout', 'IN_PROGRESS', 'HIGH', assignee: 4, creator: 1, due: DateTime.now().add(const Duration(days: 1))),
        _t(8, 'Customer interview summary', 'ASSIGNED', 'NORMAL', assignee: 3, creator: 1, due: DateTime.now().add(const Duration(days: 3))),
        _t(9, 'Publish release notes', 'DONE', 'NORMAL', due: DateTime.now().subtract(const Duration(hours: 5))),
      ]);
    projects
      ..clear()
      ..addAll([
        _p(1, 'Website Revamp', 'Marketing site refresh', 'Olivia Park', 5, 12),
        _p(2, 'Mobile App 2.0', 'New checkout and onboarding', 'Alex Morgan', 6, 9),
        _p(3, 'Brand Refresh', 'Logo, colours and guidelines', 'Emma Wilson', 4, 5),
        _p(4, 'Q4 Campaign', 'Holiday launch across channels', 'Michael Chen', 3, 7),
      ]);
    notifications
      ..clear()
      ..addAll([
        {'id': 1, 'type': 'ASSIGNED', 'title': 'New task: Review homepage hero copy', 'body': 'Assigned by Emma Wilson', 'task_id': 1, 'read_at': null, 'created_at': ms(DateTime.now())},
        {'id': 2, 'type': 'COMMENT', 'title': 'Michael commented on Prepare Q4 sales report', 'body': null, 'task_id': 4, 'read_at': null, 'created_at': ms(DateTime.now())},
      ]);
    comments
      ..clear()
      ..addAll([
        _c(1, 3, 2, 'Emma Wilson', 'Shared the first draft in the project folder.', 90),
        _c(2, 3, 1, 'Alex Morgan', 'Looks great, let us add the welcome email sequence.', 60),
        _c(3, 3, 5, 'Michael Chen', 'Timeline works for the client. Ship by Friday?', 20),
      ]);
    messages
      ..clear()
      ..addAll([
        _m(1, 2, 'Emma Wilson', 'Morning! Did you get a chance to look at the hero copy?', 42),
        _m(2, 1, 'Alex Morgan', 'Yes, reviewing it now. The headline is strong.', 38),
        _m(3, 2, 'Emma Wilson', 'Great. I also updated the CTA colours to match the brand refresh.', 30),
        _m(4, 1, 'Alex Morgan', 'Perfect, I will approve it before lunch.', 12),
        _m(5, 2, 'Emma Wilson', 'Thanks! Sending the final files over.', 3),
      ]);
  }

  static Map<String, dynamic> _u(int id, String name, String role) => {
    'id': id,
    'name': name,
    'email': '${name.split(' ').first.toLowerCase()}@example.com',
    'phone': null,
    'role': role,
    'team_id': 1,
    'is_active': true,
    'team_name': 'Design Team',
  };

  String _name(int id) => users.firstWhere((u) => u['id'] == id)['name'] as String;

  Map<String, dynamic> _t(int id, String title, String status, String priority,
          {int assignee = 1, int creator = 1, DateTime? due, int comments = 0, int subtasks = 0, int subDone = 0}) =>
      {
        ...taskRow(id, title,
            status: status,
            priority: priority,
            creatorId: creator,
            assigneeId: assignee,
            assigneeName: _name(assignee),
            due: due,
            commentCount: comments,
            subtaskCount: subtasks,
            subtaskDone: subDone),
        'description': 'Align with the team and share the final version in the project folder.',
        'creator_name': _name(creator),
        'team_name': 'Design Team',
        'type_name': 'Design Review',
        'project_name': 'Website Revamp',
        'eta_at': status == 'IN_PROGRESS' ? ms(due ?? _at(19)) : null,
        'sla_deadline_at': ms(DateTime.now().add(const Duration(minutes: 25))),
      };

  static Map<String, dynamic> _p(int id, String name, String desc, String owner, int members, int open) => {
    'id': id,
    'name': name,
    'description': desc,
    'owner_id': 1,
    'owner_name': owner,
    'created_at': ms(DateTime.now().subtract(const Duration(days: 20))),
    'member_count': members,
    'open_tasks': open,
  };

  static Map<String, dynamic> _c(int id, int task, int author, String name, String text, int minsAgo) => {
    'id': id,
    'task_id': task,
    'author_id': author,
    'parent_comment_id': null,
    'content': text,
    'author_name': name,
    'edited': false,
    'created_at': ms(DateTime.now().subtract(Duration(minutes: minsAgo))),
    'reactions': [],
  };

  static Map<String, dynamic> _m(int id, int author, String name, String body, int minsAgo) => {
    'id': id,
    'conversation_id': 7,
    'author_id': author,
    'author_name': name,
    'parent_message_id': null,
    'body': body,
    'edited': false,
    'edited_at': null,
    'deleted_at': null,
    'created_at': ms(DateTime.now().subtract(Duration(minutes: minsAgo))),
    'reactions': [],
    'attachments': [],
  };

  @override
  Map<String, dynamic> get me => {'id': 1, 'name': 'Alex Morgan', 'email': 'alex.morgan@example.com', 'role': 'MANAGER', 'team_id': 1, 'team': 'Design Team'};

  @override
  Map<String, dynamic> get conversation => _conv(7, 2, 'Thanks! Sending the final files over.', 3);

  Map<String, dynamic> _conv(int id, int user, String preview, int minsAgo) => {
    'id': id,
    'kind': 'direct',
    'name': null,
    'member_user_id': user,
    'member_name': _name(user),
    'member_email': users.firstWhere((u) => u['id'] == user)['email'],
    'member_role': users.firstWhere((u) => u['id'] == user)['role'],
    'last_message_at': ms(DateTime.now().subtract(Duration(minutes: minsAgo))),
    'last_message_preview': preview,
  };

  List<Map<String, dynamic>> get conversations => [
    conversation,
    _conv(8, 5, 'Can we sync on the Q4 numbers at 3?', 35),
    _conv(9, 4, 'Wireframes are uploaded for review.', 120),
    {..._conv(10, 3, 'Daniel: Interview notes are in the doc.', 300), 'kind': 'group', 'name': 'Design Team', 'member_count': 6},
    _conv(11, 6, 'Sounds good, thanks!', 1500),
    _conv(12, 3, 'See you at the standup.', 3000),
  ];

  /// Serves the multi-conversation list and real report numbers, everything
  /// else falls through to [FakeBackend].
  @override
  // ignore: overridden_fields
  late final Dio dio = fakeDio((req) async {
    final path = req.uri.path.replaceFirst('/api', '');
    if (loggedIn && req.method == 'GET' && path == '/chat/conversations') {
      return FakeResponse(200, {'conversations': conversations});
    }
    if (loggedIn && req.method == 'GET' && path == '/reports' && req.uri.queryParameters['list'] == null) {
      return FakeResponse(200, {
        'summary': {'open': 18, 'overdue': 2, 'noResponse': 3, 'escalatedAwaiting': 1, 'escalatedPendingReview': 0, 'dueThisWeek': 9, 'done': 42, 'onTimePct': 91, 'avgResponseMin': 11},
        'people': [
          for (final (id, open, over, done, ontime, avg) in [(2, 4, 0, 12, 12, 8), (3, 3, 1, 9, 8, 14), (4, 5, 1, 11, 10, 10), (5, 2, 0, 6, 6, 7), (6, 4, 0, 4, 4, 12)])
            {'id': id, 'name': _name(id), 'role': 'MEMBER', 'team_name': 'Design Team', 'open': open, 'overdue': over, 'no_response': 0, 'escalations': 0, 'done': done, 'done_ontime': ontime, 'avg_response_min': avg},
        ],
        'byType': [
          {'id': 1, 'name': 'Design Review', 'team_name': 'Design Team', 'total': 24, 'open': 8, 'overdue': 1, 'no_response': 1, 'done': 16},
          {'id': 2, 'name': 'Content', 'team_name': 'Design Team', 'total': 18, 'open': 6, 'overdue': 1, 'no_response': 0, 'done': 12},
          {'id': 3, 'name': 'Research', 'team_name': 'Design Team', 'total': 9, 'open': 4, 'overdue': 0, 'no_response': 2, 'done': 5},
        ],
        'scope': 'MANAGER',
      });
    }
    final res = await super.dio.fetch<dynamic>(req.copyWith(validateStatus: (_) => true));
    return FakeResponse(res.statusCode ?? 200, res.data as Object);
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store screens', (t) async {
    final view = t.binding.renderViews.first;
    // --dart-define=STORE_SIZE=<w>x<h>@<dpr> (logical points) renders a display
    // there is no simulator for, e.g. 669x951@3 for the iPhone Duo slot.
    const size = String.fromEnvironment('STORE_SIZE');
    var wide = view.size.width >= 900;
    if (size.isNotEmpty) {
      final m = RegExp(r'^(\d+)x(\d+)@(\d+(?:\.\d+)?)$').firstMatch(size)!;
      final (w, h, dpr) = (double.parse(m[1]!), double.parse(m[2]!), double.parse(m[3]!));
      t.view
        ..devicePixelRatio = dpr
        ..physicalSize = Size(w * dpr, h * dpr)
        ..padding = FakeViewPadding(top: 44 * dpr, bottom: 20 * dpr)
        ..viewPadding = FakeViewPadding(top: 44 * dpr, bottom: 20 * dpr);
      addTearDown(t.view.reset);
      wide = w >= 900;
    }
    // On a simulator the app can write straight to the Mac: pass
    // --dart-define=STORE_SHOTS=/abs/path to collect the files there.
    const out = String.fromEnvironment('STORE_SHOTS');
    final dir = Directory(out.isEmpty ? '${(await getTemporaryDirectory()).path}/store_shots' : out)..createSync(recursive: true);
    // ignore: avoid_print
    print('STORE_SHOTS=${dir.path}');

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.pumpAndSettle();
    }

    Future<void> shot(String name) async {
      // ignore: avoid_print
      print('STORE_SHOT $name');
      await settle();
      final layer = view.debugLayer! as OffsetLayer;
      // The root layer already scales by the device pixel ratio.
      final image = await layer.toImage(Offset.zero & t.view.physicalSize, pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${dir.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    }

    Future<void> boot({required bool signedIn}) async {
      await t.pumpWidget(const SizedBox()); // drop the previous app's state
      await t.pump(const Duration(seconds: 1));
      final backend = DemoBackend();
      final store = MemoryTokenStore();
      if (signedIn) {
        backend.loggedIn = true;
        store
          ..access = 'acc'
          ..refresh = 'ref';
      }
      registerDependencies(
        client: ApiClient(baseUrl: 'http://fake/api', dio: backend.dio, store: store, logRequests: false),
        realtime: FakeRealtime(),
        pollInterval: Duration.zero,
      );
      await t.pumpWidget(const TaskFlowApp());
      await settle();
    }

    void go(String tab) => Get.find<ShellController>().go(tab);

    await boot(signedIn: false);
    await shot('login');
    await t.tap(find.byKey(const Key('reset-password')));
    await shot('forgot_password');

    await boot(signedIn: true);
    await shot('dashboard');
    go('tasks');
    await shot('tasks');
    go('chat');
    await shot('chat');
    await t.tap(find.text('Emma Wilson').hitTestable().first);
    await shot('chat_conversation');
    if (!wide) {
      await t.pageBack();
      await settle();
    }
    go('projects');
    await shot('projects');
    if (wide) {
      go('reports');
      await shot('reports');
    } else {
      // Phones reach Reports from More as a pushed page, without the tab bar.
      go('more');
      await settle();
      await t.tap(find.byKey(const Key('more-reports')));
      await shot('reports');
      await t.pageBack();
      await settle();
    }
    go('tasks');
    await settle();
    final card = find.descendant(of: find.byKey(const ValueKey('tab-tasks')), matching: find.text('Finalize onboarding plan for client portal'));
    await t.ensureVisible(card.first);
    await settle();
    await t.tap(card.first);
    await shot('task_detail');

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
