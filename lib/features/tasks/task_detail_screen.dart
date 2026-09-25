import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/task_logic.dart';
import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../state/realtime_controller.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/attachments.dart';
import '../../widgets/common.dart';
import '../chat/chat_screen.dart';
import '../projects/project_detail_screen.dart';
import 'comments_panel.dart';
import 'composer_sheet.dart';
import 'reassign_sheet.dart';
import 'status_sheet.dart';

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});
  final int taskId;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  TaskDetail? data;
  String? error;
  bool busy = false;
  bool showEtaHistory = false;
  List<AppUser> users = [];
  final explanationCtrl = TextEditingController();
  final payloadCtrl = TextEditingController();
  DateTime? proposedEta;
  StreamSubscription<void>? _sub;

  TaskFlowApi get api => Get.find<TaskFlowApi>();

  @override
  void initState() {
    super.initState();
    _load();
    api.users().then((u) {
      if (mounted) setState(() => users = u.where((x) => x.isActive).toList());
    }).catchError((_) {});
    _sub = Get.find<RealtimeController>().taskChanged.listen((_) => _load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await api.task(widget.taskId);
      if (mounted) setState(() => (data = d, error = null));
    } catch (e) {
      if (mounted) setState(() => error = errorText(e, 'Failed to load task'));
    }
  }

  Future<void> _act(String action, [Map<String, dynamic> extra = const {}]) async {
    setState(() => busy = true);
    final ok = await runTaskAction(context, widget.taskId, action, extra);
    if (mounted) setState(() => busy = false);
    if (ok) await _load();
  }

  Future<void> _reasonAction(String action, String title, {bool optional = false}) async {
    final r = await promptText(context, title: title, required: !optional);
    if (r == null) return;
    await _act(action, {if (r.isNotEmpty) 'reason': r});
  }

  Future<void> _escalation(Future<void> Function() run, String success) async {
    setState(() => busy = true);
    try {
      await run();
      toast(success);
      explanationCtrl.clear();
      proposedEta = null;
      await _load();
    } catch (e) {
      toastError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _onLink(String href) {
    final id = taskIdFromHref(href);
    if (id != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: id)));
    } else {
      launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    return Scaffold(
      appBar: AppBar(
        title: Text(d == null ? 'Task' : 'Task #${d.task.id}'),
        actions: [
          if (d != null) ...[
            if (chatTargetForTask(d.task, Get.find<AuthController>().me?.id) case final target?)
              IconButton(
                tooltip: 'Chat about this task',
                icon: const Icon(Icons.forum_outlined),
                onPressed: () => openChatWithUser(context, target, attachTask: d.task),
              ),
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: _load),
          ],
        ],
      ),
      body: error != null && d == null
          ? ErrorView(message: error!, onRetry: _load)
          : d == null
              ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 4, height: 110))
              : LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth >= 980;
                  final details = _details(d);
                  final comments = CommentsPanel(taskId: d.task.id, onChanged: _load, canComment: d.permissions.canComment);
                  if (wide) {
                    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(flex: 6, child: details),
                      const VerticalDivider(width: 1),
                      Expanded(
                        flex: 5,
                        child: Column(children: [
                          if (d.permissions.canViewActivity) SizedBox(height: 220, child: _activityPanel(d)),
                          if (d.permissions.canViewActivity) const Divider(),
                          _panelHeader('Comments'),
                          Expanded(child: comments),
                        ]),
                      ),
                    ]);
                  }
                  return DefaultTabController(
                    length: d.permissions.canViewActivity ? 3 : 2,
                    child: Column(children: [
                      TabBar(tabs: [
                        const Tab(text: 'Details'),
                        const Tab(key: Key('tab-comments'), text: 'Comments'),
                        if (d.permissions.canViewActivity) const Tab(text: 'Activity'),
                      ]),
                      Expanded(
                        child: TabBarView(children: [
                          details,
                          comments,
                          if (d.permissions.canViewActivity) _activityPanel(d),
                        ]),
                      ),
                    ]),
                  );
                }),
    );
  }

  Widget _panelHeader(String title) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Text(title.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
      );

  Widget _details(TaskDetail d) {
    final t = d.task;
    final p = d.permissions;
    final me = Get.find<AuthController>().me;
    final overdue = isTaskOverdue(t);
    final descAttachments = d.attachments.where((a) => a.context == 'description').toList();
    final fileAttachments = d.attachments.where((a) => a.context != 'description').toList();
    final etaHistory = d.activity.where((a) => a.type == 'ETA_CHANGED').toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          StatusPill(t.status, onTap: () async {
            if (await showStatusSheet(context, t) == true) _load();
          }),
          if (t.slaBreachedAt != null && t.status == 'ASSIGNED')
            const Pill('No response', fg: TF.coral, bg: TF.coralSoft, icon: Icons.notifications_off_outlined),
          if (t.status == 'ASSIGNED' && t.slaBreachedAt == null && t.slaDeadlineAt != null)
            Pill('Respond: ${countdown(t.slaDeadlineAt)}', fg: Colors.white, bg: TF.amber, icon: Icons.timer_outlined),
          if (t.isBlocked) const Pill('Blocked', fg: TF.violet, bg: TF.violetSoft),
          Pill(titleCase(t.priority), fg: TF.priority(t.priority), bg: TF.priority(t.priority).withValues(alpha: 0.1), icon: Icons.flag_rounded),
          if (t.reopenCount > 0) Pill('Reopened ×${t.reopenCount}'),
        ]),
        const SizedBox(height: 12),
        SelectableText(t.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        if (t.description.trim().isNotEmpty)
          RichBody(RegExp(r'<[a-zA-Z/][^>]*>').hasMatch(t.description) ? htmlToPlainText(t.description) : t.description, onLink: _onLink)
        else
          const Text('No description', style: TextStyle(color: TF.faint, fontStyle: FontStyle.italic)),
        for (final a in descAttachments) Padding(padding: const EdgeInsets.only(top: 8), child: AttachmentTile(attachment: a, compact: true)),
        if (t.isBlocked) ...[
          const SizedBox(height: 10),
          InfoBanner(title: 'Blocked', text: t.blockedReason!, fg: TF.violet, bg: TF.violetSoft, icon: Icons.block_rounded),
        ],
        if (t.status == 'REJECTED' && t.cancelReason != null) ...[
          const SizedBox(height: 10),
          InfoBanner(title: 'Rejected', text: t.cancelReason!, fg: const Color(0xFFBE123C), bg: const Color(0xFFFDE8EE)),
        ],
        if (t.status == 'DISCUSS' && t.discussReason != null) ...[
          const SizedBox(height: 10),
          InfoBanner(title: 'Discuss', text: t.discussReason!, fg: TF.violet, bg: TF.violetSoft, icon: Icons.forum_outlined),
        ],
        if (t.inputRequestNote != null && p.canViewInputRequest) ...[
          const SizedBox(height: 10),
          InfoBanner(title: 'Information requested', text: t.inputRequestNote!, fg: const Color(0xFF0E7490), bg: const Color(0xFFE0F4F8)),
        ],
        if (t.inputPayload != null && p.canViewInputPayload) ...[
          const SizedBox(height: 10),
          InfoBanner(title: 'Provided data', text: t.inputPayload!, fg: TF.green, bg: TF.greenSoft),
        ],
        const SizedBox(height: 16),
        _facts(d, overdue, etaHistory, me),
        if (d.batchTasks.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 4, children: [
            const Text('Part of a batch:', style: TextStyle(fontSize: 12.5, color: TF.muted)),
            for (final b in d.batchTasks)
              InkWell(
                onTap: () => _onLink('/tasks/${b.id}'),
                child: Text('#${b.id} ${b.title}',
                    style: const TextStyle(fontSize: 12.5, color: TF.primary, decoration: TextDecoration.underline)),
              ),
          ]),
        ],
        if (p.mustExplain) ...[
          const SizedBox(height: 16),
          ExplainEscalationCard(
            busy: busy,
            controller: explanationCtrl,
            proposedEta: proposedEta,
            onEta: (v) => setState(() => proposedEta = v),
            onSubmit: () => _escalation(
              () => api.submitEscalationExplanation(t.id, explanationCtrl.text.trim(), proposedEta),
              'Explanation submitted',
            ),
          ),
        ],
        if (d.escalation?.explanation != null && t.status == 'ESCALATED') ...[
          const SizedBox(height: 16),
          ReviewEscalationCard(
            escalation: d.escalation!,
            busy: busy,
            canReview: p.canReview,
            onReview: (r) => _escalation(
              () => api.reviewEscalation(t.id, r),
              r == 'ACCEPTED' ? 'Escalation accepted' : 'Escalation rejected',
            ),
          ),
        ],
        const SizedBox(height: 16),
        _actions(d),
        if (p.canProvideInput && t.status == 'WAITING_FOR_INPUT') ...[
          const SizedBox(height: 16),
          ProvideInputCard(
            task: t,
            controller: payloadCtrl,
            busy: busy,
            onSubmit: () {
              final v = payloadCtrl.text.trim();
              if (v.isEmpty) return toast('Enter the requested information');
              _act('provide_input', {'inputPayload': v});
            },
          ),
        ],
        if (fileAttachments.isNotEmpty) ...[
          const SizedBox(height: 22),
          SectionHeader(title: 'Attachments', icon: Icons.attach_file_rounded, count: fileAttachments.length),
          for (final a in fileAttachments) Padding(padding: const EdgeInsets.only(bottom: 8), child: AttachmentTile(attachment: a)),
        ],
        if (t.parentId == null) ...[
          const SizedBox(height: 22),
          _subtasks(d, me),
        ],
      ]),
    );
  }

  Widget _facts(TaskDetail d, bool overdue, List<Activity> etaHistory, Me? me) {
    final t = d.task;
    final p = d.permissions;
    final memberIds = d.members.map((m) => m.userId).toSet();
    final candidates = users.where((u) => u.id != t.assigneeId && !memberIds.contains(u.id)).toList();

    Widget row(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 118, child: Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall)),
            Expanded(child: value),
          ]),
        );
    const valueStyle = TextStyle(fontSize: 14, color: TF.ink, fontWeight: FontWeight.w500);

    return Surface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(children: [
        row(
          'Assignee',
          InkWell(
            onTap: canReassignTask(t, me)
                ? () async {
                    if (await showReassignSheet(context, t) == true) _load();
                  }
                : null,
            child: Row(children: [
              Avatar(t.assigneeName ?? t.teamName, size: 24),
              const SizedBox(width: 8),
              Flexible(child: Text(t.assigneeName ?? (t.teamName != null ? 'Team: ${t.teamName}' : '—'), style: valueStyle)),
              if (canReassignTask(t, me)) const Icon(Icons.edit_outlined, size: 15, color: TF.muted),
            ]),
          ),
        ),
        if (d.members.isNotEmpty) ...[
          const Divider(),
          row(
            'Members',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final m in d.members)
                Row(children: [
                  Expanded(child: Text(m.userName, style: valueStyle)),
                  Pill(titleCase(m.role)),
                  if (p.canManageMembers)
                    IconButton(
                      tooltip: 'Remove',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 17, color: TF.coral),
                      onPressed: () => _act('remove_member', {'userId': m.userId}),
                    ),
                ]),
            ]),
          ),
        ],
        if (p.canManageMembers && candidates.isNotEmpty) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('add-member'),
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('Add collaborator or watcher'),
                onPressed: () => _addMember(candidates),
              ),
            ),
          ),
        ],
        const Divider(),
        row('Created by', Text('${t.creatorName ?? '—'} · ${timeAgo(t.createdAt)}', style: valueStyle)),
        const Divider(),
        row(
          'Due',
          Text('${fmtDateTime(t.dueAt)}${overdue ? '  (overdue)' : ''}',
              style: valueStyle.copyWith(color: overdue ? TF.coral : TF.ink, fontWeight: overdue ? FontWeight.w700 : null)),
        ),
        const Divider(),
        row(
          'ETA',
          Row(children: [
            Text(fmtDateTime(t.etaAt), style: valueStyle),
            if (etaHistory.isNotEmpty)
              TextButton(
                onPressed: () => setState(() => showEtaHistory = !showEtaHistory),
                child: Text('history (${etaHistory.length})'),
              ),
          ]),
        ),
        if (showEtaHistory)
          for (final h in etaHistory)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6, left: 118),
              padding: const EdgeInsets.only(left: 8),
              decoration: const BoxDecoration(border: Border(left: BorderSide(color: TF.line, width: 2))),
              child: Text(
                '${h.actorName ?? 'System'}: ${fmtDateTime(toDate(h.meta['from']))} → ${fmtDateTime(toDate(h.meta['to']))} · ${timeAgo(h.createdAt)}',
                style: const TextStyle(fontSize: 12, color: TF.muted),
              ),
            ),
        if (t.typeName != null) ...[const Divider(), row('Task type', Text(t.typeName!, style: valueStyle))],
        if (t.acknowledgedAt != null) ...[const Divider(), row('Accepted', Text(fmtDateTime(t.acknowledgedAt), style: valueStyle))],
        if (t.doneAt != null) ...[const Divider(), row('Done at', Text(fmtDateTime(t.doneAt), style: valueStyle))],
        if (t.projectName != null) ...[
          const Divider(),
          row(
            'Project',
            InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(projectId: t.projectId!))),
              child: Text(t.projectName!, style: valueStyle.copyWith(color: TF.primary, decoration: TextDecoration.underline)),
            ),
          ),
        ],
        if (t.parentId != null) ...[
          const Divider(),
          row(
            'Parent task',
            InkWell(
              onTap: () => _onLink('/tasks/${t.parentId}'),
              child: Text('#${t.parentId}', style: valueStyle.copyWith(color: TF.primary, decoration: TextDecoration.underline)),
            ),
          ),
        ],
      ]),
    );
  }

  Future<void> _addMember(List<AppUser> candidates) async {
    final userId = await showSearchPicker<int>(
      context,
      title: 'Add member',
      options: [for (final u in candidates) PickerOption(value: u.id, label: u.name, subtitle: u.teamName, leading: Avatar(u.name))],
    );
    if (userId == null || !mounted) return;
    final role = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(title: const Text('Role'), children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'COLLABORATOR'),
          child: const ListTile(title: Text('Collaborator'), subtitle: Text('Can view & comment')),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'WATCHER'),
          child: const ListTile(title: Text('Watcher'), subtitle: Text('View updates only')),
        ),
      ]),
    );
    if (role == null) return;
    await _act('add_member', {'userId': userId, 'role': role});
  }

  Widget _actions(TaskDetail d) {
    final t = d.task;
    final p = d.permissions;
    final buttons = <Widget>[
      if (p.canAcknowledge)
        FilledButton.icon(
          key: const Key('detail-accept'),
          onPressed: busy ? null : () => _accept(t),
          icon: const Icon(Icons.handshake_outlined, size: 18),
          label: const Text('Accept + ETA'),
        ),
      if (p.canDiscuss)
        OutlinedButton(onPressed: busy ? null : () => _reasonAction('discuss', 'What should be discussed? (optional)', optional: true), child: const Text('Discuss')),
      if (p.canReject)
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: TF.coral),
          onPressed: busy ? null : () => _reasonAction('reject', 'Why reject this task?'),
          child: const Text('Reject'),
        ),
      if (p.canStart)
        FilledButton.icon(
          key: const Key('detail-start'),
          onPressed: busy ? null : () => _act('start'),
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: Text(t.status == 'ESCALATED' ? 'Mark in progress' : 'Start'),
        ),
      if (p.canRequestInput)
        OutlinedButton(
          onPressed: busy
              ? null
              : () async {
                  final note = await promptText(context,
                      title: 'Request information',
                      message: 'Describe what you need. This will be visible to the task creator or Admin.',
                      hint: 'Example: Need SMTP host, port, user, and app password',
                      minLength: 10,
                      confirmLabel: 'Send request');
                  if (note != null) _act('request_input', {'inputRequestNote': note});
                },
          child: const Text('Request information'),
        ),
      if (p.canResumeAfterInput)
        FilledButton(onPressed: busy ? null : () => _act('resume_after_input'), child: const Text('Continue working')),
      if (p.canDone)
        FilledButton.icon(
          key: const Key('detail-done'),
          style: FilledButton.styleFrom(backgroundColor: TF.green),
          onPressed: busy ? null : () => _act('done'),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Mark done'),
        ),
      if (p.canEditEta)
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final v = await pickDateTime(context, initial: t.etaAt ?? DateTime.now());
                  if (v != null) _act('update_eta', {'etaAt': v.millisecondsSinceEpoch});
                },
          icon: const Icon(Icons.schedule_rounded, size: 18),
          label: const Text('Edit ETA'),
        ),
      if (p.canBlock && !t.isBlocked)
        OutlinedButton(onPressed: busy ? null : () => _reasonAction('block', 'What is blocking you?'), child: const Text('Blocked')),
      if (t.isBlocked && p.canUnblock)
        OutlinedButton(onPressed: busy ? null : () => _act('unblock'), child: const Text('Unblock')),
      if (p.canReopen)
        OutlinedButton(onPressed: busy ? null : () => _reasonAction('reopen', 'Why reopen this task?'), child: const Text('Reopen')),
      if (p.canCancel)
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: TF.coral),
          onPressed: busy ? null : () => _reasonAction('cancel', 'Why cancel this task?'),
          child: const Text('Cancel task'),
        ),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: buttons);
  }

  Future<void> _accept(Task t) async {
    DateTime? eta;
    final ok = await showAppSheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Accept & set ETA', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('You are accepting "${t.title}". An ETA is mandatory.', style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 14),
              DateTimeField(
                value: eta,
                onChanged: (v) => setSheet(() => eta = v),
                label: 'Pick your ETA',
                quick: const [('eod', 'Today EOD'), ('24h', '+24 hours'), ('48h', '+2 days')],
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('accept-submit'),
                onPressed: () {
                  if (eta == null) return toast('Set your ETA — it is mandatory');
                  Navigator.pop(ctx, true);
                },
                child: const Text('Accept with this ETA'),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok == true && eta != null) await _act('acknowledge', {'etaAt': eta!.millisecondsSinceEpoch});
  }

  Widget _subtasks(TaskDetail d, Me? me) {
    final done = d.subtasks.where((s) => s.status == 'DONE').length;
    final pct = subtaskPercent(done, d.subtasks.length);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(
        title: 'Subtasks',
        icon: Icons.checklist_rounded,
        color: TF.green,
        count: d.subtasks.length,
        trailing: d.permissions.canAddSubtask
            ? TextButton.icon(
                key: const Key('add-subtask'),
                onPressed: () async {
                  final ids = await showComposer(context, presetParentId: d.task.id);
                  if (ids != null) _load();
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
              )
            : null,
      ),
      if (d.subtasks.isNotEmpty) ...[
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: pct / 100, minHeight: 6, backgroundColor: TF.sunken, color: TF.green),
            ),
          ),
          const SizedBox(width: 10),
          Text('$done of ${d.subtasks.length} · $pct%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: TF.green)),
        ]),
        const SizedBox(height: 8),
      ],
      if (d.subtasks.isEmpty) const Text('No subtasks yet.', style: TextStyle(color: TF.muted, fontSize: 13)),
      for (final s in d.subtasks)
        Container(
          key: ValueKey('subtask-${s.id}'),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(color: TF.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: TF.line)),
          child: Row(children: [
            Checkbox(
              value: s.status == 'DONE',
              onChanged: s.status == 'DONE'
                  ? null
                  : (_) async {
                      try {
                        await api.taskAction(s.id, 'done');
                        toast('Subtask marked done');
                        _load();
                      } catch (e) {
                        toastError(e);
                      }
                    },
            ),
            Expanded(
              child: InkWell(
                onTap: () => _onLink('/tasks/${s.id}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          decoration: s.status == 'DONE' ? TextDecoration.lineThrough : null,
                          color: s.status == 'DONE' ? TF.muted : TF.ink,
                        )),
                    const SizedBox(height: 2),
                    Text(
                      [s.assigneeName ?? 'Unassigned', if (s.doneAt != null) 'done ${fmtDateTime(s.doneAt)}'].join(' · '),
                      style: const TextStyle(fontSize: 12, color: TF.muted),
                    ),
                  ]),
                ),
              ),
            ),
            if (canReassignTask(s, me, parent: d.task))
              IconButton(
                tooltip: 'Change assignee',
                icon: const Icon(Icons.person_outline_rounded, size: 19),
                onPressed: () async {
                  if (await showReassignSheet(context, s) == true) _load();
                },
              ),
          ]),
        ),
    ]);
  }

  Widget _activityPanel(TaskDetail d) {
    if (d.activity.isEmpty) return const Center(child: Text('No activity yet.', style: TextStyle(color: TF.muted)));
    return ListView(padding: const EdgeInsets.all(14), children: [
      for (final a in d.activity)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6, right: 10),
              decoration: const BoxDecoration(color: TF.primary, shape: BoxShape.circle),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: a.actorName ?? 'System', style: const TextStyle(fontWeight: FontWeight.w700, color: TF.ink)),
                  TextSpan(text: ' ${activityTypeLabel(a.type)} · ${timeAgo(a.createdAt)}'),
                ]), style: const TextStyle(fontSize: 13, color: TF.muted)),
                if (a.detail.isNotEmpty) Text(a.detail, style: const TextStyle(fontSize: 12.5, color: TF.inkSoft)),
              ]),
            ),
          ]),
        ),
    ]);
  }
}
