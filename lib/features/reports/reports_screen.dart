import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/format.dart';
import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/files.dart';
import '../../widgets/filters.dart';
import '../shell/top_bar.dart';
import '../tasks/task_detail_screen.dart';

/// Report period filter: all | today | 7 | 30 | 90 | range.
class ReportPeriod {
  const ReportPeriod({this.mode = 'all', this.from, this.to});
  final String mode;
  final DateTime? from;
  final DateTime? to;

  Map<String, dynamic> toQuery() {
    if (mode == 'today') {
      final b = todayBounds();
      return {'createdFrom': b.from, 'createdTo': b.to};
    }
    if (mode == '7' || mode == '30' || mode == '90') return {'days': mode};
    if (mode == 'range') {
      final b = rangeBounds(from, to);
      return b == null ? {} : {'createdFrom': b.from, 'createdTo': b.to};
    }
    return {};
  }
}

String reportsCsv(List<ReportPerson> people) {
  String cell(Object? v) {
    final s = '${v ?? ''}';
    return s.contains(',') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final rows = [
    'Name,Team,Open,Overdue,No response,Escalations,Done,Done (self),Assigned out,Done by assignee,Done on time,Avg response (min)',
    for (final p in people)
      [p.name, p.teamName, p.open, p.overdue, p.noResponse, p.escalations, p.done, p.doneSelf, p.assignedOut, p.doneByAssignee, p.doneOnTime, p.avgResponseMin]
          .map(cell)
          .join(','),
  ];
  return rows.join('\n');
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Report? data;
  String? error;
  ReportPeriod period = const ReportPeriod();
  bool showOverall = true;
  int? teamId;
  int? typeId;
  List<Team> teams = [];
  List<TaskType> types = [];

  TaskFlowApi get api => Get.find<TaskFlowApi>();
  Me? get me => Get.find<AuthController>().me;

  @override
  void initState() {
    super.initState();
    if (me?.isAdminOrCeo ?? false) {
      api.teams().then((t) => mounted ? setState(() => teams = t) : null).catchError((_) {});
    }
    _loadTypes();
    _load();
  }

  Map<String, dynamic> _query([Map<String, dynamic> extra = const {}]) {
    final q = <String, dynamic>{...period.toQuery(), 'teamId': teamId, 'taskTypeId': typeId};
    if (q.containsKey('createdFrom') || q.containsKey('days')) q['overall'] = showOverall ? 'true' : 'false';
    return {...q, ...extra};
  }

  Future<void> _load() async {
    try {
      final r = await api.report(_query());
      if (mounted) setState(() => (data = r, error = null));
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    }
  }

  Future<void> _loadTypes() async {
    final tid = (me?.isAdminOrCeo ?? false) ? teamId : me?.teamId;
    if (tid == null) {
      setState(() => types = []);
      return;
    }
    try {
      final t = await api.taskTypes(teamId: tid);
      if (mounted) setState(() => types = t);
    } catch (_) {
      if (mounted) setState(() => types = []);
    }
  }

  void _set(VoidCallback f) {
    setState(f);
    _load();
  }

  bool get _hasFilters => teamId != null || typeId != null || period.mode != 'all' || !showOverall;

  Future<void> _drill(String metric, String title, [Map<String, dynamic> extra = const {}]) async {
    await showAppSheet(
      context,
      expand: true,
      builder: (ctx) => _DrillSheet(title: title, load: () => api.reportDrill(_query({'list': metric, ...extra}))),
    );
  }

  Future<void> _export() async {
    final d = data;
    if (d == null) return;
    try {
      final ok = await saveBytes('taskflow-report.csv', utf8.encode(reportsCsv(d.people)), mimeType: 'text/csv');
      if (ok) toast('Report exported');
    } catch (e) {
      toastError(e, 'Export failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final isBoss = me?.isAdminOrCeo ?? false;
    const periods = [('all', 'All time'), ('today', 'Today'), ('7', '7 days'), ('30', '30 days'), ('90', '90 days')];

    return Scaffold(
      appBar: TopBar(title: 'Reports', actions: [
        if (d != null && d.people.isNotEmpty)
          IconButton(key: const Key('export-csv'), tooltip: 'Export CSV', onPressed: _export, icon: const Icon(Icons.download_rounded)),
      ]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          PageBody(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (d != null)
                Row(children: [
                  Expanded(child: Text(d.scopeLabel.toUpperCase(), style: Theme.of(context).textTheme.labelSmall)),
                  Pill(
                    '${d.summary.attention} need${d.summary.attention == 1 ? 's' : ''} attention',
                    key: const Key('attention-pill'),
                    icon: d.summary.attention > 0 ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                    fg: d.summary.attention > 0 ? TF.coral : TF.green,
                    bg: d.summary.attention > 0 ? TF.coralSoft : TF.greenSoft,
                  ),
                ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (isBoss)
                  MenuChip(
                    key: const Key('report-team'),
                    label: teamId == null ? 'All teams' : teams.where((t) => t.id == teamId).firstOrNull?.name ?? 'Team',
                    icon: Icons.groups_2_outlined,
                    active: teamId != null,
                    options: [('', 'All teams'), for (final t in teams) ('${t.id}', t.name)],
                    onSelected: (v) {
                      _set(() {
                        teamId = int.tryParse(v);
                        typeId = null;
                      });
                      _loadTypes();
                    },
                  ),
                if (types.isNotEmpty)
                  MenuChip(
                    label: typeId == null ? 'All task types' : types.where((t) => t.id == typeId).firstOrNull?.name ?? 'Type',
                    icon: Icons.sell_outlined,
                    active: typeId != null,
                    options: [('', 'All task types'), for (final t in types) ('${t.id}', t.name)],
                    onSelected: (v) => _set(() => typeId = int.tryParse(v)),
                  ),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in periods)
                  ChoiceChip(
                    key: ValueKey('period-${p.$1}'),
                    label: Text(p.$2),
                    selected: period.mode == p.$1,
                    showCheckmark: false,
                    onSelected: (_) => _set(() => period = ReportPeriod(mode: p.$1)),
                  ),
                ChoiceChip(
                  label: Text(period.mode == 'range' ? '${fmtShortDate(period.from)} – ${fmtShortDate(period.to)}' : 'Range'),
                  selected: period.mode == 'range',
                  showCheckmark: false,
                  onSelected: (_) async {
                    final now = DateTime.now();
                    final r = await showDateRangePicker(context: context, firstDate: DateTime(now.year - 3), lastDate: now);
                    if (r != null) _set(() => period = ReportPeriod(mode: 'range', from: r.start, to: r.end));
                  },
                ),
              ]),
              if (period.mode != 'all')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Include open work created earlier (overall)'),
                  value: showOverall,
                  onChanged: (v) => _set(() => showOverall = v),
                ),
              if (_hasFilters)
                TextButton.icon(
                  onPressed: () {
                    _set(() {
                      teamId = null;
                      typeId = null;
                      period = const ReportPeriod();
                      showOverall = true;
                    });
                    _loadTypes();
                  },
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Reset filters'),
                ),
              const SizedBox(height: 14),
              if (d == null)
                error != null ? ErrorView(message: error!, onRetry: _load) : const SkeletonList(count: 3)
              else ...[
                _stats(d.summary),
                if (d.byType.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'By task type', icon: Icons.sell_outlined),
                  _typeTable(d.byType),
                ],
                if (d.people.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  SectionHeader(title: d.isPersonal ? 'Your performance' : 'By person', icon: Icons.people_outline_rounded, color: TF.violet),
                  _peopleTable(d.people),
                ],
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _stats(ReportSummary s) {
    final tiles = [
      _Stat('Open tasks', '${s.open}', Icons.inbox_outlined, TF.primary, onTap: () => _drill('open', 'Open tasks')),
      _Stat('Overdue', '${s.overdue}', Icons.schedule_rounded, TF.coral, hot: s.overdue > 0, onTap: () => _drill('overdue', 'Overdue tasks')),
      _Stat('No response (SLA)', '${s.noResponse}', Icons.notifications_off_outlined, TF.coral, hot: s.noResponse > 0, onTap: () => _drill('no_response', 'No response (SLA breached)')),
      _Stat('Awaiting explanation', '${s.escalatedAwaiting}', Icons.warning_amber_rounded, TF.amber, hot: s.escalatedAwaiting > 0, onTap: () => _drill('esc_awaiting', 'Escalations awaiting explanation')),
      _Stat('Pending review', '${s.escalatedPendingReview}', Icons.balance_rounded, TF.amber, hot: s.escalatedPendingReview > 0, onTap: () => _drill('esc_pending', 'Explanations pending review')),
      _Stat('Due this week', '${s.dueThisWeek}', Icons.date_range_rounded, TF.sky, onTap: () => _drill('due_week', 'Due this week')),
      _Stat('Done', '${s.done}', Icons.check_circle_outline_rounded, TF.green, onTap: () => _drill('done', 'Done tasks')),
      _Stat('On-time completion', s.onTimePct == null ? '—' : '${s.onTimePct}%', Icons.speed_rounded, TF.green, progress: s.onTimePct),
      _Stat('Avg response time', s.avgResponseMin == null ? '—' : '${s.avgResponseMin}m', Icons.bolt_rounded, TF.violet),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 380 ? 2 : 1);
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [for (final t in tiles) SizedBox(width: w, child: _StatTile(stat: t))]);
    });
  }

  Widget _num(int v, VoidCallback onTap, {Color? color}) => InkWell(
        onTap: onTap,
        child: Text('$v',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: color ?? TF.ink,
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
              decorationColor: TF.faint,
            )),
      );

  Widget _table(List<DataColumn> cols, List<DataRow> rows) => Surface(
        padding: EdgeInsets.zero,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingTextStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: TF.muted, letterSpacing: 0.4),
            headingRowHeight: 40,
            dataRowMinHeight: 48,
            dataRowMaxHeight: 64,
            columnSpacing: 22,
            columns: cols,
            rows: rows,
          ),
        ),
      );

  Widget _typeTable(List<ReportType> types) => _table(
        const [
          DataColumn(label: Text('TEAM')),
          DataColumn(label: Text('TASK TYPE')),
          DataColumn(label: Text('TOTAL'), numeric: true),
          DataColumn(label: Text('OPEN'), numeric: true),
          DataColumn(label: Text('OVERDUE'), numeric: true),
          DataColumn(label: Text('NO RESP.'), numeric: true),
          DataColumn(label: Text('DONE'), numeric: true),
        ],
        [
          for (final t in types)
            DataRow(cells: [
              DataCell(Text(t.teamName ?? '—', style: const TextStyle(fontSize: 12.5, color: TF.muted))),
              DataCell(Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700))),
              DataCell(_num(t.total, () => _drill('total', '${t.name} — all tasks', {'taskTypeId': t.id}))),
              DataCell(_num(t.open, () => _drill('open', '${t.name} — open', {'taskTypeId': t.id}))),
              DataCell(_num(t.overdue, () => _drill('overdue', '${t.name} — overdue', {'taskTypeId': t.id}), color: t.overdue > 0 ? TF.coral : TF.faint)),
              DataCell(_num(t.noResponse, () => _drill('no_response', '${t.name} — no response', {'taskTypeId': t.id}), color: t.noResponse > 0 ? TF.coral : TF.faint)),
              DataCell(_num(t.done, () => _drill('done', '${t.name} — done', {'taskTypeId': t.id}), color: t.done > 0 ? TF.green : TF.faint)),
            ]),
        ],
      );

  Widget _peopleTable(List<ReportPerson> people) => _table(
        const [
          DataColumn(label: Text('PERSON')),
          DataColumn(label: Text('OPEN'), numeric: true),
          DataColumn(label: Text('OVERDUE'), numeric: true),
          DataColumn(label: Text('NO RESP.'), numeric: true),
          DataColumn(label: Text('ESCAL.'), numeric: true),
          DataColumn(label: Text('DONE')),
          DataColumn(label: Text('ON TIME')),
          DataColumn(label: Text('AVG RESP.')),
        ],
        [
          for (final p in people)
            DataRow(cells: [
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                Avatar(p.name, size: 30),
                const SizedBox(width: 10),
                Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(displayName(p.name), style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (p.role == 'QA') const Padding(padding: EdgeInsets.only(left: 6), child: Pill('QA', fg: TF.sky, bg: TF.skySoft)),
                  ]),
                  Text(p.teamName ?? '—', style: const TextStyle(fontSize: 11.5, color: TF.muted)),
                ]),
              ])),
              DataCell(_num(p.open, () => _drill('open', '${p.name} — open', {'personId': p.id}))),
              DataCell(_num(p.overdue, () => _drill('overdue', '${p.name} — overdue', {'personId': p.id}), color: p.overdue > 0 ? TF.coral : TF.faint)),
              DataCell(_num(p.noResponse, () => _drill('no_response', '${p.name} — no response', {'personId': p.id}), color: p.noResponse > 0 ? TF.coral : TF.faint)),
              DataCell(_num(p.escalations, () => _drill('escalations', '${p.name} — escalations', {'personId': p.id}), color: p.escalations > 0 ? TF.amber : TF.faint)),
              DataCell(p.role != 'QA'
                  ? _num(p.done, () => _drill('done', '${p.name} — done', {'personId': p.id}), color: p.done > 0 ? TF.green : TF.faint)
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      _num(p.done, () => _drill('done', '${p.name} — all done', {'personId': p.id}), color: TF.green),
                      const Text('  self ', style: TextStyle(fontSize: 11, color: TF.muted)),
                      _num(p.doneSelf, () => _drill('done_self', '${p.name} — done (self)', {'personId': p.id})),
                      const Text('  assigned ', style: TextStyle(fontSize: 11, color: TF.muted)),
                      _num(p.assignedOut, () => _drill('assigned_out', '${p.name} — assigned out', {'personId': p.id}), color: TF.violet),
                      const Text('  user done ', style: TextStyle(fontSize: 11, color: TF.muted)),
                      _num(p.doneByAssignee, () => _drill('done_by_assignee', '${p.name} — done by assignee', {'personId': p.id}), color: TF.sky),
                    ])),
              DataCell(p.onTimePct == null
                  ? const Text('—', style: TextStyle(color: TF.faint))
                  : Pill('${p.onTimePct}%', fg: p.onTimePct! >= 80 ? TF.green : TF.amber, bg: p.onTimePct! >= 80 ? TF.greenSoft : TF.amberSoft)),
              DataCell(Text(p.avgResponseMin == null ? '—' : '${p.avgResponseMin}m', style: const TextStyle(color: TF.muted))),
            ]),
        ],
      );
}

class _Stat {
  const _Stat(this.label, this.value, this.icon, this.color, {this.onTap, this.hot = false, this.progress});
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool hot;
  final int? progress;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});
  final _Stat stat;

  @override
  Widget build(BuildContext context) => Material(
        color: TF.surface,
        borderRadius: BorderRadius.circular(TF.radius),
        child: InkWell(
          key: ValueKey('stat-${stat.label}'),
          borderRadius: BorderRadius.circular(TF.radius),
          onTap: stat.onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(TF.radius), border: Border.all(color: TF.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: stat.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Icon(stat.icon, color: stat.color, size: 18),
                ),
                const Spacer(),
                if (stat.onTap != null) const Icon(Icons.arrow_forward_rounded, size: 16, color: TF.faint),
              ]),
              const SizedBox(height: 10),
              Text(stat.value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1, color: stat.hot ? stat.color : TF.ink)),
              const SizedBox(height: 4),
              Text(stat.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TF.muted, fontWeight: FontWeight.w600)),
              if (stat.progress != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(value: stat.progress! / 100, minHeight: 5, color: TF.green, backgroundColor: TF.sunken),
                ),
              ],
            ]),
          ),
        ),
      );
}

class _DrillSheet extends StatefulWidget {
  const _DrillSheet({required this.title, required this.load});
  final String title;
  final Future<List<Task>> Function() load;

  @override
  State<_DrillSheet> createState() => _DrillSheetState();
}

class _DrillSheetState extends State<_DrillSheet> {
  List<Task>? tasks;
  String? error;

  @override
  void initState() {
    super.initState();
    widget.load().then((t) {
      if (mounted) setState(() => tasks = t);
    }).catchError((Object e) {
      if (mounted) setState(() => error = errorText(e));
    });
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        SheetTitle(widget.title, subtitle: tasks == null ? null : '${tasks!.length} task${tasks!.length == 1 ? '' : 's'}'),
        Expanded(
          child: tasks == null
              ? (error != null ? ErrorView(message: error!) : const Padding(padding: EdgeInsets.all(16), child: SkeletonList(height: 64)))
              : tasks!.isEmpty
                  ? const EmptyState(icon: Icons.celebration_outlined, color: TF.green, title: 'No tasks in this bucket')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: tasks!.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final t = tasks![i];
                        return Material(
                          color: TF.surface,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            key: ValueKey('drill-${t.id}'),
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              final nav = Navigator.of(context);
                              nav.pop();
                              nav.push(MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: t.id)));
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: TF.line)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Expanded(
                                    child: Text('#${t.id}  ${t.title}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  ),
                                  const SizedBox(width: 8),
                                  StatusPill(t.status),
                                ]),
                                const SizedBox(height: 6),
                                Text(
                                  '${t.assigneeName ?? 'Unassigned'} · Due ${fmtDateTime(t.dueAt)} · ETA ${t.etaAt == null ? '—' : fmtDateTime(t.etaAt)}',
                                  style: const TextStyle(fontSize: 12, color: TF.muted),
                                ),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ]);
}
