import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

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

    return Scaffold(
      appBar: const TopBar(title: 'Tasks'),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-task-fab'),
        heroTag: 'new-task-fab',
        onPressed: () async {
          final ids = await showComposer(context);
          if (ids != null) _load();
        },
        backgroundColor: TF.ink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New task', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            PageBody(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final s in segments)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: ValueKey('segment-${s.$1}'),
                          label: Text(s.$2),
                          selected: filter == s.$1 && assigneeFilter.isEmpty,
                          showCheckmark: false,
                          onSelected: (_) => _update(() {
                            filter = s.$1;
                            assigneeFilter = '';
                          }),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('task-search'),
                  controller: searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search tasks…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: q.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              searchCtrl.clear();
                              _update(() => q = '');
                            },
                          ),
                  ),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 350), () => _update(() => q = v.trim()));
                  },
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  MenuChip(
                    key: const Key('status-filter'),
                    label: statusLabel,
                    icon: Icons.tune_rounded,
                    active: status.isNotEmpty,
                    options: [('', 'Open tasks'), ('all', 'All statuses'), ...statusLabels.entries.map((e) => (e.key, e.value))],
                    onSelected: (v) => _update(() => status = v),
                  ),
                  if (me?.isAdminOrCeo ?? false)
                    ActionChip(
                      key: const Key('assignee-filter'),
                      avatar: const Icon(Icons.person_search_outlined, size: 17),
                      label: Text(userOrTeamLabel(assigneeFilter, users, teams)),
                      onPressed: () async {
                        final v = await pickUserOrTeam(context, users: users, teams: teams, selected: assigneeFilter);
                        if (v != null) _update(() => assigneeFilter = v);
                      },
                    ),
                ]),
                const SizedBox(height: 8),
                DueFilterBar(value: due, onChanged: (d) => _update(() => due = d)),
                if (_hasFilters)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('reset-filters'),
                      onPressed: _reset,
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: const Text('Reset filters'),
                    ),
                  ),
                const SizedBox(height: 12),
                if (loading && result == null)
                  const SkeletonList()
                else if (error != null && result == null)
                  ErrorView(message: error!, onRetry: _load)
                else if (result!.tasks.isEmpty)
                  const Surface(child: EmptyState(icon: Icons.inbox_outlined, title: 'No tasks match', message: 'Try a different filter.'))
                else ...[
                  AnimatedOpacity(
                    opacity: loading ? 0.5 : 1,
                    duration: const Duration(milliseconds: 150),
                    child: TaskList(tasks: result!.tasks, onChanged: () => _load(quiet: true)),
                  ),
                  _pagination(result!.pagination),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pagination(Pagination p) {
    if (p.totalPages <= 1) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('${p.total} task${p.total == 1 ? '' : 's'}', style: const TextStyle(color: TF.muted, fontSize: 12.5)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        Expanded(
          child: Text('Page ${p.page} of ${p.totalPages} · ${p.total} tasks',
              key: const Key('pagination-label'), style: const TextStyle(color: TF.muted, fontSize: 12.5)),
        ),
        OutlinedButton(
          key: const Key('page-prev'),
          onPressed: page > 1 && !loading
              ? () {
                  setState(() => page--);
                  _load();
                }
              : null,
          child: const Icon(Icons.chevron_left_rounded),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          key: const Key('page-next'),
          onPressed: page < p.totalPages && !loading
              ? () {
                  setState(() => page++);
                  _load();
                }
              : null,
          child: const Icon(Icons.chevron_right_rounded),
        ),
      ]),
    );
  }
}
