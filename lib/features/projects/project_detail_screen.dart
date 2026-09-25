import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/format.dart';
import '../../core/task_logic.dart';
import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/attachments.dart';
import '../../widgets/common.dart';
import '../../widgets/files.dart';
import '../tasks/composer_sheet.dart';
import '../tasks/task_card.dart';

class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.projectId});
  final int projectId;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  ProjectDetail? data;
  String? error;
  List<AppUser> users = [];
  bool uploading = false;
  final noteCtrl = TextEditingController();

  TaskFlowApi get api => Get.find<TaskFlowApi>();

  @override
  void initState() {
    super.initState();
    _load();
    api.users().then((u) => mounted ? setState(() => users = u.where((x) => x.isActive).toList()) : null).catchError((_) {});
  }

  Future<void> _load() async {
    try {
      final d = await api.project(widget.projectId);
      if (mounted) setState(() => (data = d, error = null));
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    }
  }

  Future<void> _patch(Map<String, dynamic> body, String success) async {
    try {
      await api.updateProject(widget.projectId, body);
      toast(success);
      await _load();
    } catch (e) {
      toastError(e);
    }
  }

  Future<void> _upload() async {
    final files = await pickFilesAsBytes();
    if (files.isEmpty) return;
    setState(() => uploading = true);
    try {
      for (final f in files) {
        await api.upload(f.bytes, f.name, projectId: widget.projectId);
      }
      toast(files.length > 1 ? '${files.length} files uploaded' : 'File uploaded');
      await _load();
    } catch (e) {
      toastError(e, 'Upload failed');
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Project')),
        body: error != null ? ErrorView(message: error!, onRetry: _load) : const Padding(padding: EdgeInsets.all(16), child: SkeletonList()),
      );
    }
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(d.project.name),
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            const Tab(text: 'Overview'),
            Tab(key: const Key('project-tab-tasks'), text: 'Tasks (${d.tasks.length})'),
            Tab(key: const Key('project-tab-files'), text: 'Files (${d.files.length})'),
            const Tab(key: Key('project-tab-activity'), text: 'Activity'),
          ]),
        ),
        body: TabBarView(children: [
          _overview(d),
          _tasks(d),
          _files(d),
          _activity(d),
        ]),
      ),
    );
  }

  Widget _padded(List<Widget> children) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [PageBody(maxWidth: 900, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children))]),
      );

  Widget _overview(ProjectDetail d) {
    final candidates = users.where((u) => !d.members.any((m) => m.id == u.id)).toList();
    return _padded([
      Text('Owner: ${d.project.ownerName ?? '—'} · created ${fmtDate(d.project.createdAt)}', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 14),
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('DESCRIPTION', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          SelectableText(d.project.description?.isNotEmpty == true ? d.project.description! : '—'),
        ]),
      ),
      const SizedBox(height: 18),
      const SectionHeader(title: 'Notes — visible to every member', icon: Icons.sticky_note_2_outlined, color: TF.amber),
      for (final n in d.notes)
        Container(
          key: ValueKey('note-${n.id}'),
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: n.pinned ? TF.amberSoft : TF.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: n.pinned ? TF.amber.withValues(alpha: 0.4) : TF.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${n.pinned ? '📌 ' : ''}${n.body}'),
            const SizedBox(height: 4),
            Row(children: [
              Text('${n.authorName ?? ''} · ${timeAgo(n.createdAt)}', style: const TextStyle(fontSize: 11.5, color: TF.muted)),
              if (d.canManage)
                TextButton(
                  onPressed: () => _patch({'togglePinNoteId': n.id}, n.pinned ? 'Note unpinned' : 'Note pinned'),
                  child: Text(n.pinned ? 'Unpin' : 'Pin'),
                ),
            ]),
          ]),
        ),
      Row(children: [
        Expanded(child: TextField(key: const Key('note-input'), controller: noteCtrl, decoration: const InputDecoration(hintText: 'Add a note for the team…'), onChanged: (_) => setState(() {}))),
        const SizedBox(width: 8),
        FilledButton(
          key: const Key('note-add'),
          onPressed: noteCtrl.text.trim().isEmpty
              ? null
              : () {
                  final v = noteCtrl.text.trim();
                  noteCtrl.clear();
                  _patch({'note': v}, 'Note added');
                },
          child: const Text('Add'),
        ),
      ]),
      const SizedBox(height: 22),
      SectionHeader(title: 'Members', icon: Icons.people_outline_rounded, count: d.members.length),
      for (final m in d.members)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Avatar(m.name),
          title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(m.role),
          trailing: d.canManage && m.id != d.project.ownerId
              ? TextButton(
                  style: TextButton.styleFrom(foregroundColor: TF.coral),
                  onPressed: () => _patch({'removeMemberId': m.id}, 'Member removed'),
                  child: const Text('Remove'),
                )
              : null,
        ),
      if (d.canManage && candidates.isNotEmpty)
        OutlinedButton.icon(
          key: const Key('project-add-member'),
          onPressed: () async {
            final id = await showSearchPicker<int>(
              context,
              title: 'Add member',
              options: [for (final u in candidates) PickerOption(value: u.id, label: u.name, subtitle: u.teamName, leading: Avatar(u.name))],
            );
            if (id != null) _patch({'addMemberId': id}, 'Member added');
          },
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: const Text('Add member'),
        ),
    ]);
  }

  Widget _tasks(ProjectDetail d) => _padded([
        FilledButton.icon(
          key: const Key('project-new-task'),
          onPressed: () async {
            if (await showComposer(context, presetProjectId: d.project.id) != null) _load();
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('New task in this project'),
        ),
        const SizedBox(height: 14),
        if (d.tasks.isEmpty)
          const Surface(child: EmptyState(icon: Icons.task_alt_rounded, title: 'No tasks in this project yet'))
        else
          TaskList(tasks: d.tasks, onChanged: _load),
      ]);

  Widget _files(ProjectDetail d) => _padded([
        OutlinedButton.icon(
          key: const Key('project-upload'),
          onPressed: uploading ? null : _upload,
          icon: const Icon(Icons.upload_rounded),
          label: Text(uploading ? 'Uploading…' : 'Upload file to project'),
        ),
        const SizedBox(height: 14),
        if (d.files.isEmpty)
          const Surface(child: EmptyState(icon: Icons.insert_drive_file_outlined, title: 'No files yet'))
        else
          for (final f in d.files) Padding(padding: const EdgeInsets.only(bottom: 8), child: AttachmentTile(attachment: f)),
      ]);

  Widget _activity(ProjectDetail d) => _padded([
        if (d.activity.isEmpty) const EmptyState(icon: Icons.history_rounded, title: 'No activity yet'),
        for (final a in d.activity)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6, right: 10), decoration: const BoxDecoration(color: TF.primary, shape: BoxShape.circle)),
              Expanded(
                child: Wrap(children: [
                  Text(a.actorName ?? 'System', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Text(' ${activityTypeLabel(a.type)}', style: const TextStyle(fontSize: 13, color: TF.muted)),
                  if (a.taskTitle != null) ...[
                    const Text(' on ', style: TextStyle(fontSize: 13, color: TF.muted)),
                    InkWell(
                      onTap: a.taskId == null ? null : () => openTask(context, a.taskId!),
                      child: Text(a.taskTitle!, style: const TextStyle(fontSize: 13, color: TF.primary, decoration: TextDecoration.underline)),
                    ),
                  ],
                  Text(' · ${timeAgo(a.createdAt)}', style: const TextStyle(fontSize: 13, color: TF.faint)),
                ]),
              ),
            ]),
          ),
      ]);
}
