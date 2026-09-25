import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/app.dart';
import 'package:taskflow/core/api_client.dart';
import 'package:taskflow/state/realtime_controller.dart';

import 'fake_adapter.dart';

class Req {
  Req(this.method, this.path, this.query, this.body);
  final String method;
  final String path;
  final Map<String, String> query;
  final dynamic body;

  @override
  String toString() => '$method $path $query ${body ?? ''}';
}

/// Realtime that never opens a socket.
class FakeRealtime extends RealtimeController {
  @override
  void connect({required String apiBase, required String cookie}) {}
}

String ms(DateTime d) => '${d.millisecondsSinceEpoch}';

Map<String, dynamic> taskRow(
  int id,
  String title, {
  String status = 'IN_PROGRESS',
  int creatorId = 1,
  int? assigneeId = 4,
  String? assigneeName = 'Neha Kapoor',
  DateTime? due,
  String priority = 'NORMAL',
  int commentCount = 0,
  int subtaskCount = 0,
  int subtaskDone = 0,
  int? parentId,
}) =>
    {
      'id': id,
      'title': title,
      'description': 'Description for $title',
      'status': status,
      'priority': priority,
      'creator_id': creatorId,
      'assignee_id': assigneeId,
      'parent_id': parentId,
      'due_at': ms(due ?? DateTime.now().add(const Duration(days: 2))),
      'eta_at': null,
      'created_at': ms(DateTime.now().subtract(const Duration(hours: 3))),
      'sla_deadline_at': ms(DateTime.now().add(const Duration(minutes: 20))),
      'sla_breached_at': null,
      'subtask_count': subtaskCount,
      'subtask_done': subtaskDone,
      'comment_count': commentCount,
      'member_count': 0,
      'escalation_review_pending': false,
      'assignee_name': assigneeName,
      'creator_name': 'Kumar Bibhaw Raj (CTO)',
      'team_name': null,
      'project_name': null,
      'type_name': 'Lead Follow-up',
    };

/// In-memory TMS_BE stand-in. Records every request for assertions.
class FakeBackend {
  FakeBackend({this.role = 'ADMIN', this.userId = 1});

  final String role;
  final int userId;
  final requests = <Req>[];
  bool loggedIn = false;
  int nextId = 100;

  final users = <Map<String, dynamic>>[
    {'id': 1, 'name': 'Kumar Bibhaw Raj (CTO)', 'email': 'admin@rentfoxxy.com', 'phone': null, 'role': 'ADMIN', 'team_id': null, 'is_active': true, 'team_name': null},
    {'id': 4, 'name': 'Neha Kapoor', 'email': 'neha@rentfoxxy.com', 'phone': null, 'role': 'MEMBER', 'team_id': 1, 'is_active': true, 'team_name': 'Sales'},
    {'id': 5, 'name': 'Amit Saxena', 'email': 'amit@rentfoxxy.com', 'phone': '9876543210', 'role': 'MEMBER', 'team_id': 1, 'is_active': true, 'team_name': 'Sales'},
  ];
  final teams = <Map<String, dynamic>>[
    {'id': 1, 'name': 'Sales', 'manager_id': null, 'manager_name': null, 'member_count': 2},
  ];
  final types = <Map<String, dynamic>>[
    {'id': 1, 'team_id': 1, 'name': 'Lead Follow-up', 'is_active': true, 'team_name': 'Sales', 'used_count': 2},
  ];
  late final tasks = <Map<String, dynamic>>[
    taskRow(1, 'Follow up corporate leads', status: 'ASSIGNED', assigneeId: userId, assigneeName: 'Me'),
    taskRow(2, 'Prepare fleet report', status: 'IN_PROGRESS', assigneeId: userId, assigneeName: 'Me', commentCount: 2, subtaskCount: 2, subtaskDone: 1),
    taskRow(3, 'Refund deposit', status: 'ESCALATED', assigneeId: userId, assigneeName: 'Me', due: DateTime.now().subtract(const Duration(hours: 4))),
    taskRow(4, 'Delegated audit', status: 'DISCUSS', creatorId: userId, assigneeId: 4),
  ];
  final comments = <Map<String, dynamic>>[
    {'id': 1, 'task_id': 2, 'author_id': 4, 'parent_comment_id': null, 'content': 'Draft is ready', 'author_name': 'Neha Kapoor', 'edited': false, 'created_at': '1790000000000', 'reactions': []},
  ];
  final notifications = <Map<String, dynamic>>[
    {'id': 1, 'type': 'ASSIGNED', 'title': 'New task: Follow up corporate leads', 'body': 'Assigned by CEO', 'task_id': 1, 'read_at': null, 'created_at': '1790000000000'},
    {'id': 2, 'type': 'COMMENT', 'title': 'Neha commented', 'body': null, 'task_id': 2, 'read_at': '1790000000001', 'created_at': '1790000000000'},
  ];
  final projects = <Map<String, dynamic>>[
    {'id': 1, 'name': 'Corporate Expansion Q3', 'description': 'Grow corporate rentals', 'owner_id': 1, 'owner_name': 'CEO', 'created_at': '1790000000000', 'member_count': 3, 'open_tasks': 2},
  ];
  final messages = <Map<String, dynamic>>[
    {'id': 1, 'conversation_id': 7, 'author_id': 4, 'author_name': 'Neha Kapoor', 'parent_message_id': null, 'body': 'Hi! see [Tap to view](/tasks/2)', 'edited': false, 'edited_at': null, 'deleted_at': null, 'created_at': ms(DateTime.now()), 'reactions': [], 'attachments': []},
  ];
  Map<String, dynamic> get conversation => {
        'id': 7,
        'kind': 'direct',
        'name': null,
        'member_user_id': 4,
        'member_name': 'Neha Kapoor',
        'member_email': 'neha@rentfoxxy.com',
        'member_role': 'MEMBER',
        'last_message_at': ms(DateTime.now()),
        'last_message_preview': messages.last['body'],
      };

  Map<String, dynamic> get me => {'id': userId, 'name': 'Kumar Bibhaw Raj (CTO)', 'email': 'admin@rentfoxxy.com', 'role': role, 'team_id': role == 'MANAGER' ? 1 : null, 'team': null};

  Map<String, dynamic> permissions(Map<String, dynamic> t) {
    final assignee = t['assignee_id'] == userId;
    final s = t['status'];
    return {
      'canComment': true,
      'canManageMembers': true,
      'canAcknowledge': assignee && s == 'ASSIGNED',
      'canDiscuss': assignee && s == 'ASSIGNED',
      'canReject': assignee && s == 'ASSIGNED',
      'canStart': assignee && s == 'ACKNOWLEDGED',
      'canDone': s == 'IN_PROGRESS' || s == 'ACKNOWLEDGED',
      'canEditEta': assignee && s == 'IN_PROGRESS',
      'canCancel': true,
      'canBlock': assignee && s == 'IN_PROGRESS',
      'canAddSubtask': t['parent_id'] == null,
      'canViewActivity': true,
      'mustExplain': assignee && s == 'ESCALATED',
    };
  }

  List<Req> where(String method, String path) => requests.where((r) => r.method == method && r.path == path).toList();
  Req last(String method, String path) => where(method, path).last;

  late final Dio dio = fakeDio((req) async {
    final path = req.uri.path.replaceFirst('/api', '');
    final body = jsonBody(req);
    requests.add(Req(req.method, path, req.uri.queryParameters, body));
    final res = _handle(req.method, path, req.uri.queryParameters, body);
    return FakeResponse(res.$1, res.$2);
  });

  (int, Object) _handle(String method, String path, Map<String, String> q, dynamic body) {
    ok(Object o) => (200, o);
    if (path == '/auth/login') {
      if (body['password'] != 'password123') return (401, {'error': 'Invalid email or password'});
      loggedIn = true;
      return ok({'ok': true, 'accessToken': 'acc', 'refreshToken': 'ref', 'user': me});
    }
    if (path == '/auth/logout') return ok({'ok': true});
    if (path == '/auth/forgot-password') return ok({'message': 'Code sent if the account exists.'});
    if (path == '/auth/reset-password') return ok({'ok': true});
    if (!loggedIn) return (401, {'error': 'Please authenticate'});

    switch ((method, path)) {
      case ('GET', '/me'):
        return ok({'user': me, 'unread': notifications.where((n) => n['read_at'] == null).length});
      case ('GET', '/users'):
        return ok({'users': users});
      case ('POST', '/users'):
        users.add({'id': nextId++, ...body, 'team_id': body['teamId'], 'is_active': true, 'team_name': null});
        return ok({'id': nextId});
      case ('PATCH', '/users'):
        return ok({'ok': true});
      case ('GET', '/teams'):
        return ok({'teams': teams});
      case ('GET', '/task-types'):
        return ok({'types': types});
      case ('POST', '/task-types'):
        types.add({'id': nextId++, 'team_id': body['teamId'], 'name': body['name'], 'is_active': true, 'team_name': 'Sales', 'used_count': 0});
        return ok({'ok': true});
      case ('GET', '/tasks'):
        var list = tasks.where((t) => t['parent_id'] == null).toList();
        final status = q['status'] ?? '';
        if (status.isEmpty) list = list.where((t) => t['status'] != 'DONE').toList();
        if (status.isNotEmpty && status != 'all') list = list.where((t) => t['status'] == status).toList();
        if (q['filter'] == 'mine') list = list.where((t) => t['assignee_id'] == userId).toList();
        if (q['filter'] == 'created') list = list.where((t) => t['creator_id'] == userId).toList();
        final search = q['q'];
        if (search != null) list = list.where((t) => (t['title'] as String).toLowerCase().contains(search.toLowerCase())).toList();
        final limit = int.parse(q['limit'] ?? '25');
        final page = int.parse(q['page'] ?? '1');
        final total = list.length;
        final slice = list.skip((page - 1) * limit).take(limit).toList();
        return ok({'tasks': slice, 'pagination': {'page': page, 'limit': limit, 'total': total, 'totalPages': (total / limit).ceil().clamp(1, 999)}});
      case ('POST', '/tasks'):
        final lines = body['multiple'] == true ? List<String>.from(body['lines']) : [body['title'] as String];
        final ids = <int>[];
        for (final l in lines) {
          final id = nextId++;
          ids.add(id);
          tasks.add(taskRow(id, l, status: 'ASSIGNED', creatorId: userId, assigneeId: body['assigneeId'], parentId: body['parentId']));
        }
        return ok({'ids': ids});
      case ('GET', '/notifications'):
        return ok({'notifications': notifications});
      case ('POST', '/notifications'):
        for (final n in notifications) {
          if (body['all'] == true || (body['ids'] as List?)?.contains(n['id']) == true) n['read_at'] = '1790000000009';
        }
        return ok({'ok': true});
      case ('POST', '/notifications/clear'):
        notifications.clear();
        return ok({'ok': true});
      case ('GET', '/projects'):
        return ok({'projects': projects});
      case ('POST', '/projects'):
        projects.add({'id': nextId++, 'name': body['name'], 'description': body['description'], 'owner_id': userId, 'owner_name': 'Me', 'member_count': 1, 'open_tasks': 0});
        return ok({'ok': true});
      case ('GET', '/reports'):
        if (q['list'] != null) return ok({'tasks': tasks.take(2).toList()});
        return ok({
          'summary': {'open': 4, 'overdue': 1, 'noResponse': 2, 'escalatedAwaiting': 1, 'escalatedPendingReview': 0, 'dueThisWeek': 3, 'done': 5, 'onTimePct': 80, 'avgResponseMin': 12},
          'people': [
            {'id': 4, 'name': 'Neha Kapoor', 'role': 'MEMBER', 'team_name': 'Sales', 'open': 2, 'overdue': 1, 'no_response': 0, 'escalations': 1, 'done': 4, 'done_ontime': 3, 'avg_response_min': 9},
          ],
          'byType': [
            {'id': 1, 'name': 'Lead Follow-up', 'team_name': 'Sales', 'total': 5, 'open': 2, 'overdue': 1, 'no_response': 0, 'done': 3},
          ],
          'scope': role,
        });
      case ('GET', '/chat/targets'):
        return ok({'targets': users.where((u) => u['id'] != userId).map((u) => {...u, 'conversation_id': u['id'] == 4 ? 7 : null}).toList()});
      case ('GET', '/chat/conversations'):
        return ok({'conversations': [conversation]});
      case ('POST', '/chat/open'):
        return ok({'conversation': conversation, 'messages': messages});
      case ('GET', '/chat/conversations/7/messages'):
        return ok({'conversation': conversation, 'messages': messages});
      case ('POST', '/chat/conversations/7/messages'):
        final m = {
          'id': nextId++,
          'conversation_id': 7,
          'author_id': userId,
          'author_name': 'Me',
          'parent_message_id': body['parentMessageId'],
          'body': body['body'],
          'edited': false,
          'deleted_at': null,
          'created_at': ms(DateTime.now()),
          'reactions': [],
          'attachments': [],
        };
        messages.add(m);
        return ok({'message': m, 'conversation': conversation});
      case ('GET', '/boards'):
        return ok({'boards': []});
    }

    final taskMatch = RegExp(r'^/tasks/(\d+)$').firstMatch(path);
    if (taskMatch != null) {
      final id = int.parse(taskMatch.group(1)!);
      final t = tasks.firstWhere((t) => t['id'] == id);
      if (method == 'GET') {
        return ok({
          'task': t,
          'members': [],
          'subtasks': tasks.where((s) => s['parent_id'] == id).toList(),
          'activity': [
            {'id': 1, 'type': 'CREATED', 'actor_name': 'CEO', 'meta': '{}', 'created_at': '1790000000000'},
          ],
          'attachments': [],
          'escalation': null,
          'batchTasks': [],
          'permissions': permissions(t),
        });
      }
      if (method == 'PATCH') {
        final action = body['action'];
        t['status'] = switch (action) {
          'acknowledge' => 'ACKNOWLEDGED',
          'start' => 'IN_PROGRESS',
          'done' => 'DONE',
          'cancel' => 'CANCELLED',
          'discuss' => 'DISCUSS',
          _ => t['status'],
        };
        return ok({'ok': true});
      }
      if (method == 'DELETE') {
        tasks.remove(t);
        return ok({'ok': true});
      }
    }
    final commentsMatch = RegExp(r'^/tasks/(\d+)/comments$').firstMatch(path);
    if (commentsMatch != null) {
      final id = int.parse(commentsMatch.group(1)!);
      if (method == 'POST') {
        comments.add({'id': nextId++, 'task_id': id, 'author_id': userId, 'parent_comment_id': body['parentCommentId'], 'content': body['content'], 'author_name': 'Me', 'edited': false, 'created_at': ms(DateTime.now()), 'reactions': []});
      }
      return ok({'comments': comments.where((c) => c['task_id'] == id).toList()});
    }
    if (RegExp(r'^/tasks/\d+/comments/\d+/reactions$').hasMatch(path)) return ok({'ok': true});
    if (path == '/tasks/template-data') return ok({});
    return (404, {'error': 'Not found: $method $path'});
  }
}

const phone = Size(390, 844);
const desktop = Size(1280, 860);

/// Boots the full app against [backend] with the given screen size.
Future<void> bootApp(WidgetTester tester, FakeBackend backend, {Size size = phone, bool signedIn = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = MemoryTokenStore();
  if (signedIn) {
    backend.loggedIn = true;
    store
      ..access = 'acc'
      ..refresh = 'ref';
  }
  registerDependencies(
    client: ApiClient(baseUrl: 'http://fake/api', dio: backend.dio, store: store),
    realtime: FakeRealtime(),
    pollInterval: Duration.zero,
  );
  await tester.pumpWidget(const TaskFlowApp());
  await tester.pumpAndSettle();
}

/// Unmounts the app so periodic timers are cancelled before the test ends.
Future<void> teardownApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}
