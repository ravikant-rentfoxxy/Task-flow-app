import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/format.dart';
import '../../core/task_logic.dart';
import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_ui.dart';
import '../../widgets/common.dart';
import '../../widgets/files.dart';

class ComposerResult {
  ComposerResult({required this.ids, this.title, this.description, this.assigneeId, this.lines});
  final List<int> ids;
  final String? title;
  final String? description;
  final int? assigneeId;
  final List<String>? lines;
}

/// Opens the task composer. Resolves to the created task ids, or null if dismissed.
Future<List<int>?> showComposer(
  BuildContext context, {
  int? presetProjectId,
  int? presetParentId,
  List<int> presetAttachmentIds = const [],
  int? presetBoardId,
  String? presetTitle,
  int? presetAssigneeId,
}) async {
  final r = await showComposerDetailed(
    context,
    presetProjectId: presetProjectId,
    presetParentId: presetParentId,
    presetAttachmentIds: presetAttachmentIds,
    presetBoardId: presetBoardId,
    presetTitle: presetTitle,
    presetAssigneeId: presetAssigneeId,
  );
  return r?.ids;
}

Future<ComposerResult?> showComposerDetailed(
  BuildContext context, {
  int? presetProjectId,
  int? presetParentId,
  List<int> presetAttachmentIds = const [],
  int? presetBoardId,
  String? presetTitle,
  int? presetAssigneeId,
}) {
  return Navigator.of(context).push<ComposerResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ComposerSheet(
        presetProjectId: presetProjectId,
        presetParentId: presetParentId,
        presetAttachmentIds: presetAttachmentIds,
        presetBoardId: presetBoardId,
        presetTitle: presetTitle,
        presetAssigneeId: presetAssigneeId,
      ),
    ),
  );
}

class _PendingFile {
  _PendingFile(this.name, this.bytes);
  final String name;
  final List<int> bytes;
}

class ComposerSheet extends StatefulWidget {
  const ComposerSheet({
    super.key,
    this.presetProjectId,
    this.presetParentId,
    this.presetAttachmentIds = const [],
    this.presetBoardId,
    this.presetTitle,
    this.presetAssigneeId,
  });

  final int? presetProjectId;
  final int? presetParentId;
  final List<int> presetAttachmentIds;
  final int? presetBoardId;
  final String? presetTitle;
  final int? presetAssigneeId;

  @override
  State<ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends State<ComposerSheet> {
  final titleCtrl = TextEditingController();
  final linesCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final subtaskCtrl = TextEditingController();

  List<AppUser> users = [];
  List<Team> teams = [];
  List<Project> projects = [];
  List<TaskType> taskTypes = [];
  bool loadingTypes = false;

  /// `u:<id>` for a person or `t:<id>` for a team.
  String? assignee;
  int? taskTypeId;
  int? projectId;
  String priority = 'NORMAL';
  DateTime? due;
  bool multiple = false;
  bool showSubtasks = false;
  bool showMembers = false;
  final List<String> subtasks = [];
  final Set<int> collaborators = {};
  final Set<int> watchers = {};
  final List<_PendingFile> files = [];
  bool busy = false;
  String? error;

  bool get isSubtask => widget.presetParentId != null;
  bool get canAddSubtasks => !isSubtask && !multiple;
  int? get primaryUserId => assignee?.startsWith('u:') == true ? int.parse(assignee!.substring(2)) : null;
  int? get teamId => assignee?.startsWith('t:') == true ? int.parse(assignee!.substring(2)) : null;

  @override
  void initState() {
    super.initState();
    titleCtrl.text = widget.presetTitle ?? '';
    projectId = widget.presetProjectId;
    if (widget.presetAssigneeId != null) assignee = 'u:${widget.presetAssigneeId}';
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    final api = Get.find<TaskFlowApi>();
    try {
      final r = await Future.wait([api.users(), api.teams(), api.projects()]);
      if (!mounted) return;
      setState(() {
        users = (r[0] as List<AppUser>).where((u) => u.isActive).toList();
        teams = r[1] as List<Team>;
        projects = r[2] as List<Project>;
      });
      if (assignee != null) _loadTypes();
    } catch (e) {
      toastError(e);
    }
  }

  Future<void> _loadTypes() async {
    setState(() {
      taskTypeId = null;
      taskTypes = [];
      loadingTypes = assignee != null;
    });
    if (assignee == null) return;
    try {
      final types = await Get.find<TaskFlowApi>().taskTypes(userId: primaryUserId, teamId: teamId);
      if (mounted) setState(() => taskTypes = types.where((t) => t.isActive).toList());
    } catch (_) {
      if (mounted) setState(() => taskTypes = []);
    } finally {
      if (mounted) setState(() => loadingTypes = false);
    }
  }

  void _setAssignee(String? v) {
    setState(() {
      assignee = v;
      collaborators.clear();
      watchers.clear();
    });
    _loadTypes();
  }

  String get _assigneeLabel {
    if (assignee == null) return users.isEmpty ? 'Loading people…' : 'Choose assignee';
    final id = int.parse(assignee!.substring(2));
    if (assignee!.startsWith('t:')) {
      final t = teams.where((t) => t.id == id).firstOrNull;
      return t == null ? 'Team' : 'Team · ${t.name}';
    }
    return users.where((u) => u.id == id).firstOrNull?.name ?? 'User #$id';
  }

  Future<void> _pickAssignee() async {
    final v = await showSearchPicker<String>(
      context,
      title: 'Assign to',
      selected: assignee,
      searchHint: 'Search people or teams…',
      options: [
        for (final u in users)
          PickerOption(
            value: 'u:${u.id}',
            label: u.name,
            subtitle: [u.teamName, u.role].whereType<String>().join(' · '),
            group: 'People',
            leading: Avatar(u.name, size: 32),
          ),
        if (!isSubtask)
          for (final t in teams)
            PickerOption(
              value: 't:${t.id}',
              label: t.name,
              subtitle: '${t.memberCount} members',
              group: 'Teams',
              leading: const CircleAvatar(radius: 16, backgroundColor: TF.sunken, child: Icon(Icons.groups_2_outlined, size: 18)),
            ),
      ],
    );
    if (v != null) _setAssignee(v);
  }

  Future<void> _pickFiles() async {
    final picked = await pickFilesAsBytes();
    if (!mounted) return;
    setState(() {
      for (final f in picked) {
        files.add(_PendingFile(f.name, f.bytes));
      }
    });
  }

  List<String> get _lines => linesCtrl.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  Future<void> _submit() async {
    setState(() => error = null);
    String? problem;
    if (due == null) {
      problem = 'Pick a due date & time';
    } else if (assignee == null) {
      problem = 'Pick an assignee';
    } else if (multiple && _lines.isEmpty) {
      problem = 'Enter at least one task title';
    } else if (!multiple && titleCtrl.text.trim().isEmpty) {
      problem = 'Title is required';
    }
    if (problem != null) {
      setState(() => error = problem);
      toast(problem);
      return;
    }

    setState(() => busy = true);
    final api = Get.find<TaskFlowApi>();
    try {
      final attachmentIds = [...widget.presetAttachmentIds];
      for (final f in files) {
        final a = await api.upload(f.bytes, f.name);
        attachmentIds.add(a.id);
      }
      final ids = await api.createTask(
        NewTask(
          title: titleCtrl.text.trim(),
          description: descCtrl.text.trim(),
          assigneeId: primaryUserId,
          teamId: teamId,
          priority: priority,
          dueAt: due!,
          projectId: projectId,
          parentId: widget.presetParentId,
          boardId: widget.presetBoardId,
          taskTypeId: taskTypeId,
          multiple: multiple,
          lines: multiple ? _lines : const [],
          attachmentIds: attachmentIds,
          collaboratorIds: collaborators.toList(),
          watcherIds: watchers.toList(),
        ),
      );

      if (canAddSubtasks && showSubtasks && subtasks.isNotEmpty && ids.isNotEmpty) {
        try {
          await api.createTask(
            NewTask(
              dueAt: due!,
              priority: priority,
              assigneeId: primaryUserId,
              teamId: teamId,
              parentId: ids.first,
              multiple: true,
              lines: subtasks,
            ),
          );
        } catch (e) {
          toast('Task created, but subtasks failed: ${errorText(e)}');
        }
      }

      final count = ids.length;
      if (isSubtask) {
        toast(count > 1 ? '$count subtasks created' : 'Subtask created');
      } else if (multiple) {
        toast('$count task${count == 1 ? '' : 's'} created');
      } else {
        toast('Task created');
      }
      if (!mounted) return;
      Navigator.pop(
        context,
        ComposerResult(
          ids: ids,
          title: multiple ? null : titleCtrl.text.trim(),
          description: descCtrl.text.trim(),
          assigneeId: primaryUserId,
          lines: multiple ? _lines : null,
        ),
      );
    } catch (e) {
      setState(() => error = errorText(e));
      toastError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamMembers = teamId == null ? <AppUser>[] : users.where((u) => u.teamId == teamId).toList();
    final memberCandidates = users.where((u) => u.id != primaryUserId).toList();
    final canPickMembers = primaryUserId != null && memberCandidates.isNotEmpty;
    final selectedProject = projects.where((p) => p.id == projectId).firstOrNull;
    final selectedType = taskTypes.where((t) => t.id == taskTypeId).firstOrNull;
    final hasAttachments = files.isNotEmpty || widget.presetAttachmentIds.isNotEmpty;
    final selectedTeam = teamId == null ? null : teams.where((t) => t.id == teamId).firstOrNull;
    final assigneeTeamName =
        selectedTeam?.name ?? (primaryUserId == null ? null : users.where((u) => u.id == primaryUserId).firstOrNull?.teamName);
    final memberCount = collaborators.length + watchers.length;

    final submitLabel = busy ? 'Creating…' : (multiple ? 'Create all' : 'Create');

    return Scaffold(
      backgroundColor: Brand.surface,
      body: SafeArea(
        bottom: false,
        // Not lazy: the form is short, and every field must exist for autofill and scrolling to it.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: PageBody(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Hero: title, live summary of the choices, Create, mode toggle
                ListenableBuilder(
                  listenable: linesCtrl,
                  builder: (_, _) => _Hero(
                    eyebrow: isSubtask ? 'Add to task' : 'Create',
                    title: isSubtask ? 'New Subtask' : (multiple ? 'New Tasks' : 'New Task'),
                    summary: [
                      if (multiple) '${_lines.length} task${_lines.length == 1 ? '' : 's'}',
                      assignee == null ? 'No assignee yet' : _assigneeLabel,
                      due == null ? 'No due date' : 'Due ${fmtDateTime(due)}',
                      '${titleCase(priority)} priority',
                    ].join(' · '),
                    submitLabel: submitLabel,
                    busy: busy,
                    onSubmit: _submit,
                    segments: isSubtask
                        ? null
                        : HeroSegments(
                            items: [
                              (const Key('composer-single'), 'Single Task', !multiple, () => _setMultiple(false)),
                              (const Key('composer-multiple'), 'Several at Once', multiple, () => _setMultiple(true)),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Title & description
                BrandSectionTitle(
                  title: multiple ? 'Task titles' : 'Title & description',
                  trailing: multiple
                      ? ListenableBuilder(listenable: linesCtrl, builder: (_, _) => CountBubble(_lines.length))
                      : ListenableBuilder(
                          listenable: titleCtrl,
                          builder: (_, _) => Text(
                            '${titleCtrl.text.length}/140',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Brand.onVariant),
                          ),
                        ),
                ),
                _Card(
                  children: [
                    _Label(multiple ? 'One per line' : 'Title'),
                    if (multiple)
                      TextField(
                        key: const Key('composer-lines'),
                        controller: linesCtrl,
                        minLines: 4,
                        maxLines: 10,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Brand.navy),
                        decoration: _fieldDecoration('One task per line…\nPrepare sales report\nCall vendor about invoice'),
                      )
                    else
                      TextField(
                        key: const Key('composer-title'),
                        controller: titleCtrl,
                        maxLength: 140,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Brand.navy),
                        decoration: _fieldDecoration('Task title (e.g., Update customer invoice)').copyWith(counterText: ''),
                      ),
                    const SizedBox(height: 14),
                    const _Label('Description & notes'),
                    TextField(
                      key: const Key('composer-description'),
                      controller: descCtrl,
                      minLines: 3,
                      maxLines: 8,
                      style: const TextStyle(fontSize: 13, color: Brand.navy, height: 1.4),
                      decoration: _fieldDecoration('Add context, prerequisites or acceptance criteria… Links: [label](https://example.com)'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Assignment
                BrandSectionTitle(title: 'Assignment', tag: assigneeTeamName),
                _Card(
                  children: [
                    const _Label('Assignee'),
                    _PickerRow(
                      key: const Key('composer-assignee'),
                      leading: assignee == null
                          ? const Icon(Icons.person_outline_rounded, size: 19, color: Brand.onVariant)
                          : teamId != null
                          ? const _LimeDot()
                          : Avatar(_assigneeLabel, size: 24),
                      label: _assigneeLabel,
                      placeholder: assignee == null,
                      onTap: users.isEmpty && teams.isEmpty ? null : _pickAssignee,
                    ),
                    if (teamMembers.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const _SubLabel('Team members — tap to assign a person'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final m in teamMembers)
                            _PersonChip(name: m.name, selected: primaryUserId == m.id, onTap: () => _setAssignee('u:${m.id}')),
                        ],
                      ),
                    ],
                    if (!isSubtask) ...[
                      const SizedBox(height: 14),
                      const _Label('Task type'),
                      _PickerRow(
                        key: const Key('composer-type'),
                        tinted: false,
                        leading: const Icon(Icons.terminal_rounded, size: 19, color: Brand.navy),
                        label: loadingTypes ? 'Loading…' : selectedType?.name ?? (taskTypes.isEmpty ? 'No task types' : 'Choose task type (optional)'),
                        trailing: selectedType?.teamName,
                        placeholder: selectedType == null,
                        onTap: taskTypes.isEmpty
                            ? null
                            : () async {
                                final v = await showSearchPicker<int>(
                                  context,
                                  title: 'Task type',
                                  selected: taskTypeId ?? -1,
                                  options: [
                                    const PickerOption(value: -1, label: 'None'),
                                    for (final t in taskTypes) PickerOption(value: t.id, label: t.name, subtitle: t.teamName),
                                  ],
                                );
                                if (v != null) setState(() => taskTypeId = v == -1 ? null : v);
                              },
                      ),
                      if (assignee != null && !loadingTypes && taskTypes.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: InfoBanner(
                            fg: Color(0xFF8A5A0B),
                            bg: TF.amberSoft,
                            icon: Icons.info_outline_rounded,
                            text: 'This team has no task types yet. A Head/Admin can add them from Admin. The task can still be created without a type.',
                          ),
                        ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),

                // ── Priority & due
                BrandSectionTitle(title: 'Priority & due', tag: '${titleCase(priority)} priority'),
                _Card(
                  children: [
                    const _Label('Priority level'),
                    Row(
                      children: [
                        for (final p in priorities) ...[
                          if (p != priorities.first) const SizedBox(width: 8),
                          Expanded(
                            child: _PriorityTile(
                              key: ValueKey('priority-$p'),
                              label: titleCase(p),
                              color: _priorityColor(p),
                              selected: priority == p,
                              onTap: () => setState(() => priority = p),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    const _Label('Target due date'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final q in const [('eod', 'Today EOD'), ('tomorrow', 'Tomorrow noon'), ('2d', '+2 days')])
                          _QuickChip(
                            label: q.$2,
                            selected: due == quickTime(q.$1),
                            onTap: () => setState(() => due = quickTime(q.$1)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _PickerRow(
                      key: const Key('composer-due'),
                      leading: Icon(Icons.event_rounded, size: 19, color: due == null ? Brand.onVariant : Brand.navy),
                      label: due == null ? 'Pick due date & time' : fmtDateTime(due),
                      placeholder: due == null,
                      onTap: () async {
                        final d = await pickDateTime(context, initial: due);
                        if (d != null) setState(() => due = d);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Project, people, subtasks, files
                BrandSectionTitle(title: isSubtask ? 'Attachments' : 'Project & extras'),
                _Card(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  children: [
                    if (!isSubtask)
                      _OptionRow(
                        key: const Key('composer-project'),
                        icon: Icons.folder_outlined,
                        title: 'Target Project',
                        trailing: _LimePill(selectedProject?.name ?? 'No project', chevron: true),
                        onTap: () async {
                          final v = await showSearchPicker<int>(
                            context,
                            title: 'Project',
                            selected: projectId ?? -1,
                            options: [
                              const PickerOption(value: -1, label: 'No project'),
                              for (final p in projects) PickerOption(value: p.id, label: p.name, subtitle: p.ownerName),
                            ],
                          );
                          if (v != null) setState(() => projectId = v == -1 ? null : v);
                        },
                      ),
                    if (canPickMembers) ...[
                      const _RowDivider(),
                      _OptionRow(
                        key: const Key('composer-members-toggle'),
                        icon: Icons.visibility_outlined,
                        title: 'Collaborators & Watchers',
                        trailing: _LimePill(
                          memberCount > 0 ? '$memberCount added' : 'Add',
                          icon: showMembers ? Icons.expand_less_rounded : Icons.person_add_alt_rounded,
                        ),
                        onTap: () => setState(() => showMembers = !showMembers),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Brand.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Brand.outline),
                              ),
                              child: const Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Roles: ',
                                      style: TextStyle(fontWeight: FontWeight.w700, color: Brand.navy),
                                    ),
                                    TextSpan(text: 'Collaborators can view & comment; Watchers receive updates only.'),
                                  ],
                                ),
                                style: TextStyle(fontSize: 11.5, height: 1.45, color: Brand.onVariant),
                              ),
                            ),
                            if (showMembers) ...[
                              const SizedBox(height: 10),
                              _Inset(
                                children: [
                                  const _SubLabel('Collaborators — can view & comment'),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final u in memberCandidates)
                                        _PersonChip(
                                          name: u.name,
                                          selected: collaborators.contains(u.id),
                                          onTap: watchers.contains(u.id)
                                              ? null
                                              : () => setState(
                                                  () => collaborators.contains(u.id) ? collaborators.remove(u.id) : collaborators.add(u.id),
                                                ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  const _SubLabel('Watchers — view updates only'),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final u in memberCandidates)
                                        _PersonChip(
                                          name: u.name,
                                          selected: watchers.contains(u.id),
                                          onTap: collaborators.contains(u.id)
                                              ? null
                                              : () => setState(() => watchers.contains(u.id) ? watchers.remove(u.id) : watchers.add(u.id)),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (canAddSubtasks) ...[
                      const _RowDivider(),
                      _OptionRow(
                        icon: Icons.account_tree_outlined,
                        title: 'Subtasks',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                '${subtasks.length} item${subtasks.length == 1 ? '' : 's'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Brand.onVariant),
                              ),
                            ),
                            if (showSubtasks) const Icon(Icons.expand_less_rounded, size: 20, color: Brand.onVariant),
                          ],
                        ),
                        onTap: showSubtasks ? () => setState(() => showSubtasks = false) : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        child: showSubtasks
                            ? _Inset(
                                children: [
                                  const _SubLabel('Created under this task'),
                                  for (final st in subtasks.asMap().entries)
                                    Row(
                                      children: [
                                        const Icon(Icons.subdirectory_arrow_right_rounded, size: 17, color: Brand.navy),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(st.value, style: const TextStyle(fontSize: 13, color: Brand.navy)),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.close_rounded, size: 18, color: Brand.onVariant),
                                          onPressed: () => setState(() => subtasks.removeAt(st.key)),
                                        ),
                                      ],
                                    ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          key: const Key('composer-subtask-input'),
                                          controller: subtaskCtrl,
                                          style: const TextStyle(fontSize: 13, color: Brand.navy),
                                          decoration: _fieldDecoration('Add a subtask…', fill: Brand.card),
                                          onSubmitted: (_) => _addSubtask(),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      FilledButton(
                                        key: const Key('composer-subtask-add'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Brand.navy,
                                          foregroundColor: Brand.lime,
                                          minimumSize: const Size(0, 46),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                        ),
                                        onPressed: _addSubtask,
                                        child: const Text('Add'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Subtasks inherit the assignee, due date and priority above.',
                                    style: TextStyle(fontSize: 11.5, color: Brand.onVariant),
                                  ),
                                ],
                              )
                            : OutlinedButton(
                                key: const Key('composer-subtasks-toggle'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Brand.navy,
                                  backgroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(42),
                                  side: const BorderSide(color: Brand.outline, width: 1.2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                ),
                                onPressed: () => setState(() => showSubtasks = true),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.add_circle_outline_rounded, size: 18),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        subtasks.isEmpty ? 'Add initial subtasks…' : 'Show subtasks',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                    if (!isSubtask || canPickMembers || canAddSubtasks) const _RowDivider(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.attach_file_rounded, size: 19, color: Brand.navy),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Attachments',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Brand.navy),
                                ),
                              ),
                              if (files.isNotEmpty) ...[const SizedBox(width: 8), CountBubble(files.length)],
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (widget.presetAttachmentIds.isNotEmpty)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _LimePill('Drawing from Scribble attached', icon: Icons.check_rounded),
                              ),
                            ),
                          for (final f in files.asMap().entries)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.fromLTRB(12, 2, 2, 2),
                              decoration: BoxDecoration(
                                color: _limeField,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _limeLine),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.insert_drive_file_outlined, size: 18, color: Brand.navy),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      f.value.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5, color: Brand.navy),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 18, color: Brand.onVariant),
                                    onPressed: () => setState(() => files.removeAt(f.key)),
                                  ),
                                ],
                              ),
                            ),
                          CustomPaint(
                            painter: const _DashedBorder(color: Color(0xFFB8C2D0), radius: 12),
                            child: Material(
                              color: Brand.surface,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                key: const Key('composer-attach'),
                                borderRadius: BorderRadius.circular(12),
                                onTap: _pickFiles,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.cloud_upload_outlined, size: 20, color: Brand.navy),
                                      const SizedBox(width: 10),
                                      Flexible(
                                        child: Text(
                                          hasAttachments ? 'Attach more files' : 'Attach images, logs, or specs',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Brand.navy),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 14),
                  InfoBanner(text: error!, fg: brandRedInk, bg: brandRedSoft, icon: Icons.error_outline_rounded),
                ],
                const SizedBox(height: 18),
                // Second Create at the end of the form so it is reachable without scrolling back up.
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Brand.lime,
                    disabledBackgroundColor: Brand.lime.withValues(alpha: 0.55),
                    foregroundColor: Brand.navy,
                    disabledForegroundColor: Brand.navy,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: Brand.navy, width: 1.5),
                    ),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  onPressed: busy ? null : _submit,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(child: Text(submitLabel, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (!busy) ...[const SizedBox(width: 6), const Icon(Icons.arrow_forward_rounded, size: 18)],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setMultiple(bool v) => setState(() {
    multiple = v;
    if (v) {
      showSubtasks = false;
      subtasks.clear();
    }
  });

  static Color _priorityColor(String p) => switch (p) {
    'URGENT' => brandRed,
    'HIGH' => Brand.navy,
    'NORMAL' => Brand.onVariant,
    _ => const Color(0xFF94A3B8),
  };

  void _addSubtask() {
    final s = subtaskCtrl.text.trim();
    if (s.isEmpty) return;
    setState(() {
      subtasks.add(s);
      subtaskCtrl.clear();
    });
  }
}

// ── Pieces ────────────────────────────────────────────────────────────────

const _limeField = Color(0xFFF7F9EC);
const _limeLine = Color(0xFFE4F0A6);
const _labelInk = Color(0xFF1E293B);

/// Lime-tinted input with a thin lime border; navy when focused.
InputDecoration _fieldDecoration(String hint, {Color fill = _limeField}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: _limeLine, width: 1.2),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w400),
    hintMaxLines: 3,
    filled: true,
    fillColor: fill,
    isDense: false,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Brand.navy, width: 1.5),
    ),
  );
}

/// Navy hero: back · eyebrow/title · Create, a summary of the current choices, then the mode toggle.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.eyebrow,
    required this.title,
    required this.summary,
    required this.submitLabel,
    required this.busy,
    required this.onSubmit,
    this.segments,
  });
  final String eyebrow;
  final String title;
  final String summary;
  final String submitLabel;
  final bool busy;
  final VoidCallback onSubmit;
  final Widget? segments;

  @override
  Widget build(BuildContext context) => HeroCard(
    padding: const EdgeInsets.fromLTRB(10, 12, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19, color: Colors.white),
              onPressed: () => Navigator.maybePop(context),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HeroEyebrow(eyebrow),
                  const SizedBox(height: 2),
                  HeroTitle(title, maxLines: 1),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              key: const Key('composer-submit'),
              style: FilledButton.styleFrom(
                backgroundColor: Brand.lime,
                disabledBackgroundColor: Brand.lime.withValues(alpha: 0.55),
                foregroundColor: Brand.navy,
                disabledForegroundColor: Brand.navy,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              onPressed: busy ? null : onSubmit,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(submitLabel),
                  if (!busy) ...[const SizedBox(width: 6), const Icon(Icons.arrow_forward_rounded, size: 18)],
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 0, 0),
          child: Text(
            summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, height: 1.35, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.72)),
          ),
        ),
        if (segments != null) ...[
          const SizedBox(height: 14),
          Padding(padding: const EdgeInsets.only(left: 6), child: segments),
        ],
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children, this.padding = const EdgeInsets.all(14)});
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Brand.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Brand.outline),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );
}

/// Small caps, letter-spaced field label ("TITLE", "PRIORITY LEVEL").
class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: _labelInk),
    ),
  );
}

class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Brand.onVariant),
    ),
  );
}

class _LimeDot extends StatelessWidget {
  const _LimeDot();

  @override
  Widget build(BuildContext context) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      color: Brand.lime,
      shape: BoxShape.circle,
      border: Border.all(color: Brand.navy, width: 2),
    ),
  );
}

/// Compact lime pill (navy text); optional leading icon or trailing chevron.
class _LimePill extends StatelessWidget {
  const _LimePill(this.label, {this.icon, this.chevron = false});
  final String label;
  final IconData? icon;
  final bool chevron;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(10, 4, chevron ? 6 : 10, 4),
    decoration: BoxDecoration(
      color: Brand.lime,
      borderRadius: BorderRadius.circular(chevron ? 8 : 99),
      border: chevron ? Border.all(color: Brand.limeDim) : null,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 15, color: Brand.navy), const SizedBox(width: 4)],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Brand.navy),
          ),
        ),
        if (chevron) ...[const SizedBox(width: 2), const Icon(Icons.chevron_right_rounded, size: 18, color: Brand.navy)],
      ],
    ),
  );
}

/// Tappable dropdown row: lime-tinted (default) or white outlined.
class _PickerRow extends StatelessWidget {
  const _PickerRow({
    super.key,
    required this.leading,
    required this.label,
    required this.onTap,
    this.placeholder = false,
    this.trailing,
    this.tinted = true,
  });
  final Widget leading;
  final String label;
  final VoidCallback? onTap;
  final bool placeholder;
  final String? trailing;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: tinted ? _limeLine : Brand.outline, width: 1.2),
    );
    return Material(
      color: tinted ? _limeField : Brand.surface,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            children: [
              SizedBox(width: 26, child: Center(child: leading)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: placeholder ? FontWeight.w400 : FontWeight.w600,
                    color: placeholder ? Brand.onVariant : Brand.navy,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Flexible(child: _LimePill(trailing!)),
              ],
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: onTap == null ? const Color(0xFF94A3B8) : Brand.navy),
            ],
          ),
        ),
      ),
    );
  }
}

/// Person chip: navy with lime text + check when selected, white outlined otherwise.
class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.name, required this.selected, required this.onTap});
  final String name;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null && !selected ? 0.45 : 1,
    child: Material(
      color: selected ? Brand.navy : Colors.white,
      shape: StadiumBorder(side: BorderSide(color: selected ? Brand.navy : Brand.outline, width: 1.2)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Avatar(name, size: 26),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? Brand.lime : Brand.navy),
                ),
              ),
              if (selected) ...[const SizedBox(width: 6), const Icon(Icons.check_rounded, size: 17, color: Brand.lime)],
            ],
          ),
        ),
      ),
    ),
  );
}

/// Priority tile: coloured dot over label; lime with a 2px navy border when selected.
class _PriorityTile extends StatelessWidget {
  const _PriorityTile({super.key, required this.label, required this.color, required this.selected, required this.onTap});
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: selected ? Brand.navy : Brand.outline, width: selected ? 2 : 1.2),
    );
    return Material(
      color: selected ? Brand.lime : Brand.surface,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Brand.navy : Brand.onVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Due-date quick pick: navy with lime text + calendar when selected.
class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? Brand.navy : Colors.white,
    shape: StadiumBorder(side: BorderSide(color: selected ? Brand.navy : Brand.outline, width: 1.2)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[const Icon(Icons.event_available_rounded, size: 17, color: Brand.lime), const SizedBox(width: 6)],
            Text(
              label,
              style: TextStyle(fontSize: 12.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w600, color: selected ? Brand.lime : Brand.navy),
            ),
          ],
        ),
      ),
    ),
  );
}

/// List row inside the options card; tappable when [onTap] is set.
class _OptionRow extends StatelessWidget {
  const _OptionRow({super.key, required this.icon, required this.title, required this.trailing, this.onTap});
  final IconData icon;
  final String title;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          Icon(icon, size: 19, color: Brand.navy),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Brand.navy),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Align(alignment: Alignment.centerRight, child: trailing),
          ),
        ],
      ),
    ),
  );
}

class _Inset extends StatelessWidget {
  const _Inset({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Brand.limeLight,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _limeLine),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => const Divider(height: 1, color: Brand.outline);
}

/// Dashed rounded-rect outline for the attachment drop area.
class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, (d + 5).clamp(0, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color || old.radius != radius;
}
