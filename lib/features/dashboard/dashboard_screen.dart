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

    final total = list.length;

    return Scaffold(
      backgroundColor: Brand.bg,
      appBar: const BrandTopBar(subtitle: 'Dashboard'),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('dashboard-new-task'),
        heroTag: 'dashboard-new-task',
        onPressed: () async {
          if (await showComposer(context) != null) _load();
        },
        backgroundColor: Brand.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: const StadiumBorder(),
        icon: const Icon(Icons.add_rounded, size: 26),
        label: const Text('New task', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ),
      body: RefreshIndicator(
        color: Brand.primary,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 104),
          children: [
            PageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('EEEE, d MMMM').format(now).toUpperCase(),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1, color: Brand.primaryDeep),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${greetingFor(now)}${me == null ? '' : ', ${firstName(me.name)}'}',
                    key: const Key('greeting'),
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.7, color: Brand.ink, height: 1.15),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (canFilter)
                        _SoftChip(
                          key: const Key('dashboard-filter'),
                          icon: Icons.person_search_outlined,
                          label: userOrTeamLabel(assigneeFilter, users, teams, empty: 'Everyone (my dashboard)'),
                          active: viewingFiltered,
                          onTap: () async {
                            final v = await pickUserOrTeam(
                              context,
                              users: users,
                              teams: teams,
                              selected: assigneeFilter,
                              emptyLabel: 'Everyone (my dashboard)',
                            );
                            if (v != null) _setFilter(() => assigneeFilter = v);
                          },
                        ),
                      _SoftChip(
                        icon: Icons.gesture_rounded,
                        label: 'Scribble',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScribbleScreen())),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _DueSegments(value: due, onChanged: (d) => _setFilter(() => due = d)),
                  if (canFilter && online.isNotEmpty) ...[const SizedBox(height: 12), _OnlineStrip(users: online)],
                  const SizedBox(height: 18),
                  if (mine == null && error == null)
                    const SkeletonList(count: 3)
                  else if (error != null && mine == null)
                    ErrorView(message: error!, onRetry: _load)
                  else ...[
                    _Metrics(
                      total: total,
                      needsAck: needsAck.length,
                      escalated: escalated.length,
                      inProgress: inProgress.length,
                      dueToday: dueToday.length,
                    ),
                    const SizedBox(height: 28),
                    _section(
                      'Accept response',
                      '30-min SLA',
                      needsAck,
                      tagFg: Brand.amber,
                      tagBg: Brand.amberSoft,
                      action: (t) => t.status == 'ASSIGNED'
                          ? FilledButton.icon(
                              key: ValueKey('accept-${t.id}'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Brand.primary,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 48),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              onPressed: () async {
                                if (await showStatusSheet(context, t) == true) _load();
                              },
                              icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                              label: const Text('Accept + ETA'),
                            )
                          : null,
                    ),
                    if (escalated.isNotEmpty) _EscalatedPanel(tasks: escalated, onChanged: _load),
                    _section('Due today', null, dueToday),
                    _section('In progress', null, inProgress.where((t) => !dueToday.contains(t)).toList()),
                    _section('Assigned by me', 'open', createdOpen, tagFg: TF.violet, tagBg: TF.violetSoft),
                    _section('Recently done', null, doneRecent),
                    if (list.isEmpty && created.isEmpty && done.isEmpty)
                      Container(
                        decoration: BoxDecoration(
                          color: Brand.card,
                          borderRadius: BorderRadius.circular(Brand.radius),
                          boxShadow: Brand.shadow,
                        ),
                        child: EmptyState(
                          icon: Icons.check_circle_outline_rounded,
                          color: TF.green,
                          title: viewingFiltered ? 'No matching tasks' : 'All clear',
                          message: viewingFiltered
                              ? 'Try another person or team.'
                              : 'Nothing on your plate. Create a task or sketch one on the board.',
                          action: viewingFiltered
                              ? null
                              : FilledButton.icon(
                                  style: FilledButton.styleFrom(backgroundColor: Brand.primary),
                                  onPressed: () async {
                                    if (await showComposer(context) != null) _load();
                                  },
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('New task'),
                                ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(
    String title,
    String? tag,
    List<Task> tasks, {
    Color tagFg = Brand.inkSoft,
    Color tagBg = Brand.slateSoft,
    Widget? Function(Task)? action,
  }) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title: title, tag: tag, tagFg: tagFg, tagBg: tagBg, count: tasks.length),
          TaskList(tasks: tasks, onChanged: _load, actionFor: action, roomy: true),
        ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────

// ── Filters ───────────────────────────────────────────────────────────────

class _SoftChip extends StatelessWidget {
  const _SoftChip({super.key, required this.icon, required this.label, required this.onTap, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Material(
    color: active ? Brand.primarySoft : Brand.card,
    shape: StadiumBorder(side: BorderSide(color: active ? Brand.primary.withValues(alpha: 0.3) : Brand.line)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: active ? Brand.primaryDeep : Brand.muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: active ? Brand.primaryDeep : Brand.inkSoft),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Segmented version of [DueFilterBar]: any · today · date range.
class _DueSegments extends StatelessWidget {
  const _DueSegments({required this.value, required this.onChanged});
  final DueFilter value;
  final ValueChanged<DueFilter> onChanged;

  Future<void> _pickRange(BuildContext context) async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
      initialDateRange: value.from != null && value.to != null ? DateTimeRange(start: value.from!, end: value.to!) : null,
    );
    if (r != null) onChanged(DueFilter(mode: 'range', from: r.start, to: r.end));
  }

  @override
  Widget build(BuildContext context) {
    final rangeLabel = value.mode == 'range' && value.from != null && value.to != null
        ? '${fmtShortDate(value.from)} – ${fmtShortDate(value.to)}'
        : 'Date range';
    Widget seg(String key, String label, bool selected, VoidCallback onTap) => Expanded(
      child: GestureDetector(
        key: Key(key),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 42,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? Brand.card : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected ? [BoxShadow(color: Brand.ink.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))] : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Brand.primaryDeep : Brand.inkSoft,
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Brand.slateSoft.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          seg('due-all', 'Any due date', value.mode == 'all', () => onChanged(const DueFilter())),
          seg('due-today', 'Due today', value.mode == 'today', () => onChanged(const DueFilter(mode: 'today'))),
          seg('due-range', rangeLabel, value.mode == 'range', () => _pickRange(context)),
        ],
      ),
    );
  }
}

// ── Metrics ───────────────────────────────────────────────────────────────

class _Metrics extends StatelessWidget {
  const _Metrics({required this.total, required this.needsAck, required this.escalated, required this.inProgress, required this.dueToday});
  final int total;
  final int needsAck;
  final int escalated;
  final int inProgress;
  final int dueToday;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _MetricTile(
        key: const Key('metric-accept'),
        icon: Icons.timer_outlined,
        color: Brand.sky,
        soft: Brand.skySoft,
        value: needsAck,
        total: total,
        label: 'Accept response',
      ),
      _MetricTile(
        key: const Key('metric-escalated'),
        icon: Icons.warning_amber_rounded,
        color: Brand.red,
        soft: Brand.redSoft,
        value: escalated,
        total: total,
        label: 'Escalated',
        hot: escalated > 0,
      ),
      _MetricTile(
        key: const Key('metric-progress'),
        icon: Icons.autorenew_rounded,
        color: Brand.primary,
        soft: Brand.primarySoft,
        value: inProgress,
        total: total,
        label: 'In progress',
      ),
      _MetricTile(
        key: const Key('metric-today'),
        icon: Icons.today_rounded,
        color: Brand.slate,
        soft: Brand.slateSoft,
        value: dueToday,
        total: total,
        label: 'Due today',
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 720 ? 4 : 2;
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    super.key,
    required this.icon,
    required this.color,
    required this.soft,
    required this.value,
    required this.total,
    required this.label,
    this.hot = false,
  });
  final IconData icon;
  final Color color;
  final Color soft;
  final int value;
  final int total;
  final String label;
  final bool hot;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
    decoration: BoxDecoration(
      color: Brand.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: hot ? color.withValues(alpha: 0.3) : Brand.line),
      boxShadow: Brand.shadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.1, letterSpacing: -0.5, color: hot ? color : Brand.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Brand.inkSoft, height: 1.2),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : value / total,
            minHeight: 4,
            color: color,
            backgroundColor: Brand.slateSoft,
          ),
        ),
      ],
    ),
  );
}

// ── Sections ──────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count, this.tag, this.tagFg = Brand.inkSoft, this.tagBg = Brand.slateSoft});
  final String title;
  final int count;
  final String? tag;
  final Color tagFg;
  final Color tagBg;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: Brand.ink),
          ),
        ),
        if (tag != null) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: tagBg, borderRadius: BorderRadius.circular(99)),
            child: Text(
              tag!,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: tagFg),
            ),
          ),
        ],
        const Spacer(),
        Text(
          count == 1 ? '1 task' : '$count tasks',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Brand.muted),
        ),
      ],
    ),
  );
}

/// Escalated tasks sit in a tinted red panel so they stand out.
class _EscalatedPanel extends StatelessWidget {
  const _EscalatedPanel({required this.tasks, required this.onChanged});
  final List<Task> tasks;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 26),
    padding: const EdgeInsets.fromLTRB(14, 16, 14, 4),
    decoration: BoxDecoration(
      color: Brand.redPanel,
      borderRadius: BorderRadius.circular(Brand.radius + 2),
      border: Border.all(color: Brand.red.withValues(alpha: 0.12)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Icon(Icons.error_outline_rounded, color: Brand.red, size: 24),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Escalated',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: Brand.red, height: 1.2),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Brand.red, borderRadius: BorderRadius.circular(99)),
                  child: Text(
                    'Explanation required · ${tasks.length}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
        TaskList(tasks: tasks, onChanged: onChanged, roomy: true),
      ],
    ),
  );
}

class _OnlineStrip extends StatelessWidget {
  const _OnlineStrip({required this.users});
  final List<({int id, String name})> users;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    decoration: BoxDecoration(
      color: Brand.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Brand.line),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: Brand.greenSoft, borderRadius: BorderRadius.circular(99)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(color: Brand.green, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                '${users.length} online',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Brand.green),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final u in users)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: 'Chat with ${u.name}',
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => openChatWithUser(context, u.id),
                        child: Avatar(u.name, size: 30, online: true),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
