import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/format.dart';
import '../../data/taskflow_api.dart';
import '../../state/chat_unread_controller.dart';
import '../../state/realtime_controller.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_ui.dart';
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
        return Badge(
          backgroundColor: wide ? TF.coral : Brand.navy,
          textColor: wide ? null : Brand.lime,
          label: Text(chatUnread > 9 ? '9+' : '$chatUnread'),
          child: i,
        );
      }

      // Phone bar: active icon gets a small lime dot underneath.
      Widget navIcon(_Dest d, bool selected) {
        if (!selected) return icon(d, false);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            icon(d, true),
            Positioned(
              bottom: -6,
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: Brand.lime, shape: BoxShape.circle),
              ),
            ),
          ],
        );
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
            border: Border(top: BorderSide(color: Brand.outline.withValues(alpha: 0.6))),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, -4))],
          ),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              indicatorColor: Colors.transparent,
              overlayColor: WidgetStatePropertyAll(Brand.lime.withValues(alpha: 0.15)),
              height: 70,
              labelTextStyle: WidgetStateProperty.resolveWith(
                (s) => TextStyle(
                  fontSize: 12,
                  fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
                  color: s.contains(WidgetState.selected) ? Brand.navy : Brand.onVariant,
                ),
              ),
              iconTheme: WidgetStateProperty.resolveWith(
                (s) => IconThemeData(color: s.contains(WidgetState.selected) ? Brand.navy : Brand.onVariant, size: 25),
              ),
            ),
            child: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => shell.go(dests[i].id),
              destinations: [
                for (final d in dests)
                  NavigationDestination(key: ValueKey('nav-${d.id}'), icon: navIcon(d, false), selectedIcon: navIcon(d, true), label: d.label),
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
    const logo = AppLogo(size: 40);
    if (!extended) return logo;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Work Plus', style: TextStyle(fontFamily: kBrandFont, fontWeight: FontWeight.w700, fontSize: 15.5, letterSpacing: -0.2)),
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
      backgroundColor: Brand.surface,
      appBar: const TopBar(title: 'More'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          if (me != null) ...[
            HeroCard(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Brand.lime, shape: BoxShape.circle),
                    child: Avatar(me.name, size: 50),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const HeroEyebrow('Signed in as'),
                        const SizedBox(height: 4),
                        Text(
                          displayName(me.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          me.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.65)),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            LimeTag(me.roleLabel),
                            if (me.team != null) LimeTag(me.team!),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          const BrandSectionTitle(title: 'Workspace'),
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
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const Key('more-logout'),
            style: OutlinedButton.styleFrom(
              foregroundColor: brandRed,
              backgroundColor: Colors.white,
              side: BorderSide(color: brandRed.withValues(alpha: 0.35)),
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            onPressed: () async {
              Get.find<ChatUnreadController>().clear();
              await Get.find<AuthController>().logout();
            },
            icon: const Icon(Icons.logout_rounded, size: 19),
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
    padding: const EdgeInsets.only(bottom: 8),
    child: BrandCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Brand.navy),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Brand.onVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: Brand.surfaceLow, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.chevron_right_rounded, size: 18, color: Brand.navy),
          ),
        ],
      ),
    ),
  );
}
