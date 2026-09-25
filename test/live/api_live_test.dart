// End-to-end contract test of the app's data layer against a real TMS_BE.
//
//   TF_LIVE_API=http://localhost:4100/api flutter test test/live
//
// Uses the seeded demo accounts (password123). Skipped when TF_LIVE_API is unset.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Color, Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/api_client.dart';
import 'package:taskflow/data/taskflow_api.dart';
import 'package:taskflow/features/scribble/scribble_screen.dart';

final base = Platform.environment['TF_LIVE_API'];

Future<TaskFlowApi> signIn(String email) async {
  final api = TaskFlowApi(ApiClient(baseUrl: base!, store: MemoryTokenStore()));
  await api.login(email, 'password123');
  return api;
}

void main() {
  if (base == null) {
    test('live API (set TF_LIVE_API to run)', () {}, skip: 'TF_LIVE_API not set');
    return;
  }

  late TaskFlowApi admin;
  late TaskFlowApi neha;
  late int nehaId;
  final stamp = DateTime.now().millisecondsSinceEpoch;
  DateTime inHours(int h) => DateTime.now().add(Duration(hours: h));

  setUpAll(() async {
    admin = await signIn('admin@rentfoxxy.com');
    neha = await signIn('neha@rentfoxxy.com');
    nehaId = (await neha.me()).me.id;
  });

  test('auth: me, bad login, logout clears tokens', () async {
    final me = await admin.me();
    expect(me.me.role, 'ADMIN');
    expect(me.me.isAdminOrCeo, isTrue);
    await expectLater(
      TaskFlowApi(ApiClient(baseUrl: base!)).login('admin@rentfoxxy.com', 'wrong'),
      throwsA(isA<ApiException>()),
    );
    final temp = await signIn('amit@rentfoxxy.com');
    await temp.logout();
    expect(temp.client.hasSession, isFalse);
    await expectLater(temp.me(), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, '401', isTrue)));
  });

  test('directory: users, teams, task types', () async {
    final users = await admin.users();
    expect(users.map((u) => u.email), contains('neha@rentfoxxy.com'));
    final teams = await admin.teams();
    expect(teams.map((t) => t.name), containsAll(['Sales', 'Support']));
    final salesTypes = await admin.taskTypes(userId: nehaId);
    expect(salesTypes, isNotEmpty);
    expect((await admin.taskTypes(manage: true)).first.teamName, isNotNull);
  });

  test('task lifecycle: create → accept → input loop → done', () async {
    final ids = await admin.createTask(NewTask(
      title: 'Live test $stamp',
      description: 'Created by [flutter](https://flutter.dev) test',
      assigneeId: nehaId,
      priority: 'HIGH',
      dueAt: inHours(48),
    ));
    expect(ids, hasLength(1));
    final id = ids.first;

    var d = await neha.task(id);
    expect(d.task.status, 'ASSIGNED');
    expect(d.permissions.canAcknowledge, isTrue);
    expect(d.task.priority, 'HIGH');

    await neha.taskAction(id, 'acknowledge', {'etaAt': inHours(24).millisecondsSinceEpoch});
    d = await neha.task(id);
    expect(d.task.status, 'ACKNOWLEDGED');
    expect(d.task.etaAt, isNotNull);

    await neha.taskAction(id, 'start');
    expect((await neha.task(id)).task.status, 'IN_PROGRESS');

    await neha.taskAction(id, 'update_eta', {'etaAt': inHours(30).millisecondsSinceEpoch});
    expect((await admin.task(id)).activity.any((a) => a.type == 'ETA_CHANGED'), isTrue);

    await neha.taskAction(id, 'request_input', {'inputRequestNote': 'Need the SMTP credentials please'});
    d = await admin.task(id);
    expect(d.task.status, 'WAITING_FOR_INPUT');
    expect(d.permissions.canProvideInput, isTrue);

    await admin.taskAction(id, 'provide_input', {'inputPayload': 'SMTP_HOST=smtp.example.com'});
    d = await neha.task(id);
    expect(d.task.status, 'INPUT_PROVIDED');
    expect(d.permissions.canResumeAfterInput, isTrue);
    expect(d.task.inputPayload, contains('SMTP_HOST'));

    await neha.taskAction(id, 'resume_after_input');
    await neha.taskAction(id, 'block', {'reason': 'Waiting on vendor'});
    expect((await admin.task(id)).task.isBlocked, isTrue);
    await neha.taskAction(id, 'unblock');
    expect((await admin.task(id)).task.isBlocked, isFalse);

    await neha.taskAction(id, 'done');
    d = await admin.task(id);
    expect(d.task.status, 'DONE');
    expect(d.permissions.canReopen, isTrue);

    await admin.taskAction(id, 'reopen', {'reason': 'Missed one item'});
    d = await admin.task(id);
    expect(d.task.status, isNot('DONE'));
    expect(d.task.reopenCount, 1);

    await admin.taskAction(id, 'cancel', {'reason': 'No longer needed'});
    expect((await admin.task(id)).task.status, 'CANCELLED');
  });

  test('discuss, reject, reassign, members, delete', () async {
    final id = (await admin.createTask(NewTask(title: 'Discuss $stamp', assigneeId: nehaId, dueAt: inHours(10)))).first;
    await neha.taskAction(id, 'discuss', {'reason': 'Scope unclear'});
    var d = await admin.task(id);
    expect(d.task.status, 'DISCUSS');
    expect(d.task.discussReason, 'Scope unclear');

    final amit = (await admin.users()).firstWhere((u) => u.email == 'amit@rentfoxxy.com');
    await admin.taskAction(id, 'reassign', {'assigneeId': amit.id});
    d = await admin.task(id);
    expect(d.task.assigneeId, amit.id);
    expect(d.task.status, 'ASSIGNED');

    await admin.taskAction(id, 'add_member', {'userId': nehaId, 'role': 'WATCHER'});
    d = await admin.task(id);
    expect(d.members.single.userId, nehaId);
    expect((await neha.task(id)).permissions.canComment, isFalse, reason: 'watchers are read-only');
    await admin.taskAction(id, 'remove_member', {'userId': nehaId});
    expect((await admin.task(id)).members, isEmpty);

    final rej = (await admin.createTask(NewTask(title: 'Reject $stamp', assigneeId: nehaId, dueAt: inHours(10)))).first;
    await neha.taskAction(rej, 'reject', {'reason': 'Not my area'});
    expect((await admin.task(rej)).task.status, 'REJECTED');

    await admin.deleteTask(id);
    await expectLater(admin.task(id), throwsA(isA<ApiException>()));
  });

  test('subtasks, multiple tasks, open-subtask override', () async {
    final parent = (await admin.createTask(NewTask(title: 'Parent $stamp', assigneeId: nehaId, dueAt: inHours(20)))).first;
    final subs = await admin.createTask(NewTask(parentId: parent, assigneeId: nehaId, dueAt: inHours(20), multiple: true, lines: ['Sub A', 'Sub B']));
    expect(subs, hasLength(2));
    var d = await admin.task(parent);
    expect(d.subtasks.map((s) => s.title), ['Sub A', 'Sub B']);

    await admin.taskAction(subs.first, 'done');
    d = await admin.task(parent);
    expect(d.subtasks.where((s) => s.status == 'DONE'), hasLength(1));

    try {
      await admin.taskAction(parent, 'done');
      fail('expected OPEN_SUBTASKS');
    } on ApiException catch (e) {
      expect(e.code, 'OPEN_SUBTASKS');
    }
    await admin.taskAction(parent, 'done', {'overrideReason': 'Closing from test'});
    expect((await admin.task(parent)).task.status, 'DONE');

    final many = await admin.createTask(NewTask(assigneeId: nehaId, dueAt: inHours(5), multiple: true, lines: ['M1 $stamp', 'M2 $stamp', 'M3 $stamp']));
    expect(many, hasLength(3));
  });

  test('team assignment, filters and pagination', () async {
    final sales = (await admin.teams()).firstWhere((t) => t.name == 'Sales');
    final ids = await admin.createTask(NewTask(title: 'Team task $stamp', teamId: sales.id, dueAt: inHours(3)));
    final page = await admin.tasks(TaskQuery(filter: 'all', teamId: sales.id, q: 'Team task $stamp', status: 'all'));
    expect(page.tasks.map((t) => t.id), contains(ids.first));
    expect(page.tasks.first.teamName, 'Sales');

    final mine = await neha.tasks(const TaskQuery(filter: 'mine', limit: 2));
    expect(mine.tasks.length, lessThanOrEqualTo(2));
    expect(mine.pagination.totalPages, greaterThanOrEqualTo(1));

    final today = await admin.tasks(TaskQuery(filter: 'all', dueFrom: DateTime.now().millisecondsSinceEpoch, dueTo: inHours(4).millisecondsSinceEpoch));
    expect(today.tasks.every((t) => t.dueAt!.isBefore(inHours(5))), isTrue);

    await expectLater(neha.tasks(TaskQuery(filter: 'all', teamId: sales.id)), throwsA(isA<ApiException>()));
  });

  test('comments: add, reply, edit, react', () async {
    final id = (await admin.createTask(NewTask(title: 'Comments $stamp', assigneeId: nehaId, dueAt: inHours(10)))).first;
    await admin.addComment(id, 'First!');
    var list = await neha.comments(id);
    await neha.addComment(id, 'Reply here', parentId: list.single.id);
    list = await admin.comments(id);
    expect(list.firstWhere((c) => c.content == 'Reply here').parentId, list.first.id);

    await admin.editComment(id, list.first.id, 'First (edited)');
    await neha.toggleCommentReaction(id, list.first.id, '👍');
    list = await admin.comments(id);
    final first = list.firstWhere((c) => c.id == list.first.id);
    expect(first.content, 'First (edited)');
    expect(first.edited, isTrue);
    expect(first.reactions.single.emoji, '👍');
    expect((await admin.tasks(TaskQuery(filter: 'created', q: 'Comments $stamp'))).tasks.single.commentCount, 2);
  });

  test('escalation: explain and review', () async {
    final id = (await admin.createTask(NewTask(title: 'Escalate $stamp', assigneeId: nehaId, dueAt: DateTime.now().add(const Duration(seconds: 2))))).first;
    await neha.taskAction(id, 'acknowledge', {'etaAt': DateTime.now().add(const Duration(seconds: 2)).millisecondsSinceEpoch});
    await Future<void>.delayed(const Duration(seconds: 4));
    // Force the backend SLA/escalation sweep (normally throttled to once a minute).
    final cronSecret = Platform.environment['TF_CRON_SECRET'] ?? 'TF_CRON_k8mP2xQ4nR8vL3wJ6hT9yB5';
    await admin.client.get('/cron/sla-check', query: {'secret': cronSecret});
    var d = await neha.task(id);
    expect(d.task.status, 'ESCALATED');
    expect(d.permissions.mustExplain, isTrue);

    await neha.submitEscalationExplanation(id, 'Vendor delayed the shipment by two days.', inHours(48));
    d = await admin.task(id);
    expect(d.escalation?.explanation, contains('Vendor'));
    expect(d.permissions.canReview, isTrue);
    await admin.reviewEscalation(id, 'ACCEPTED');
    d = await admin.task(id);
    expect(d.task.status, isNot('ESCALATED'));
  });

  test('projects: create, notes, pin, members, files, tasks', () async {
    await admin.createProject('Project $stamp', 'Live test project');
    final p = (await admin.projects()).firstWhere((p) => p.name == 'Project $stamp');
    await admin.updateProject(p.id, {'note': 'Kick-off Monday'});
    var d = await admin.project(p.id);
    await admin.updateProject(p.id, {'togglePinNoteId': d.notes.single.id});
    await admin.updateProject(p.id, {'addMemberId': nehaId});
    await admin.upload(utf8.encode('hello'), 'brief.txt', projectId: p.id);
    await admin.createTask(NewTask(title: 'In project $stamp', assigneeId: nehaId, dueAt: inHours(6), projectId: p.id));
    d = await neha.project(p.id);
    expect(d.notes.single.pinned, isTrue);
    expect(d.members.map((m) => m.id), contains(nehaId));
    expect(d.files.single.fileName, 'brief.txt');
    expect(d.tasks.single.projectId, p.id);
    expect(d.activity, isNotEmpty);
    await admin.updateProject(p.id, {'removeMemberId': nehaId});
    expect((await admin.project(p.id)).members.map((m) => m.id), isNot(contains(nehaId)));
  });

  test('uploads: attach to task, download bytes, delete', () async {
    final a = await admin.upload(utf8.encode('attachment body'), 'notes.txt');
    final id = (await admin.createTask(NewTask(title: 'Attach $stamp', assigneeId: nehaId, dueAt: inHours(6), attachmentIds: [a.id]))).first;
    final d = await neha.task(id);
    expect(d.attachments.single.fileName, 'notes.txt');
    expect(utf8.decode(await neha.client.getBytes('/uploads/${a.id}')), 'attachment body');
    final loose = await admin.upload(utf8.encode('x'), 'tmp.txt');
    await admin.deleteUpload(loose.id);
  });

  test('notifications: assignment notifies, mark read, clear', () async {
    await admin.createTask(NewTask(title: 'Notify $stamp', assigneeId: nehaId, dueAt: inHours(6)));
    var list = await neha.notifications();
    final n = list.firstWhere((n) => n.title.contains('Notify $stamp') || (n.body ?? '').contains('Notify $stamp'));
    expect(n.taskId, isNotNull);
    await neha.markNotificationsRead(ids: [n.id]);
    list = await neha.notifications();
    expect(list.firstWhere((x) => x.id == n.id).isRead, isTrue);
    await neha.markNotificationsRead(all: true);
    expect((await neha.me()).unread, 0);
    await neha.clearNotifications();
    expect(await neha.notifications(), isEmpty);
  });

  test('reports: summary, scope, drill-down, filters', () async {
    final r = await admin.report({});
    expect(r.scope, 'ADMIN');
    expect(r.people, isNotEmpty);
    expect(r.summary.open, greaterThan(0));
    final drill = await admin.reportDrill({'list': 'open'});
    expect(drill.length, r.summary.open);
    final week = await admin.report({'days': '7', 'overall': 'false'});
    expect(week.summary.open, lessThanOrEqualTo(r.summary.open));
    final mine = await neha.report({});
    expect(mine.isPersonal, isTrue);
    final person = await admin.reportDrill({'list': 'open', 'personId': nehaId});
    expect(person, isNotEmpty);
  });

  test('admin: users, teams, task types CRUD', () async {
    final email = 'live$stamp@rentfoxxy.com';
    await admin.createUser({'name': 'Live User', 'email': email, 'password': 'secret1', 'phone': '9876543210', 'role': 'MEMBER', 'teamId': null});
    var u = (await admin.users()).firstWhere((u) => u.email == email);
    expect(u.phone, '9876543210');
    await admin.updateUser(u.id, {'role': 'QA', 'isActive': false});
    u = (await admin.users()).firstWhere((x) => x.id == u.id);
    expect(u.role, 'QA');
    expect(u.isActive, isFalse);
    await admin.updateUser(u.id, {'isActive': true, 'password': 'secret2'});
    await expectLater(
      TaskFlowApi(ApiClient(baseUrl: base!)).login(email, 'secret1'),
      throwsA(isA<ApiException>()),
      reason: 'old password must stop working',
    );
    final fresh = TaskFlowApi(ApiClient(baseUrl: base!));
    await fresh.login(email, 'secret2');
    await expectLater(neha.createUser({'name': 'x', 'email': 'x$stamp@x.com', 'password': 'secret1'}), throwsA(isA<ApiException>()));

    await admin.createTeam('Team $stamp', null);
    var team = (await admin.teams()).firstWhere((t) => t.name == 'Team $stamp');
    await admin.updateTeam(team.id, {'name': 'Team $stamp B', 'managerId': u.id, 'memberIds': [u.id]});
    team = (await admin.teams()).firstWhere((t) => t.id == team.id);
    expect(team.name, 'Team $stamp B');
    expect(team.managerId, u.id);

    await admin.createTaskType(team.id, 'Type $stamp');
    var tt = (await admin.taskTypes(manage: true)).firstWhere((t) => t.name == 'Type $stamp');
    await admin.updateTaskType(tt.id, {'name': 'Type $stamp B', 'isActive': false});
    tt = (await admin.taskTypes(manage: true)).firstWhere((t) => t.id == tt.id);
    expect(tt.isActive, isFalse);
    await admin.deleteTaskType(tt.id);
    expect((await admin.taskTypes(manage: true)).any((t) => t.id == tt.id), isFalse);

    await admin.updateTeam(team.id, {'memberIds': <int>[], 'managerId': null});
    await admin.deleteTeam(team.id);
    await admin.deleteUser(u.id);
    expect((await admin.users()).any((x) => x.id == u.id), isFalse);
  });

  test('chat: direct messages, reactions, edit, delete, groups', () async {
    final open = await admin.openChat(nehaId);
    final cid = open.conversation.id;
    final sent = await admin.sendMessage(cid, 'Hello Neha $stamp');
    expect(sent.message.body, 'Hello Neha $stamp');
    final reply = await neha.sendMessage(cid, 'Hi!', parentId: sent.message.id);
    expect(reply.message.parentId, sent.message.id);

    final reacted = await neha.toggleMessageReaction(sent.message.id, '🎉');
    expect(reacted.message.reactions.single.emoji, '🎉');
    final edited = await admin.editMessage(sent.message.id, 'Hello Neha (edited)');
    expect(edited.message.edited, isTrue);
    final deleted = await admin.deleteMessage(sent.message.id);
    expect(deleted.message.isDeleted, isTrue);

    final msgs = await neha.messages(cid);
    expect(msgs.messages.map((m) => m.id), contains(reply.message.id));
    expect((await neha.conversations()).map((c) => c.id), contains(cid));
    expect((await admin.chatTargets()).map((t) => t.id), contains(nehaId));

    final a = await admin.upload(utf8.encode('file'), 'chat.txt');
    final withFile = await admin.sendMessage(cid, '', attachmentIds: [a.id]);
    expect(withFile.message.attachments.single.fileName, 'chat.txt');

    final g = await admin.createGroup('Group $stamp', [nehaId]);
    expect(g.isGroup, isTrue);
    final detail = await admin.groupDetail(g.id);
    expect(detail.members.map((m) => m.id), contains(nehaId));
    expect(detail.canManage, isTrue);
    final renamed = await admin.updateGroup(g.id, name: 'Group $stamp B');
    expect(renamed.title, 'Group $stamp B');
    final gm = await neha.sendMessage(g.id, 'hey @[CTO](user:1)');
    expect(gm.conversation.isGroup, isTrue);
    await expectLater(neha.createGroup('nope', [1]), throwsA(isA<ApiException>()));
  });

  test('boards: save, update, list, delete', () async {
    final id = await admin.saveBoard(name: 'Board $stamp', scene: encodeScene([Stroke(color: const Color(0xFF000000), width: 2, points: [Offset.zero])]));
    await admin.saveBoard(id: id, name: 'Board $stamp B', scene: encodeScene([]));
    final b = (await admin.boards()).firstWhere((b) => b.id == id);
    expect(b.name, 'Board $stamp B');
    expect(decodeScene(b.scene).fromWeb, isFalse);
    await admin.deleteBoard(id);
    expect((await admin.boards()).any((x) => x.id == id), isFalse);
  });
}
