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
import '../../widgets/brand_ui.dart';
import '../../widgets/common.dart';
import '../../widgets/filters.dart';
import '../shell/home_shell.dart';
import '../shell/top_bar.dart';
import 'composer_sheet.dart';
import 'task_card.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  static const pageSize = 15;

  String filter = 'mine';
  String status = '';
  String q = '';
  String assigneeFilter = '';
  DueFilter due = const DueFilter();
  int page = 1;

  TaskPage? result;
  String? error;
  bool loading = true;
  List<AppUser> users = [];
  List<Team> teams = [];
  Timer? _debounce;
  StreamSubscription<void>? _sub;
  Worker? _statusLink;
  final searchCtrl = TextEditingController();

  TaskFlowApi get api => Get.find<TaskFlowApi>();

  @override
  void initState() {
    super.initState();
    final me = Get.find<AuthController>().me;
    if (me?.isAdminOrCeo ?? false) {
      api.users().then((u) => mounted ? setState(() => users = u) : null).catchError((_) {});
      api.teams().then((t) => mounted ? setState(() => teams = t) : null).catchError((_) {});
    }
    if (Get.isRegistered<ShellController>()) {
      final shell = Get.find<ShellController>();
      _takeStatusLink(shell, initial: true);
      _statusLink = ever(shell.tasksStatus, (_) => _takeStatusLink(shell));
    }
    _load();
    _sub = Get.find<RealtimeController>().taskChanged.listen((_) => _load(quiet: true));
  }

  /// Applies a status sent from the dashboard ("See all") on top of the
  /// default view: my tasks, no search, person or due filter.
  void _takeStatusLink(ShellController shell, {bool initial = false}) {
    final s = shell.tasksStatus.value;
    if (s == null) return;
    shell.tasksStatus.value = null;
    void apply() {
      filter = 'mine';
      status = s;
      q = '';
      assigneeFilter = '';
      due = const DueFilter();
    }

    searchCtrl.clear();
    if (initial) {
      apply(); // initState loads right after
    } else {
      _update(apply);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    _statusLink?.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => loading = true);
    final me = Get.find<AuthController>().me;
    final canFilter = me?.isAdminOrCeo ?? false;
    int? assigneeId;
    int? teamId;
    if (canFilter && assigneeFilter.isNotEmpty) {
      final id = int.parse(assigneeFilter.substring(2));
      if (assigneeFilter.startsWith('u:')) assigneeId = id;
      if (assigneeFilter.startsWith('t:')) teamId = id;
    }
    final dq = due.toQuery();
    try {
      final r = await api.tasks(TaskQuery(
        filter: canFilter && assigneeFilter.isNotEmpty ? 'all' : filter,
        status: status,
        q: q,
        assigneeId: assigneeId,
        teamId: teamId,
        dueFrom: dq['dueFrom'] as int?,
        dueTo: dq['dueTo'] as int?,
        page: page,
        limit: pageSize,
      ));
      if (mounted) setState(() => (result = r, error = null));
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _update(VoidCallback change) {
    setState(() {
      change();
      page = 1;
    });
    _load();
  }

  bool get _hasFilters => filter != 'mine' || status.isNotEmpty || q.isNotEmpty || assigneeFilter.isNotEmpty || due.isActive;

  void _reset() {
    searchCtrl.clear();
    _update(() {
      filter = 'mine';
      status = '';
      q = '';
      assigneeFilter = '';
      due = const DueFilter();
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = Get.find<AuthController>().me;
    final segments = [
      ('mine', 'My tasks'),
      ('created', 'Created by me'),
      if (me?.isManager ?? false) ('team', 'Team'),
      if (me?.isAdminOrCeo ?? false) ('all', 'All'),
    ];
    final statusName = status.isEmpty ? 'Open' : (status == 'all' ? 'All' : statusLabels[status] ?? status);
    final total = result != null && !loading ? ' (${result!.pagination.total})' : '';

    final isAdmin = me?.isAdminOrCeo ?? false;
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Brand.outline));

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: const BrandTopBar(subtitle: 'Tasks'),
      // Round dark button with a lime "+".
      floatingActionButton: SizedBox(
        width: 54,
        height: 54,
        child: FloatingActionButton(
          key: const Key('new-task-fab'),
          heroTag: 'new-task-fab',
          tooltip: 'New task',
          onPressed: () async {
            final ids = await showComposer(context);
            if (ids != null) _load();
          },
          backgroundColor: const Color(0xFF111A2E),
          foregroundColor: const Color(0xFFD7F83A),
          elevation: 0,
          highlightElevation: 0,
          shape: const CircleBorder(),
          child: const _BoldPlus(size: 22, stroke: 3.2, color: Color(0xFFD7F83A)),
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _hero(segments, statusName),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: TextField(
                      key: const Key('task-search'),
                      controller: searchCtrl,
                      style: const TextStyle(fontSize: 13, color: Brand.navy),
                      decoration: InputDecoration(
                        hintText: 'Search by title or description…',
                        hintStyle: const TextStyle(fontSize: 13, color: Brand.onVariant),
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Brand.onVariant),
                        suffixIcon: q.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20, color: Brand.onVariant),
                                onPressed: () {
                                  searchCtrl.clear();
                                  _update(() => q = '');
                                },
                              ),
                        border: border,
                        enabledBorder: border,
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Brand.navy, width: 1.5),
                        ),
                      ),
                      onChanged: (v) {
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 350), () => _update(() => q = v.trim()));
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  _FilterButton(active: _hasFilters, onTap: () => _openFilters(isAdmin)),
                ]),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Row(children: [
                    _FilterPill<String>(
                      key: const Key('status-filter'),
                      icon: Icons.check_circle_outline_rounded,
                      label: 'Status: $statusName$total',
                      active: true,
                      primary: true,
                      options: [('', 'Open tasks'), ('all', 'All statuses'), ...statusLabels.entries.map((e) => (e.key, e.value))],
                      onSelected: (v) => _update(() => status = v),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 8),
                      _FilterPill<String>(
                        key: const Key('assignee-filter'),
                        icon: Icons.person_search_outlined,
                        label: userOrTeamLabel(assigneeFilter, users, teams),
                        active: assigneeFilter.isNotEmpty,
                        onTap: _pickAssignee,
                      ),
                    ],
                    const SizedBox(width: 8),
                    _FilterPill<String>(
                      key: const Key('due-filter'),
                      icon: Icons.event_outlined,
                      label: 'Due: ${_dueLabel()}',
                      active: due.isActive,
                      options: const [('all', 'Any due date'), ('today', 'Due today'), ('range', 'Date range')],
                      optionKey: (v) => Key('due-$v'),
                      onSelected: _setDue,
                    ),
                    if (_hasFilters) ...[
                      const SizedBox(width: 4),
                      TextButton.icon(
                        key: const Key('reset-filters'),
                        style: TextButton.styleFrom(foregroundColor: Brand.navy, textStyle: const TextStyle(fontWeight: FontWeight.w700)),
                        onPressed: _reset,
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: const Text('Reset filters'),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 16),
                BrandSectionTitle(
                  title: '$statusName tasks',
                  count: result != null && !loading ? result!.pagination.total : null,
                ),
                if (loading && result == null)
                  const SkeletonList()
                else if (error != null && result == null)
                  ErrorView(message: error!, onRetry: _load)
                else if (result!.tasks.isEmpty)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Brand.outline),
                    ),
                    child: const EmptyState(icon: Icons.inbox_outlined, color: Brand.navy, title: 'No tasks match', message: 'Try a different filter.'),
                  )
                else ...[
                  AnimatedOpacity(
                    opacity: loading ? 0.5 : 1,
                    duration: const Duration(milliseconds: 150),
                    child: TaskList(tasks: result!.tasks, onChanged: () => _load(quiet: true), roomy: true),
                  ),
                  const SizedBox(height: 8),
                  _pagination(result!.pagination, result!.tasks.length),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  /// Navy hero: scope + live pill, the result count for the status filter and
  /// the My tasks / Created by me / Team / All segments.
  Widget _hero(List<(String, String)> segments, String statusName) {
    final scope = assigneeFilter.isNotEmpty
        ? userOrTeamLabel(assigneeFilter, users, teams)
        : segments.firstWhere((s) => s.$1 == filter, orElse: () => segments.first).$2;
    final total = result?.pagination.total;
    final noun = statusName == 'All' ? 'tasks' : '${statusName.toLowerCase()} tasks';
    return HeroCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: HeroEyebrow('Tasks · $scope')),
          Obx(() => Get.find<RealtimeController>().connected.value ? const LivePill() : const SizedBox.shrink()),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            constraints: const BoxConstraints(minWidth: 40),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Brand.lime, borderRadius: BorderRadius.circular(12)),
            child: loading && result == null
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Brand.navy))
                : Text('${total ?? 0}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1, color: Brand.navy)),
          ),
          const SizedBox(width: 12),
          Expanded(child: HeroTitle(total == 1 ? noun.replaceFirst('tasks', 'task') : noun, maxLines: 1)),
        ]),
        if (due.isActive || q.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            [if (q.isNotEmpty) 'Matching "$q"', if (due.isActive) 'Due ${_dueLabel().toLowerCase()}'].join('  •  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.7)),
          ),
        ],
        const SizedBox(height: 14),
        HeroSegments(items: [
          for (final s in segments)
            (
              ValueKey('segment-${s.$1}'),
              s.$2,
              assigneeFilter.isEmpty && filter == s.$1,
              () => _update(() {
                    filter = s.$1;
                    assigneeFilter = '';
                  }),
            ),
        ]),
      ]),
    );
  }

  Future<void> _pickAssignee() async {
    final v = await pickUserOrTeam(context, users: users, teams: teams, selected: assigneeFilter);
    if (v != null) _update(() => assigneeFilter = v);
  }

  /// All filters in one sheet (opened from the navy filter button).
  Future<void> _openFilters(bool isAdmin) async {
    final picked = await showAppSheet<VoidCallback>(
      context,
      builder: (ctx) {
        Widget chip(String label, bool selected, VoidCallback apply) => _SheetChip(
              label: label,
              selected: selected,
              onTap: () => Navigator.of(ctx).pop(apply),
            );
        Widget heading(String text) => Padding(
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
              child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Brand.onVariant, letterSpacing: 0.3)),
            );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            const SheetTitle('Filters'),
            heading('STATUS'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final o in [('', 'Open tasks'), ('all', 'All statuses'), ...statusLabels.entries.map((e) => (e.key, e.value))])
                chip(o.$2, status == o.$1, () => _update(() => status = o.$1)),
            ]),
            heading('DUE DATE'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              chip('Any due date', due.mode == 'all', () => _setDue('all')),
              chip('Due today', due.mode == 'today', () => _setDue('today')),
              chip(due.mode == 'range' ? _dueLabel() : 'Date range', due.mode == 'range', () => _setDue('range')),
            ]),
            if (isAdmin) ...[
              heading('ASSIGNEE'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                chip(userOrTeamLabel(assigneeFilter, users, teams), assigneeFilter.isNotEmpty, _pickAssignee),
              ]),
            ],
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Brand.navy,
                    side: const BorderSide(color: Brand.outline),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _hasFilters ? () => Navigator.of(ctx).pop(_reset) : null,
                  child: const Text('Reset', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Brand.navy,
                    foregroundColor: Brand.lime,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ]),
        );
      },
    );
    picked?.call();
  }

  String _dueLabel() => switch (due.mode) {
        'today' => 'Today',
        'range' when due.from != null && due.to != null => '${fmtShortDate(due.from)} – ${fmtShortDate(due.to)}',
        _ => 'Any',
      };

  Future<void> _setDue(String mode) async {
    if (mode == 'all') return _update(() => due = const DueFilter());
    if (mode == 'today') return _update(() => due = const DueFilter(mode: 'today'));
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
      initialDateRange: due.from != null && due.to != null ? DateTimeRange(start: due.from!, end: due.to!) : null,
    );
    if (r != null) _update(() => due = DueFilter(mode: 'range', from: r.start, to: r.end));
  }

  /// Navy "Showing X of Y tasks" pill with a lime dot and page arrows.
  Widget _pagination(Pagination p, int shown) {
    final multi = p.totalPages > 1;
    final start = (p.page - 1) * p.limit + 1;
    final label = multi
        ? 'Showing $start–${start + shown - 1} of ${p.total} tasks'
        : 'Showing $shown of ${p.total} task${p.total == 1 ? '' : 's'}';
    Widget arrow(Key key, IconData icon, VoidCallback? onTap) => IconButton(
          key: key,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
          icon: Icon(icon, color: onTap == null ? Colors.white.withValues(alpha: 0.3) : Brand.lime),
        );
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: EdgeInsets.fromLTRB(18, multi ? 4 : 12, multi ? 4 : 18, multi ? 4 : 12),
        decoration: BoxDecoration(
          color: Brand.navy,
          borderRadius: BorderRadius.circular(99),
          boxShadow: [BoxShadow(color: Brand.navy.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 9, height: 9, decoration: const BoxDecoration(color: Brand.lime, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(label,
                key: multi ? const Key('pagination-label') : null,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
          ),
          if (multi) ...[
            const SizedBox(width: 6),
            arrow(
                const Key('page-prev'),
                Icons.chevron_left_rounded,
                page > 1 && !loading
                    ? () {
                        setState(() => page--);
                        _load();
                      }
                    : null),
            arrow(
                const Key('page-next'),
                Icons.chevron_right_rounded,
                page < p.totalPages && !loading
                    ? () {
                        setState(() => page++);
                        _load();
                      }
                    : null),
          ],
        ]),
      ),
    );
  }
}

/// Navy square filter button with a lime icon; a lime dot marks active filters.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Filters',
        child: Material(
          key: const Key('filters-button'),
          color: Brand.navy,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Stack(alignment: Alignment.center, children: [
                const Icon(Icons.tune_rounded, size: 22, color: Brand.lime),
                if (active)
                  Positioned(
                    top: 9,
                    right: 9,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(color: Brand.lime, shape: BoxShape.circle, border: Border.all(color: Brand.navy, width: 1.5)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
}

/// Selectable chip inside the filter sheet.
class _SheetChip extends StatelessWidget {
  const _SheetChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? Brand.navy : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? Brand.navy : Brand.outline)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? Brand.lime : Brand.navy)),
          ),
        ),
      );
}

/// Rounded filter pill: opens a menu of [options], or runs [onTap]. The
/// [primary] pill is navy with lime text; others are white and outlined, or
/// lime-tinted when [active].
class _FilterPill<T> extends StatelessWidget {
  const _FilterPill({
    super.key,
    required this.icon,
    required this.label,
    this.active = false,
    this.primary = false,
    this.options = const [],
    this.optionKey,
    this.onSelected,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;

  /// Navy with lime text when active (the main filter).
  final bool primary;
  final List<(T, String)> options;
  final Key Function(T)? optionKey;
  final ValueChanged<T>? onSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final filled = primary && active;
    final fg = filled ? Brand.lime : Brand.navy;
    final pill = Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
      decoration: BoxDecoration(
        color: filled ? Brand.navy : (active ? Brand.limeLight : Colors.white),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: filled ? Brand.navy : (active ? Brand.limeDim : Brand.outline)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (filled || active) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 5)],
        Text(label, style: TextStyle(fontSize: 12, fontWeight: filled ? FontWeight.w700 : FontWeight.w500, color: fg)),
        const SizedBox(width: 2),
        Icon(Icons.expand_more_rounded, size: 18, color: fg),
      ]),
    );
    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: BorderRadius.circular(99), onTap: onTap, child: pill),
      );
    }
    return PopupMenuButton<T>(
      tooltip: '',
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final o in options) PopupMenuItem(key: optionKey?.call(o.$1), value: o.$1, child: Text(o.$2)),
      ],
      child: pill,
    );
  }
}

/// "+" drawn with rounded strokes so its weight can be set (icon fonts can't).
class _BoldPlus extends StatelessWidget {
  const _BoldPlus({required this.size, required this.stroke, required this.color});
  final double size;
  final double stroke;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _PlusPainter(stroke, color));
}

class _PlusPainter extends CustomPainter {
  const _PlusPainter(this.stroke, this.color);
  final double stroke;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final inset = stroke / 2;
    final mid = size.width / 2;
    canvas.drawLine(Offset(mid, inset), Offset(mid, size.height - inset), paint);
    canvas.drawLine(Offset(inset, mid), Offset(size.width - inset, mid), paint);
  }

  @override
  bool shouldRepaint(_PlusPainter old) => old.stroke != stroke || old.color != color;
}
