import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../shell/top_bar.dart';
import 'project_detail_screen.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<Project>? projects;
  String? error;

  TaskFlowApi get api => Get.find<TaskFlowApi>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await api.projects();
      if (mounted) setState(() => (projects = p, error = null));
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    }
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final desc = TextEditingController();
    final ok = await showAppSheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('New project', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 14),
              const FieldLabel('Name'),
              TextField(key: const Key('project-name'), controller: name, onChanged: (_) => set(() {})),
              const SizedBox(height: 10),
              const FieldLabel('Description'),
              TextField(key: const Key('project-desc'), controller: desc, minLines: 3, maxLines: 6),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('project-create'),
                onPressed: name.text.trim().isEmpty ? null : () => Navigator.pop(ctx, true),
                child: const Text('Create project'),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok != true) return;
    try {
      await api.createProject(name.text.trim(), desc.text.trim());
      toast('Project created');
      _load();
    } catch (e) {
      toastError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = projects;
    return Scaffold(
      appBar: const TopBar(title: 'Projects'),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-project'),
        heroTag: 'new-project',
        onPressed: _create,
        backgroundColor: TF.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: const StadiumBorder(),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New project', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 104), children: [
          PageBody(
            child: list == null
                ? (error != null ? ErrorView(message: error!, onRetry: _load) : const SkeletonList(height: 110))
                : list.isEmpty
                    ? const Surface(child: EmptyState(icon: Icons.folder_open_rounded, title: 'No projects yet', message: 'Group related tasks, files and notes.'))
                    : LayoutBuilder(builder: (context, c) {
                        final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 600 ? 2 : 1);
                        final w = (c.maxWidth - (cols - 1) * 12) / cols;
                        return Wrap(spacing: 12, runSpacing: 12, children: [
                          for (final p in list) SizedBox(width: w, child: _ProjectCard(project: p, onChanged: _load)),
                        ]);
                      }),
          ),
        ]),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onChanged});
  final Project project;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final hue = [TF.primary, TF.violet, TF.sky, TF.amber, TF.coral][project.id % 5];
    return Material(
      color: TF.surface,
      borderRadius: BorderRadius.circular(TF.radius),
      child: InkWell(
        key: ValueKey('project-${project.id}'),
        borderRadius: BorderRadius.circular(TF.radius),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(projectId: project.id)));
          onChanged();
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TF.radius),
            border: Border.all(color: TF.line),
            boxShadow: Brand.shadow,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: hue.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(Icons.folder_rounded, color: hue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: TF.ink)),
              ),
            ]),
            const SizedBox(height: 10),
            Text(project.description?.isNotEmpty == true ? project.description! : 'No description',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.4, color: TF.muted)),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              Pill('${project.memberCount} members', icon: Icons.people_outline_rounded),
              Pill('${project.openTasks} open', icon: Icons.task_alt_rounded, fg: TF.primaryDeep, bg: TF.primarySoft),
              if (project.ownerName != null) Pill(project.ownerName!, icon: Icons.person_outline_rounded),
            ]),
          ]),
        ),
      ),
    );
  }
}
