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

const _red = Color(0xFFDC2626);
const _redSoft = Color(0xFFFEE2E2);
const _amberInk = Color(0xFF92400E);
const _amberSoft = Color(0xFFFFFBEB);
const _amberLine = Color(0x99FDE68A);
const _edgeGrey = Color(0xFFCBD5E1);

/// Compact list row (Tasks tab, project detail), lime-on-navy: an
/// urgency-coloured left edge, a tappable status tag with priority / alert
/// tags and the SLA timer or due date, a two-line title, an optional
/// blocked / discuss reason, and one meta line (assignee, team, project, ETA,
/// subtask progress, comments, chat and the menu).
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
    final active = task.status == 'IN_PROGRESS' || task.status == 'ACKNOWLEDGED';
    final hot = task.priority == 'URGENT' || task.isBlocked || overdue || noResponse || needsAction || task.status == 'ESCALATED';
    final edge = hot
        ? _red
        : task.priority == 'HIGH' || slaRunning
        ? const Color(0xFFF59E0B)
        : active
        ? Brand.lime
        : _edgeGrey;
    final team = task.assigneeName != null ? task.teamName : null;
    final eta = task.etaAt != null && !closedStatuses.contains(task.status) ? task.etaAt : null;

    final tags = <Widget>[
      _StatusButton(
        status: task.status,
        danger: task.isBlocked || task.status == 'ESCALATED' || task.status == 'REJECTED',
        onTap: () => _openStatusFor(context, task, onChanged),
      ),
      if (task.priority == 'URGENT')
        const _Chip('URGENT', fg: Color(0xFF991B1B), bg: _redSoft, bold: true)
      else if (task.priority == 'HIGH')
        const _Chip('HIGH', fg: Color(0xFF78350F), bg: Color(0xFFFEF3C7), bold: true)
      else
        _Chip(titleCase(task.priority), fg: Brand.onVariant, bg: Colors.white, border: Brand.outline),
      if (needsAction) const _Chip('Action needed', fg: Colors.white, bg: _red, bold: true),
      if (task.isBlocked) const _Chip('Blocked', fg: Color(0xFF78350F), bg: Color(0xFFFEF3C7), icon: Icons.block_rounded, bold: true),
      if (noResponse) const _Chip('No response', fg: Color(0xFF991B1B), bg: _redSoft, icon: Icons.timer_off_outlined, bold: true),
      if (task.typeName != null) _Chip(task.typeName!, fg: Brand.onVariant, bg: Brand.surfaceLow),
    ];

    final trailing = slaRunning
        ? DashTimer(countdown(task.slaDeadlineAt), fg: _amberInk, bg: _amberSoft, border: _amberLine, dot: const Color(0xFFF59E0B))
        : _DueLine(task: task, overdue: overdue);

    final discuss = (task.discussReason ?? '').trim();
    final blockedReason = (task.blockedReason ?? '').trim();
    final reason = task.isBlocked && blockedReason.isNotEmpty
        ? 'Blocked: $blockedReason'
        : (needsAction && discuss.isNotEmpty ? discuss : null);

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
                          const SizedBox(width: 8),
                          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 140), child: trailing),
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
                    if (reason != null) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Row(
                          children: [
                            Icon(
                              task.isBlocked ? Icons.block_rounded : Icons.notifications_active_outlined,
                              size: 13,
                              color: _amberInk,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                reason,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _amberInk),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: canReassignTask(task, me) ? () => _reassignFor(context, task, onChanged) : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Avatar(task.assigneeName ?? task.teamName, size: 20),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(text: task.who, style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.navy)),
                                          if (task.memberCount > 0) TextSpan(text: ' +${task.memberCount}'),
                                          if (team != null) TextSpan(text: '  •  $team'),
                                          if (task.projectName != null)
                                            TextSpan(text: '  •  ${task.projectName}')
                                          else
                                            TextSpan(text: '  •  by ${displayName(task.creatorName)}'),
                                          if (eta != null) TextSpan(text: '  •  ETA ${fmtShortDate(eta)}'),
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11.5, color: Brand.onVariant),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (task.subtaskCount > 0) _Checklist(done: task.subtaskDone, total: task.subtaskCount),
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
                    if (action != null) ...[
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(right: 12, bottom: 6),
                        child: SizedBox(width: double.infinity, child: action),
                      ),
                    ],
                  ],
                ),
              ),
              Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 4, color: edge)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Due date for the tag row: "Today, 6:00 PM" — red with an alert icon once
/// overdue; nothing when there is no due date.
class _DueLine extends StatelessWidget {
  const _DueLine({required this.task, required this.overdue});
  final Task task;
  final bool overdue;

  static String _when(DateTime d) {
    final now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final diff = day.difference(DateTime(now.year, now.month, now.day)).inDays;
    final label = switch (diff) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => fmtShortDate(d),
    };
    return '$label, ${fmtTime(d)}';
  }

  @override
  Widget build(BuildContext context) {
    final due = task.dueAt;
    if (due == null) return const SizedBox.shrink();
    final color = overdue ? _red : Brand.onVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(overdue ? Icons.event_busy_rounded : Icons.schedule_rounded, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              overdue ? 'Overdue · ${_when(due)}' : _when(due),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: overdue ? _red : Brand.navy),
            ),
          ),
        ],
      ),
    );
  }
}

/// "3/4" subtasks with a tiny lime bar, for the meta line.
class _Checklist extends StatelessWidget {
  const _Checklist({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '$done of $total subtasks completed',
    child: Padding(
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
    ),
  );
}

/// Status tag that opens the status sheet: lime-light for active work, red
/// when blocked / escalated / rejected, otherwise the status colours.
class _StatusButton extends StatelessWidget {
  const _StatusButton({required this.status, required this.onTap, this.danger = false});
  final String status;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final active = status == 'IN_PROGRESS' || status == 'ACKNOWLEDGED';
    final c = TF.status(status);
    final plain = closedStatuses.contains(status);
    final fg = danger ? _red : (active || plain ? Brand.navy : c.fg);
    final bg = danger ? const Color(0xFFFEF2F2) : (active ? Brand.limeLight : (plain ? Brand.surfaceLow : c.bg));
    final side = danger ? const Color(0x55DC2626) : (active ? Brand.limeDim.withValues(alpha: 0.5) : Colors.transparent);
    return Material(
      key: ValueKey('status-$status'),
      color: bg,
      shape: StadiumBorder(side: BorderSide(color: side)),
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

/// Small rounded tag used on list rows: optional icon, optional border.
class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.fg, required this.bg, this.border, this.icon, this.bold = false});
  final String label;
  final Color fg;
  final Color bg;
  final Color? border;
  final IconData? icon;
  final bool bold;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      border: border != null ? Border.all(color: border!) : null,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg, fontSize: 10.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, letterSpacing: 0.2),
          ),
        ),
      ],
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
