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
    final me = Get.find<AuthController>().me;
    final chatTarget = d == null ? null : chatTargetForTask(d.task, me?.id);
    return Scaffold(
      backgroundColor: Brand.bg,
      appBar: _DetailHeader(
        title: d == null ? 'Task' : 'Task #${d.task.id}',
        actions: [
          if (d != null) ...[
            if (chatTarget != null)
              IconButton(
                tooltip: 'Chat about this task',
                icon: const Icon(Icons.forum_outlined, color: Brand.inkSoft),
                onPressed: () => openChatWithUser(context, chatTarget, attachTask: d.task),
              ),
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded, color: Brand.inkSoft), onPressed: _load),
          ],
        ],
      ),
      body: error != null && d == null
          ? ErrorView(message: error!, onRetry: _load)
          : d == null
              ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 4, height: 110))
              : Column(children: [
                  _responseBanner(d.task),
                  Expanded(
                    child: LayoutBuilder(builder: (context, c) {
                      final wide = c.maxWidth >= 980;
                      final details = _details(d);
                      final comments = CommentsPanel(taskId: d.task.id, onChanged: _load, canComment: d.permissions.canComment);
                      if (wide) {
                        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(flex: 6, child: details),
                          const VerticalDivider(width: 1, color: Brand.line),
                          Expanded(
                            flex: 5,
                            child: Container(
                              color: Brand.card,
                              child: Column(children: [
                                if (d.permissions.canViewActivity) ...[
                                  _panelHeader(Icons.history_rounded, 'Activity'),
                                  SizedBox(height: 220, child: _activityPanel(d)),
                                  const Divider(color: Brand.line),
                                ],
                                _panelHeader(Icons.forum_outlined, 'Comments'),
                                Expanded(child: comments),
                              ]),
                            ),
                          ),
                        ]);
                      }
                      return DefaultTabController(
                        length: d.permissions.canViewActivity ? 3 : 2,
                        child: Column(children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Container(
                              height: 46,
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(color: Brand.primarySoft.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(14)),
                              child: TabBar(
                                dividerColor: Colors.transparent,
                                indicatorSize: TabBarIndicatorSize.tab,
                                indicator: BoxDecoration(
                                  color: Brand.card,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [BoxShadow(color: Brand.ink.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
                                ),
                                labelColor: Brand.primaryDeep,
                                unselectedLabelColor: Brand.inkSoft,
                                labelStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                                unselectedLabelStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
                                tabs: [
                                  const Tab(text: 'Details'),
                                  const Tab(key: Key('tab-comments'), text: 'Comments'),
                                  if (d.permissions.canViewActivity) const Tab(text: 'Activity'),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: TabBarView(children: [
                              details,
                              Container(
                                margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                                clipBehavior: Clip.antiAlias,
                                decoration: _cardDecoration,
                                child: comments,
                              ),
                              if (d.permissions.canViewActivity)
                                Container(
                                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                                  clipBehavior: Clip.antiAlias,
                                  decoration: _cardDecoration,
                                  child: _activityPanel(d),
                                ),
                            ]),
                          ),
                        ]),
                      );
                    }),
                  ),
                ]),
    );
  }

  /// Amber "respond within" / red "no response" strip under the header.
  Widget _responseBanner(Task t) {
    if (t.status != 'ASSIGNED') return const SizedBox.shrink();
    final breached = t.slaBreachedAt != null;
    if (!breached && t.slaDeadlineAt == null) return const SizedBox.shrink();
    final fg = breached ? Brand.red : Brand.amber;
    return Container(
      width: double.infinity,
      color: breached ? Brand.redSoft : Brand.amberSoft,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(children: [
        Icon(breached ? Icons.notifications_off_outlined : Icons.timer_outlined, size: 20, color: fg),
        const SizedBox(width: 10),
        Expanded(
          child: Text(breached ? 'No response' : 'Respond: ${countdown(t.slaDeadlineAt)}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
        ),
        StatusPill(t.status),
      ]),
    );
  }

  Widget _panelHeader(IconData icon, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Row(children: [
          Icon(icon, size: 20, color: Brand.primary),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Brand.ink)),
        ]),
      );

  Widget _details(TaskDetail d) {
    final t = d.task;
    final p = d.permissions;
    final me = Get.find<AuthController>().me;
    final overdue = isTaskOverdue(t);
    final descAttachments = d.attachments.where((a) => a.context == 'description').toList();
    final fileAttachments = d.attachments.where((a) => a.context != 'description').toList();
    final etaHistory = d.activity.where((a) => a.type == 'ETA_CHANGED').toList();
    final hot = t.priority == 'URGENT' || t.priority == 'HIGH';

    return RefreshIndicator(
      color: Brand.primary,
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: [
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          StatusPill(t.status, onTap: () async {
            if (await showStatusSheet(context, t) == true) _load();
          }),
          _Chip(
            titleCase(t.priority),
            fg: t.priority == 'URGENT' ? Brand.red : (t.priority == 'HIGH' ? Brand.amber : Brand.inkSoft),
            bg: t.priority == 'URGENT' ? Brand.redSoft : (t.priority == 'HIGH' ? Brand.amberSoft : Brand.slateSoft),
            icon: hot ? Icons.priority_high_rounded : Icons.flag_outlined,
          ),
          if (t.isBlocked) const _Chip('Blocked', fg: TF.violet, bg: TF.violetSoft, icon: Icons.block_rounded),
          if (t.reopenCount > 0) _Chip('Reopened ×${t.reopenCount}', fg: Brand.inkSoft, bg: Brand.slateSoft, icon: Icons.replay_rounded),
          if (t.projectName != null)
            _Chip(
              t.projectName!,
              fg: Brand.inkSoft,
              bg: Brand.slateSoft,
              icon: Icons.folder_open_outlined,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(projectId: t.projectId!))),
            ),
        ]),
        const SizedBox(height: 14),
        SelectableText(t.title,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.2, color: Brand.ink)),
        const SizedBox(height: 10),
        if (t.description.trim().isNotEmpty)
          DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 15.5, height: 1.5, color: Brand.inkSoft),
            child: RichBody(RegExp(r'<[a-zA-Z/][^>]*>').hasMatch(t.description) ? htmlToPlainText(t.description) : t.description,
                onLink: _onLink),
          )
        else
          const Text('No description', style: TextStyle(color: Brand.faint, fontStyle: FontStyle.italic)),
        for (final a in descAttachments) Padding(padding: const EdgeInsets.only(top: 8), child: AttachmentTile(attachment: a, compact: true)),
        const SizedBox(height: 16),
        _actions(d),
        _facts(d, overdue, etaHistory, me),
        if (t.isBlocked) _Notice(title: 'Blocked', text: t.blockedReason!, fg: TF.violet, bg: TF.violetSoft, icon: Icons.block_rounded),
        if (t.status == 'REJECTED' && t.cancelReason != null)
          _Notice(title: 'Rejected', text: t.cancelReason!, fg: const Color(0xFFBE123C), bg: const Color(0xFFFDE8EE), icon: Icons.cancel_outlined),
        if (t.status == 'DISCUSS' && t.discussReason != null)
          _Notice(title: 'Discuss', text: t.discussReason!, fg: TF.violet, bg: TF.violetSoft, icon: Icons.forum_outlined),
        if (t.inputRequestNote != null && p.canViewInputRequest)
          _Notice(
            title: 'Information requested',
            text: t.inputRequestNote!,
            fg: const Color(0xFF9A4A0B),
            bg: const Color(0xFFFEF6E0),
            icon: Icons.key_outlined,
          ),
        if (t.inputPayload != null && p.canViewInputPayload)
          _Notice(title: 'Provided data', text: t.inputPayload!, fg: Brand.green, bg: Brand.greenSoft, icon: Icons.check_circle_outline_rounded),
        if (d.batchTasks.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 4, children: [
            const Text('Part of a batch:', style: TextStyle(fontSize: 13, color: Brand.muted)),
            for (final b in d.batchTasks)
              InkWell(
                onTap: () => _onLink('/tasks/${b.id}'),
                child: Text('#${b.id} ${b.title}',
                    style: const TextStyle(fontSize: 13, color: Brand.primary, decoration: TextDecoration.underline)),
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
        if (t.parentId == null) ...[
          const SizedBox(height: 16),
          _subtasks(d, me),
        ],
        if (fileAttachments.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionCard(
            icon: Icons.attach_file_rounded,
            title: 'Attachments (${fileAttachments.length})',
            children: [
              for (final a in fileAttachments) Padding(padding: const EdgeInsets.only(bottom: 8), child: AttachmentTile(attachment: a)),
            ],
          ),
        ],
        _members(d),
      ]),
    );
  }

  Widget _facts(TaskDetail d, bool overdue, List<Activity> etaHistory, Me? me) {
    final t = d.task;
    final canReassign = canReassignTask(t, me);

    Widget line(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 13, color: Brand.muted))),
            Expanded(child: value),
          ]),
        );
    const valueStyle = TextStyle(fontSize: 14, color: Brand.ink, fontWeight: FontWeight.w600);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 10) / 2;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            SizedBox(
              width: w,
              child: _FactTile(
                icon: Icons.person_outline_rounded,
                label: 'Created by',
                avatar: t.creatorName,
                value: t.creatorName ?? '—',
                sub: timeAgo(t.createdAt),
              ),
            ),
            SizedBox(
              width: w,
              child: _FactTile(
                icon: Icons.assignment_ind_outlined,
                label: 'Assignee',
                avatar: t.assigneeName ?? t.teamName,
                value: t.assigneeName ?? (t.teamName != null ? 'Team: ${t.teamName}' : '—'),
                trailing: canReassign ? Icons.edit_outlined : null,
                onTap: canReassign
                    ? () async {
                        if (await showReassignSheet(context, t) == true) _load();
                      }
                    : null,
              ),
            ),
            SizedBox(
              width: w,
              child: _FactTile(
                icon: Icons.event_outlined,
                label: 'Due',
                value: fmtDateTime(t.dueAt),
                sub: overdue ? 'overdue' : null,
                danger: overdue,
              ),
            ),
            SizedBox(
              width: w,
              child: _FactTile(
                icon: Icons.hourglass_bottom_rounded,
                label: 'ETA',
                value: fmtDateTime(t.etaAt),
                accent: true,
                sub: etaHistory.isEmpty ? null : 'history (${etaHistory.length})',
                onTap: etaHistory.isEmpty ? null : () => setState(() => showEtaHistory = !showEtaHistory),
              ),
            ),
          ]);
        }),
        if (showEtaHistory)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final h in etaHistory)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.only(left: 10),
                  decoration: const BoxDecoration(border: Border(left: BorderSide(color: Brand.primarySoft, width: 3))),
                  child: Text(
                    '${h.actorName ?? 'System'}: ${fmtDateTime(toDate(h.meta['from']))} → ${fmtDateTime(toDate(h.meta['to']))} · ${timeAgo(h.createdAt)}',
                    style: const TextStyle(fontSize: 12.5, color: Brand.muted),
                  ),
                ),
            ]),
          ),
        if (t.typeName != null || t.acknowledgedAt != null || t.doneAt != null || t.parentId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
            child: Column(children: [
              if (t.typeName != null) line('Task type', Text(t.typeName!, style: valueStyle)),
              if (t.acknowledgedAt != null) line('Accepted', Text(fmtDateTime(t.acknowledgedAt), style: valueStyle)),
              if (t.doneAt != null) line('Done at', Text(fmtDateTime(t.doneAt), style: valueStyle)),
              if (t.parentId != null)
                line(
                  'Parent task',
                  InkWell(
                    onTap: () => _onLink('/tasks/${t.parentId}'),
                    child: Text('#${t.parentId}', style: valueStyle.copyWith(color: Brand.primary, decoration: TextDecoration.underline)),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }

  Widget _members(TaskDetail d) {
    final t = d.task;
    final p = d.permissions;
    final memberIds = d.members.map((m) => m.userId).toSet();
    final candidates = users.where((u) => u.id != t.assigneeId && !memberIds.contains(u.id)).toList();
    final canAdd = p.canManageMembers && candidates.isNotEmpty;
    if (d.members.isEmpty && !canAdd) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: _SectionCard(
        icon: Icons.visibility_outlined,
        title: 'Collaborators & watchers',
        trailing: d.members.isEmpty ? null : Text('${d.members.length}', style: const TextStyle(fontSize: 13, color: Brand.muted)),
        children: [
          if (d.members.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in d.members)
                Container(
                  padding: const EdgeInsets.fromLTRB(5, 5, 6, 5),
                  decoration: BoxDecoration(color: Brand.field, borderRadius: BorderRadius.circular(99)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Avatar(m.userName, size: 26),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(m.userName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Brand.ink)),
                    ),
                    const SizedBox(width: 6),
                    Pill(titleCase(m.role), fg: Brand.primaryDeep, bg: Brand.primarySoft),
                    if (p.canManageMembers)
                      InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _act('remove_member', {'userId': m.userId}),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close_rounded, size: 17, color: Brand.red),
                        ),
                      )
                    else
                      const SizedBox(width: 6),
                  ]),
                ),
            ]),
          if (canAdd)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('add-member'),
                style: TextButton.styleFrom(foregroundColor: Brand.primary, padding: const EdgeInsets.symmetric(horizontal: 4)),
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 19),
                label: const Text('Add collaborator or watcher'),
                onPressed: () => _addMember(candidates),
              ),
            ),
        ],
      ),
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
    VoidCallback? on(VoidCallback f) => busy ? null : f;
    final buttons = <Widget>[
      if (p.canAcknowledge)
        _ActionButton(
          key: const Key('detail-accept'),
          label: 'Accept + ETA',
          icon: Icons.verified_outlined,
          kind: _Kind.primary,
          onPressed: on(() => _accept(t)),
        ),
      if (p.canDiscuss)
        _ActionButton(
          label: 'Discuss',
          icon: Icons.chat_bubble_outline_rounded,
          onPressed: on(() => _reasonAction('discuss', 'What should be discussed? (optional)', optional: true)),
        ),
      if (p.canReject)
        _ActionButton(
          label: 'Reject',
          icon: Icons.close_rounded,
          kind: _Kind.danger,
          onPressed: on(() => _reasonAction('reject', 'Why reject this task?')),
        ),
      if (p.canStart)
        _ActionButton(
          key: const Key('detail-start'),
          label: t.status == 'ESCALATED' ? 'Mark in progress' : 'Start',
          icon: Icons.play_arrow_rounded,
          kind: _Kind.primary,
          onPressed: on(() => _act('start')),
        ),
      if (p.canRequestInput)
        _ActionButton(
          label: 'Request information',
          icon: Icons.help_outline_rounded,
          onPressed: on(() async {
            final note = await promptText(context,
                title: 'Request information',
                message: 'Describe what you need. This will be visible to the task creator or Admin.',
                hint: 'Example: Need SMTP host, port, user, and app password',
                minLength: 10,
                confirmLabel: 'Send request');
            if (note != null) _act('request_input', {'inputRequestNote': note});
          }),
        ),
      if (p.canResumeAfterInput)
        _ActionButton(
          label: 'Continue working',
          icon: Icons.play_circle_outline_rounded,
          kind: _Kind.primary,
          onPressed: on(() => _act('resume_after_input')),
        ),
      if (p.canDone)
        _ActionButton(
          key: const Key('detail-done'),
          label: 'Mark done',
          icon: Icons.check_rounded,
          kind: _Kind.success,
          onPressed: on(() => _act('done')),
        ),
      if (p.canEditEta)
        _ActionButton(
          label: 'Edit ETA',
          icon: Icons.schedule_rounded,
          onPressed: on(() async {
            final v = await pickDateTime(context, initial: t.etaAt ?? DateTime.now());
            if (v != null) _act('update_eta', {'etaAt': v.millisecondsSinceEpoch});
          }),
        ),
      if (p.canBlock && !t.isBlocked)
        _ActionButton(label: 'Blocked', icon: Icons.block_rounded, onPressed: on(() => _reasonAction('block', 'What is blocking you?'))),
      if (t.isBlocked && p.canUnblock) _ActionButton(label: 'Unblock', icon: Icons.lock_open_rounded, onPressed: on(() => _act('unblock'))),
      if (p.canReopen)
        _ActionButton(label: 'Reopen', icon: Icons.replay_rounded, onPressed: on(() => _reasonAction('reopen', 'Why reopen this task?'))),
      if (p.canCancel)
        _ActionButton(
          label: 'Cancel task',
          icon: Icons.delete_outline_rounded,
          kind: _Kind.danger,
          onPressed: on(() => _reasonAction('cancel', 'Why cancel this task?')),
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
    return _SectionCard(
      icon: Icons.checklist_rounded,
      title: 'Subtasks',
      trailing: d.subtasks.isEmpty
          ? null
          : Text('$done of ${d.subtasks.length} · $pct%', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Brand.inkSoft)),
      children: [
        if (d.subtasks.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: pct / 100, minHeight: 8, backgroundColor: Brand.primarySoft, color: Brand.primary),
          ),
          const SizedBox(height: 12),
        ],
        if (d.subtasks.isEmpty) const Text('No subtasks yet.', style: TextStyle(color: Brand.muted, fontSize: 14)),
        for (final s in d.subtasks)
          Container(
            key: ValueKey('subtask-${s.id}'),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: Brand.field, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Checkbox(
                value: s.status == 'DONE',
                activeColor: Brand.primary,
                side: const BorderSide(color: Brand.faint, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
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
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            decoration: s.status == 'DONE' ? TextDecoration.lineThrough : null,
                            color: s.status == 'DONE' ? Brand.muted : Brand.ink,
                          )),
                      const SizedBox(height: 3),
                      Row(children: [
                        Icon(s.status == 'DONE' ? Icons.check_circle_outline_rounded : Icons.account_circle_outlined,
                            size: 15, color: s.status == 'DONE' ? Brand.green : Brand.muted),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            [s.assigneeName ?? 'Unassigned', if (s.doneAt != null) 'done ${fmtDateTime(s.doneAt)}'].join(' · '),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Brand.muted),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),
              ),
              if (canReassignTask(s, me, parent: d.task))
                IconButton(
                  tooltip: 'Change assignee',
                  icon: const Icon(Icons.person_outline_rounded, size: 19, color: Brand.inkSoft),
                  onPressed: () async {
                    if (await showReassignSheet(context, s) == true) _load();
                  },
                ),
            ]),
          ),
        if (d.permissions.canAddSubtask)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('add-subtask'),
              style: TextButton.styleFrom(foregroundColor: Brand.primary, padding: const EdgeInsets.symmetric(horizontal: 4)),
              onPressed: () async {
                final ids = await showComposer(context, presetParentId: d.task.id);
                if (ids != null) _load();
              },
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
              label: const Text('Add subtask', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }

  Widget _activityPanel(TaskDetail d) {
    if (d.activity.isEmpty) return const Center(child: Text('No activity yet.', style: TextStyle(color: Brand.muted)));
    return ListView(padding: const EdgeInsets.all(14), children: [
      for (final a in d.activity)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Avatar(a.actorName ?? 'System', size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                decoration: BoxDecoration(color: Brand.field, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: a.actorName ?? 'System', style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.ink)),
                          TextSpan(text: ' ${activityTypeLabel(a.type)}'),
                        ]),
                        style: const TextStyle(fontSize: 13.5, color: Brand.inkSoft),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(timeAgo(a.createdAt), style: const TextStyle(fontSize: 12, color: Brand.muted)),
                  ]),
                  if (a.detail.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(a.detail, style: const TextStyle(fontSize: 13, color: Brand.inkSoft)),
                  ],
                ]),
              ),
            ),
          ]),
        ),
    ]);
  }
}

// ── Pieces ────────────────────────────────────────────────────────────────

final _cardDecoration = BoxDecoration(
  color: Brand.card,
  borderRadius: BorderRadius.circular(Brand.radius),
  border: Border.all(color: Brand.line),
  boxShadow: Brand.shadow,
);

class _DetailHeader extends StatelessWidget implements PreferredSizeWidget {
  const _DetailHeader({required this.title, required this.actions});
  final String title;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        child: SafeArea(
          bottom: false,
          child: Container(
            height: 64,
            padding: const EdgeInsets.only(right: 6),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Brand.line))),
            child: Row(children: [
              IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 21, color: Brand.inkSoft),
                onPressed: () => Navigator.maybePop(context),
              ),
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Brand.ink, borderRadius: BorderRadius.circular(10)),
                child: const Text('TF', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: Brand.ink)),
              ),
              ...actions,
            ]),
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.fg, required this.bg, this.icon, this.onTap});
  final String label;
  final Color fg;
  final Color bg;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 5)],
        Flexible(
          child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
        ),
      ]),
    );
    if (onTap == null) return chip;
    return Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(99), onTap: onTap, child: chip));
  }
}

enum _Kind { primary, secondary, success, danger }

class _ActionButton extends StatelessWidget {
  const _ActionButton({super.key, required this.label, required this.icon, required this.onPressed, this.kind = _Kind.secondary});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final _Kind kind;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (kind) {
      _Kind.primary => (Brand.primary, Colors.white),
      _Kind.success => (TF.green, Colors.white),
      _Kind.danger => (Brand.redSoft, Brand.red),
      _Kind.secondary => (Brand.primarySoft, Brand.primaryDeep),
    };
    final filled = kind == _Kind.primary || kind == _Kind.success;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: filled && onPressed != null
            ? [BoxShadow(color: bg.withValues(alpha: 0.28), blurRadius: 12, offset: const Offset(0, 5))]
            : null,
      ),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: bg.withValues(alpha: 0.5),
          disabledForegroundColor: fg.withValues(alpha: 0.7),
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          elevation: 0,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }
}

/// Tinted fact tile (Created by / Assignee / Due / ETA).
class _FactTile extends StatelessWidget {
  const _FactTile({
    required this.icon,
    required this.label,
    required this.value,
    this.avatar,
    this.sub,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.accent = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final String? avatar;
  final String? sub;
  final IconData? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Brand.red : (accent ? Brand.primaryDeep : Brand.ink);
    final labelColor = accent ? Brand.primaryDeep : Brand.inkSoft;
    return Material(
      color: Brand.field,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 16, color: labelColor),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: labelColor))),
              if (trailing != null) Icon(trailing, size: 15, color: Brand.muted),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              if (avatar != null) ...[Avatar(avatar, size: 28), const SizedBox(width: 8)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: color, height: 1.25)),
                  if (sub != null)
                    Text(sub!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: danger ? Brand.red : (onTap != null ? Brand.primary : Brand.muted),
                          fontWeight: onTap != null || danger ? FontWeight.w600 : FontWeight.w400,
                        )),
                ]),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Tinted notice card with an icon bubble ("Blocked", "Information requested", …).
class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.text, required this.fg, required this.bg, required this.icon});
  final String title;
  final String text;
  final Color fg;
  final Color bg;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Brand.radius),
          border: Border.all(color: fg.withValues(alpha: 0.15)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: fg.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Brand.ink)),
              const SizedBox(height: 4),
              SelectableText(text, style: TextStyle(fontSize: 14.5, height: 1.4, color: fg)),
            ]),
          ),
        ]),
      );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.icon, required this.title, required this.children, this.trailing});
  final IconData icon;
  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        decoration: _cardDecoration,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, size: 22, color: Brand.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: Brand.ink)),
            ),
            ?trailing,
          ]),
          const SizedBox(height: 14),
          ...children,
        ]),
      );
}
