import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_ui.dart';
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
    final meId = Get.find<AuthController>().me?.id;
    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: const TopBar(title: 'Projects'),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-project'),
        heroTag: 'new-project',
        onPressed: _create,
        backgroundColor: Brand.lime,
        foregroundColor: Brand.navy,
        elevation: 2,
        shape: const StadiumBorder(side: BorderSide(color: Brand.navy, width: 2)),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New project', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        color: Brand.navy,
        backgroundColor: Brand.lime,
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 104), children: [
          PageBody(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _ProjectsHero(projects: list, meId: meId),
              const SizedBox(height: 22),
              if (list == null)
                (error != null ? ErrorView(message: error!, onRetry: _load) : const SkeletonList(height: 84))
              else if (list.isEmpty)
                Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.outline)),
                  child: const EmptyState(
                    icon: Icons.folder_open_rounded,
                    color: Brand.navy,
                    title: 'No projects yet',
                    message: 'Group related tasks, files and notes.',
                  ),
                )
              else ...[
                BrandSectionTitle(title: 'All projects', count: list.length),
                LayoutBuilder(builder: (context, c) {
                  final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 600 ? 2 : 1);
                  final w = (c.maxWidth - (cols - 1) * 10) / cols;
                  return Wrap(spacing: 10, runSpacing: 10, children: [
                    for (final p in list) SizedBox(width: w, child: _ProjectCard(project: p, onChanged: _load)),
                  ]);
                }),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Navy summary: project count, open tasks across projects, and projects you own.
class _ProjectsHero extends StatelessWidget {
  const _ProjectsHero({required this.projects, required this.meId});
  final List<Project>? projects;
  final int? meId;

  @override
  Widget build(BuildContext context) {
    final list = projects;
    final open = list?.fold<int>(0, (a, p) => a + p.openTasks);
    final owned = list?.where((p) => meId != null && p.ownerId == meId).length;
    return HeroCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const HeroEyebrow('Workspace'),
        const SizedBox(height: 8),
        HeroTitle(
          list == null
              ? 'Loading projects…'
              : list.isEmpty
                  ? 'Start your first project'
                  : '${list.length} ${list.length == 1 ? 'project' : 'projects'} in motion',
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _HeroStat(value: list == null ? '—' : '${list.length}', label: 'Projects')),
          const SizedBox(width: 8),
          Expanded(child: _HeroStat(value: open == null ? '—' : '$open', label: 'Open tasks', accent: true)),
          const SizedBox(width: 8),
          Expanded(child: _HeroStat(value: owned == null ? '—' : '$owned', label: 'Owned by you')),
        ]),
      ]),
    );
  }
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

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onChanged});
  final Project project;
  final VoidCallback onChanged;

  static const _tiles = <(Color, Color)>[
    (Brand.navy, Brand.lime),
    (Brand.lime, Brand.navy),
    (Brand.skySoft, Brand.sky),
    (Brand.amberSoft, Brand.amber),
    (Brand.surfaceMid, Brand.navy),
  ];

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _tiles[project.id % _tiles.length];
    final name = project.name.trim();
    final initial = name.isEmpty ? '#' : name.characters.first.toUpperCase();
    final desc = project.description?.trim() ?? '';
    final meta = [
      '${project.memberCount} ${project.memberCount == 1 ? 'member' : 'members'}',
      if (project.ownerName != null) project.ownerName!,
    ].join(' · ');
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Brand.outline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('project-${project.id}'),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(projectId: project.id)));
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
              child: Text(initial, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: fg)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: Brand.navy)),
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: project.openTasks > 0 ? LimeTag('${project.openTasks} open') : const _MutedTag('No open tasks')),
                ]),
                const SizedBox(height: 3),
                Text(desc.isNotEmpty ? desc : 'No description',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, height: 1.35, color: desc.isNotEmpty ? Brand.onVariant : TF.faint)),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.people_outline_rounded, size: 14, color: Brand.onVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(meta,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Brand.onVariant)),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MutedTag extends StatelessWidget {
  const _MutedTag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: Brand.surfaceLow, borderRadius: BorderRadius.circular(99), border: Border.all(color: Brand.outline)),
        child: Text(text,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Brand.onVariant)),
      );
}
