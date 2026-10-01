import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/format.dart';
import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/realtime_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_ui.dart';
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
  bool showTypeDetails = false;
  StreamSubscription<void>? _sub;

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
    if (Get.isRegistered<RealtimeController>()) _sub = Get.find<RealtimeController>().taskChanged.listen((_) => _load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
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

  String get _periodLabel => switch (period.mode) {
        'today' => 'Today',
        '7' => 'Last 7 days',
        '30' => 'Last 30 days',
        '90' => 'Last 90 days',
        'range' => '${fmtShortDate(period.from)} – ${fmtShortDate(period.to)}',
        _ => 'All time',
      };

  void _resetFilters() {
    _set(() {
      teamId = null;
      typeId = null;
      period = const ReportPeriod();
      showOverall = true;
    });
    _loadTypes();
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final isBoss = me?.isAdminOrCeo ?? false;

    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: const BrandTopBar(subtitle: 'Reports'),
      body: RefreshIndicator(
        color: Brand.navy,
        backgroundColor: Brand.lime,
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: [
          PageBody(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _hero(d, isBoss),
              const SizedBox(height: 14),
              if (d == null)
                error != null ? ErrorView(message: error!, onRetry: _load) : const SkeletonList(count: 3)
              else ...[
                _stats(d.summary),
                if (d.byType.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _typeCard(d.byType),
                ],
                if (d.people.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _peopleCard(d.people, personal: d.isPersonal),
                  const SizedBox(height: 18),
                  FilledButton(
                    key: const Key('export-csv'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Brand.navy,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    onPressed: _export,
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.download_rounded, size: 20, color: Brand.lime),
                      SizedBox(width: 8),
                      Flexible(child: Text('Export CSV', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                ],
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  /// Navy hero: scope + period summary, attention count, scope/type chips and the period segments.
  Widget _hero(Report? d, bool isBoss) {
    const periods = [('all', 'All'), ('today', 'Today'), ('7', '7D'), ('30', '30D'), ('90', '90D')];
    final team = teams.where((t) => t.id == teamId).firstOrNull;
    final title = team?.name ?? d?.scopeLabel ?? 'Reports';
    return HeroCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: HeroEyebrow('Reports · $_periodLabel')),
          if (Get.isRegistered<RealtimeController>())
            Obx(() => Get.find<RealtimeController>().connected.value
                ? const Padding(padding: EdgeInsets.only(left: 8), child: LivePill())
                : const SizedBox.shrink()),
        ]),
        const SizedBox(height: 10),
        HeroTitle(title, maxLines: 1),
        if (d != null) ...[
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: _AttentionPill(key: const Key('attention-pill'), count: d.summary.attention)),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (isBoss) ...[
            _HeroChip(
              label: 'Company wide',
              icon: Icons.apartment_rounded,
              selected: teamId == null,
              onTap: teamId == null
                  ? null
                  : () {
                      _set(() {
                        teamId = null;
                        typeId = null;
                      });
                      _loadTypes();
                    },
            ),
            _MenuPill(
              key: const Key('report-team'),
              label: teamId == null ? 'By team' : team?.name ?? 'Team',
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
          ],
          if (types.isNotEmpty)
            _MenuPill(
              label: typeId == null ? 'All task types' : types.where((t) => t.id == typeId).firstOrNull?.name ?? 'Type',
              icon: Icons.sell_outlined,
              active: typeId != null,
              options: [('', 'All task types'), for (final t in types) ('${t.id}', t.name)],
              onSelected: (v) => _set(() => typeId = int.tryParse(v)),
            ),
          _HeroChip(
            icon: Icons.calendar_today_outlined,
            label: period.mode == 'range' ? '${fmtShortDate(period.from)} – ${fmtShortDate(period.to)}' : 'Range',
            selected: period.mode == 'range',
            onTap: () async {
              final now = DateTime.now();
              final r = await showDateRangePicker(context: context, firstDate: DateTime(now.year - 3), lastDate: now);
              if (r != null) _set(() => period = ReportPeriod(mode: 'range', from: r.start, to: r.end));
            },
          ),
          if (_hasFilters) _HeroChip(label: 'Reset filters', icon: Icons.restart_alt_rounded, selected: false, onTap: _resetFilters),
        ]),
        const SizedBox(height: 12),
        HeroSegments(items: [
          for (final p in periods)
            (ValueKey('period-${p.$1}'), p.$2, period.mode == p.$1, () => _set(() => period = ReportPeriod(mode: p.$1))),
        ]),
        if (period.mode != 'all') ...[
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text('Include open work created earlier (overall)',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.8))),
            ),
            const SizedBox(width: 8),
            Switch(
              value: showOverall,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeThumbColor: Brand.navy,
              activeTrackColor: Brand.lime,
              inactiveThumbColor: Colors.white.withValues(alpha: 0.7),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
              trackOutlineColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.2)),
              onChanged: (v) => _set(() => showOverall = v),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _stats(ReportSummary s) {
    final avg = s.avgResponseMin;
    final headline = [
      StatTile(
        key: const ValueKey('stat-On-time completion'),
        label: 'On-time rate',
        value: s.onTimePct == null ? '—' : '${s.onTimePct}%',
        icon: Icons.verified_outlined,
        iconBg: Brand.navy,
        iconFg: Brand.lime,
        share: s.onTimePct == null ? null : s.onTimePct! / 100,
      ),
      StatTile(
        key: const ValueKey('stat-Avg response time'),
        label: 'Avg response · target <30m',
        value: avg == null ? '—' : '${avg}m',
        icon: Icons.speed_rounded,
        iconBg: Brand.limeLight,
        hot: avg != null && avg > 30,
      ),
      StatTile(
        key: const ValueKey('stat-Overdue'),
        label: 'Overdue',
        value: '${s.overdue}',
        icon: Icons.warning_amber_rounded,
        iconBg: brandRedSoft,
        iconFg: brandRed,
        hot: s.overdue > 0,
        onTap: () => _drill('overdue', 'Overdue tasks'),
      ),
      StatTile(
        key: const ValueKey('stat-Awaiting explanation'),
        label: 'Awaiting explanation',
        value: '${s.escalatedAwaiting}',
        icon: Icons.notifications_active_outlined,
        iconBg: _amberSoft,
        iconFg: _amberInk,
        hot: s.escalatedAwaiting > 0,
        onTap: () => _drill('esc_awaiting', 'Escalations awaiting explanation'),
      ),
    ];
    final kpis = [
      _KpiTile(id: 'Open tasks', label: 'Open tasks', value: s.open, onTap: () => _drill('open', 'Open tasks')),
      _KpiTile(
        id: 'Due this week',
        label: 'Due this week',
        value: s.dueThisWeek,
        dot: s.dueThisWeek > 0 ? Brand.limeDim : null,
        onTap: () => _drill('due_week', 'Due this week'),
      ),
      _KpiTile(id: 'Done', label: 'Completed', value: s.done, onTap: () => _drill('done', 'Done tasks')),
      _KpiTile(
        id: 'No response (SLA)',
        label: 'Missed SLA',
        value: s.noResponse,
        hot: s.noResponse > 0,
        onTap: () => _drill('no_response', 'No response (SLA breached)'),
      ),
      _KpiTile(
        id: 'Pending review',
        label: 'Pending review',
        value: s.escalatedPendingReview,
        hot: s.escalatedPendingReview > 0,
        hotColor: _amberInk,
        onTap: () => _drill('esc_pending', 'Explanations pending review'),
      ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, c) => _grid(headline, cols: c.maxWidth >= 560 ? 4 : 2, gap: 10)),
      const SizedBox(height: 20),
      const BrandSectionTitle(title: 'Key metrics'),
      LayoutBuilder(builder: (context, c) => _grid(kpis, cols: c.maxWidth >= 720 ? 5 : 2, gap: 10)),
    ]);
  }

  Widget _typeCard(List<ReportType> types) {
    const palette = [Brand.lime, Brand.navy, Color(0xFF0D9488), Color(0xFFF59E0B), Color(0xFF7C3AED), Brand.sky, brandRed, Brand.slate];
    final sum = types.fold<int>(0, (a, t) => a + t.total);
    Color color(int i) => palette[i % palette.length];
    final chips = [
      for (final e in types.asMap().entries)
        Material(
          color: Brand.surfaceLow,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => _drill('total', '${e.value.name} — all tasks', {'taskTypeId': e.value.id}),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: color(e.key), shape: BoxShape.circle)),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(e.value.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Brand.navy)),
                ),
                if (sum > 0) ...[
                  const SizedBox(width: 6),
                  Text('${(e.value.total * 100 / sum).round()}%',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Brand.navy)),
                ],
              ]),
            ),
          ),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      BrandSectionTitle(title: 'Task types', count: types.length),
      BrandCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('$sum task${sum == 1 ? '' : 's'} across ${types.length} type${types.length == 1 ? '' : 's'}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Brand.onVariant)),
          const SizedBox(height: 10),
          if (sum > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 10,
                child: Row(children: [
                  for (final e in types.asMap().entries)
                    if (e.value.total > 0) Expanded(flex: e.value.total, child: Container(color: color(e.key))),
                ]),
              ),
            ),
            const SizedBox(height: 12),
          ],
          LayoutBuilder(builder: (context, c) => _grid(chips, cols: c.maxWidth >= 720 ? 4 : 2, gap: 8, stretch: false)),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('type-details'),
              style: TextButton.styleFrom(foregroundColor: Brand.navy, padding: const EdgeInsets.symmetric(horizontal: 4)),
              onPressed: () => setState(() => showTypeDetails = !showTypeDetails),
              icon: Icon(showTypeDetails ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20),
              label: Text(showTypeDetails ? 'Hide details' : 'Show details', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ),
          if (showTypeDetails)
            for (final e in types.asMap().entries) ...[
              const SizedBox(height: 8),
              _Inset(children: [
                Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: color(e.key), shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.value.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Brand.navy)),
                      Text(e.value.teamName ?? '—',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Brand.onVariant)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  _DrillNum('Total', e.value.total, () => _drill('total', '${e.value.name} — all tasks', {'taskTypeId': e.value.id})),
                  _DrillNum('Open', e.value.open, () => _drill('open', '${e.value.name} — open', {'taskTypeId': e.value.id})),
                  _DrillNum('Overdue', e.value.overdue, () => _drill('overdue', '${e.value.name} — overdue', {'taskTypeId': e.value.id}),
                      color: brandRed),
                  _DrillNum('No resp.', e.value.noResponse,
                      () => _drill('no_response', '${e.value.name} — no response', {'taskTypeId': e.value.id}),
                      color: brandRed),
                  _DrillNum('Done', e.value.done, () => _drill('done', '${e.value.name} — done', {'taskTypeId': e.value.id}), color: Brand.green),
                ]),
              ]),
            ],
        ]),
      ),
    ]);
  }

  Widget _peopleCard(List<ReportPerson> people, {required bool personal}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandSectionTitle(title: personal ? 'Your performance' : 'Team performance', count: people.length),
          LayoutBuilder(
            builder: (context, c) => _grid([for (final p in people) _personTile(p)], cols: c.maxWidth >= 720 ? 2 : 1, gap: 10),
          ),
        ],
      );

  Widget _personTile(ReportPerson p) {
    final pct = p.onTimePct;
    final (pillBg, pillFg, pillBorder) = pct == null
        ? (Brand.surfaceMid, Brand.onVariant, Colors.transparent)
        : pct >= 90
            ? (Brand.lime, Brand.navy, Colors.transparent)
            : pct >= 80
                ? (Brand.limeLight, Brand.navy, Brand.limeDim.withValues(alpha: 0.6))
                : (_amberSoft, _amberInk, _amber.withValues(alpha: 0.4));
    final sub = [p.teamName, if (p.role != null) _roleLabel(p.role!)].whereType<String>().join(' · ');
    const statStyle = TextStyle(fontSize: 11.5, color: Brand.onVariant);
    const statBold = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Brand.navy);
    return BrandCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: pct != null && pct >= 90 ? Brand.lime : Brand.outline, width: 2),
            ),
            child: Avatar(p.name, size: 34),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(displayName(p.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Brand.navy)),
                ),
                if (p.role == 'QA') const Padding(padding: EdgeInsets.only(left: 6), child: Pill('QA', fg: TF.sky, bg: TF.skySoft)),
              ]),
              if (sub.isNotEmpty)
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Brand.onVariant)),
            ]),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(99), border: Border.all(color: pillBorder)),
              child: Text(pct == null ? 'No data' : '$pct% On-Time',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: pillFg)),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.task_alt_rounded, size: 15, color: Brand.onVariant),
          const SizedBox(width: 5),
          Expanded(
            child: Text.rich(
              TextSpan(children: [TextSpan(text: '${p.done}', style: statBold), const TextSpan(text: ' tasks done')]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: statStyle,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.speed_rounded, size: 15, color: Brand.onVariant),
          const SizedBox(width: 5),
          Flexible(
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Avg resp: '),
                TextSpan(text: p.avgResponseMin == null ? '—' : '${p.avgResponseMin}m', style: statBold),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: statStyle,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _DrillNum('Open', p.open, () => _drill('open', '${p.name} — open', {'personId': p.id})),
          _DrillNum('Overdue', p.overdue, () => _drill('overdue', '${p.name} — overdue', {'personId': p.id}), color: brandRed),
          _DrillNum('No resp.', p.noResponse, () => _drill('no_response', '${p.name} — no response', {'personId': p.id}), color: brandRed),
          _DrillNum('Escal.', p.escalations, () => _drill('escalations', '${p.name} — escalations', {'personId': p.id}), color: _amberInk),
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
      ]),
    );
  }
}

String _roleLabel(String role) => const {
      'ADMIN': 'Super Admin',
      'CEO': 'CEO',
      'MANAGER': 'Manager',
      'MEMBER': 'Member',
      'QA': 'QA',
    }[role] ??
    role;

const _amber = Color(0xFFF59E0B);
const _amberInk = Color(0xFF92400E);
const _amberSoft = Color(0xFFFFFBEB);

/// Lays [tiles] out in rows of [cols]; tiles in a row share the tallest height. A lone trailing tile spans the row.
Widget _grid(List<Widget> tiles, {required int cols, double gap = 12, bool stretch = true}) {
  final rows = <Widget>[];
  for (var i = 0; i < tiles.length; i += cols) {
    final chunk = tiles.sublist(i, i + cols > tiles.length ? tiles.length : i + cols);
    final row = Row(crossAxisAlignment: stretch ? CrossAxisAlignment.stretch : CrossAxisAlignment.center, children: [
      for (final e in chunk.asMap().entries) ...[
        if (e.key > 0) SizedBox(width: gap),
        Expanded(child: e.value),
      ],
      // Keep a partial last row aligned to the grid unless it is a single tile.
      if (chunk.length > 1 && chunk.length < cols)
        for (var k = chunk.length; k < cols; k++) ...[SizedBox(width: gap), const Expanded(child: SizedBox.shrink())],
    ]);
    rows.add(Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : gap), child: stretch ? IntrinsicHeight(child: row) : row));
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
}

/// Compact white KPI tile under "Key metrics".
class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.id, required this.label, required this.value, this.onTap, this.dot, this.hot = false, this.hotColor = brandRed});
  final String id;
  final String label;
  final int value;
  final VoidCallback? onTap;
  final Color? dot;
  final bool hot;
  final Color hotColor;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: hot ? hotColor.withValues(alpha: 0.3) : Brand.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('stat-$id'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 11),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Brand.onVariant)),
                ),
                if (dot != null) ...[
                  const SizedBox(width: 6),
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                ],
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded, size: 16, color: Brand.faint),
              ]),
              const SizedBox(height: 4),
              Text('$value',
                  maxLines: 1,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -0.5, color: hot ? hotColor : Brand.navy)),
            ]),
          ),
        ),
      );
}

class _Inset extends StatelessWidget {
  const _Inset({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Brand.surfaceLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Brand.outline.withValues(alpha: 0.6)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

/// Label + number chip that opens the drill-down list.
class _DrillNum extends StatelessWidget {
  const _DrillNum(this.label, this.value, this.onTap, {this.color = Brand.navy, this.always = false});
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
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Brand.outline.withValues(alpha: 0.9))),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('$label ', style: const TextStyle(fontSize: 11.5, color: Brand.onVariant)),
            Text('$value',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
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

/// "N need attention" pill on the navy hero (red-soft when there is work, lime when clear).
class _AttentionPill extends StatelessWidget {
  const _AttentionPill({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final hot = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: hot ? brandRedSoft : Brand.lime, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: hot ? brandRed : Brand.navy, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(
          child: Text('$count need${count == 1 ? 's' : ''} attention',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: hot ? brandRedInk : Brand.navy)),
        ),
      ]),
    );
  }
}

/// Chip on the navy hero: lime when selected, translucent white otherwise.
class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label, required this.selected, this.onTap, this.icon, this.menu = false});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool menu;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Brand.navy : Colors.white.withValues(alpha: 0.85);
    final chip = Container(
      padding: EdgeInsets.fromLTRB(10, 6, menu ? 6 : 11, 6),
      decoration: BoxDecoration(
        color: selected ? Brand.lime : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: selected ? Brand.lime : Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: selected ? Brand.navy : Brand.lime), const SizedBox(width: 6)],
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: fg)),
        ),
        if (menu) ...[const SizedBox(width: 2), Icon(Icons.expand_more_rounded, size: 16, color: fg)],
      ]),
    );
    if (onTap == null) return chip;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: chip);
  }
}

/// Hero chip that opens a popup menu of options.
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
        child: _HeroChip(label: label, icon: icon, selected: active, menu: true),
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
                                  style: const TextStyle(fontSize: 11.5, color: TF.muted),
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
