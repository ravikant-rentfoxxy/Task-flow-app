import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';

/// Scrolls [f] into view (if inside a scrollable) and taps it.
Future<void> tapOn(WidgetTester t, Finder f) async {
  final target = f.last;
  if (find.ancestor(of: target, matching: find.byType(Scrollable)).evaluate().isNotEmpty) {
    await t.ensureVisible(target);
    await t.pumpAndSettle();
  }
  await t.tap(target);
  await t.pumpAndSettle();
}

/// Scrolls the top-most vertical list until [f] is built and visible.
Future<void> reveal(WidgetTester t, Finder f) async {
  final lists = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
  await t.scrollUntilVisible(f, 150, scrollable: lists.last);
  await t.pumpAndSettle();
}

/// Taps the top-most widget showing [text] (menus and sheets sit last in the tree).
Future<void> tapText(WidgetTester t, String text) => tapOn(t, find.text(text));

Future<void> goTab(WidgetTester t, String id) async {
  await tapOn(t, find.byKey(ValueKey('nav-$id')));
}

void main() {
  group('auth', () {
    testWidgets('wrong password shows error, correct password opens dashboard', (t) async {
      final b = FakeBackend();
      await bootApp(t, b, signedIn: false);
      expect(find.text('Welcome back'), findsOneWidget);

      await t.enterText(find.byKey(const Key('login-email')), 'admin@rentfoxxy.com');
      await t.enterText(find.byKey(const Key('login-password')), 'nope');
      await tapOn(t, find.byKey(const Key('login-submit')));
      expect(find.text('Invalid email or password'), findsOneWidget);

      await t.enterText(find.byKey(const Key('login-password')), 'password123');
      await tapOn(t, find.byKey(const Key('login-submit')));
      expect(find.byKey(const Key('greeting')), findsOneWidget);
      expect(b.last('POST', '/auth/login').body, {'email': 'admin@rentfoxxy.com', 'password': 'password123'});
      await teardownApp(t);
    });

    testWidgets('password reset sends code then new password', (t) async {
      final b = FakeBackend();
      await bootApp(t, b, signedIn: false);
      await tapOn(t, find.byKey(const Key('reset-password')));
      await t.enterText(find.byKey(const Key('reset-email')), 'neha@rentfoxxy.com');
      await tapOn(t, find.byKey(const Key('reset-submit')));
      expect(find.text('Code sent if the account exists.'), findsOneWidget);
      await t.enterText(find.byKey(const Key('reset-otp')), '123456');
      await t.enterText(find.byKey(const Key('reset-new')), 'newpass1');
      await t.enterText(find.byKey(const Key('reset-confirm')), 'newpass1');
      await tapOn(t, find.byKey(const Key('reset-submit')));
      expect(b.last('POST', '/auth/reset-password').body,
          {'email': 'neha@rentfoxxy.com', 'otp': '123456', 'newPassword': 'newpass1', 'confirmPassword': 'newpass1'});
      expect(find.text('Welcome back'), findsOneWidget);
      expect(b.where('POST', '/auth/login'), isEmpty);
      await t.pump(const Duration(seconds: 31));
      await teardownApp(t);
    });

    testWidgets('logout from account menu returns to login', (t) async {
      final b = FakeBackend();
      await bootApp(t, b);
      await tapOn(t, find.byKey(const Key('account-menu')).first);
      await tapOn(t, find.byKey(const Key('logout')));
      expect(find.text('Welcome back'), findsOneWidget);
      expect(b.where('POST', '/auth/logout'), hasLength(1));
      await teardownApp(t);
    });
  });

  group('dashboard', () {
    for (final size in [phone, desktop]) {
      testWidgets('metrics and sections render (${size.width.toInt()}px)', (t) async {
        final b = FakeBackend();
        await bootApp(t, b, size: size);
        expect(find.text('30-min SLA'), findsOneWidget, reason: 'accept response section');
        expect(find.textContaining('Explanation required'), findsOneWidget, reason: 'escalated panel');
        expect(find.text('Follow up corporate leads'), findsOneWidget);
        expect(find.text('Delegated audit'), findsOneWidget, reason: 'assigned by me · open');
        final metric = t.widget<Text>(find.descendant(of: find.byKey(const Key('metric-accept')), matching: find.text('1')));
        expect(metric.data, '1');
        expect(find.text('Action needed'), findsWidgets, reason: 'creator sees discuss badge');
        await teardownApp(t);
      });
    }

    testWidgets('Accept + ETA flow from dashboard', (t) async {
      final b = FakeBackend();
      await bootApp(t, b);
      await tapOn(t, find.byKey(const ValueKey('accept-1')));
      await tapOn(t, find.byKey(const ValueKey('action-Accept + ETA')));
      await tapText(t, 'Today EOD');
      await tapOn(t, find.byKey(const Key('status-submit')));
      final patch = b.last('PATCH', '/tasks/1');
      expect(patch.body['action'], 'acknowledge');
      expect(patch.body['etaAt'], isA<int>());
      expect(find.text('Task accepted'), findsOneWidget);
      await teardownApp(t);
    });
  });

  group('tasks list', () {
    testWidgets('segments, search, status filter and reset hit the API', (t) async {
      final b = FakeBackend();
      await bootApp(t, b);
      await goTab(t, 'tasks');
      expect(b.last('GET', '/tasks').query['filter'], 'mine');

      await tapOn(t, find.byKey(const ValueKey('segment-created')));
      expect(b.last('GET', '/tasks').query['filter'], 'created');
      expect(find.text('Delegated audit'), findsOneWidget);

      await t.enterText(find.byKey(const Key('task-search')), 'audit');
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(b.last('GET', '/tasks').query['q'], 'audit');

      await tapOn(t, find.byKey(const Key('status-filter')));
      await tapText(t, 'Discuss');
      expect(b.last('GET', '/tasks').query['status'], 'DISCUSS');

      await tapOn(t, find.byKey(const Key('due-filter')));
      await tapOn(t, find.byKey(const Key('due-today')));
      expect(b.last('GET', '/tasks').query.keys, containsAll(['dueFrom', 'dueTo']));

      await tapOn(t, find.byKey(const Key('reset-filters')));
      final q = b.last('GET', '/tasks').query;
      expect(q['filter'], 'mine');
      expect(q.containsKey('status'), isFalse);
      expect(q.containsKey('q'), isFalse);
      await teardownApp(t);
    });

    testWidgets('pagination moves between pages', (t) async {
      final b = FakeBackend();
      for (var i = 0; i < 20; i++) {
        b.tasks.add(taskRow(200 + i, 'Bulk task $i', assigneeId: 1, assigneeName: 'Me'));
      }
      await bootApp(t, b);
      await goTab(t, 'tasks');
      expect(find.byKey(const Key('pagination-label')), findsOneWidget);
      await reveal(t, find.byKey(const Key('page-next')));
      await tapOn(t, find.byKey(const Key('page-next')));
      expect(b.last('GET', '/tasks').query['page'], '2');
      await teardownApp(t);
    });

    testWidgets('comments sheet posts a comment', (t) async {
      final b = FakeBackend();
      await bootApp(t, b);
      await goTab(t, 'tasks');
      await tapOn(t, find.byKey(const ValueKey('comments-2')));
      expect(find.text('Draft is ready'), findsOneWidget);
      await t.enterText(find.byKey(const Key('comment-input')), 'Looks good');
      await t.pump();
      await tapOn(t, find.byKey(const Key('comment-send')));
      expect(b.last('POST', '/tasks/2/comments').body, {'content': 'Looks good', 'parentCommentId': null});
      expect(find.text('Looks good'), findsOneWidget);
      await teardownApp(t);
    });

    testWidgets('admin can delete a task from the card menu', (t) async {
      final b = FakeBackend();
      await bootApp(t, b);
      await goTab(t, 'tasks');
      await tapOn(t, find.byKey(const ValueKey('task-menu-2')));
      await tapText(t, 'Delete task');
      await tapText(t, 'Delete');
      expect(b.where('DELETE', '/tasks/2'), hasLength(1));
      expect(find.text('Prepare fleet report'), findsNothing);
      await teardownApp(t);
    });
  });

  group('composer', () {
    testWidgets('validates then creates a task with assignee, due and priority', (t) async {
      final b = FakeBackend();
      await bootApp(t, b);
      await tapOn(t, find.byKey(const Key('dashboard-new-task')));

      await tapOn(t, find.byKey(const Key('composer-submit')));
      expect(find.text('Pick a due date & time'), findsWidgets);

      await t.enterText(find.byKey(const Key('composer-title')), 'Call vendor');
      await tapOn(t, find.byKey(const Key('composer-assignee')));
      await tapOn(t, find.byKey(const ValueKey('pick-Neha Kapoor')));
      await tapText(t, 'Tomorrow noon');
      await tapOn(t, find.byKey(const ValueKey('priority-URGENT')));
      await tapOn(t, find.byKey(const Key('composer-submit')));

      final body = b.last('POST', '/tasks').body as Map;
      expect(body['title'], 'Call vendor');
      expect(body['assigneeId'], 4);
      expect(body['priority'], 'URGENT');
      expect(body['dueAt'], isA<int>());
      expect(body['multiple'], isFalse);
      expect(find.text('Task created'), findsOneWidget);
      await teardownApp(t);
    });

    testWidgets('multiple tasks and inline subtasks', (t) async {
      final b = FakeBackend();
      await bootApp(t, b);
      await tapOn(t, find.byKey(const Key('dashboard-new-task')));
      await t.enterText(find.byKey(const Key('composer-title')), 'Parent');
      await t.pumpAndSettle(); // let the focused field finish scrolling itself into view
      await tapOn(t, find.byKey(const Key('composer-subtasks-toggle')));
      await reveal(t, find.byKey(const Key('composer-subtask-input')));
      await t.enterText(find.byKey(const Key('composer-subtask-input')), 'Step one');
      await tapOn(t, find.byKey(const Key('composer-subtask-add')));
      await tapOn(t, find.byKey(const Key('composer-assignee')));
      await tapOn(t, find.byKey(const ValueKey('pick-Neha Kapoor')));
      await tapText(t, 'Today EOD');
      await tapOn(t, find.byKey(const Key('composer-submit')));
      final posts = b.where('POST', '/tasks');
      expect(posts, hasLength(2));
      expect(posts[1].body['parentId'], isA<int>());
      expect(posts[1].body['lines'], ['Step one']);
      await t.pump(const Duration(seconds: 5)); // let the toast leave
      await t.pumpAndSettle();

      await tapOn(t, find.byKey(const Key('dashboard-new-task')));
      await tapOn(t, find.byKey(const Key('composer-multiple')));
      await t.enterText(find.byKey(const Key('composer-lines')), 'One\nTwo\n\nThree');
      await tapOn(t, find.byKey(const Key('composer-assignee')));
      await tapOn(t, find.byKey(const ValueKey('pick-Amit Saxena')));
      await tapText(t, '+2 days');
      await tapOn(t, find.byKey(const Key('composer-submit')));
      expect(b.last('POST', '/tasks').body['lines'], ['One', 'Two', 'Three']);
      expect(find.text('3 tasks created'), findsOneWidget);
      await teardownApp(t);
    });
  });

  group('task detail', () {
    for (final size in [phone, desktop]) {
      testWidgets('renders and runs actions (${size.width.toInt()}px)', (t) async {
        final b = FakeBackend();
        await bootApp(t, b, size: size);
        await tapOn(t, find.text('Prepare fleet report').first);
        expect(find.text('Task #2'), findsOneWidget);
        expect(find.textContaining('Description for Prepare fleet report'), findsOneWidget);

        await tapOn(t, find.byKey(const Key('detail-done')));
        expect(b.last('PATCH', '/tasks/2').body, {'action': 'done'});
        expect(find.text('Task marked done'), findsOneWidget);
        await teardownApp(t);
      });
    }

    testWidgets('cancel asks for a reason', (t) async {
      final b = FakeBackend();
      await bootApp(t, b);
      await tapOn(t, find.text('Prepare fleet report').first);
      await t.scrollUntilVisible(find.text('Cancel task'), 300, scrollable: find.byType(Scrollable).first);
      await tapOn(t, find.text('Cancel task'));
      await t.enterText(find.byKey(const Key('prompt-field')), 'Duplicate');
      await t.pump();
      await tapOn(t, find.byKey(const Key('prompt-submit')));
      expect(b.last('PATCH', '/tasks/2').body, {'action': 'cancel', 'reason': 'Duplicate'});
      await teardownApp(t);
    });

    testWidgets('comments tab on phone', (t) async {
      final b = FakeBackend();
      await bootApp(t, b);
      await tapOn(t, find.text('Prepare fleet report').first);
      await tapOn(t, find.byKey(const Key('tab-comments')));
      expect(find.text('Draft is ready'), findsOneWidget);
      await teardownApp(t);
    });
  });

  group('notifications', () {
    testWidgets('badge, list, mark read and clear', (t) async {
      final b = FakeBackend();
      await bootApp(t, b);
      expect(find.descendant(of: find.byKey(const Key('notification-bell')).first, matching: find.text('1')), findsOneWidget);
      await tapOn(t, find.byKey(const Key('notification-bell')).first);
      expect(find.text('New task: Follow up corporate leads'), findsOneWidget);
      await tapOn(t, find.byKey(const Key('mark-all-read')));
      expect(b.last('POST', '/notifications').body, {'all': true});
      await tapOn(t, find.byKey(const Key('clear-notifications')));
      expect(b.where('POST', '/notifications/clear'), hasLength(1));
      expect(find.text('No notifications'), findsOneWidget);
      await teardownApp(t);
    });

    testWidgets('tapping a notification opens its task', (t) async {
      final b = FakeBackend();
      await bootApp(t, b);
      await tapOn(t, find.byKey(const Key('notification-bell')).first);
      await tapOn(t, find.byKey(const ValueKey('notification-1')));
      expect(find.text('Task #1'), findsOneWidget);
      expect(b.where('POST', '/notifications').last.body, {'ids': [1]});
      await teardownApp(t);
    });
  });

  group('chat', () {
    testWidgets('open conversation, render task link, send message', (t) async {
      final b = FakeBackend();
      await bootApp(t, b);
      await goTab(t, 'chat');
      expect(find.text('Neha Kapoor'), findsWidgets);
      await tapOn(t, find.byKey(const ValueKey('conv-7')));
      expect(find.byKey(const Key('thread-title')), findsOneWidget);
      expect(find.text('Tap to view'), findsOneWidget);
      await t.enterText(find.byKey(const Key('chat-input')), 'On it!');
      await t.pump();
      await tapOn(t, find.byKey(const Key('chat-send')));
      expect(b.last('POST', '/chat/conversations/7/messages').body, {'body': 'On it!', 'parentMessageId': null, 'attachmentIds': []});
      expect(find.text('On it!'), findsOneWidget);
      await teardownApp(t);
    });

    testWidgets('chat from task card attaches the task', (t) async {
      final b = FakeBackend();
      await bootApp(t, b);
      await goTab(t, 'tasks');
      await tapOn(t, find.byKey(const ValueKey('segment-created')));
      await tapOn(t, find.byTooltip('Chat with assignee').first);
      expect(b.last('POST', '/chat/open').body, {'userId': 4});
      expect(find.byKey(const Key('attached-task')), findsOneWidget);
      await tapOn(t, find.byKey(const Key('chat-send')));
      final body = b.last('POST', '/chat/conversations/7/messages').body['body'] as String;
      expect(body, contains('[Tap to view](/tasks/4)'));
      await teardownApp(t);
    });

    testWidgets('desktop shows split view', (t) async {
      final b = FakeBackend();
      await bootApp(t, b, size: desktop);
      await tapOn(t, find.text('Chat').first);
      expect(find.text('Select a chat'), findsOneWidget);
      await tapOn(t, find.byKey(const ValueKey('conv-7')));
      expect(find.byKey(const Key('chat-input')), findsOneWidget);
      await teardownApp(t);
    });
  });

  group('projects, reports, admin', () {
    testWidgets('create project', (t) async {
      final b = FakeBackend();
      await bootApp(t, b);
      await goTab(t, 'projects');
      expect(find.text('Corporate Expansion Q3'), findsOneWidget);
      await tapOn(t, find.byKey(const Key('new-project')));
      await t.enterText(find.byKey(const Key('project-name')), 'Warehouse revamp');
      await t.pump();
      await tapOn(t, find.byKey(const Key('project-create')));
      expect(b.last('POST', '/projects').body, {'name': 'Warehouse revamp', 'description': ''});
      expect(find.text('Warehouse revamp'), findsOneWidget);
      await teardownApp(t);
    });

    testWidgets('reports stats and drill-down', (t) async {
      final b = FakeBackend();
      await bootApp(t, b);
      await goTab(t, 'more');
      await tapOn(t, find.byKey(const Key('more-reports')));
      expect(find.text('4 need attention'), findsOneWidget);
      expect(find.text('80%'), findsWidgets);
      await tapOn(t, find.byKey(const ValueKey('stat-Overdue')));
      expect(b.last('GET', '/reports').query['list'], 'overdue');
      expect(find.text('Overdue tasks'), findsOneWidget);
      await tapOn(t, find.byKey(const ValueKey('drill-1')));
      expect(find.text('Task #1'), findsOneWidget);
      await teardownApp(t);
    });

    testWidgets('reports period filter', (t) async {
      final b = FakeBackend();
      await bootApp(t, b, size: desktop);
      await tapOn(t, find.text('Reports').first);
      await tapOn(t, find.byKey(const ValueKey('period-7')));
      expect(b.last('GET', '/reports').query, containsPair('days', '7'));
      expect(b.last('GET', '/reports').query, containsPair('overall', 'true'));
      await teardownApp(t);
    });

    testWidgets('admin adds a task type and a user', (t) async {
      final b = FakeBackend();
      await bootApp(t, b, size: desktop);
      await tapOn(t, find.text('Admin').first);
      await tapOn(t, find.byKey(const Key('add-type')));
      await tapOn(t, find.byKey(const Key('type-team')));
      await tapOn(t, find.text('Sales').last);
      await t.enterText(find.byKey(const Key('type-name')), 'Demo Visit');
      await t.pump();
      await tapOn(t, find.byKey(const Key('type-create')));
      expect(b.last('POST', '/task-types').body, {'teamId': 1, 'name': 'Demo Visit'});
      expect(find.text('Demo Visit'), findsOneWidget);

      await tapOn(t, find.byKey(const Key('add-user')));
      await t.enterText(find.byKey(const Key('user-name')), 'Riya');
      await t.enterText(find.byKey(const Key('user-email')), 'riya@rentfoxxy.com');
      await t.enterText(find.byKey(const Key('user-phone')), '12');
      await t.enterText(find.byKey(const Key('user-password')), 'secret1');
      await t.pump();
      expect(find.text('Enter a valid 10-digit phone number'), findsOneWidget);
      await t.enterText(find.byKey(const Key('user-phone')), '9876543210');
      await t.pump();
      await tapOn(t, find.byKey(const Key('user-create')));
      final body = b.last('POST', '/users').body;
      expect(body['email'], 'riya@rentfoxxy.com');
      expect(body['phone'], '9876543210');
      expect(body['role'], 'MEMBER');
      await teardownApp(t);
    });

    testWidgets('members do not see admin entry', (t) async {
      final b = FakeBackend(role: 'MEMBER', userId: 1);
      await bootApp(t, b);
      await goTab(t, 'more');
      expect(find.byKey(const Key('more-admin')), findsNothing);
      expect(find.byKey(const Key('more-reports')), findsOneWidget);
      await teardownApp(t);
    });

    testWidgets('scribble opens and draws', (t) async {
      final b = FakeBackend();
      await bootApp(t, b);
      await goTab(t, 'more');
      await tapOn(t, find.byKey(const Key('more-scribble')));
      await t.drag(find.byKey(const Key('canvas')), const Offset(120, 80));
      await t.pumpAndSettle();
      expect(t.widget<IconButton>(find.byKey(const Key('board-undo'))).onPressed, isNotNull);
      await teardownApp(t);
    });
  });
}
