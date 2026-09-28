import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/format.dart';
import '../../core/task_logic.dart';
import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../chat/chat_screen.dart';
import 'comments_panel.dart';
import 'composer_sheet.dart';
import 'reassign_sheet.dart';
import 'status_sheet.dart';
import 'task_detail_screen.dart';

void openTask(BuildContext context, int id) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: id)));
}

class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.onChanged,
    this.action,
  });

  final Task task;
  final VoidCallback onChanged;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final me = Get.find<AuthController>().me;
    final overdue = isTaskOverdue(task);
    final needsAction = taskNeedsActionForViewer(task, me);
    final slaRunning = task.status == 'ASSIGNED' && task.slaBreachedAt == null && task.slaDeadlineAt != null;
    final accent = overdue && task.status != 'ESCALATED' ? TF.coral : TF.status(task.status).fg;
    final chatTarget = chatTargetForTask(task, me?.id);

    return Container(
      key: ValueKey('task-card-${task.id}'),
      decoration: BoxDecoration(
        color: TF.surface,
        borderRadius: BorderRadius.circular(TF.radius),
        border: Border.all(color: needsAction ? TF.coral.withValues(alpha: 0.55) : TF.line, width: needsAction ? 1.4 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: task.id)));
            onChanged();
          },
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      StatusPill(task.status, onTap: () => _openStatus(context)),
                      if (needsAction) const Pill('Action needed', fg: Colors.white, bg: TF.coral, icon: Icons.priority_high_rounded),
                      if (task.slaBreachedAt != null && task.status == 'ASSIGNED')
                        const Pill('No response', fg: TF.coral, bg: TF.coralSoft, icon: Icons.notifications_off_outlined),
                      if (slaRunning)
                        Pill(countdown(task.slaDeadlineAt), fg: TF.amber, bg: TF.amberSoft, icon: Icons.timer_outlined),
                      if (task.isBlocked) const Pill('Blocked', fg: TF.violet, bg: TF.violetSoft, icon: Icons.block_rounded),
                      if (task.typeName != null) Pill(task.typeName!, icon: Icons.sell_outlined, fg: TF.muted, bg: TF.sunken),
                      if (task.priority == 'URGENT' || task.priority == 'HIGH')
                        Pill(titleCase(task.priority), fg: TF.priority(task.priority), bg: TF.priority(task.priority).withValues(alpha: 0.1), icon: Icons.flag_rounded),
                    ]),
                    const SizedBox(height: 8),
                    Text(task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: TF.ink, height: 1.3)),
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: canReassignTask(task, me) ? () => _reassign(context) : null,
                      child: Row(children: [
                        Avatar(task.assigneeName ?? task.teamName, size: 22),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: task.who, style: const TextStyle(color: TF.inkSoft, fontWeight: FontWeight.w600)),
                              if (task.memberCount > 0) TextSpan(text: ' +${task.memberCount}'),
                              TextSpan(text: '  ·  by ${displayName(task.creatorName)}'),
                              if (task.projectName != null)
                                TextSpan(text: '  ·  ${task.projectName}', style: const TextStyle(color: TF.primary, fontWeight: FontWeight.w600)),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, color: TF.muted),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      _Meta(icon: Icons.event_outlined, label: 'Due', value: fmtShortDate(task.dueAt), danger: overdue),
                      const SizedBox(width: 14),
                      _Meta(icon: Icons.schedule_rounded, label: 'ETA', value: fmtShortDate(task.etaAt)),
                      if (task.subtaskCount > 0) ...[
                        const SizedBox(width: 14),
                        _SubtaskMeter(done: task.subtaskDone, total: task.subtaskCount),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      _IconAction(
                        key: ValueKey('comments-${task.id}'),
                        icon: Icons.mode_comment_outlined,
                        label: task.commentCount > 0 ? '${task.commentCount}' : null,
                        tooltip: 'Comments',
                        onTap: () => _comments(context),
                      ),
                      if (chatTarget != null)
                        _IconAction(
                          icon: Icons.forum_outlined,
                          tooltip: task.assigneeId == me?.id ? 'Chat with assigner' : 'Chat with assignee',
                          onTap: () => openChatWithUser(context, chatTarget, attachTask: task),
                        ),
                      const Spacer(),
                      ?action,
                      _TaskMenu(task: task, onChanged: onChanged),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _openStatus(BuildContext context) => _openStatusFor(context, task, onChanged);
  Future<void> _reassign(BuildContext context) => _reassignFor(context, task, onChanged);
  Future<void> _comments(BuildContext context) => _commentsFor(context, task, onChanged);
}

Future<void> _openStatusFor(BuildContext context, Task task, VoidCallback onChanged) async {
  final changed = await showStatusSheet(context, task);
  if (changed == true) onChanged();
}

Future<void> _reassignFor(BuildContext context, Task task, VoidCallback onChanged) async {
  final changed = await showReassignSheet(context, task);
  if (changed == true) onChanged();
}

Future<void> _commentsFor(BuildContext context, Task task, VoidCallback onChanged) async {
  await showAppSheet(
    context,
    expand: true,
    builder: (ctx) => Column(
      children: [
        SheetTitle('Comments', subtitle: task.title),
        const Divider(),
        Expanded(
          child: CommentsPanel(taskId: task.id, onChanged: onChanged),
        ),
      ],
    ),
  );
  onChanged();
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label, required this.value, this.danger = false});
  final IconData icon;
  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: danger ? TF.coral : TF.faint),
        const SizedBox(width: 4),
        Text('$label ', style: const TextStyle(fontSize: 12, color: TF.muted)),
        Text(value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: danger ? TF.coral : TF.inkSoft)),
      ]);
}

class _SubtaskMeter extends StatelessWidget {
  const _SubtaskMeter({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final pct = subtaskPercent(done, total);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 36,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(value: pct / 100, minHeight: 5, backgroundColor: TF.sunken, color: TF.green),
        ),
      ),
      const SizedBox(width: 6),
      Text('$done/$total', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: TF.green)),
    ]);
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({super.key, required this.icon, required this.onTap, this.label, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip ?? '',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18, color: TF.muted),
              if (label != null) ...[
                const SizedBox(width: 4),
                Text(label!, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: TF.inkSoft)),
              ],
            ]),
          ),
        ),
      );
}

class _TaskMenu extends StatelessWidget {
  const _TaskMenu({required this.task, required this.onChanged});
  final Task task;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final me = Get.find<AuthController>().me;
    return PopupMenuButton<String>(
      key: ValueKey('task-menu-${task.id}'),
      icon: const Icon(Icons.more_horiz_rounded, color: TF.muted, size: 20),
      tooltip: 'Actions',
      onSelected: (v) async {
        if (v == 'subtask') {
          final ids = await showComposer(context, presetParentId: task.id);
          if (ids != null) onChanged();
        } else if (v == 'delete') {
          final ok = await confirmDialog(context,
              title: 'Delete task?',
              message: 'Delete "${task.title}"? This hides the task and its subtasks from the app.',
              confirmLabel: 'Delete',
              destructive: true);
          if (!ok || !context.mounted) return;
          try {
            await Get.find<TaskFlowApi>().deleteTask(task.id);
            toast('Task deleted');
            onChanged();
          } catch (e) {
            toastError(e, 'Delete failed');
          }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'subtask',
          enabled: canCreateSubtask(task),
          child: const ListTile(dense: true, leading: Icon(Icons.add_task_rounded), title: Text('Create subtask')),
        ),
        if (canDeleteTask(me))
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.delete_outline_rounded, color: TF.coral),
              title: Text('Delete task', style: TextStyle(color: TF.coral)),
            ),
          ),
      ],
    );
  }
}

/// Vertical list of task cards.
class TaskList extends StatelessWidget {
  const TaskList({super.key, required this.tasks, required this.onChanged, this.actionFor, this.roomy = false});

  final List<Task> tasks;
  final VoidCallback onChanged;
  final Widget? Function(Task)? actionFor;

  /// Use the roomier [RoomyTaskCard] instead of the compact list card.
  final bool roomy;

  Widget _card(Task t) => roomy
      ? RoomyTaskCard(task: t, onChanged: onChanged, action: actionFor?.call(t))
      : TaskCard(task: t, onChanged: onChanged, action: actionFor?.call(t));

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 680 ? 2 : 1);
      if (cols == 1) {
        return Column(children: [
          for (final t in tasks)
            Padding(
              padding: EdgeInsets.only(bottom: roomy ? 14 : 10),
              child: _card(t),
            ),
        ]);
      }
      final width = (c.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        for (final t in tasks)
          SizedBox(width: width, child: _card(t)),
      ]);
    });
  }
}

/// Roomy card (dashboard, Tasks tab): same data and actions as [TaskCard], as a
/// white card with a status-coloured edge, a status button and the primary
/// action full width at the bottom.
class RoomyTaskCard extends StatelessWidget {
  const RoomyTaskCard({super.key, required this.task, required this.onChanged, this.action});

  final Task task;
  final VoidCallback onChanged;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final me = Get.find<AuthController>().me;
    final overdue = isTaskOverdue(task);
    final needsAction = taskNeedsActionForViewer(task, me);
    final slaRunning = task.status == 'ASSIGNED' && task.slaBreachedAt == null && task.slaDeadlineAt != null;
    final noResponse = task.slaBreachedAt != null && task.status == 'ASSIGNED';
    final chatTarget = chatTargetForTask(task, me?.id);
    final hotPriority = task.priority == 'URGENT' || task.priority == 'HIGH';
    final accent = overdue && task.status != 'ESCALATED' ? Brand.red : TF.status(task.status).fg;
    final tags = <Widget>[
      if (hotPriority)
        _Tag(
          titleCase(task.priority),
          fg: task.priority == 'URGENT' ? Brand.red : Brand.amber,
          bg: task.priority == 'URGENT' ? Brand.redSoft : Brand.amberSoft,
          icon: task.priority == 'URGENT' ? Icons.error_outline_rounded : null,
          bold: true,
        ),
      if (task.typeName != null) _Tag(task.typeName!, fg: Brand.inkSoft, bg: Brand.slateSoft),
      if (task.isBlocked) const _Tag('Blocked', fg: Brand.amber, bg: Brand.amberSoft, icon: Icons.block_rounded, bold: true),
      if (needsAction) const _Tag('Action needed', fg: Colors.white, bg: Brand.red, icon: Icons.priority_high_rounded, bold: true),
    ];

    return Container(
      key: ValueKey('task-card-${task.id}'),
      decoration: BoxDecoration(
        color: Brand.card,
        borderRadius: BorderRadius.circular(Brand.radius),
        border: Border.all(color: needsAction ? Brand.red.withValues(alpha: 0.45) : Brand.line, width: needsAction ? 1.3 : 1),
        boxShadow: Brand.shadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: task.id)));
            onChanged();
          },
          child: Stack(
            children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tags.isNotEmpty || slaRunning || noResponse) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: tags),
                      ),
                      if (slaRunning || noResponse) ...[
                        const SizedBox(width: 8),
                        noResponse
                            ? const _Tag('No response', fg: Brand.red, bg: Brand.redSoft, icon: Icons.notifications_off_outlined, bold: true)
                            : _Tag(countdown(task.slaDeadlineAt), fg: Brand.amber, bg: Brand.amberSoft, dot: true, bold: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Brand.ink, height: 1.3, letterSpacing: -0.2),
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: canReassignTask(task, me) ? () => _reassignFor(context, task, onChanged) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Avatar(task.assigneeName ?? task.teamName, size: 24),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: task.who,
                                  style: const TextStyle(color: Brand.ink, fontWeight: FontWeight.w600),
                                ),
                                if (task.memberCount > 0) TextSpan(text: ' +${task.memberCount}'),
                                TextSpan(text: '  •  by ${displayName(task.creatorName)}'),
                                if (task.projectName != null)
                                  TextSpan(
                                    text: '  •  ${task.projectName}',
                                    style: const TextStyle(color: Brand.primary, fontWeight: FontWeight.w600),
                                  ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5, color: Brand.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: Brand.field, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Expanded(
                        child: _DashMeta(icon: Icons.event_outlined, label: 'Due', value: fmtShortDate(task.dueAt), danger: overdue),
                      ),
                      Container(width: 1, height: 22, color: Brand.line),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DashMeta(icon: Icons.schedule_rounded, label: 'ETA', value: fmtShortDate(task.etaAt)),
                      ),
                    ],
                  ),
                ),
                if (task.subtaskCount > 0) ...[const SizedBox(height: 12), _DashSubtasks(done: task.subtaskDone, total: task.subtaskCount)],
                const SizedBox(height: 6),
                Row(
                  children: [
                    _IconAction(
                      key: ValueKey('comments-${task.id}'),
                      icon: Icons.mode_comment_outlined,
                      label: task.commentCount > 0 ? '${task.commentCount}' : null,
                      tooltip: 'Comments',
                      onTap: () => _commentsFor(context, task, onChanged),
                    ),
                    if (chatTarget != null)
                      _IconAction(
                        icon: Icons.forum_outlined,
                        tooltip: task.assigneeId == me?.id ? 'Chat with assigner' : 'Chat with assignee',
                        onTap: () => openChatWithUser(context, chatTarget, attachTask: task),
                      ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _StatusButton(status: task.status, onTap: () => _openStatusFor(context, task, onChanged)),
                      ),
                    ),
                    _TaskMenu(task: task, onChanged: onChanged),
                  ],
                ),
                if (action != null) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: SizedBox(width: double.infinity, child: action),
                  ),
                ],
              ],
            ),
          ),
              Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 4, color: accent)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Status chip that opens the status sheet, tinted with the status colours.
class _StatusButton extends StatelessWidget {
  const _StatusButton({required this.status, required this.onTap});
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = TF.status(status);
    return Material(
      key: ValueKey('status-$status'),
      color: c.bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  statusLabel(status),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.fg),
                ),
              ),
              Icon(Icons.arrow_drop_down_rounded, size: 22, color: c.fg),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {required this.fg, required this.bg, this.icon, this.dot = false, this.bold = false});
  final String label;
  final Color fg;
  final Color bg;
  final IconData? icon;
  final bool dot;
  final bool bold;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
        ],
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg, fontSize: 12, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, letterSpacing: 0.2),
          ),
        ),
      ],
    ),
  );
}

class _DashMeta extends StatelessWidget {
  const _DashMeta({required this.icon, required this.label, required this.value, this.danger = false});
  final IconData icon;
  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 17, color: danger ? Brand.red : Brand.muted),
      const SizedBox(width: 6),
      Flexible(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$label '),
              TextSpan(
                text: value,
                style: TextStyle(fontWeight: FontWeight.w700, color: danger ? Brand.red : Brand.ink),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: Brand.muted),
        ),
      ),
    ],
  );
}

class _DashSubtasks extends StatelessWidget {
  const _DashSubtasks({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final pct = subtaskPercent(done, total);
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(color: Brand.field, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist_rounded, size: 17, color: Brand.inkSoft),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Subtasks', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Brand.inkSoft)),
              ),
              Text('$done/$total', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Brand.primary)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: pct / 100, minHeight: 6, backgroundColor: Brand.slateSoft, color: Brand.primary),
          ),
        ],
      ),
    );
  }
}
