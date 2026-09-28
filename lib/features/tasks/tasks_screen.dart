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
    _load();
    _sub = Get.find<RealtimeController>().taskChanged.listen((_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
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
    final statusLabel = status.isEmpty ? 'Open tasks' : (status == 'all' ? 'All statuses' : statusLabels[status] ?? status);

    final isAdmin = me?.isAdminOrCeo ?? false;

    return Scaffold(
      backgroundColor: Brand.bg,
      appBar: const BrandTopBar(subtitle: 'Tasks'),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-task-fab'),
        heroTag: 'new-task-fab',
        onPressed: () async {
          final ids = await showComposer(context);
          if (ids != null) _load();
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Segments(
                  segments: segments,
                  selected: assigneeFilter.isEmpty ? filter : null,
                  onSelected: (id) => _update(() {
                    filter = id;
                    assigneeFilter = '';
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('task-search'),
                  controller: searchCtrl,
                  style: const TextStyle(fontSize: 15.5, color: Brand.ink),
                  decoration: InputDecoration(
                    hintText: 'Search tasks…',
                    hintStyle: const TextStyle(fontSize: 15.5, color: Brand.faint),
                    filled: true,
                    fillColor: Brand.card,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.search_rounded, size: 24, color: Brand.inkSoft),
                    ),
                    suffixIcon: q.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20, color: Brand.muted),
                            onPressed: () {
                              searchCtrl.clear();
                              _update(() => q = '');
                            },
                          ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Brand.line)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Brand.line)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Brand.primary.withValues(alpha: 0.7), width: 1.5),
                    ),
                  ),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 350), () => _update(() => q = v.trim()));
                  },
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Row(children: [
                    _FilterPill<String>(
                      key: const Key('status-filter'),
                      icon: Icons.check_circle_outline_rounded,
                      label: 'Status: $statusLabel',
                      active: status.isNotEmpty,
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
                        onTap: () async {
                          final v = await pickUserOrTeam(context, users: users, teams: teams, selected: assigneeFilter);
                          if (v != null) _update(() => assigneeFilter = v);
                        },
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
                        style: TextButton.styleFrom(foregroundColor: Brand.primaryDeep),
                        onPressed: _reset,
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: const Text('Reset filters'),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 16),
                if (loading && result == null)
                  const SkeletonList()
                else if (error != null && result == null)
                  ErrorView(message: error!, onRetry: _load)
                else if (result!.tasks.isEmpty)
                  Container(
                    decoration: BoxDecoration(color: Brand.card, borderRadius: BorderRadius.circular(Brand.radius), boxShadow: Brand.shadow),
                    child: const EmptyState(icon: Icons.inbox_outlined, color: Brand.primary, title: 'No tasks match', message: 'Try a different filter.'),
                  )
                else ...[
                  AnimatedOpacity(
                    opacity: loading ? 0.5 : 1,
                    duration: const Duration(milliseconds: 150),
                    child: TaskList(tasks: result!.tasks, onChanged: () => _load(quiet: true), roomy: true),
                  ),
                  const SizedBox(height: 8),
                  _pagination(result!.pagination),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
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

  Widget _pagination(Pagination p) {
    final label = p.totalPages <= 1
        ? '${p.total} task${p.total == 1 ? '' : 's'}'
        : 'Page ${p.page} of ${p.totalPages} · ${p.total} tasks';
    Widget arrow(Key key, IconData icon, VoidCallback? onTap) => IconButton(
          key: key,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
          icon: Icon(icon, color: onTap == null ? Colors.white.withValues(alpha: 0.3) : Colors.white),
        );
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: EdgeInsets.fromLTRB(18, p.totalPages <= 1 ? 12 : 4, p.totalPages <= 1 ? 18 : 4, p.totalPages <= 1 ? 12 : 4),
        decoration: BoxDecoration(
          color: Brand.ink,
          borderRadius: BorderRadius.circular(99),
          boxShadow: [BoxShadow(color: Brand.ink.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 9, height: 9, decoration: const BoxDecoration(color: Color(0xFF34D399), shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(label,
                key: p.totalPages <= 1 ? null : const Key('pagination-label'),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
          ),
          if (p.totalPages > 1) ...[
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

/// My tasks · Created by me · Team · All as one segmented control.
class _Segments extends StatelessWidget {
  const _Segments({required this.segments, required this.selected, required this.onSelected});
  final List<(String, String)> segments;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Brand.primarySoft.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          for (final s in segments)
            Expanded(
              child: GestureDetector(
                key: ValueKey('segment-${s.$1}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(s.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  constraints: const BoxConstraints(minHeight: 46),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected == s.$1 ? Brand.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: selected == s.$1
                        ? [BoxShadow(color: Brand.ink.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))]
                        : null,
                  ),
                  child: Text(s.$2,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.2,
                        fontWeight: selected == s.$1 ? FontWeight.w700 : FontWeight.w500,
                        color: selected == s.$1 ? Brand.ink : Brand.inkSoft,
                      )),
                ),
              ),
            ),
        ]),
      );
}

/// Rounded filter pill: opens a menu of [options], or runs [onTap].
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

  /// Filled indigo when active (the main filter).
  final bool primary;
  final List<(T, String)> options;
  final Key Function(T)? optionKey;
  final ValueChanged<T>? onSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final filled = primary && active;
    final fg = filled ? Colors.white : (active ? Brand.primaryDeep : Brand.inkSoft);
    final pill = Container(
      padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
      decoration: BoxDecoration(
        color: filled ? Brand.primary : (active ? Brand.primarySoft : Brand.card),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: filled ? Brand.primary : (active ? Brand.primary.withValues(alpha: 0.3) : Brand.line)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: fg),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
        const SizedBox(width: 2),
        Icon(Icons.expand_more_rounded, size: 20, color: fg),
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
