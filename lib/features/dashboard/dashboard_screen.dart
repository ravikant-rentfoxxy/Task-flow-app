import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';

import '../../core/format.dart';
import '../../core/task_logic.dart';
import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../state/realtime_controller.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/filters.dart';
import '../chat/chat_screen.dart';
import '../scribble/scribble_screen.dart';
import '../shell/top_bar.dart';
import '../tasks/composer_sheet.dart';
import '../tasks/status_sheet.dart';
import '../tasks/task_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Task>? mine;
  List<Task> created = [];
  List<Task> done = [];
  String? error;
  String assigneeFilter = '';
  DueFilter due = const DueFilter();
  List<AppUser> users = [];
  List<Team> teams = [];
  Timer? _poll;
  StreamSubscription<void>? _sub;

  TaskFlowApi get api => Get.find<TaskFlowApi>();
  bool get canFilter => Get.find<AuthController>().me?.isAdminOrCeo ?? false;
  bool get viewingFiltered => canFilter && assigneeFilter.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (canFilter) {
      api.users().then((u) => mounted ? setState(() => users = u) : null).catchError((_) {});
      api.teams().then((t) => mounted ? setState(() => teams = t) : null).catchError((_) {});
    }
    _load();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _load());
    _sub = Get.find<RealtimeController>().taskChanged.listen((_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final dq = due.toQuery();
    TaskQuery query(String filter, {int? assigneeId, int? teamId, String status = '', int limit = 100}) => TaskQuery(
          filter: filter,
          status: status,
          assigneeId: assigneeId,
          teamId: teamId,
          dueFrom: dq['dueFrom'] as int?,
          dueTo: dq['dueTo'] as int?,
          limit: limit,
        );
    try {
      if (viewingFiltered) {
        final id = int.parse(assigneeFilter.substring(2));
        final uid = assigneeFilter.startsWith('u:') ? id : null;
        final tid = assigneeFilter.startsWith('t:') ? id : null;
        final r = await Future.wait([
          api.tasks(query('all', assigneeId: uid, teamId: tid)),
          api.tasks(query('all', assigneeId: uid, teamId: tid, status: 'DONE', limit: 5)),
        ]);
        if (mounted) setState(() => (mine = r[0].tasks, created = [], done = r[1].tasks, error = null));
        return;
      }
      final r = await Future.wait([
        api.tasks(query('mine')),
        api.tasks(query('created')),
        api.tasks(query('mine', status: 'DONE', limit: 5)),
      ]);
      if (mounted) setState(() => (mine = r[0].tasks, created = r[1].tasks, done = r[2].tasks, error = null));
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    }
  }

  void _setFilter(VoidCallback f) {
    setState(f);
    _load();
  }

  @override
  Widget build(BuildContext context) => Obx(() => _reactiveBuild(context));

  Widget _reactiveBuild(BuildContext context) {
    final me = Get.find<AuthController>().me;
    final presence = Get.find<RealtimeController>().presence;
    final now = DateTime.now();
    final list = mine ?? const <Task>[];
    final dayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    final needsAck = list.where((t) => t.status == 'ASSIGNED' || t.status == 'DISCUSS').toList();
    final escalated = list.where((t) => t.status == 'ESCALATED').toList();
    final inProgress = list.where((t) => t.status == 'ACKNOWLEDGED' || t.status == 'IN_PROGRESS').toList();
    final dueToday = inProgress.where((t) => isDueInWindow(t, now, dayEnd)).toList();
    final doneRecent = done;
    final createdOpen = viewingFiltered
        ? <Task>[]
        : created.where((t) => !closedStatuses.contains(t.status) && t.assigneeId != me?.id).toList();
    final online = presence.users.where((u) => u.id != me?.id).toList();

    return Scaffold(
      appBar: const TopBar(title: 'Dashboard'),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('dashboard-new-task'),
        heroTag: 'dashboard-new-task',
        onPressed: () async {
          if (await showComposer(context) != null) _load();
        },
        backgroundColor: TF.ink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New task', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
          PageBody(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(DateFormat('EEEE, d MMMM').format(now).toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 4),
              Text('${greetingFor(now)}${me == null ? '' : ', ${firstName(me.name)}'}',
                  key: const Key('greeting'), style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (canFilter)
                  ActionChip(
                    key: const Key('dashboard-filter'),
                    avatar: const Icon(Icons.person_search_outlined, size: 17),
                    label: Text(userOrTeamLabel(assigneeFilter, users, teams, empty: 'Everyone (my dashboard)')),
                    onPressed: () async {
                      final v = await pickUserOrTeam(context,
                          users: users, teams: teams, selected: assigneeFilter, emptyLabel: 'Everyone (my dashboard)');
                      if (v != null) _setFilter(() => assigneeFilter = v);
                    },
                  ),
                ActionChip(
                  avatar: const Icon(Icons.gesture_rounded, size: 17),
                  label: const Text('Scribble'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScribbleScreen())),
                ),
              ]),
              const SizedBox(height: 8),
              DueFilterBar(value: due, onChanged: (d) => _setFilter(() => due = d)),
              if (canFilter && online.isNotEmpty) ...[
                const SizedBox(height: 12),
                _OnlineStrip(users: online),
              ],
              const SizedBox(height: 16),
              if (mine == null && error == null)
                const SkeletonList(count: 3)
              else if (error != null && mine == null)
                ErrorView(message: error!, onRetry: _load)
              else ...[
                _Metrics(needsAck: needsAck.length, escalated: escalated.length, inProgress: inProgress.length, dueToday: dueToday.length),
                const SizedBox(height: 24),
                _section('Accept response · 30-min SLA', Icons.bolt_rounded, TF.coral, needsAck,
                    action: (t) => t.status == 'ASSIGNED'
                        ? FilledButton(
                            key: ValueKey('accept-${t.id}'),
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 12)),
                            onPressed: () async {
                              if (await showStatusSheet(context, t) == true) _load();
                            },
                            child: const Text('Accept + ETA', style: TextStyle(fontSize: 12.5)),
                          )
                        : null),
                _section('Escalated · explanation required', Icons.warning_amber_rounded, TF.coral, escalated),
                _section('Due today', Icons.today_rounded, TF.amber, dueToday),
                _section('In progress', Icons.autorenew_rounded, TF.primary, inProgress.where((t) => !dueToday.contains(t)).toList()),
                _section('Assigned by me · open', Icons.send_rounded, TF.violet, createdOpen),
                _section('Recently done', Icons.check_circle_outline_rounded, TF.green, doneRecent),
                if (list.isEmpty && created.isEmpty && done.isEmpty)
                  Surface(
                    child: EmptyState(
                      icon: Icons.check_circle_outline_rounded,
                      color: TF.green,
                      title: viewingFiltered ? 'No matching tasks' : 'All clear',
                      message: viewingFiltered ? 'Try another person or team.' : 'Nothing on your plate. Create a task or sketch one on the board.',
                      action: viewingFiltered
                          ? null
                          : FilledButton.icon(
                              onPressed: () async {
                                if (await showComposer(context) != null) _load();
                              },
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('New task'),
                            ),
                    ),
                  ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _section(String title, IconData icon, Color color, List<Task> tasks, {Widget? Function(Task)? action}) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(title: title, icon: icon, color: color, count: tasks.length),
        TaskList(tasks: tasks, onChanged: _load, actionFor: action),
      ]),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.needsAck, required this.escalated, required this.inProgress, required this.dueToday});
  final int needsAck;
  final int escalated;
  final int inProgress;
  final int dueToday;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _MetricTile(key: const Key('metric-accept'), icon: Icons.bolt_rounded, color: TF.coral, value: needsAck, label: 'Accept response', hot: needsAck > 0),
      _MetricTile(key: const Key('metric-escalated'), icon: Icons.warning_amber_rounded, color: TF.amber, value: escalated, label: 'Escalated', hot: escalated > 0),
      _MetricTile(key: const Key('metric-progress'), icon: Icons.autorenew_rounded, color: TF.primary, value: inProgress, label: 'In progress'),
      _MetricTile(key: const Key('metric-today'), icon: Icons.today_rounded, color: TF.sky, value: dueToday, label: 'Due today'),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 720 ? 4 : 2;
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
    });
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({super.key, required this.icon, required this.color, required this.value, required this.label, this.hot = false});
  final IconData icon;
  final Color color;
  final int value;
  final String label;
  final bool hot;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hot ? color.withValues(alpha: 0.07) : TF.surface,
          borderRadius: BorderRadius.circular(TF.radius),
          border: Border.all(color: hot ? color.withValues(alpha: 0.35) : TF.line),
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$value', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1, color: hot ? color : TF.ink)),
              const SizedBox(height: 4),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TF.muted, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      );
}

class _OnlineStrip extends StatelessWidget {
  const _OnlineStrip({required this.users});
  final List<({int id, String name})> users;

  @override
  Widget build(BuildContext context) => Surface(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: TF.green, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('${users.length} online', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final u in users)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: 'Chat with ${u.name}',
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => openChatWithUser(context, u.id),
                        child: Avatar(u.name, size: 28, online: true),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ]),
      );
}
