import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
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
      SheetTitle('Change assignee', subtitle: 'The task goes back to "Accept response" for the new person.'),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextField(
          decoration: const InputDecoration(hintText: 'Search by name or email…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
          onChanged: (v) => setState(() => query = v),
        ),
      ),
      Expanded(
        child: users == null
            ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(height: 56))
            : ListView(children: [
                for (final u in list)
                  ListTile(
                    key: ValueKey('reassign-${u.id}'),
                    enabled: busyId == null && u.id != widget.task.assigneeId,
                    leading: Avatar(u.name, size: 36),
                    title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(u.email ?? '', style: const TextStyle(fontSize: 12.5)),
                    trailing: u.id == widget.task.assigneeId
                        ? const Pill('Current', fg: TF.primaryDeep, bg: TF.primarySoft)
                        : busyId == u.id
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : null,
                    onTap: () => _pick(u),
                  ),
                if (list.isEmpty) const EmptyState(icon: Icons.person_search_rounded, title: 'No users found'),
              ]),
      ),
    ]);
  }
}
