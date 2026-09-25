import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/format.dart';
import 'package:taskflow/core/task_logic.dart';
import 'package:taskflow/features/reports/reports_screen.dart';
import 'package:taskflow/features/scribble/scribble_screen.dart';
import 'package:taskflow/models/models.dart';
import 'package:taskflow/widgets/filters.dart';

Task task({
  int id = 1,
  String status = 'IN_PROGRESS',
  int? creatorId = 10,
  int? assigneeId = 20,
  DateTime? dueAt,
  String? blocked,
  bool reviewPending = false,
  int? parentId,
}) =>
    Task(
      id: id,
      title: 'T$id',
      status: status,
      creatorId: creatorId,
      assigneeId: assigneeId,
      dueAt: dueAt,
      blockedReason: blocked,
      escalationReviewPending: reviewPending,
      parentId: parentId,
    );

Me me(int id, String role) => Me(id: id, name: 'User $id', email: 'u$id@x.com', role: role);

void main() {
  group('timestamps', () {
    test('parses bigint strings, numbers and ISO', () {
      expect(parseTimestamp('1790236365449'), 1790236365449);
      expect(parseTimestamp(1790236365449), 1790236365449);
      expect(parseTimestamp('2026-01-02T00:00:00.000Z'), DateTime.utc(2026, 1, 2).millisecondsSinceEpoch);
      expect(parseTimestamp(''), isNull);
      expect(parseTimestamp(null), isNull);
      expect(parseTimestamp('garbage'), isNull);
    });

    test('timeAgo and countdown', () {
      final now = DateTime(2026, 1, 1, 12);
      expect(timeAgo(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
      expect(timeAgo(now.subtract(const Duration(minutes: 5)), now: now), '5m ago');
      expect(timeAgo(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
      expect(timeAgo(now.subtract(const Duration(days: 2)), now: now), '2d ago');
      expect(countdown(now.add(const Duration(minutes: 25)), now: now), '25m left');
      expect(countdown(now.add(const Duration(minutes: 185)), now: now), '3h 5m left');
      expect(countdown(now.add(const Duration(days: 3)), now: now), '3d left');
      expect(countdown(now.subtract(const Duration(minutes: 1)), now: now), 'breached');
    });

    test('names and html', () {
      expect(initials('Suresh Kumar (Sales Head)'), 'SK');
      expect(displayName('Suresh Kumar (Sales Head)'), 'Suresh Kumar');
      expect(firstName('Kumar Bibhaw Raj (CTO)'), 'Kumar');
      expect(htmlToPlainText('<p>Hello&nbsp;<b>world</b></p>'), 'Hello world');
    });

    test('day bounds and due filter query', () {
      final b = todayBounds(DateTime(2026, 3, 4, 15));
      expect(DateTime.fromMillisecondsSinceEpoch(b.from), DateTime(2026, 3, 4));
      expect(DateTime.fromMillisecondsSinceEpoch(b.to).hour, 23);
      expect(rangeBounds(DateTime(2026, 3, 5), DateTime(2026, 3, 4)), isNull);
      expect(const DueFilter().toQuery(), isEmpty);
      expect(const DueFilter(mode: 'today').toQuery().keys, containsAll(['dueFrom', 'dueTo']));
      expect(DueFilter(mode: 'range', from: DateTime(2026, 1, 1), to: DateTime(2026, 1, 3)).toQuery()['dueFrom'],
          DateTime(2026, 1, 1).millisecondsSinceEpoch);
    });
  });

  group('task rules', () {
    test('overdue ignores closed tasks', () {
      final past = DateTime.now().subtract(const Duration(hours: 1));
      expect(isTaskOverdue(task(dueAt: past)), isTrue);
      expect(isTaskOverdue(task(dueAt: past, status: 'DONE')), isFalse);
      expect(isTaskOverdue(task(dueAt: DateTime.now().add(const Duration(hours: 1)))), isFalse);
    });

    test('action needed for creator / admin', () {
      final discuss = task(status: 'DISCUSS');
      expect(taskNeedsActionForViewer(discuss, me(10, 'MEMBER')), isTrue, reason: 'creator');
      expect(taskNeedsActionForViewer(discuss, me(99, 'ADMIN')), isTrue, reason: 'admin');
      expect(taskNeedsActionForViewer(discuss, me(20, 'MEMBER')), isFalse, reason: 'assignee');
      expect(taskNeedsActionForViewer(task(blocked: 'waiting on vendor'), me(10, 'MEMBER')), isTrue);
      final esc = task(status: 'ESCALATED', reviewPending: true);
      expect(taskNeedsActionForViewer(esc, me(99, 'CEO')), isTrue);
      expect(taskNeedsActionForViewer(esc, me(10, 'MEMBER')), isFalse);
    });

    test('reassign permission', () {
      expect(canReassignTask(task(), me(10, 'MEMBER')), isTrue, reason: 'creator');
      expect(canReassignTask(task(), me(99, 'ADMIN')), isTrue);
      expect(canReassignTask(task(), me(20, 'MEMBER')), isFalse);
      expect(canReassignTask(task(status: 'DONE'), me(99, 'ADMIN')), isFalse);
      expect(canReassignTask(task(creatorId: 5, parentId: 1), me(10, 'MEMBER'), parent: task(creatorId: 10)), isTrue);
    });

    test('subtasks, delete and chat target', () {
      expect(canCreateSubtask(task()), isTrue);
      expect(canCreateSubtask(task(parentId: 3)), isFalse);
      expect(canCreateSubtask(task(status: 'CANCELLED')), isFalse);
      expect(canDeleteTask(me(1, 'CEO')), isTrue);
      expect(canDeleteTask(me(1, 'MANAGER')), isFalse);
      expect(chatTargetForTask(task(), 20), 10, reason: 'assignee chats with creator');
      expect(chatTargetForTask(task(), 10), 20, reason: 'others chat with assignee');
      expect(chatTargetForTask(task(assigneeId: null), 10), isNull);
      expect(subtaskPercent(1, 3), 33);
      expect(subtaskPercent(5, 0), 0);
    });

    test('rich text parsing and task links', () {
      final parts = parseRichText('Hi @[Neha Kapoor](user:4) see [Tap to view](/tasks/12) ok');
      expect(parts.whereType<MentionPart>().single.name, 'Neha Kapoor');
      final link = parts.whereType<LinkPart>().single;
      expect(link.label, 'Tap to view');
      expect(taskIdFromHref(link.href), 12);
      expect(taskIdFromHref('https://x.com'), isNull);
    });

    test('mention encode / decode round trip', () {
      final members = [(id: 4, name: 'Neha Kapoor'), (id: 5, name: 'Amit Saxena (QA)')];
      final encoded = encodeMentionsForSend('hey @Neha Kapoor and @Amit Saxena!', members);
      expect(encoded, 'hey @[Neha Kapoor](user:4) and @[Amit Saxena](user:5)!');
      expect(decodeMentionsForDisplay(encoded), 'hey @Neha Kapoor and @Amit Saxena!');
    });

    test('task chat messages', () {
      final body = buildTaskMentionBody(Task(id: 7, title: 'Call vendor', description: 'Ask about invoice'), 'please check');
      expect(body, contains('[Tap to view](/tasks/7)'));
      expect(body, contains('Ask about invoice'));
      expect(body.trim().endsWith('please check'), isTrue);
      final multi = buildTaskCreatedMessage([1, 2], lines: ['A', 'B']);
      expect(multi, contains('1. A'));
      expect(multi, contains('(/tasks/2)'));
    });
  });

  group('models', () {
    test('task parses backend row', () {
      final t = Task.fromJson({
        'id': 5,
        'title': 'Clear backlog',
        'status': 'ESCALATED',
        'priority': 'HIGH',
        'due_at': '1790236365449',
        'subtask_count': 2,
        'subtask_done': 1,
        'escalation_review_pending': 't',
        'assignee_name': null,
        'team_name': 'Support',
      });
      expect(t.dueAt, DateTime.fromMillisecondsSinceEpoch(1790236365449));
      expect(t.escalationReviewPending, isTrue);
      expect(t.who, 'Team Support');
    });

    test('activity meta json string', () {
      final a = Activity.fromJson({'id': 1, 'type': 'ETA_CHANGED', 'meta': '{"from":1,"to":2,"reason":"late"}', 'created_at': '5'});
      expect(a.meta['to'], 2);
      expect(a.detail, 'late');
    });

    test('permissions default canComment true', () {
      expect(TaskPermissions({}).canComment, isTrue);
      expect(TaskPermissions({'canComment': false, 'canDone': true}).canDone, isTrue);
    });

    test('report on-time percent', () {
      final p = ReportPerson({'id': 1, 'name': 'X', 'done': 4, 'done_ontime': 3});
      expect(p.onTimePct, 75);
      expect(ReportPerson({'id': 1, 'name': 'X', 'done': 0}).onTimePct, isNull);
    });
  });

  test('reports CSV escapes commas', () {
    final csv = reportsCsv([ReportPerson({'id': 1, 'name': 'Doe, Jane', 'team_name': 'Sales', 'open': 2})]);
    final lines = csv.split('\n');
    expect(lines.first, startsWith('Name,Team,Open'));
    expect(lines[1], startsWith('"Doe, Jane",Sales,2'));
  });

  group('scribble scenes', () {
    test('round trips own format', () {
      final scene = encodeScene([Stroke(color: const Color(0xFF112233), width: 3, points: [const Offset(1, 2), const Offset(3, 4)])]);
      final decoded = decodeScene(jsonEncode(scene));
      expect(decoded.fromWeb, isFalse);
      expect(decoded.strokes.single.points.last, const Offset(3, 4));
      expect(decoded.strokes.single.color, const Color(0xFF112233));
    });

    test('imports excalidraw freedraw strokes as web board', () {
      final decoded = decodeScene(
          '{"elements":[{"type":"freedraw","x":10,"y":20,"strokeColor":"#ff0000","strokeWidth":2,"points":[[0,0],[5,5]]},{"type":"freedraw","isDeleted":true,"points":[[0,0]]}]}');
      expect(decoded.fromWeb, isTrue);
      expect(decoded.strokes, hasLength(1));
      expect(decoded.strokes.first.points.last, const Offset(15, 25));
    });

    test('tolerates empty / broken scenes', () {
      expect(decodeScene(null).strokes, isEmpty);
      expect(decodeScene('not json').strokes, isEmpty);
    });
  });
}
