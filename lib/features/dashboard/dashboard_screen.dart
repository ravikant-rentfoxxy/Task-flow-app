import 'dart:async';

import 'package:flutter/material.dart';
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
import '../tasks/task_detail_screen.dart';

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
  bool loading = true; // first load starts in initState
  DateTime? updatedAt;
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
    if (mounted && !loading) setState(() => loading = true);
    try {
      if (viewingFiltered) {
        final id = int.parse(assigneeFilter.substring(2));
        final uid = assigneeFilter.startsWith('u:') ? id : null;
        final tid = assigneeFilter.startsWith('t:') ? id : null;
        final r = await Future.wait([
          api.tasks(query('all', assigneeId: uid, teamId: tid)),
          api.tasks(query('all', assigneeId: uid, teamId: tid, status: 'DONE', limit: 5)),
        ]);
        if (mounted) setState(() => (mine = r[0].tasks, created = [], done = r[1].tasks, error = null, updatedAt = DateTime.now()));
        return;
      }
      final r = await Future.wait([
        api.tasks(query('mine')),
        api.tasks(query('created')),
        api.tasks(query('mine', status: 'DONE', limit: 5)),
      ]);
      if (mounted) setState(() => (mine = r[0].tasks, created = r[1].tasks, done = r[2].tasks, error = null, updatedAt = DateTime.now()));
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _setFilter(VoidCallback f) {
    setState(f);
    _load();
  }

  // Section anchors so the metric tiles can scroll to their list.
  final _acceptKey = GlobalKey();
  final _escalatedKey = GlobalKey();
  final _progressKey = GlobalKey();
  final _todayKey = GlobalKey();

  void _jumpTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) => Obx(() => _reactiveBuild(context));

  Widget _reactiveBuild(BuildContext context) {
    final me = Get.find<AuthController>().me;
    final realtime = Get.find<RealtimeController>();
    final presence = realtime.presence;
    final live = realtime.connected.value;
    final now = DateTime.now();
    final list = mine ?? const <Task>[];
    final dayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    final needsAck = list.where((t) => t.status == 'ASSIGNED' || t.status == 'DISCUSS').toList();
    final escalated = list.where((t) => t.status == 'ESCALATED').toList();
    final inProgress = list.where((t) => t.status == 'ACKNOWLEDGED' || t.status == 'IN_PROGRESS').toList();
    final dueToday = inProgress.where((t) => isDueInWindow(t, now, dayEnd)).toList();
    final otherProgress = inProgress.where((t) => !dueToday.contains(t)).toList();
    final createdOpen = viewingFiltered
        ? <Task>[]
        : created.where((t) => !closedStatuses.contains(t.status) && t.assigneeId != me?.id).toList();
    final online = presence.users.where((u) => u.id != me?.id).toList();
    final urgent = needsAck.length + escalated.length;

    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: const BrandTopBar(subtitle: 'Dashboard'),
      floatingActionButton: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          boxShadow: [BoxShadow(color: Brand.lime.withValues(alpha: 0.5), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: FloatingActionButton.extended(
          key: const Key('dashboard-new-task'),
          heroTag: 'dashboard-new-task',
          onPressed: () async {
            if (await showComposer(context) != null) _load();
          },
          backgroundColor: Brand.lime,
          foregroundColor: Brand.navy,
          elevation: 0,
          highlightElevation: 0,
          shape: const StadiumBorder(side: BorderSide(color: Brand.navy, width: 2)),
          icon: const Icon(Icons.add_rounded, size: 24),
          label: const Text('New task', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        ),
      ),
      body: RefreshIndicator(
        color: Brand.navy,
        backgroundColor: Brand.lime,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 104),
          children: [
            PageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Hero(
                    greeting: '${greetingFor(now)}${me == null ? '' : ', ${firstName(me.name)}'}',
                    date: fmtDayDate(now),
                    live: live,
                    urgent: mine == null ? null : urgent,
                    loading: loading,
                    updatedAt: updatedAt,
                    due: due,
                    onDue: (d) => _setFilter(() => due = d),
                    onUrgentTap: urgent == 0 ? null : () => _jumpTo(needsAck.isNotEmpty ? _acceptKey : _escalatedKey),
                  ),
                  const SizedBox(height: 12),
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
                  if (canFilter && online.isNotEmpty) ...[const SizedBox(height: 10), _OnlineStrip(users: online)],
                  const SizedBox(height: 14),
                  if (mine == null && error == null)
                    const SkeletonList(count: 3)
                  else if (error != null && mine == null)
                    ErrorView(message: error!, onRetry: _load)
                  else ...[
                    _Metrics(
                      total: list.length,
                      tiles: [
                        _MetricData(const Key('metric-accept'), 'To accept', Icons.timer_outlined, needsAck.length, Brand.lime, Brand.navy,
                            () => _jumpTo(_acceptKey)),
                        _MetricData(const Key('metric-escalated'), 'Escalated', Icons.warning_amber_rounded, escalated.length, _red,
                            Colors.white, () => _jumpTo(_escalatedKey), hot: escalated.isNotEmpty),
                        _MetricData(const Key('metric-progress'), 'In progress', Icons.cached_rounded, inProgress.length, Brand.navy,
                            Brand.lime, () => _jumpTo(otherProgress.isNotEmpty ? _progressKey : _todayKey)),
                        _MetricData(const Key('metric-today'), 'Due today', Icons.calendar_today_rounded, dueToday.length, Brand.surfaceMid,
                            Brand.navy, () => _jumpTo(_todayKey)),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _section('To Accept', '30-min SLA', needsAck, key: _acceptKey, actions: (t) => _acceptActions(t, me)),
                    if (escalated.isNotEmpty)
                      _EscalatedPanel(key: _escalatedKey, tasks: escalated, me: me, onChanged: _load),
                    _section('Due Today', null, dueToday, key: _todayKey),
                    _section('In Progress', null, otherProgress, key: _progressKey),
                    _section('Assigned by Me', 'open', createdOpen),
                    _section('Recently Done', null, done),
                    if (list.isEmpty && created.isEmpty && done.isEmpty)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Brand.outline),
                        ),
                        child: EmptyState(
                          icon: Icons.check_circle_outline_rounded,
                          color: Brand.navy,
                          title: viewingFiltered ? 'No matching tasks' : 'All clear',
                          message: viewingFiltered
                              ? 'Try another person or team.'
                              : 'Nothing on your plate. Create a task or sketch one on the board.',
                          action: viewingFiltered
                              ? null
                              : FilledButton.icon(
                                  style: FilledButton.styleFrom(backgroundColor: Brand.lime, foregroundColor: Brand.navy),
                                  onPressed: () async {
                                    if (await showComposer(context) != null) _load();
                                  },
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('New task', style: TextStyle(fontWeight: FontWeight.w700)),
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

  /// Discuss (assignee only) + Accept + ETA for tasks awaiting a response.
  List<Widget> _acceptActions(Task t, Me? me) {
    if (t.status != 'ASSIGNED') return const [];
    return [
      if (t.assigneeId != null && t.assigneeId == me?.id)
        _DashButton(
          key: ValueKey('discuss-${t.id}'),
          icon: Icons.chat_outlined,
          label: 'Discuss',
          onPressed: () async {
            final r = await promptText(
              context,
              title: 'What should be discussed?',
              hint: 'Optional note for the assigner',
              confirmLabel: 'Discuss',
              required: false,
            );
            if (r == null || !mounted) return;
            if (await runTaskAction(context, t.id, 'discuss', {if (r.trim().isNotEmpty) 'reason': r.trim()})) _load();
          },
        ),
      _DashButton(
        key: ValueKey('accept-${t.id}'),
        icon: Icons.check_circle_rounded,
        label: 'Accept + ETA',
        primary: true,
        onPressed: () async {
          if (await showStatusSheet(context, t) == true) _load();
        },
      ),
    ];
  }

  Widget _section(String title, String? tag, List<Task> tasks, {Key? key, List<Widget> Function(Task)? actions}) {
    if (tasks.isEmpty) return SizedBox.shrink(key: key);
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(title: title, tag: tag, count: tasks.length),
          TaskList(
            tasks: tasks,
            onChanged: _load,
            cardBuilder: (t) => DashboardTaskCard(task: t, onChanged: _load, actions: actions?.call(t) ?? const []),
          ),
        ],
      ),
    );
  }
}

const _red = Color(0xFFDC2626);
const _redSoft = Color(0xFFFEE2E2);
const _redInk = Color(0xFF991B1B);

/// "Thu, 1 Oct".
String fmtDayDate(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
}

// ── Hero ──────────────────────────────────────────────────────────────────

/// Navy command card: live status, date, greeting, urgent count, sync line and
/// the due-date filter.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.greeting,
    required this.date,
    required this.live,
    required this.urgent,
    required this.loading,
    required this.updatedAt,
    required this.due,
    required this.onDue,
    required this.onUrgentTap,
  });
  final String greeting;
  final String date;
  final bool live;
  final int? urgent;
  final bool loading;
  final DateTime? updatedAt;
  final DueFilter due;
  final ValueChanged<DueFilter> onDue;
  final VoidCallback? onUrgentTap;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Brand.navy,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [BoxShadow(color: Brand.navy.withValues(alpha: 0.10), blurRadius: 20, offset: const Offset(0, 6))],
    ),
    child: Stack(
      children: [
        Positioned(
          right: -50,
          top: -60,
          child: _glow(170, 0.10),
        ),
        Positioned(
          right: 40,
          bottom: -70,
          child: _glow(120, 0.06),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (live) const _LivePill(),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      date.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: Colors.white.withValues(alpha: 0.6)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                greeting,
                key: const Key('greeting'),
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: Colors.white, height: 1.2),
              ),
              const SizedBox(height: 10),
              if (urgent != null) _UrgentRow(count: urgent!, onTap: onUrgentTap),
              const SizedBox(height: 14),
              _DueSegments(value: due, onChanged: onDue),
              const SizedBox(height: 8),
              _SyncLine(loading: loading, updatedAt: updatedAt),
            ],
          ),
        ),
      ],
    ),
  );

  static Widget _glow(double size, double alpha) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: Brand.lime.withValues(alpha: alpha), shape: BoxShape.circle),
  );
}

/// Lime count bubble + "need your response", or an all-clear line.
class _UrgentRow extends StatelessWidget {
  const _UrgentRow({required this.count, required this.onTap});
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      return Row(
        children: [
          const Icon(Icons.check_circle_rounded, size: 18, color: Brand.lime),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "You're all caught up",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.8)),
            ),
          ),
        ],
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 34),
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Brand.lime, borderRadius: BorderRadius.circular(10)),
              child: Text(
                '$count',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Brand.navy),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                count == 1 ? 'task needs your response' : 'tasks need your response',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, size: 18, color: Brand.lime),
          ],
        ),
      ),
    );
  }
}

/// "Updated just now" with a spinning sync icon while loading (on navy).
class _SyncLine extends StatefulWidget {
  const _SyncLine({required this.loading, required this.updatedAt});
  final bool loading;
  final DateTime? updatedAt;

  @override
  State<_SyncLine> createState() => _SyncLineState();
}

class _SyncLineState extends State<_SyncLine> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_SyncLine old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.loading && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.loading && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.loading
        ? 'Syncing…'
        : widget.updatedAt == null
        ? ''
        : 'Updated ${timeAgo(widget.updatedAt)}';
    final color = Colors.white.withValues(alpha: 0.55);
    return Row(
      children: [
        RotationTransition(
          turns: _spin,
          child: Icon(Icons.sync_rounded, size: 13, color: color),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: color),
          ),
        ),
      ],
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(color: Brand.lime, borderRadius: BorderRadius.circular(99)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(color: Brand.navy, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        const Text(
          'LIVE',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: Brand.navy),
        ),
      ],
    ),
  );
}

/// Segmented due filter on navy: any · today · custom range (lime selected).
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
        : 'Custom range';
    Widget seg(String key, String label, bool selected, VoidCallback onTap) => Expanded(
      child: GestureDetector(
        key: Key(key),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 32,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(color: selected ? Brand.lime : Colors.transparent, borderRadius: BorderRadius.circular(9)),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? Brand.navy : Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
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

// ── Filters ───────────────────────────────────────────────────────────────

class _SoftChip extends StatelessWidget {
  const _SoftChip({super.key, required this.icon, required this.label, required this.onTap, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Material(
    color: active ? Brand.limeLight : Colors.white,
    shape: StadiumBorder(side: BorderSide(color: active ? Brand.limeDim : Brand.outline)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? Brand.navy : Brand.onVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w600, color: Brand.navy),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Metrics ───────────────────────────────────────────────────────────────

class _MetricData {
  const _MetricData(this.key, this.label, this.icon, this.value, this.iconBg, this.iconFg, this.onTap, {this.hot = false});
  final Key key;
  final String label;
  final IconData icon;
  final int value;
  final Color iconBg;
  final Color iconFg;
  final VoidCallback onTap;
  final bool hot;
}

/// One slim row of four tappable counters (2×2 on very narrow screens).
class _Metrics extends StatelessWidget {
  const _Metrics({required this.total, required this.tiles});
  final int total;
  final List<_MetricData> tiles;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final cols = c.maxWidth < 300 ? 2 : 4;
      final w = (c.maxWidth - (cols - 1) * 8) / cols;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final t in tiles) SizedBox(width: w, child: _MetricTile(data: t, total: total))],
      );
    },
  );
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.data, required this.total});
  final _MetricData data;
  final int total;

  @override
  Widget build(BuildContext context) => Material(
    key: data.key,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: data.hot ? _red.withValues(alpha: 0.3) : Brand.outline),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: data.value == 0 ? null : data.onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: data.iconBg, borderRadius: BorderRadius.circular(8)),
              child: Icon(data.icon, size: 15, color: data.iconFg),
            ),
            const SizedBox(height: 8),
            Text(
              '${data.value}',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: -0.6,
                color: data.hot ? _red : Brand.navy,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Brand.onVariant),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : data.value / total,
                minHeight: 3,
                color: data.hot ? _red : (data.iconBg == Brand.surfaceMid ? Brand.navy : (data.iconBg == Brand.navy ? Brand.lime : data.iconBg)),
                backgroundColor: Brand.surfaceMid,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Sections ──────────────────────────────────────────────────────────────

/// Lime accent bar · title · optional lime tag ······ navy count bubble.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count, this.tag});
  final String title;
  final int count;
  final String? tag;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(color: Brand.lime, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: Brand.navy),
                ),
              ),
              if (tag != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Brand.limeLight,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: Brand.limeDim),
                  ),
                  child: Text(
                    tag!,
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Brand.navy),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          constraints: const BoxConstraints(minWidth: 24),
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Brand.navy, borderRadius: BorderRadius.circular(99)),
          child: Text(
            '$count',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Brand.lime),
          ),
        ),
      ],
    ),
  );
}

/// Equal-width card button: lime primary, grey secondary.
class _DashButton extends StatelessWidget {
  const _DashButton({super.key, required this.icon, required this.label, required this.onPressed, this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    style: FilledButton.styleFrom(
      backgroundColor: primary ? Brand.lime : Brand.surfaceLow,
      foregroundColor: Brand.navy,
      elevation: 0,
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: primary ? BorderSide.none : BorderSide(color: Brand.outline.withValues(alpha: 0.8)),
      ),
      textStyle: TextStyle(fontSize: 12.5, fontWeight: primary ? FontWeight.w800 : FontWeight.w600),
    ),
    onPressed: onPressed,
    icon: Icon(icon, size: 16),
    label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
  );
}

/// Escalated tasks in a red-tinted panel; each needs an explanation (assignee)
/// or a review (Admin/CEO).
class _EscalatedPanel extends StatelessWidget {
  const _EscalatedPanel({super.key, required this.tasks, required this.me, required this.onChanged});
  final List<Task> tasks;
  final Me? me;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF2F2),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _red.withValues(alpha: 0.18)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Escalated',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Brand.navy, letterSpacing: -0.2),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(99)),
                child: Text(
                  'Explanation required · ${tasks.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        for (final t in tasks) ...[const SizedBox(height: 10), _EscalatedItem(task: t, me: me, onChanged: onChanged)],
      ],
    ),
  );
}

class _EscalatedItem extends StatelessWidget {
  const _EscalatedItem({required this.task, required this.me, required this.onChanged});
  final Task task;
  final Me? me;
  final VoidCallback onChanged;

  static String _span(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 48) return d.inHours == 1 ? '1 hour' : '${d.inHours} hours';
    return '${d.inDays} days';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final due = task.dueAt;
    final eta = task.etaAt;
    final headline = due != null && due.isBefore(now) ? 'Overdue by ${_span(now.difference(due))}' : 'Escalated';
    final snippet = htmlToPlainText(task.description).split('\n').first.trim();
    final detail = eta != null && eta.isBefore(now)
        ? 'Previous ETA passed ${fmtDateTime(eta)}.${snippet.isEmpty ? '' : ' $snippet'}'
        : snippet;
    final mine = task.assigneeId != null && task.assigneeId == me?.id;

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: _red.withValues(alpha: 0.12))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('task-card-${task.id}'),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: task.id)));
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: _red, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _red),
                    ),
                  ),
                  if (task.priority == 'URGENT' || task.priority == 'HIGH')
                    DashTag(task.priority, fg: _redInk, bg: _redSoft, bold: true),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Brand.navy, height: 1.3),
              ),
              const SizedBox(height: 2),
              Text(
                mine ? 'From ${displayName(task.creatorName)}' : 'Assigned to ${task.who}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: Brand.onVariant),
              ),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, height: 1.4, color: Brand.onVariant),
                ),
              ],
              const SizedBox(height: 10),
              _DashButton(
                key: ValueKey('escalation-${task.id}'),
                icon: mine ? Icons.edit_note_rounded : Icons.fact_check_outlined,
                label: mine ? 'Submit Delay Explanation' : 'Review escalation',
                primary: true,
                onPressed: () async {
                  if (await showStatusSheet(context, task) == true) onChanged();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnlineStrip extends StatelessWidget {
  const _OnlineStrip({required this.users});
  final List<({int id, String name})> users;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Brand.outline),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: Brand.lime, borderRadius: BorderRadius.circular(99)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: Brand.navy, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(
                '${users.length} online',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Brand.navy),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
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
                        child: Avatar(u.name, size: 28, online: true),
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
