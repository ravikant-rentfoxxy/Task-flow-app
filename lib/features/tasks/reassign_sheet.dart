import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_ui.dart';
import '../../widgets/common.dart';

Future<bool?> showReassignSheet(BuildContext context, Task task) =>
    showAppSheet<bool>(context, expand: true, builder: (_) => ReassignSheet(task: task));

class ReassignSheet extends StatefulWidget {
  const ReassignSheet({super.key, required this.task});
  final Task task;

  @override
  State<ReassignSheet> createState() => _ReassignSheetState();
}

class _ReassignSheetState extends State<ReassignSheet> {
  List<AppUser>? users;
  String query = '';
  int? busyId;

  @override
  void initState() {
    super.initState();
    Get.find<TaskFlowApi>().users().then((u) {
      if (!mounted) return;
      setState(() => users = u.where((x) => x.isActive).toList()..sort((a, b) => a.name.compareTo(b.name)));
    }).catchError((Object e) {
      toastError(e);
    });
  }

  Future<void> _pick(AppUser u) async {
    setState(() => busyId = u.id);
    try {
      await Get.find<TaskFlowApi>().taskAction(widget.task.id, 'reassign', {'assigneeId': u.id});
      toast('Assignee updated');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      toastError(e);
      if (mounted) setState(() => busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final list = (users ?? [])
        .where((u) => q.isEmpty || u.name.toLowerCase().contains(q) || (u.email?.toLowerCase().contains(q) ?? false))
        .toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const BrandSectionTitle(title: 'Change assignee', padding: EdgeInsets.only(bottom: 6)),
          const Text('The task goes back to "Accept response" for the new person.',
              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Brand.onVariant)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: Brand.navy, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Expanded(
                child: Text(widget.task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text('Now: ${widget.task.who}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Brand.lime)),
              ),
            ]),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextField(
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(hintText: 'Search by name or email…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
          onChanged: (v) => setState(() => query = v),
        ),
      ),
      if (users != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: BrandSectionTitle(title: 'People', count: list.length, padding: EdgeInsets.zero),
        ),
      Expanded(
        child: users == null
            ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(height: 56))
            : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
                for (final u in list) _row(u),
                if (list.isEmpty) const EmptyState(icon: Icons.person_search_rounded, title: 'No users found'),
              ]),
      ),
    ]);
  }

  Widget _row(AppUser u) {
    final current = u.id == widget.task.assigneeId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: current ? Brand.limeLight : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: current ? Brand.limeDim : Brand.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: ValueKey('reassign-${u.id}'),
          enabled: busyId == null && !current,
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: Avatar(u.name, size: 34),
          title: Text(u.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Brand.navy)),
          subtitle: Text([u.email ?? '', if (u.teamName != null) u.teamName!].where((s) => s.isNotEmpty).join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Brand.onVariant)),
          trailing: current
              ? const LimeTag('Current')
              : busyId == u.id
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Brand.navy))
                  : const Icon(Icons.chevron_right_rounded, color: Brand.onVariant),
          onTap: () => _pick(u),
        ),
      ),
    );
  }
}
