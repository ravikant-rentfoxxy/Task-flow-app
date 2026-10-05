import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
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
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TF.ink, height: 1.3)),
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
                            style: const TextStyle(fontSize: 12, color: TF.muted),
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
        Text('$label ', style: const TextStyle(fontSize: 11.5, color: TF.muted)),
        Text(value,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: danger ? TF.coral : TF.inkSoft)),
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
      Text('$done/$total', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: TF.green)),
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
                Text(label!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: TF.inkSoft)),
              ],
            ]),
          ),
        ),
      );
}

class _TaskMenu extends StatelessWidget {
  const _TaskMenu({required this.task, required this.onChanged, this.icon});
  final Task task;
  final VoidCallback onChanged;

  /// Overrides the default "more" icon (e.g. Tabler dots on the Tasks card).
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final me = Get.find<AuthController>().me;
    return PopupMenuButton<String>(
      key: ValueKey('task-menu-${task.id}'),
      icon: icon ?? const Icon(Icons.more_horiz_rounded, color: TF.muted, size: 20),
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
  const TaskList({super.key, required this.tasks, required this.onChanged, this.actionFor, this.roomy = false, this.cardBuilder});

  final List<Task> tasks;
  final VoidCallback onChanged;
  final Widget? Function(Task)? actionFor;

  /// Use the roomier [RoomyTaskCard] instead of the compact list card.
  final bool roomy;

  /// Overrides the card widget (e.g. [DashboardTaskCard]).
  final Widget Function(Task)? cardBuilder;

  Widget _card(Task t) =>
      cardBuilder?.call(t) ??
      (roomy
          ? RoomyTaskCard(task: t, onChanged: onChanged, action: actionFor?.call(t))
          : TaskCard(task: t, onChanged: onChanged, action: actionFor?.call(t)));

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 680 ? 2 : 1);
      if (cols == 1) {
        return Column(children: [
          for (final t in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
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


// Tasks-tab card palette (matches the Work Plus design).
const _tInk = Color(0xFF111A2E);
const _tMuted = Color(0xFF6B7691);
const _tLine = Color(0xFFE3E6EF);
const _tDivider = Color(0xFFECEEF3);
const _tChip = Color(0xFFEBEEF5);
const _tLime = Color(0xFFD7F83A);
const _tRed = Color(0xFFD03B3B);

/// Tasks-tab card: priority, type and alert pills with the status pill on the
/// right, the title, the due time, an optional blocked / discuss reason, then
/// a divider and the assignee "by" creator line with subtask progress,
/// comments, chat and the menu (Tabler icons).
class RoomyTaskCard extends StatelessWidget {
  const RoomyTaskCard({super.key, required this.task, required this.onChanged, this.action});

  final Task task;
  final VoidCallback onChanged;
  final Widget? action;

  static ({Color fg, Color bg, Color dot}) _priority(String p) => switch (p) {
    'URGENT' => (fg: const Color(0xFFA32C2C), bg: const Color(0xFFFDE8E7), dot: const Color(0xFFE34948)),
    'HIGH' => (fg: const Color(0xFF7A4A06), bg: const Color(0xFFFEF1D6), dot: const Color(0xFFF59E0B)),
    _ => (fg: const Color(0xFF4A5470), bg: _tChip, dot: const Color(0xFF8F9BB5)),
  };

  /// "Today, 6:00 PM", "Tomorrow, 9:30 AM" or "12 Aug, 7:23 PM".
  static String _when(DateTime d) {
    final now = DateTime.now();
    final diff = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    final day = switch (diff) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => fmtShortDate(d),
    };
    return '$day, ${fmtTime(d)}';
  }

  @override
  Widget build(BuildContext context) {
    final me = Get.find<AuthController>().me;
    final overdue = isTaskOverdue(task);
    final needsAction = taskNeedsActionForViewer(task, me);
    final slaRunning = task.status == 'ASSIGNED' && task.slaBreachedAt == null && task.slaDeadlineAt != null;
    final noResponse = task.slaBreachedAt != null && task.status == 'ASSIGNED';
    final chatTarget = chatTargetForTask(task, me?.id);
    final p = _priority(task.priority);

    final tags = <Widget>[
      _TPill(titleCase(task.priority), fg: p.fg, bg: p.bg, dot: p.dot),
      if (task.typeName != null) _TPill(task.typeName!, fg: const Color(0xFF4A5470), bg: _tChip),
      if (needsAction) const _TPill('Action needed', fg: Colors.white, bg: _tRed),
      if (task.isBlocked) const _TPill('Blocked', fg: Color(0xFF7A4A06), bg: Color(0xFFFEF1D6), icon: TablerIcons.ban),
      if (noResponse)
        const _TPill('No response', fg: Color(0xFFA32C2C), bg: Color(0xFFFDE8E7), icon: TablerIcons.clock_off)
      else if (slaRunning)
        _TPill(countdown(task.slaDeadlineAt), fg: const Color(0xFF7A4A06), bg: const Color(0xFFFEF1D6), icon: TablerIcons.hourglass),
    ];

    final discuss = (task.discussReason ?? '').trim();
    final blockedReason = (task.blockedReason ?? '').trim();
    final reason = task.isBlocked && blockedReason.isNotEmpty
        ? 'Blocked: $blockedReason'
        : (needsAction && discuss.isNotEmpty ? discuss : null);
    final due = task.dueAt;
    final assignee = task.memberCount > 0 ? '${task.who} +${task.memberCount}' : task.who;

    return Material(
      key: ValueKey('task-card-${task.id}'),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: needsAction ? _tRed.withValues(alpha: 0.35) : _tLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: task.id)));
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: tags)),
                  const SizedBox(width: 8),
                  _TStatus(status: task.status, onTap: () => _openStatusFor(context, task, onChanged)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _tInk, height: 1.3),
              ),
              if (due != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(TablerIcons.clock, size: 16, color: overdue ? _tRed : _tMuted),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        overdue ? 'Overdue · ${_when(due)}' : _when(due),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: overdue ? _tRed : _tMuted, fontWeight: overdue ? FontWeight.w600 : FontWeight.w400),
                      ),
                    ),
                  ],
                ),
              ],
              if (reason != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(task.isBlocked ? TablerIcons.ban : TablerIcons.alert_circle, size: 15, color: const Color(0xFF7A4A06)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        reason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xFF7A4A06)),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              const Divider(height: 1, thickness: 1, color: _tDivider),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: canReassignTask(task, me) ? () => _reassignFor(context, task, onChanged) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            _TAvatar(task.assigneeName ?? task.teamName),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(text: assignee, style: const TextStyle(fontWeight: FontWeight.w600, color: _tInk)),
                                    TextSpan(text: '  by ${displayName(task.creatorName)}'),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13.5, color: _tMuted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (task.subtaskCount > 0) _TSubtasks(done: task.subtaskDone, total: task.subtaskCount),
                  _TIconButton(
                    key: ValueKey('comments-${task.id}'),
                    icon: TablerIcons.message,
                    label: task.commentCount > 0 ? '${task.commentCount}' : null,
                    tooltip: 'Comments',
                    onTap: () => _commentsFor(context, task, onChanged),
                  ),
                  if (chatTarget != null)
                    _TIconButton(
                      icon: TablerIcons.messages,
                      tooltip: task.assigneeId == me?.id ? 'Chat with assigner' : 'Chat with assignee',
                      onTap: () => openChatWithUser(context, chatTarget, attachTask: task),
                    ),
                  _TaskMenu(
                    task: task,
                    onChanged: onChanged,
                    icon: const Icon(TablerIcons.dots, color: _tMuted, size: 20),
                  ),
                ],
              ),
              if (action != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 8),
                  child: SizedBox(width: double.infinity, child: action),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded pill with a leading dot or icon.
class _TPill extends StatelessWidget {
  const _TPill(this.label, {required this.fg, required this.bg, this.dot, this.icon});
  final String label;
  final Color fg;
  final Color bg;
  final Color? dot;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot != null) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
        ] else if (icon != null) ...[
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: fg),
          ),
        ),
      ],
    ),
  );
}

/// Status pill with a chevron that opens the status sheet; green with a check
/// when done, lime for active work, otherwise the status colours.
class _TStatus extends StatelessWidget {
  const _TStatus({required this.status, required this.onTap});
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = status == 'DONE';
    final active = status == 'IN_PROGRESS' || status == 'ACKNOWLEDGED';
    final danger = status == 'ESCALATED' || status == 'REJECTED';
    final c = TF.status(status);
    final fg = done ? const Color(0xFF14693A) : (active ? _tInk : (danger ? const Color(0xFFA32C2C) : c.fg));
    final bg = done ? const Color(0xFFE6F6EC) : (active ? _tLime : (danger ? const Color(0xFFFDE8E7) : c.bg));
    return Material(
      key: ValueKey('status-$status'),
      color: bg,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (done) ...[Icon(TablerIcons.check, size: 14, color: fg), const SizedBox(width: 5)],
              Text(statusLabel(status), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: fg)),
              const SizedBox(width: 4),
              Icon(TablerIcons.chevron_down, size: 14, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Navy circle with a lime initial.
class _TAvatar extends StatelessWidget {
  const _TAvatar(this.name);
  final String? name;

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: const BoxDecoration(color: _tInk, shape: BoxShape.circle),
    child: Text(
      initials(name).characters.take(1).toString(),
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _tLime),
    ),
  );
}

/// "1/1" with a short lime bar.
class _TSubtasks extends StatelessWidget {
  const _TSubtasks({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '$done of $total subtasks completed',
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: subtaskPercent(done, total) / 100,
                minHeight: 5,
                color: _tLime,
                backgroundColor: _tChip,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text('$done/$total', style: const TextStyle(fontSize: 13, color: _tInk)),
        ],
      ),
    ),
  );
}

/// Slate Tabler icon button with an optional count.
class _TIconButton extends StatelessWidget {
  const _TIconButton({super.key, required this.icon, required this.onTap, this.label, this.tooltip});
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
        padding: const EdgeInsets.all(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: _tMuted),
            if (label != null) ...[
              const SizedBox(width: 3),
              Text(label!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _tInk)),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Compact dashboard row (lime-on-navy): an urgency-coloured accent bar, status
/// and priority tags with the SLA countdown or ETA, a two-line title, and a meta
/// line (from/assignee, subtask progress, comments, chat, menu).
/// [actions] render as equal-width buttons along the bottom.
class DashboardTaskCard extends StatelessWidget {
  const DashboardTaskCard({super.key, required this.task, required this.onChanged, this.actions = const []});

  final Task task;
  final VoidCallback onChanged;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final me = Get.find<AuthController>().me;
    final overdue = isTaskOverdue(task);
    final needsAction = taskNeedsActionForViewer(task, me);
    final slaRunning = task.status == 'ASSIGNED' && task.slaBreachedAt == null && task.slaDeadlineAt != null;
    final noResponse = task.slaBreachedAt != null && task.status == 'ASSIGNED';
    final chatTarget = chatTargetForTask(task, me?.id);
    final mineToDo = task.assigneeId != null && task.assigneeId == me?.id;
    final hot = task.priority == 'URGENT' || overdue || noResponse || needsAction || task.status == 'ESCALATED';
    final accent = hot
        ? const Color(0xFFDC2626)
        : task.priority == 'HIGH' || slaRunning
        ? const Color(0xFFF59E0B)
        : task.status == 'IN_PROGRESS' || task.status == 'ACKNOWLEDGED'
        ? Brand.lime
        : Brand.outline;

    final tags = <Widget>[
      _DashStatus(status: task.status, onTap: () => _openStatusFor(context, task, onChanged)),
      if (task.priority == 'URGENT')
        const DashTag('URGENT', fg: Color(0xFF991B1B), bg: Color(0xFFFEE2E2), bold: true)
      else if (task.priority == 'HIGH')
        const DashTag('HIGH', fg: Color(0xFF78350F), bg: Color(0xFFFEF3C7), bold: true),
      if (needsAction) const DashTag('Action needed', fg: Colors.white, bg: Color(0xFFDC2626), bold: true),
      if (overdue && task.status != 'ESCALATED') const DashTag('Overdue', fg: Color(0xFF991B1B), bg: Color(0xFFFEE2E2), bold: true),
      if (task.isBlocked) const DashTag('Blocked', fg: Color(0xFF78350F), bg: Color(0xFFFEF3C7), bold: true),
    ];

    Widget? trailing;
    if (noResponse) {
      trailing = const DashTimer('No response', fg: Color(0xFF991B1B), bg: Color(0xFFFEE2E2), border: Color(0x33DC2626));
    } else if (slaRunning) {
      trailing = DashTimer(
        countdown(task.slaDeadlineAt),
        fg: const Color(0xFF92400E),
        bg: const Color(0xFFFFFBEB),
        border: const Color(0x99FDE68A),
        dot: const Color(0xFFF59E0B),
      );
    } else if (task.etaAt != null && !closedStatuses.contains(task.status)) {
      trailing = Text(
        'ETA ${_etaLabel(task.etaAt!)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Brand.onVariant),
      );
    }

    return Container(
      key: ValueKey('task-card-${task.id}'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: needsAction ? const Color(0x55DC2626) : Brand.outline),
        boxShadow: [BoxShadow(color: Brand.navy.withValues(alpha: 0.03), blurRadius: 3, offset: const Offset(0, 1))],
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
                padding: const EdgeInsets.fromLTRB(16, 10, 4, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Wrap(spacing: 5, runSpacing: 5, crossAxisAlignment: WrapCrossAlignment.center, children: tags),
                          ),
                          if (trailing != null) ...[
                            const SizedBox(width: 8),
                            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 130), child: trailing),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Brand.navy, height: 1.3, letterSpacing: -0.1),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: canReassignTask(task, me) ? () => _reassignFor(context, task, onChanged) : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(text: mineToDo ? 'From ' : 'To '),
                                    TextSpan(
                                      text: mineToDo ? displayName(task.creatorName) : task.who,
                                      style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.navy),
                                    ),
                                    if (task.memberCount > 0) TextSpan(text: ' +${task.memberCount}'),
                                    if (task.projectName != null) TextSpan(text: '  •  ${task.projectName}'),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, color: Brand.onVariant),
                              ),
                            ),
                          ),
                        ),
                        if (task.subtaskCount > 0) _MiniSubtasks(done: task.subtaskDone, total: task.subtaskCount),
                        _IconAction(
                          key: ValueKey('comments-${task.id}'),
                          icon: Icons.chat_bubble_outline_rounded,
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
                        _TaskMenu(task: task, onChanged: onChanged),
                      ],
                    ),
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(right: 12, bottom: 6),
                        child: Row(
                          children: [
                            for (var i = 0; i < actions.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Expanded(child: actions[i]),
                            ],
                          ],
                        ),
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

  /// Time only when the ETA is today, otherwise the short date.
  static String _etaLabel(DateTime eta) {
    final now = DateTime.now();
    final today = eta.year == now.year && eta.month == now.month && eta.day == now.day;
    return today ? fmtTime(eta) : fmtShortDate(eta);
  }
}

/// "3/4" with a tiny lime bar, for compact rows.
class _MiniSubtasks extends StatelessWidget {
  const _MiniSubtasks({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 28,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: subtaskPercent(done, total) / 100,
              minHeight: 5,
              color: Brand.lime,
              backgroundColor: Brand.navy.withValues(alpha: 0.1),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text('$done/$total', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Brand.navy)),
      ],
    ),
  );
}

/// Status chip that opens the status sheet; lime for active work.
class _DashStatus extends StatelessWidget {
  const _DashStatus({required this.status, required this.onTap});
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = status == 'IN_PROGRESS' || status == 'ACKNOWLEDGED';
    final c = TF.status(status);
    final fg = active ? Brand.navy : c.fg;
    final bg = active ? Brand.limeLight : c.bg;
    return Material(
      key: ValueKey('status-$status'),
      color: bg,
      shape: StadiumBorder(side: BorderSide(color: active ? Brand.limeDim.withValues(alpha: 0.5) : Colors.transparent)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 3, 4, 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  statusLabel(status),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
                ),
              ),
              Icon(Icons.arrow_drop_down_rounded, size: 18, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small rounded tag used on dashboard cards.
class DashTag extends StatelessWidget {
  const DashTag(this.label, {super.key, required this.fg, required this.bg, this.bold = false, this.outlined = false});
  final String label;
  final Color fg;
  final Color bg;
  final bool bold;
  final bool outlined;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      border: outlined ? Border.all(color: Brand.outline.withValues(alpha: 0.7)) : null,
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 10.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: fg, letterSpacing: 0.2),
    ),
  );
}

/// Pill showing time left, with an optional pulsing-style dot.
class DashTimer extends StatelessWidget {
  const DashTimer(this.label, {super.key, required this.fg, required this.bg, required this.border, this.dot});
  final String label;
  final Color fg;
  final Color bg;
  final Color border;
  final Color? dot;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot != null) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
          ),
        ),
      ],
    ),
  );
}

// ── Home (dashboard) card ─────────────────────────────────────────────────

const _hInk = Color(0xFF111A2E);
const _hMuted = Color(0xFF6B7691);
const _hLine = Color(0xFFE3E6EF);
const _hChip = Color(0xFFEBEEF5);
const _hLime = Color(0xFFD7F83A);

/// Home-screen task card: priority pill · status pill, the title, then the
/// person, subtask meter, comments, chat and menu. [actions] render as
/// equal-width buttons along the bottom.
class HomeTaskCard extends StatelessWidget {
  const HomeTaskCard({super.key, required this.task, required this.onChanged, this.actions = const []});

  final Task task;
  final VoidCallback onChanged;
  final List<Widget> actions;

  static ({Color fg, Color bg, Color dot}) _priority(String p) => switch (p) {
    'URGENT' => (fg: const Color(0xFF8A1612), bg: const Color(0xFFFDE8E7), dot: const Color(0xFFE5322D)),
    'HIGH' => (fg: const Color(0xFF7A4A06), bg: const Color(0xFFFEF1D6), dot: const Color(0xFFF59E0B)),
    _ => (fg: const Color(0xFF4A5470), bg: _hChip, dot: const Color(0xFF8F9BB5)),
  };

  @override
  Widget build(BuildContext context) {
    final me = Get.find<AuthController>().me;
    final overdue = isTaskOverdue(task);
    final needsAction = taskNeedsActionForViewer(task, me);
    final slaRunning = task.status == 'ASSIGNED' && task.slaBreachedAt == null && task.slaDeadlineAt != null;
    final noResponse = task.slaBreachedAt != null && task.status == 'ASSIGNED';
    final chatTarget = chatTargetForTask(task, me?.id);
    final mineToDo = task.assigneeId != null && task.assigneeId == me?.id;
    final person = mineToDo ? displayName(task.creatorName) : task.who;
    final p = _priority(task.priority);
    final eta = task.etaAt != null && !closedStatuses.contains(task.status) ? task.etaAt : null;

    final tags = <Widget>[
      _HomePill(titleCase(task.priority), fg: p.fg, bg: p.bg, dot: p.dot),
      if (needsAction) const _HomePill('Action needed', fg: Colors.white, bg: Color(0xFFE5322D)),
      if (overdue && task.status != 'ESCALATED') const _HomePill('Overdue', fg: Color(0xFF8A1612), bg: Color(0xFFFDE8E7)),
      if (task.isBlocked) const _HomePill('Blocked', fg: Color(0xFF7A4A06), bg: Color(0xFFFEF1D6), icon: Icons.block_rounded),
      if (noResponse)
        const _HomePill('No response', fg: Color(0xFF8A1612), bg: Color(0xFFFDE8E7), icon: Icons.timer_off_outlined)
      else if (slaRunning)
        _HomePill(countdown(task.slaDeadlineAt), fg: const Color(0xFF7A4A06), bg: const Color(0xFFFEF1D6), icon: Icons.timer_outlined),
    ];

    return Material(
      key: ValueKey('task-card-${task.id}'),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: needsAction ? const Color(0x55E5322D) : _hLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: task.id)));
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: tags)),
                    const SizedBox(width: 8),
                    _HomeStatus(status: task.status, onTap: () => _openStatusFor(context, task, onChanged)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _hInk, height: 1.3),
                ),
              ),
              if (eta != null || task.projectName != null) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    [
                      if (task.projectName != null) task.projectName!,
                      if (eta != null) 'ETA ${DashboardTaskCard._etaLabel(eta)}',
                    ].join('  •  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _hMuted),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: canReassignTask(task, me) ? () => _reassignFor(context, task, onChanged) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Avatar(mineToDo ? task.creatorName : (task.assigneeName ?? task.teamName), size: 22),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                task.memberCount > 0 ? '$person +${task.memberCount}' : person,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: _hMuted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (task.subtaskCount > 0) _HomeSubtasks(done: task.subtaskDone, total: task.subtaskCount),
                  _IconAction(
                    key: ValueKey('comments-${task.id}'),
                    icon: Icons.chat_bubble_outline_rounded,
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
                  _TaskMenu(task: task, onChanged: onChanged),
                ],
              ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 2, 8, 8),
                  child: Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: actions[i])],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded pill with a leading dot or icon.
class _HomePill extends StatelessWidget {
  const _HomePill(this.label, {required this.fg, required this.bg, this.dot, this.icon});
  final String label;
  final Color fg;
  final Color bg;
  final Color? dot;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot != null) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
        ] else if (icon != null) ...[
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
          ),
        ),
      ],
    ),
  );
}

/// Status pill that opens the status sheet: green with a check when done,
/// lime for active work, otherwise the status colours.
class _HomeStatus extends StatelessWidget {
  const _HomeStatus({required this.status, required this.onTap});
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = status == 'DONE';
    final active = status == 'IN_PROGRESS' || status == 'ACKNOWLEDGED';
    final c = TF.status(status);
    final fg = done ? const Color(0xFF14693A) : (active ? _hInk : c.fg);
    final bg = done ? const Color(0xFFE6F6EC) : (active ? _hLime : c.bg);
    return Material(
      key: ValueKey('status-$status'),
      color: bg,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (done) ...[Icon(Icons.check_rounded, size: 12, color: fg), const SizedBox(width: 4)],
              Text(
                statusLabel(status),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "1/1" with a short lime bar.
class _HomeSubtasks extends StatelessWidget {
  const _HomeSubtasks({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 26,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: subtaskPercent(done, total) / 100, minHeight: 5, color: _hLime, backgroundColor: _hChip),
          ),
        ),
        const SizedBox(width: 6),
        Text('$done/$total', style: const TextStyle(fontSize: 12, color: _hInk)),
      ],
    ),
  );
}
