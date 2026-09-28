import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/format.dart';
import '../../data/taskflow_api.dart';
import '../../state/chat_unread_controller.dart';
import '../../state/realtime_controller.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../admin/admin_screen.dart';
import '../chat/chat_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../projects/projects_screen.dart';
import '../reports/reports_screen.dart';
import '../scribble/scribble_screen.dart';
import '../tasks/tasks_screen.dart';
import 'top_bar.dart';

/// Lets deep screens switch the active tab (e.g. open Chat from a task card).
class ShellController extends GetxController {
  final _tab = 'home'.obs;
  String get tab => _tab.value;

  void go(String t) => _tab.value = t;
}

class _Dest {
  const _Dest(this.id, this.label, this.icon, this.selectedIcon);
  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _visited = <String>{'home'};
  StreamSubscription<ChatUpdate>? _chatSub;
  StreamSubscription<String?>? _notifSub;
  late final RealtimeController _realtime;

  @override
  void initState() {
    super.initState();
    Get.put(ShellController());
    final realtime = _realtime = Get.find<RealtimeController>();
    final api = Get.find<TaskFlowApi>();
    realtime.connect(apiBase: api.client.baseUrl, cookie: api.client.cookieHeader);
    final session = Get.find<AuthController>();
    final unread = Get.find<ChatUnreadController>();
    _chatSub = realtime.chat.listen((u) => unread.handle(u, session.me?.id));
    _notifSub = realtime.notifications.listen((title) {
      session.refreshQuietly();
      if (title != null && title.isNotEmpty) toast(title);
    });
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _notifSub?.cancel();
    _realtime.disconnect();
    Get.delete<ShellController>();
    super.dispose();
  }

  Widget _page(String id) => switch (id) {
    'home' => const DashboardScreen(),
    'tasks' => const TasksScreen(),
    'projects' => const ProjectsScreen(),
    'chat' => const ChatScreen(),
    'reports' => const ReportsScreen(),
    'admin' => const AdminScreen(),
    _ => const MoreScreen(),
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) => Obx(() => _build(context, c)));

  Widget _build(BuildContext context, BoxConstraints c) {
    final me = Get.find<AuthController>().me;
    final shell = Get.find<ShellController>();
    final chatUnread = Get.find<ChatUnreadController>().total;
    final canManage = me?.canManage ?? false;
    {
      final wide = c.maxWidth >= 900;
      final dests = wide
          ? [
              const _Dest('home', 'Dashboard', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
              const _Dest('tasks', 'Tasks', Icons.task_alt_outlined, Icons.task_alt_rounded),
              const _Dest('projects', 'Projects', Icons.folder_outlined, Icons.folder_rounded),
              const _Dest('chat', 'Chat', Icons.forum_outlined, Icons.forum_rounded),
              const _Dest('reports', 'Reports', Icons.insights_outlined, Icons.insights_rounded),
              if (canManage) _Dest('admin', me!.isAdmin ? 'Admin' : 'Manage', Icons.tune_outlined, Icons.tune_rounded),
            ]
          : const [
              _Dest('home', 'Home', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
              _Dest('tasks', 'Tasks', Icons.task_alt_outlined, Icons.task_alt_rounded),
              _Dest('chat', 'Chat', Icons.forum_outlined, Icons.forum_rounded),
              _Dest('projects', 'Projects', Icons.folder_outlined, Icons.folder_rounded),
              _Dest('more', 'More', Icons.grid_view_outlined, Icons.grid_view_rounded),
            ];

      var activeId = shell.tab;
      var index = dests.indexWhere((d) => d.id == activeId);
      if (index < 0) {
        if (wide) {
          // "more" only exists on phones.
          activeId = 'home';
          index = 0;
        } else {
          // Reports/Admin on a phone are shown with "More" highlighted.
          index = dests.length - 1;
        }
      }
      _visited.add(activeId);

      // Keep visited tabs alive so filters and scroll positions survive tab switches.
      final ids = <String>{..._visited};
      final stack = IndexedStack(
        index: ids.toList().indexOf(activeId),
        children: [for (final id in ids) KeyedSubtree(key: ValueKey('tab-$id'), child: _page(id))],
      );

      Widget icon(_Dest d, bool selected) {
        final i = Icon(selected ? d.selectedIcon : d.icon);
        if (d.id != 'chat' || chatUnread == 0) return i;
        return Badge(backgroundColor: TF.coral, label: Text(chatUnread > 9 ? '9+' : '$chatUnread'), child: i);
      }

      if (wide) {
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                extended: c.maxWidth >= 1200,
                selectedIndex: index,
                onDestinationSelected: (i) => shell.go(dests[i].id),
                leading: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 20),
                  child: _Brand(extended: c.maxWidth >= 1200),
                ),
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: IconButton(
                        tooltip: 'Scribble',
                        icon: const Icon(Icons.gesture_rounded, color: TF.muted),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScribbleScreen())),
                      ),
                    ),
                  ),
                ),
                destinations: [
                  for (final d in dests) NavigationRailDestination(icon: icon(d, false), selectedIcon: icon(d, true), label: Text(d.label)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: stack),
            ],
          ),
        );
      }

      return Scaffold(
        body: stack,
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            border: const Border(top: BorderSide(color: Brand.line)),
            boxShadow: [BoxShadow(color: Brand.ink.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, -4))],
          ),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Colors.white,
              indicatorColor: Brand.primarySoft,
              height: 70,
              labelTextStyle: WidgetStateProperty.resolveWith(
                (s) => TextStyle(
                  fontSize: 12,
                  fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
                  color: s.contains(WidgetState.selected) ? Brand.primary : Brand.inkSoft,
                ),
              ),
              iconTheme: WidgetStateProperty.resolveWith(
                (s) => IconThemeData(color: s.contains(WidgetState.selected) ? Brand.primary : Brand.inkSoft, size: 25),
              ),
            ),
            child: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => shell.go(dests[i].id),
              destinations: [
                for (final d in dests)
                  NavigationDestination(key: ValueKey('nav-${d.id}'), icon: icon(d, false), selectedIcon: icon(d, true), label: d.label),
              ],
            ),
          ),
        ),
      );
    }
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.extended});
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final logo = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: TF.ink, borderRadius: BorderRadius.circular(11)),
      child: const Text('TF', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
    );
    if (!extended) return logo;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TaskFlow', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -0.3)),
            Text('Task management', style: TextStyle(fontSize: 11.5, color: TF.muted)),
          ],
        ),
      ],
    );
  }
}

/// Phone-only hub for secondary destinations.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final me = Get.find<AuthController>().me;
    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return Scaffold(
      appBar: const TopBar(title: 'More'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          if (me != null)
            Surface(
              child: Row(
                children: [
                  Avatar(me.name, size: 48, dark: true),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName(me.name), style: Theme.of(context).textTheme.titleMedium),
                        Text(me.email, style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: [
                            Pill(me.roleLabel, fg: TF.primaryDeep, bg: TF.primarySoft),
                            if (me.team != null) Pill(me.team!),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          _MoreTile(
            key: const Key('more-reports'),
            icon: Icons.insights_rounded,
            color: TF.sky,
            title: 'Reports',
            subtitle: 'SLA, overdue and completion analytics',
            onTap: () => push(const ReportsScreen()),
          ),
          _MoreTile(
            key: const Key('more-scribble'),
            icon: Icons.gesture_rounded,
            color: TF.violet,
            title: 'Scribble',
            subtitle: 'Sketch on a board and send it as a task',
            onTap: () => push(const ScribbleScreen()),
          ),
          if (me?.canManage ?? false)
            _MoreTile(
              key: const Key('more-admin'),
              icon: Icons.tune_rounded,
              color: TF.amber,
              title: me!.isAdmin ? 'Admin' : 'Manage',
              subtitle: me.isAdmin ? 'Users, teams and task types' : 'Task types for your team',
              onTap: () => push(const AdminScreen()),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('more-logout'),
            style: OutlinedButton.styleFrom(foregroundColor: TF.coral, minimumSize: const Size(double.infinity, 48)),
            onPressed: () async {
              Get.find<ChatUnreadController>().clear();
              await Get.find<AuthController>().logout();
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({super.key, required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: TF.surface,
      borderRadius: BorderRadius.circular(TF.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(TF.radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TF.radius),
            border: Border.all(color: TF.line),
            boxShadow: Brand.shadow,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: TF.faint),
            ],
          ),
        ),
      ),
    ),
  );
}
