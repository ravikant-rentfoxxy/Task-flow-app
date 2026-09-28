import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/format.dart';
import '../../core/task_logic.dart';
import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
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

    return Scaffold(
      backgroundColor: Brand.bg,
      body: Column(
        children: [
          _Header(
            title: isSubtask ? 'New subtask' : 'New task',
            submitLabel: busy ? 'Creating…' : (multiple ? 'Create tasks' : (isSubtask ? 'Create subtask' : 'Create task')),
            busy: busy,
            onSubmit: _submit,
          ),
          Expanded(
            // Not lazy: the form is short, and every field must exist for autofill and scrolling to it.
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              child: PageBody(
                maxWidth: 720,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isSubtask) ...[
                      _ModeSwitch(
                        multiple: multiple,
                        onChanged: (v) => setState(() {
                          multiple = v;
                          if (v) {
                            showSubtasks = false;
                            subtasks.clear();
                          }
                        }),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // ── Title & description
                    _Card(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _Label(multiple ? 'Task titles · one per line' : 'Title')),
                            if (!multiple)
                              ListenableBuilder(
                                listenable: titleCtrl,
                                builder: (_, _) =>
                                    Text('${titleCtrl.text.length}/140', style: const TextStyle(fontSize: 12.5, color: Brand.muted)),
                              ),
                          ],
                        ),
                        if (multiple)
                          TextField(
                            key: const Key('composer-lines'),
                            controller: linesCtrl,
                            minLines: 4,
                            maxLines: 10,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Brand.ink),
                            decoration: _fieldDecoration('One task per line…\nPrepare sales report\nCall vendor about invoice'),
                          )
                        else
                          TextField(
                            key: const Key('composer-title'),
                            controller: titleCtrl,
                            maxLength: 140,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Brand.ink),
                            decoration: _fieldDecoration('Task name').copyWith(counterText: ''),
                          ),
                        const SizedBox(height: 16),
                        const _Label('Description & notes'),
                        TextField(
                          key: const Key('composer-description'),
                          controller: descCtrl,
                          minLines: 3,
                          maxLines: 8,
                          style: const TextStyle(fontSize: 15, color: Brand.ink, height: 1.4),
                          decoration: _fieldDecoration('Add description… Links: [label](https://example.com)'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // ── Assignment
                    _Card(
                      children: [
                        const _CardTitle(icon: Icons.groups_2_outlined, title: 'Assignment'),
                        const SizedBox(height: 14),
                        const _SubLabel('Assignee'),
                        _PickerRow(
                          key: const Key('composer-assignee'),
                          leading: assignee == null
                              ? const Icon(Icons.person_outline_rounded, size: 20, color: Brand.muted)
                              : teamId != null
                              ? Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(color: Brand.green, shape: BoxShape.circle),
                                )
                              : Avatar(_assigneeLabel, size: 26),
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
                      ],
                    ),
                    const SizedBox(height: 14),

                    // ── Classification
                    _Card(
                      children: [
                        if (!isSubtask) ...[
                          const _Label('Task type'),
                          _PickerRow(
                            key: const Key('composer-type'),
                            leading: const Icon(Icons.sell_outlined, size: 20, color: Brand.primary),
                            label: loadingTypes
                                ? 'Loading…'
                                : selectedType?.name ?? (taskTypes.isEmpty ? 'No task types' : 'Choose task type (optional)'),
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
                                text:
                                    'This team has no task types yet. A Head/Admin can add them from Admin. The task can still be created without a type.',
                              ),
                            ),
                          const SizedBox(height: 18),
                        ],
                        Row(
                          children: [
                            const Expanded(child: _Label('Priority')),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                titleCase(priority),
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _priorityColor(priority)),
                              ),
                            ),
                          ],
                        ),
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
                        const SizedBox(height: 18),
                        const _Label('Due date'),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          child: Row(
                            children: [
                              for (final q in const [('eod', 'Today EOD'), ('tomorrow', 'Tomorrow noon'), ('2d', '+2 days')]) ...[
                                _QuickChip(
                                  label: q.$2,
                                  selected: due == quickTime(q.$1),
                                  onTap: () => setState(() => due = quickTime(q.$1)),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        _PickerRow(
                          key: const Key('composer-due'),
                          leading: Icon(Icons.event_rounded, size: 20, color: due == null ? Brand.muted : Brand.primary),
                          label: due == null ? 'Pick due date & time' : fmtDateTime(due),
                          placeholder: due == null,
                          onTap: () async {
                            final d = await pickDateTime(context, initial: due);
                            if (d != null) setState(() => due = d);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // ── Project, people, subtasks, files
                    _Card(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      children: [
                        if (!isSubtask)
                          _OptionRow(
                            key: const Key('composer-project'),
                            icon: Icons.folder_outlined,
                            title: 'Project',
                            trailing: _ValueChip(selectedProject?.name ?? 'No project'),
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
                            title: 'Collaborators & watchers',
                            trailing: _ToggleLabel(
                              open: showMembers,
                              label: collaborators.length + watchers.length > 0 ? '${collaborators.length + watchers.length} added' : 'Add',
                              icon: Icons.person_add_alt_rounded,
                            ),
                            onTap: () => setState(() => showMembers = !showMembers),
                          ),
                          if (showMembers)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: _Inset(
                                children: [
                                  const Text(
                                    'Collaborators — can view & comment',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Brand.ink),
                                  ),
                                  const SizedBox(height: 8),
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
                                  const Text(
                                    'Watchers — view updates only',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Brand.ink),
                                  ),
                                  const SizedBox(height: 8),
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
                            ),
                        ],
                        if (canAddSubtasks) ...[
                          const _RowDivider(),
                          _OptionRow(
                            key: const Key('composer-subtasks-toggle'),
                            icon: Icons.account_tree_outlined,
                            title: 'Subtasks',
                            trailing: _ToggleLabel(
                              open: showSubtasks,
                              label: subtasks.isEmpty ? 'Add' : '${subtasks.length} item${subtasks.length == 1 ? '' : 's'}',
                              icon: Icons.add_circle_outline_rounded,
                            ),
                            onTap: () => setState(() => showSubtasks = !showSubtasks),
                          ),
                          if (showSubtasks)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: _Inset(
                                children: [
                                  const Text(
                                    'Subtasks — created under this task',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Brand.ink),
                                  ),
                                  const SizedBox(height: 6),
                                  for (final st in subtasks.asMap().entries)
                                    Row(
                                      children: [
                                        const Icon(Icons.subdirectory_arrow_right_rounded, size: 18, color: Brand.primary),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(st.value, style: const TextStyle(fontSize: 14.5, color: Brand.ink)),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.close_rounded, size: 18, color: Brand.muted),
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
                                          style: const TextStyle(fontSize: 14.5, color: Brand.ink),
                                          decoration: _fieldDecoration('Add a subtask…', fill: Brand.card),
                                          onSubmitted: (_) => _addSubtask(),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      FilledButton(
                                        key: const Key('composer-subtask-add'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Brand.primary,
                                          minimumSize: const Size(0, 48),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        onPressed: _addSubtask,
                                        child: const Text('Add'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Subtasks inherit the assignee, due date and priority above.',
                                    style: TextStyle(fontSize: 12.5, color: Brand.muted),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        if (!isSubtask || canPickMembers || canAddSubtasks) const _RowDivider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.attach_file_rounded, size: 22, color: Brand.inkSoft),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'Attachments',
                                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: Brand.ink),
                                    ),
                                  ),
                                  if (files.isNotEmpty)
                                    Text(
                                      '${files.length} file${files.length > 1 ? 's' : ''}',
                                      style: const TextStyle(fontSize: 13, color: Brand.muted),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              if (widget.presetAttachmentIds.isNotEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 8),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Pill(
                                      'Drawing from Scribble attached',
                                      fg: TF.green,
                                      bg: TF.greenSoft,
                                      icon: Icons.check_rounded,
                                    ),
                                  ),
                                ),
                              for (final f in files.asMap().entries)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                                  decoration: BoxDecoration(color: Brand.field, borderRadius: BorderRadius.circular(12)),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.insert_drive_file_outlined, size: 20, color: Brand.primary),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          f.value.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 14, color: Brand.ink),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close_rounded, size: 18, color: Brand.muted),
                                        onPressed: () => setState(() => files.removeAt(f.key)),
                                      ),
                                    ],
                                  ),
                                ),
                              Material(
                                color: Brand.field,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  key: const Key('composer-attach'),
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: _pickFiles,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.cloud_upload_outlined, size: 22, color: Brand.primary),
                                        const SizedBox(width: 10),
                                        Text(
                                          hasAttachments ? 'Attach more files' : 'Attach files',
                                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Brand.inkSoft),
                                        ),
                                      ],
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
                      InfoBanner(text: error!, fg: TF.coral, bg: TF.coralSoft, icon: Icons.error_outline_rounded),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _priorityColor(String p) => switch (p) {
    'URGENT' => Brand.red,
    'HIGH' => const Color(0xFF0E7490),
    'NORMAL' => Brand.primary,
    _ => Brand.faint,
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

InputDecoration _fieldDecoration(String hint, {Color fill = Brand.field}) {
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none);
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Brand.faint, fontSize: 15, fontWeight: FontWeight.w400),
    filled: true,
    fillColor: fill,
    isDense: false,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Brand.primary.withValues(alpha: 0.6), width: 1.5),
    ),
  );
}

/// Back · TF · "Create task" bar, then Cancel · • title · Create →.
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.submitLabel, required this.busy, required this.onSubmit});
  final String title;
  final String submitLabel;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SafeArea(
      bottom: false,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Brand.line)),
        ),
        padding: const EdgeInsets.fromLTRB(4, 4, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 21, color: Brand.inkSoft),
                  onPressed: () => Navigator.maybePop(context),
                ),
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Brand.ink, borderRadius: BorderRadius.circular(9)),
                  child: const Text(
                    'TF',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'TaskFlow',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: Brand.ink),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Brand.inkSoft,
                    textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500),
                  ),
                  onPressed: () => Navigator.maybePop(context),
                  child: const Text('Cancel'),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: Brand.primary, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: Brand.ink),
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  key: const Key('composer-submit'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Brand.primary,
                    disabledBackgroundColor: Brand.primary.withValues(alpha: 0.6),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  onPressed: busy ? null : onSubmit,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(submitLabel),
                      if (!busy) ...[const SizedBox(width: 6), const Icon(Icons.arrow_forward_rounded, size: 19)],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Single task · Multiple tasks.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.multiple, required this.onChanged});
  final bool multiple;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(Key? key, IconData icon, String label, bool selected, bool value) => Expanded(
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          decoration: BoxDecoration(
            color: selected ? Brand.card : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected ? [BoxShadow(color: Brand.ink.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? Brand.primary : Brand.inkSoft),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Brand.primary : Brand.inkSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Brand.primarySoft.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          seg(const Key('composer-single'), Icons.edit_note_rounded, 'Single task', !multiple, false),
          seg(const Key('composer-multiple'), Icons.playlist_add_rounded, 'Multiple tasks', multiple, true),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children, this.padding = const EdgeInsets.fromLTRB(16, 18, 16, 18)});
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Brand.card,
      borderRadius: BorderRadius.circular(Brand.radius),
      border: Border.all(color: Brand.line),
      boxShadow: Brand.shadow,
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );
}

/// Small caps field label ("TITLE", "PRIORITY").
class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: Brand.inkSoft),
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
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Brand.inkSoft),
    ),
  );
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 22, color: Brand.primary),
      const SizedBox(width: 10),
      Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Brand.ink),
      ),
    ],
  );
}

/// Lavender tappable row with a leading widget and a dropdown chevron.
class _PickerRow extends StatelessWidget {
  const _PickerRow({super.key, required this.leading, required this.label, required this.onTap, this.placeholder = false, this.trailing});
  final Widget leading;
  final String label;
  final VoidCallback? onTap;
  final bool placeholder;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Material(
    color: Brand.field,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
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
                  fontSize: 15.5,
                  fontWeight: placeholder ? FontWeight.w400 : FontWeight.w600,
                  color: placeholder ? Brand.muted : Brand.ink,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: Brand.slateSoft, borderRadius: BorderRadius.circular(99)),
                child: Text(trailing!, style: const TextStyle(fontSize: 12, color: Brand.inkSoft)),
              ),
            ],
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down_rounded, size: 24, color: onTap == null ? Brand.faint : Brand.inkSoft),
          ],
        ),
      ),
    ),
  );
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.name, required this.selected, required this.onTap});
  final String name;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null && !selected ? 0.45 : 1,
    child: Material(
      color: selected ? Brand.primary : Brand.field,
      shape: const StadiumBorder(),
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
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: selected ? Colors.white : Brand.ink),
                ),
              ),
              if (selected) ...[const SizedBox(width: 6), const Icon(Icons.check_rounded, size: 17, color: Colors.white)],
            ],
          ),
        ),
      ),
    ),
  );
}

class _PriorityTile extends StatelessWidget {
  const _PriorityTile({super.key, required this.label, required this.color, required this.selected, required this.onTap});
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? color.withValues(alpha: 0.12) : Brand.field,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: selected ? color : Colors.transparent, width: 1.6),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: Brand.ink),
            ),
          ],
        ),
      ),
    ),
  );
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? Brand.primary : Brand.field,
    shape: const StadiumBorder(),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[const Icon(Icons.event_available_rounded, size: 17, color: Colors.white), const SizedBox(width: 6)],
            Text(
              label,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: selected ? Colors.white : Brand.inkSoft),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Tappable list row inside the options card.
class _OptionRow extends StatelessWidget {
  const _OptionRow({super.key, required this.icon, required this.title, required this.trailing, required this.onTap});
  final IconData icon;
  final String title;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Icon(icon, size: 22, color: Brand.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: Brand.ink),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(child: trailing),
        ],
      ),
    ),
  );
}

class _ValueChip extends StatelessWidget {
  const _ValueChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
    decoration: BoxDecoration(color: Brand.field, borderRadius: BorderRadius.circular(10)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Brand.ink),
          ),
        ),
        const Icon(Icons.chevron_right_rounded, size: 20, color: Brand.inkSoft),
      ],
    ),
  );
}

class _ToggleLabel extends StatelessWidget {
  const _ToggleLabel({required this.open, required this.label, required this.icon});
  final bool open;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(open ? Icons.expand_less_rounded : icon, size: 19, color: Brand.primary),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Brand.primary),
        ),
      ),
    ],
  );
}

class _Inset extends StatelessWidget {
  const _Inset({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Brand.field, borderRadius: BorderRadius.circular(14)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => const Divider(height: 1, indent: 16, endIndent: 16, color: Brand.line);
}
