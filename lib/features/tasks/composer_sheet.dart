import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
  return showAppSheet<ComposerResult>(
    context,
    expand: true,
    builder: (_) => ComposerSheet(
      presetProjectId: presetProjectId,
      presetParentId: presetParentId,
      presetAttachmentIds: presetAttachmentIds,
      presetBoardId: presetBoardId,
      presetTitle: presetTitle,
      presetAssigneeId: presetAssigneeId,
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
      final ids = await api.createTask(NewTask(
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
      ));

      if (canAddSubtasks && showSubtasks && subtasks.isNotEmpty && ids.isNotEmpty) {
        try {
          await api.createTask(NewTask(
            dueAt: due!,
            priority: priority,
            assigneeId: primaryUserId,
            teamId: teamId,
            parentId: ids.first,
            multiple: true,
            lines: subtasks,
          ));
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

    return Column(children: [
      SheetTitle(
        isSubtask ? 'New subtask' : 'New task',
        trailing: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            if (!isSubtask) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                ActionChip(
                  key: const Key('composer-project'),
                  avatar: const Icon(Icons.folder_outlined, size: 17),
                  label: Text(selectedProject?.name ?? 'No project'),
                  onPressed: () async {
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
                FilterChip(
                  key: const Key('composer-multiple'),
                  label: const Text('Multiple tasks'),
                  selected: multiple,
                  onSelected: (v) => setState(() {
                    multiple = v;
                    if (v) {
                      showSubtasks = false;
                      subtasks.clear();
                    }
                  }),
                ),
                if (canAddSubtasks)
                  FilterChip(
                    key: const Key('composer-subtasks-toggle'),
                    label: const Text('Subtasks'),
                    selected: showSubtasks,
                    onSelected: (v) => setState(() => showSubtasks = v),
                  ),
                if (canPickMembers)
                  FilterChip(
                    key: const Key('composer-members-toggle'),
                    label: const Text('Collaborators & watchers'),
                    selected: showMembers,
                    onSelected: (v) => setState(() => showMembers = v),
                  ),
              ]),
              const SizedBox(height: 14),
            ],
            if (multiple)
              TextField(
                key: const Key('composer-lines'),
                controller: linesCtrl,
                minLines: 4,
                maxLines: 10,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(hintText: 'One task per line…\nPrepare sales report\nCall vendor about invoice'),
              )
            else
              TextField(
                key: const Key('composer-title'),
                controller: titleCtrl,
                maxLength: 140,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                decoration: const InputDecoration(
                  hintText: 'Task name',
                  counterText: '',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            const SizedBox(height: 6),
            TextField(
              key: const Key('composer-description'),
              controller: descCtrl,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(hintText: 'Add description… Links: [label](https://example.com)'),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Assignee'),
            PickerField(
              key: const Key('composer-assignee'),
              label: _assigneeLabel,
              placeholder: assignee == null,
              icon: Icons.person_outline_rounded,
              onTap: users.isEmpty && teams.isEmpty ? null : _pickAssignee,
            ),
            if (teamMembers.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Team members — tap to assign a person', style: TextStyle(fontSize: 12, color: TF.muted)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final m in teamMembers) ActionChip(label: Text(m.name), onPressed: () => _setAssignee('u:${m.id}')),
              ]),
            ],
            if (!isSubtask) ...[
              const SizedBox(height: 12),
              const FieldLabel('Task type'),
              PickerField(
                key: const Key('composer-type'),
                label: loadingTypes
                    ? 'Loading…'
                    : selectedType?.name ?? (taskTypes.isEmpty ? 'No task types' : 'Choose task type (optional)'),
                placeholder: selectedType == null,
                icon: Icons.sell_outlined,
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
                  padding: EdgeInsets.only(top: 8),
                  child: InfoBanner(
                    fg: Color(0xFF8A5A0B),
                    bg: TF.amberSoft,
                    icon: Icons.info_outline_rounded,
                    text: 'This team has no task types yet. A Head/Admin can add them from Admin. The task can still be created without a type.',
                  ),
                ),
            ],
            const SizedBox(height: 12),
            const FieldLabel('Due date'),
            DateTimeField(
              key: const Key('composer-due'),
              value: due,
              onChanged: (d) => setState(() => due = d),
              label: 'Pick due date & time',
              quick: const [('eod', 'Today EOD'), ('tomorrow', 'Tomorrow noon'), ('2d', '+2 days')],
            ),
            const SizedBox(height: 12),
            const FieldLabel('Priority'),
            Wrap(spacing: 8, children: [
              for (final p in priorities)
                ChoiceChip(
                  key: ValueKey('priority-$p'),
                  avatar: Icon(Icons.flag_rounded, size: 16, color: priority == p ? Colors.white : TF.priority(p)),
                  label: Text(titleCase(p)),
                  selected: priority == p,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => priority = p),
                ),
            ]),
            if (showSubtasks && canAddSubtasks) ...[
              const SizedBox(height: 16),
              Surface(
                color: TF.paper,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Subtasks — created under this task', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 8),
                  for (final s in subtasks.asMap().entries)
                    Row(children: [
                      const Icon(Icons.circle, size: 7, color: TF.faint),
                      const SizedBox(width: 10),
                      Expanded(child: Text(s.value)),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => subtasks.removeAt(s.key)),
                      ),
                    ]),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        key: const Key('composer-subtask-input'),
                        controller: subtaskCtrl,
                        decoration: const InputDecoration(hintText: 'Add a subtask…'),
                        onSubmitted: (_) => _addSubtask(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(key: const Key('composer-subtask-add'), onPressed: _addSubtask, child: const Text('Add')),
                  ]),
                  const SizedBox(height: 6),
                  const Text('Subtasks inherit the assignee, due date and priority above.', style: TextStyle(fontSize: 12, color: TF.muted)),
                ]),
              ),
            ],
            if (showMembers && canPickMembers) ...[
              const SizedBox(height: 16),
              Surface(
                color: TF.paper,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Collaborators — can view & comment', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final u in memberCandidates)
                      FilterChip(
                        label: Text(u.name),
                        selected: collaborators.contains(u.id),
                        onSelected: watchers.contains(u.id)
                            ? null
                            : (v) => setState(() => v ? collaborators.add(u.id) : collaborators.remove(u.id)),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  const Text('Watchers — view updates only', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final u in memberCandidates)
                      FilterChip(
                        label: Text(u.name),
                        selected: watchers.contains(u.id),
                        onSelected: collaborators.contains(u.id)
                            ? null
                            : (v) => setState(() => v ? watchers.add(u.id) : watchers.remove(u.id)),
                      ),
                  ]),
                ]),
              ),
            ],
            if (files.isNotEmpty || widget.presetAttachmentIds.isNotEmpty) ...[
              const SizedBox(height: 16),
              const FieldLabel('Attachments'),
              if (widget.presetAttachmentIds.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Pill('Drawing from Scribble attached', fg: TF.green, bg: TF.greenSoft, icon: Icons.check_rounded),
                ),
              for (final f in files.asMap().entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(f.value.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => files.removeAt(f.key)),
                  ),
                ),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              InfoBanner(text: error!, fg: TF.coral, bg: TF.coralSoft, icon: Icons.error_outline_rounded),
            ],
          ],
        ),
      ),
      Container(
        decoration: const BoxDecoration(color: TF.paper, border: Border(top: BorderSide(color: TF.line))),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: SafeArea(
          top: false,
          child: Row(children: [
            IconButton(
              key: const Key('composer-attach'),
              tooltip: 'Attach files',
              onPressed: _pickFiles,
              icon: const Icon(Icons.attach_file_rounded),
            ),
            if (files.isNotEmpty) Text('${files.length} file${files.length > 1 ? 's' : ''}', style: const TextStyle(color: TF.muted)),
            const Spacer(),
            FilledButton(
              key: const Key('composer-submit'),
              onPressed: busy ? null : _submit,
              child: Text(busy ? 'Creating…' : (multiple ? 'Create tasks' : (isSubtask ? 'Create subtask' : 'Create task'))),
            ),
          ]),
        ),
      ),
    ]);
  }

  void _addSubtask() {
    final s = subtaskCtrl.text.trim();
    if (s.isEmpty) return;
    setState(() {
      subtasks.add(s);
      subtaskCtrl.clear();
    });
  }
}
