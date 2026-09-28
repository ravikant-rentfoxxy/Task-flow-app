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
      backgroundColor: Brand.bg,
      appBar: const BrandTopBar(subtitle: 'Reports'),
      body: RefreshIndicator(
        color: Brand.primary,
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: [
          PageBody(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (d != null) ...[
                Row(children: [
                  Expanded(
                    child: Text(d.scopeLabel.toUpperCase(),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: Brand.inkSoft)),
                  ),
                  _AttentionPill(key: const Key('attention-pill'), count: d.summary.attention),
                ]),
                const SizedBox(height: 12),
              ],
              if (isBoss || types.isNotEmpty) ...[
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (isBoss)
                    _MenuPill(
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
                    _MenuPill(
                      label: typeId == null ? 'All task types' : types.where((t) => t.id == typeId).firstOrNull?.name ?? 'Type',
                      icon: Icons.sell_outlined,
                      active: typeId != null,
                      options: [('', 'All task types'), for (final t in types) ('${t.id}', t.name)],
                      onSelected: (v) => _set(() => typeId = int.tryParse(v)),
                    ),
                ]),
                const SizedBox(height: 10),
              ],
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(children: [
                  for (final p in periods) ...[
                    _PeriodPill(
                      key: ValueKey('period-${p.$1}'),
                      label: p.$2,
                      selected: period.mode == p.$1,
                      onTap: () => _set(() => period = ReportPeriod(mode: p.$1)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  _PeriodPill(
                    icon: Icons.calendar_today_outlined,
                    label: period.mode == 'range' ? '${fmtShortDate(period.from)} – ${fmtShortDate(period.to)}' : 'Range',
                    selected: period.mode == 'range',
                    onTap: () async {
                      final now = DateTime.now();
                      final r = await showDateRangePicker(context: context, firstDate: DateTime(now.year - 3), lastDate: now);
                      if (r != null) _set(() => period = ReportPeriod(mode: 'range', from: r.start, to: r.end));
                    },
                  ),
                ]),
              ),
              if (period.mode != 'all') ...[
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(color: Brand.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: Brand.line)),
                  child: SwitchListTile(
                    dense: true,
                    activeThumbColor: Colors.white,
                    activeTrackColor: Brand.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    title: const Text('Include open work created earlier (overall)',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: Brand.ink)),
                    value: showOverall,
                    onChanged: (v) => _set(() => showOverall = v),
                  ),
                ),
              ],
              if (_hasFilters)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Brand.primaryDeep),
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
                ),
              const SizedBox(height: 14),
              if (d == null)
                error != null ? ErrorView(message: error!, onRetry: _load) : const SkeletonList(count: 3)
              else ...[
                _stats(d.summary),
                if (d.byType.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _typeCard(d.byType),
                ],
                if (d.people.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _peopleCard(d.people, personal: d.isPersonal),
                  const SizedBox(height: 20),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Brand.primary.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6))],
                    ),
                    child: FilledButton.icon(
                      key: const Key('export-csv'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Brand.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      onPressed: _export,
                      icon: const Icon(Icons.download_rounded, size: 22),
                      label: const Text('Export CSV'),
                    ),
                  ),
                ],
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _stats(ReportSummary s) {
    final hero = [
      _Stat('On-time completion', s.onTimePct == null ? '—' : '${s.onTimePct}%', Icons.verified_outlined, Brand.primary,
          progress: s.onTimePct),
      _Stat('Avg response time', s.avgResponseMin == null ? '—' : '${s.avgResponseMin}m', Icons.speed_rounded, Brand.green),
      _Stat('Overdue', '${s.overdue}', Icons.warning_amber_rounded, Brand.red,
          hot: s.overdue > 0, onTap: () => _drill('overdue', 'Overdue tasks')),
      _Stat('Awaiting explanation', '${s.escalatedAwaiting}', Icons.notifications_active_outlined, Brand.amber,
          hot: s.escalatedAwaiting > 0, onTap: () => _drill('esc_awaiting', 'Escalations awaiting explanation')),
    ];
    final kpis = [
      _Stat('Open tasks', '${s.open}', Icons.inbox_outlined, Brand.ink, onTap: () => _drill('open', 'Open tasks')),
      _Stat('Due this week', '${s.dueThisWeek}', Icons.date_range_rounded, Brand.primary, onTap: () => _drill('due_week', 'Due this week')),
      _Stat('Done', '${s.done}', Icons.check_circle_outline_rounded, Brand.green, onTap: () => _drill('done', 'Done tasks')),
      _Stat('No response (SLA)', '${s.noResponse}', Icons.notifications_off_outlined, Brand.red,
          hot: s.noResponse > 0, onTap: () => _drill('no_response', 'No response (SLA breached)')),
      _Stat('Pending review', '${s.escalatedPendingReview}', Icons.balance_rounded, Brand.amber,
          hot: s.escalatedPendingReview > 0, onTap: () => _drill('esc_pending', 'Explanations pending review')),
    ];
    Widget grid(List<_Stat> stats, Widget Function(_Stat) tile, {required int wideCols, double gap = 12}) => LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 720 ? wideCols : 2;
            final w = (c.maxWidth - (cols - 1) * gap) / cols;
            return Wrap(spacing: gap, runSpacing: gap, children: [for (final st in stats) SizedBox(width: w, child: tile(st))]);
          },
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      grid(hero, (st) => _HeroTile(stat: st), wideCols: 4),
      const SizedBox(height: 16),
      _Card(title: 'Key performance metrics', children: [
        grid(kpis, (st) => _KpiTile(stat: st), wideCols: 3, gap: 10),
      ]),
    ]);
  }

  Widget _typeCard(List<ReportType> types) {
    const palette = [Brand.primary, Color(0xFFE59E0B), Color(0xFF0E7490), Color(0xFF9333EA), Brand.red, Brand.green, Brand.sky, Brand.slate];
    final sum = types.fold<int>(0, (a, t) => a + t.total);
    return _Card(
      title: 'By task type',
      subtitle: '$sum task${sum == 1 ? '' : 's'} across ${types.length} type${types.length == 1 ? '' : 's'}',
      children: [
        if (sum > 0) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 12,
              child: Row(children: [
                for (final e in types.asMap().entries)
                  if (e.value.total > 0) Expanded(flex: e.value.total, child: Container(color: palette[e.key % palette.length])),
              ]),
            ),
          ),
          const SizedBox(height: 14),
        ],
        for (final e in types.asMap().entries) ...[
          if (e.key > 0) const SizedBox(height: 10),
          _Inset(children: [
            Row(children: [
              Container(width: 11, height: 11, decoration: BoxDecoration(color: palette[e.key % palette.length], shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.value.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Brand.ink)),
                  Text(e.value.teamName ?? '—', style: const TextStyle(fontSize: 12.5, color: Brand.muted)),
                ]),
              ),
              if (sum > 0)
                Text('${(e.value.total * 100 / sum).round()}%',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Brand.inkSoft)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _DrillNum('Total', e.value.total, () => _drill('total', '${e.value.name} — all tasks', {'taskTypeId': e.value.id})),
              _DrillNum('Open', e.value.open, () => _drill('open', '${e.value.name} — open', {'taskTypeId': e.value.id})),
              _DrillNum('Overdue', e.value.overdue, () => _drill('overdue', '${e.value.name} — overdue', {'taskTypeId': e.value.id}),
                  color: Brand.red),
              _DrillNum('No resp.', e.value.noResponse,
                  () => _drill('no_response', '${e.value.name} — no response', {'taskTypeId': e.value.id}),
                  color: Brand.red),
              _DrillNum('Done', e.value.done, () => _drill('done', '${e.value.name} — done', {'taskTypeId': e.value.id}), color: Brand.green),
            ]),
          ]),
        ],
      ],
    );
  }

  Widget _peopleCard(List<ReportPerson> people, {required bool personal}) => _Card(
        title: personal ? 'Your performance' : 'By person',
        children: [
          for (final e in people.asMap().entries) ...[
            if (e.key > 0) const SizedBox(height: 10),
            _personTile(e.value),
          ],
        ],
      );

  Widget _personTile(ReportPerson p) {
    final good = (p.onTimePct ?? 0) >= 80;
    return _Inset(children: [
      Row(children: [
        Avatar(p.name, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(displayName(p.name),
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Brand.ink)),
              ),
              if (p.role == 'QA') const Padding(padding: EdgeInsets.only(left: 6), child: Pill('QA', fg: TF.sky, bg: TF.skySoft)),
            ]),
            Text(p.teamName ?? '—', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Brand.primary)),
          ]),
        ),
        const SizedBox(width: 8),
        if (p.onTimePct == null)
          const Text('—', style: TextStyle(color: Brand.faint))
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: good ? Brand.greenSoft : Brand.amberSoft, borderRadius: BorderRadius.circular(99)),
            child: Text('${p.onTimePct}%',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: good ? Brand.green : Brand.amber)),
          ),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _DrillNum('Open', p.open, () => _drill('open', '${p.name} — open', {'personId': p.id})),
        _DrillNum('Overdue', p.overdue, () => _drill('overdue', '${p.name} — overdue', {'personId': p.id}), color: Brand.red),
        _DrillNum('No resp.', p.noResponse, () => _drill('no_response', '${p.name} — no response', {'personId': p.id}), color: Brand.red),
        _DrillNum('Escal.', p.escalations, () => _drill('escalations', '${p.name} — escalations', {'personId': p.id}), color: Brand.amber),
        if (p.role != 'QA')
          _DrillNum('Done', p.done, () => _drill('done', '${p.name} — done', {'personId': p.id}), color: Brand.green)
        else ...[
          _DrillNum('Done', p.done, () => _drill('done', '${p.name} — all done', {'personId': p.id}), color: Brand.green, always: true),
          _DrillNum('Self', p.doneSelf, () => _drill('done_self', '${p.name} — done (self)', {'personId': p.id}), always: true),
          _DrillNum('Assigned', p.assignedOut, () => _drill('assigned_out', '${p.name} — assigned out', {'personId': p.id}),
              color: TF.violet, always: true),
          _DrillNum('User done', p.doneByAssignee,
              () => _drill('done_by_assignee', '${p.name} — done by assignee', {'personId': p.id}),
              color: Brand.sky, always: true),
        ],
      ]),
      const SizedBox(height: 10),
      Row(children: [
        const Icon(Icons.speed_rounded, size: 17, color: Brand.muted),
        const SizedBox(width: 6),
        const Text('Avg resp. ', style: TextStyle(fontSize: 13, color: Brand.muted)),
        Text(p.avgResponseMin == null ? '—' : '${p.avgResponseMin}m',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Brand.ink)),
      ]),
    ]);
  }
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

/// Large white tile for the headline numbers.
class _HeroTile extends StatelessWidget {
  const _HeroTile({required this.stat});
  final _Stat stat;

  @override
  Widget build(BuildContext context) => Material(
        color: Brand.card,
        borderRadius: BorderRadius.circular(Brand.radius),
        child: InkWell(
          key: ValueKey('stat-${stat.label}'),
          borderRadius: BorderRadius.circular(Brand.radius),
          onTap: stat.onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Brand.radius),
              border: Border.all(color: stat.hot ? stat.color.withValues(alpha: 0.3) : Brand.line),
              boxShadow: Brand.shadow,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(stat.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Brand.inkSoft, height: 1.25)),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: stat.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Icon(stat.icon, color: stat.color, size: 19),
                ),
              ]),
              const SizedBox(height: 10),
              Text(stat.value,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                    letterSpacing: -0.8,
                    color: stat.hot ? stat.color : Brand.ink,
                  )),
              const SizedBox(height: 10),
              if (stat.progress != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                      value: stat.progress! / 100, minHeight: 5, color: stat.color, backgroundColor: Brand.slateSoft),
                )
              else if (stat.onTap != null)
                const Row(children: [
                  Text('View tasks', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Brand.primary)),
                  Spacer(),
                  Icon(Icons.arrow_forward_rounded, size: 17, color: Brand.primary),
                ])
              else
                const SizedBox(height: 5),
            ]),
          ),
        ),
      );
}

/// Compact tinted tile inside "Key performance metrics".
class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.stat});
  final _Stat stat;

  @override
  Widget build(BuildContext context) => Material(
        color: Brand.field,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey('stat-${stat.label}'),
          borderRadius: BorderRadius.circular(12),
          onTap: stat.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(stat.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Brand.inkSoft)),
                ),
                Icon(stat.icon, size: 16, color: stat.color.withValues(alpha: 0.8)),
              ]),
              const SizedBox(height: 6),
              Text(stat.value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: stat.hot || stat.color == Brand.green || stat.color == Brand.primary ? stat.color : Brand.ink,
                  )),
            ]),
          ),
        ),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children, this.subtitle});
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        decoration: BoxDecoration(
          color: Brand.card,
          borderRadius: BorderRadius.circular(Brand.radius),
          border: Border.all(color: Brand.line),
          boxShadow: Brand.shadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: Brand.ink)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: const TextStyle(fontSize: 13.5, color: Brand.muted)),
          ],
          const SizedBox(height: 14),
          ...children,
        ]),
      );
}

class _Inset extends StatelessWidget {
  const _Inset({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Brand.field, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

/// Label + number chip that opens the drill-down list.
class _DrillNum extends StatelessWidget {
  const _DrillNum(this.label, this.value, this.onTap, {this.color = Brand.ink, this.always = false});
  final String label;
  final int value;
  final VoidCallback onTap;
  final Color color;

  /// Show [color] even when the value is zero.
  final bool always;

  @override
  Widget build(BuildContext context) {
    final c = value > 0 || always ? color : Brand.faint;
    return Material(
      color: Brand.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('$label ', style: const TextStyle(fontSize: 12.5, color: Brand.muted)),
            Text('$value',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: c,
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.dotted,
                  decorationColor: Brand.faint,
                )),
          ]),
        ),
      ),
    );
  }
}

class _AttentionPill extends StatelessWidget {
  const _AttentionPill({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final hot = count > 0;
    final fg = hot ? Brand.red : Brand.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: hot ? Brand.redSoft : Brand.greenSoft, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$count need${count == 1 ? 's' : ''} attention', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

class _PeriodPill extends StatelessWidget {
  const _PeriodPill({super.key, required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? Brand.primary : Brand.card,
        shape: StadiumBorder(side: BorderSide(color: selected ? Brand.primary : Brand.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 16, color: selected ? Colors.white : Brand.inkSoft), const SizedBox(width: 6)],
              Text(label,
                  style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? Colors.white : Brand.inkSoft)),
            ]),
          ),
        ),
      );
}

class _MenuPill extends StatelessWidget {
  const _MenuPill({super.key, required this.label, required this.icon, required this.options, required this.onSelected, this.active = false});
  final String label;
  final IconData icon;
  final List<(String, String)> options;
  final ValueChanged<String> onSelected;
  final bool active;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: '',
        onSelected: onSelected,
        itemBuilder: (_) => [for (final o in options) PopupMenuItem(value: o.$1, child: Text(o.$2))],
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
          decoration: BoxDecoration(
            color: active ? Brand.primarySoft : Brand.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? Brand.primary.withValues(alpha: 0.3) : Brand.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: active ? Brand.primaryDeep : Brand.inkSoft),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: active ? Brand.primaryDeep : Brand.ink)),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 20, color: active ? Brand.primaryDeep : Brand.inkSoft),
          ]),
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
