import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/format.dart';
import '../../core/task_logic.dart';
import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/attachments.dart';
import '../../widgets/brand_ui.dart';
import '../../widgets/common.dart';
import '../../widgets/files.dart';
import '../tasks/composer_sheet.dart';
import '../tasks/task_card.dart';
import '../shell/top_bar.dart';

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
        backgroundColor: Brand.surface,
        appBar: AppBar(title: BrandTitle.text('Project')),
        body: error != null ? ErrorView(message: error!, onRetry: _load) : const Padding(padding: EdgeInsets.all(16), child: SkeletonList()),
      );
    }
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: Brand.surface,
        appBar: AppBar(
          title: BrandTitle.text(d.project.name),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Brand.navy,
            unselectedLabelColor: Brand.onVariant,
            indicatorColor: Brand.navy,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: [
              const Tab(text: 'Overview'),
              Tab(key: const Key('project-tab-tasks'), text: 'Tasks (${d.tasks.length})'),
              Tab(key: const Key('project-tab-files'), text: 'Files (${d.files.length})'),
              const Tab(key: Key('project-tab-activity'), text: 'Activity'),
            ],
          ),
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
        color: Brand.navy,
        backgroundColor: Brand.lime,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [PageBody(maxWidth: 900, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))],
        ),
      );

  static bool _isOpen(Task t) => t.status != 'DONE' && t.status != 'CANCELLED';

  Widget _hero(ProjectDetail d) {
    final p = d.project;
    final desc = p.description?.trim() ?? '';
    final open = d.tasks.where(_isOpen).length;
    return HeroCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HeroEyebrow('Project · created ${fmtDate(p.createdAt)}'),
        const SizedBox(height: 8),
        HeroTitle(p.name),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 6),
          SelectableText(desc, style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.white.withValues(alpha: 0.75))),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.person_outline_rounded, size: 15, color: Colors.white.withValues(alpha: 0.6)),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Owner: ${p.ownerName ?? '—'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.8))),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _HeroStat(value: '${d.members.length}', label: 'Members')),
          const SizedBox(width: 8),
          Expanded(child: _HeroStat(value: '$open', label: 'Open tasks', accent: true)),
          const SizedBox(width: 8),
          Expanded(child: _HeroStat(value: '${d.files.length}', label: 'Files')),
        ]),
      ]),
    );
  }

  Widget _overview(ProjectDetail d) {
    final candidates = users.where((u) => !d.members.any((m) => m.id == u.id)).toList();
    return _padded([
      _hero(d),
      const SizedBox(height: 22),
      BrandSectionTitle(title: 'Notes', tag: 'visible to every member', count: d.notes.length),
      for (final n in d.notes)
        Container(
          key: ValueKey('note-${n.id}'),
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 4),
          decoration: BoxDecoration(
            color: n.pinned ? Brand.limeLight : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: n.pinned ? Brand.limeDim : Brand.outline),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text('${n.pinned ? '📌 ' : ''}${n.body}', style: const TextStyle(fontSize: 13, height: 1.4, color: Brand.navy)),
            ),
            Row(children: [
              Expanded(
                child: Text('${n.authorName ?? ''} · ${timeAgo(n.createdAt)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Brand.onVariant)),
              ),
              if (d.canManage)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Brand.navy, textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  onPressed: () => _patch({'togglePinNoteId': n.id}, n.pinned ? 'Note unpinned' : 'Note pinned'),
                  child: Text(n.pinned ? 'Unpin' : 'Pin'),
                )
              else
                const SizedBox(height: 8),
            ]),
          ]),
        ),
      Row(children: [
        Expanded(child: TextField(key: const Key('note-input'), controller: noteCtrl, decoration: const InputDecoration(hintText: 'Add a note for the team…'), onChanged: (_) => setState(() {}))),
        const SizedBox(width: 8),
        FilledButton(
          key: const Key('note-add'),
          style: FilledButton.styleFrom(backgroundColor: Brand.navy, foregroundColor: Brand.lime),
          onPressed: noteCtrl.text.trim().isEmpty
              ? null
              : () {
                  final v = noteCtrl.text.trim();
                  noteCtrl.clear();
                  _patch({'note': v}, 'Note added');
                },
          child: const Text('Add', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]),
      const SizedBox(height: 22),
      BrandSectionTitle(title: 'Members', count: d.members.length),
      if (d.members.isNotEmpty)
        BrandCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(children: [
            for (final (i, m) in d.members.indexed) ...[
              if (i > 0) const Divider(height: 1, color: Brand.outline),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Avatar(m.name),
                title: Text(m.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Brand.navy)),
                subtitle: Text(
                  m.id == d.project.ownerId ? '${m.role} · Owner' : m.role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Brand.onVariant),
                ),
                trailing: d.canManage && m.id != d.project.ownerId
                    ? TextButton(
                        style: TextButton.styleFrom(foregroundColor: brandRed),
                        onPressed: () => _patch({'removeMemberId': m.id}, 'Member removed'),
                        child: const Text('Remove'),
                      )
                    : null,
              ),
            ],
          ]),
        ),
      if (d.canManage && candidates.isNotEmpty) ...[
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('project-add-member'),
            style: OutlinedButton.styleFrom(foregroundColor: Brand.navy, side: const BorderSide(color: Brand.navy)),
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
        ),
      ],
    ]);
  }

  Widget _tasks(ProjectDetail d) {
    final open = d.tasks.where(_isOpen).toList();
    final closed = d.tasks.where((t) => !_isOpen(t)).toList();
    Widget list(List<Task> tasks) => TaskList(tasks: tasks, onChanged: _load, cardBuilder: (t) => DashboardTaskCard(task: t, onChanged: _load));
    return _padded([
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          key: const Key('project-new-task'),
          style: FilledButton.styleFrom(backgroundColor: Brand.lime, foregroundColor: Brand.navy),
          onPressed: () async {
            if (await showComposer(context, presetProjectId: d.project.id) != null) _load();
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('New task in this project', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
      const SizedBox(height: 18),
      if (d.tasks.isEmpty)
        const BrandCard(child: EmptyState(icon: Icons.task_alt_rounded, color: Brand.navy, title: 'No tasks in this project yet'))
      else ...[
        if (open.isNotEmpty) ...[BrandSectionTitle(title: 'Open', count: open.length), list(open), const SizedBox(height: 10)],
        if (closed.isNotEmpty) ...[BrandSectionTitle(title: 'Closed', count: closed.length), list(closed)],
      ],
    ]);
  }

  Widget _files(ProjectDetail d) => _padded([
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const Key('project-upload'),
            style: FilledButton.styleFrom(backgroundColor: Brand.navy, foregroundColor: Brand.lime),
            onPressed: uploading ? null : _upload,
            icon: const Icon(Icons.upload_rounded),
            label: Text(uploading ? 'Uploading…' : 'Upload file to project', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 18),
        BrandSectionTitle(title: 'Files', count: d.files.length),
        if (d.files.isEmpty)
          const BrandCard(child: EmptyState(icon: Icons.insert_drive_file_outlined, color: Brand.navy, title: 'No files yet'))
        else
          for (final f in d.files) Padding(padding: const EdgeInsets.only(bottom: 8), child: AttachmentTile(attachment: f)),
      ]);

  Widget _activity(ProjectDetail d) => _padded([
        BrandSectionTitle(title: 'Activity', count: d.activity.length),
        if (d.activity.isEmpty)
          const BrandCard(child: EmptyState(icon: Icons.history_rounded, color: Brand.navy, title: 'No activity yet'))
        else
          BrandCard(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
            child: Column(children: [
              for (final a in d.activity)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 5, right: 10),
                      decoration: BoxDecoration(color: Brand.lime, shape: BoxShape.circle, border: Border.all(color: Brand.navy, width: 1.5)),
                    ),
                    Expanded(
                      child: Wrap(children: [
                        Text(a.actorName ?? 'System', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Brand.navy)),
                        Text(' ${activityTypeLabel(a.type)}', style: const TextStyle(fontSize: 12, color: Brand.onVariant)),
                        if (a.taskTitle != null) ...[
                          const Text(' on ', style: TextStyle(fontSize: 12, color: Brand.onVariant)),
                          InkWell(
                            onTap: a.taskId == null ? null : () => openTask(context, a.taskId!),
                            child: Text(a.taskTitle!,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Brand.navy, decoration: TextDecoration.underline)),
                          ),
                        ],
                        Text(' · ${timeAgo(a.createdAt)}', style: const TextStyle(fontSize: 11.5, color: TF.faint)),
                      ]),
                    ),
                  ]),
                ),
            ]),
          ),
      ]);
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label, this.accent = false});
  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                maxLines: 1,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1, letterSpacing: -0.6, color: accent ? Brand.lime : Colors.white)),
          ),
          const SizedBox(height: 4),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.65))),
        ]),
      );
}
