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
import '../../widgets/brand_ui.dart';
import '../../widgets/common.dart';
import '../chat/chat_screen.dart';
import '../projects/project_detail_screen.dart';
import 'comments_panel.dart';
import 'composer_sheet.dart';
import 'reassign_sheet.dart';
import 'status_sheet.dart';

// Lime-on-navy accents shared with the dashboard.
const _red = brandRed;
const _redSoft = brandRedSoft;
const _redInk = brandRedInk;
const _redPanel = Color(0xFFFEF2F2);
const _amberInk = Color(0xFF92400E);
const _amberSoft = Color(0xFFFFFBEB);
// Text on navy.
const _onNavySoft = Color(0xFFCBD5E1);
const _onNavyRed = Color(0xFFFCA5A5);

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

  // Targets the "Action needed" card scrolls to.
  final _explainKey = GlobalKey();
  final _reviewKey = GlobalKey();
  final _inputKey = GlobalKey();

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

  Future<void> _openStatus(Task t) async {
    if (await showStatusSheet(context, t) == true) _load();
  }

  void _reveal(GlobalKey key) {
    final c = key.currentContext;
    if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 300), alignment: 0.05);
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final me = Get.find<AuthController>().me;
    final chatTarget = d == null ? null : chatTargetForTask(d.task, me?.id);
    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: _DetailHeader(
        title: d == null ? 'Task' : 'Task #${d.task.id}',
        actions: [
          if (d != null) ...[
            if (chatTarget != null)
              IconButton(
                tooltip: 'Chat about this task',
                icon: const Icon(Icons.forum_outlined, color: Brand.navy),
                onPressed: () => openChatWithUser(context, chatTarget, attachTask: d.task),
              ),
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded, color: Brand.navy), onPressed: _load),
          ],
        ],
      ),
      body: error != null && d == null
          ? ErrorView(message: error!, onRetry: _load)
          : d == null
              ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 4, height: 110))
              : LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth >= 980;
                  final need = _need(d, me, wide);
                  final details = _details(d, need);
                  final comments = CommentsPanel(taskId: d.task.id, onChanged: _load, canComment: d.permissions.canComment);
                  final Widget body;
                  if (wide) {
                    body = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(flex: 6, child: details),
                      const VerticalDivider(width: 1, color: Brand.outline),
                      Expanded(
                        flex: 5,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            if (d.permissions.canViewActivity) ...[
                              BrandSectionTitle(title: 'Activity', count: d.activity.length),
                              Container(
                                height: 220,
                                clipBehavior: Clip.antiAlias,
                                decoration: _cardDecoration,
                                child: _activityPanel(d),
                              ),
                              const SizedBox(height: 16),
                            ],
                            BrandSectionTitle(title: 'Comments', count: d.task.commentCount),
                            Expanded(
                              child: Container(clipBehavior: Clip.antiAlias, decoration: _cardDecoration, child: comments),
                            ),
                          ]),
                        ),
                      ),
                    ]);
                  } else {
                    body = DefaultTabController(
                      length: d.permissions.canViewActivity ? 3 : 2,
                      child: Column(children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Container(
                            height: 42,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Brand.outline),
                            ),
                            child: TabBar(
                              dividerColor: Colors.transparent,
                              indicatorSize: TabBarIndicatorSize.tab,
                              indicator: BoxDecoration(color: Brand.navy, borderRadius: BorderRadius.circular(9)),
                              labelColor: Brand.lime,
                              unselectedLabelColor: Brand.onVariant,
                              labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                              unselectedLabelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
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
                  }
                  return body;
                }),
    );
  }

  /// What the viewer has to do on this task, shown as the navy "Action needed" card.
  _Need? _need(TaskDetail d, Me? me, bool wide) {
    final t = d.task;
    final p = d.permissions;
    final void Function(BuildContext)? toComments = wide ? null : (ctx) => DefaultTabController.maybeOf(ctx)?.animateTo(1);
    if (p.mustExplain) {
      return _Need(
        kind: 'explain',
        icon: Icons.report_gmailerrorred_rounded,
        title: 'Explanation required',
        text: 'This task was escalated. Explain the delay and propose a new ETA before doing anything else.',
        label: 'Explain delay',
        run: (_) => _reveal(_explainKey),
      );
    }
    final esc = d.escalation;
    if (p.canReview && t.status == 'ESCALATED' && esc?.explanation != null && (esc!.reviewStatus == null || esc.reviewStatus == 'PENDING')) {
      return _Need(
        kind: 'review',
        icon: Icons.gavel_rounded,
        title: 'Escalation review',
        text: 'The assignee explained the delay. Accept the new plan or reject it.',
        label: 'Review',
        run: (_) => _reveal(_reviewKey),
      );
    }
    if (p.canProvideInput && t.status == 'WAITING_FOR_INPUT') {
      return _Need(
        kind: 'input',
        icon: Icons.key_outlined,
        title: 'Action Needed',
        text: t.inputRequestNote ?? 'The assignee needs information to continue.',
        label: 'Provide Info',
        run: (_) => _reveal(_inputKey),
      );
    }
    if (!taskNeedsActionForViewer(t, me)) return null;
    if (t.isBlocked) {
      return _Need(
        kind: 'blocked',
        icon: Icons.block_rounded,
        title: 'Task is blocked',
        text: t.blockedReason!,
        label: p.canUnblock ? 'Unblock' : (toComments == null ? null : 'Reply'),
        run: p.canUnblock ? (_) => _act('unblock') : toComments,
      );
    }
    if (t.status == 'DISCUSS') {
      return _Need(
        kind: 'discuss',
        icon: Icons.forum_outlined,
        title: 'Discussion requested',
        text: t.discussReason ?? 'The assignee wants to discuss this task before accepting it.',
        label: toComments == null ? null : 'Reply',
        run: toComments,
      );
    }
    if (t.status == 'REJECTED') {
      final canReassign = canReassignTask(t, me);
      return _Need(
        kind: 'rejected',
        icon: Icons.cancel_outlined,
        title: 'Task rejected',
        text: t.cancelReason ?? 'The assignee rejected this task.',
        label: canReassign ? 'Reassign' : null,
        run: canReassign
            ? (_) async {
                if (await showReassignSheet(context, t) == true) _load();
              }
            : null,
      );
    }
    return null;
  }

  Widget _details(TaskDetail d, _Need? need) {
    final t = d.task;
    final p = d.permissions;
    final me = Get.find<AuthController>().me;
    final fileAttachments = d.attachments.where((a) => a.context != 'description').toList();

    final action = <Widget>[
      if (need != null) _NeedCard(need: need, busy: busy),
      if (p.mustExplain)
        KeyedSubtree(
          key: _explainKey,
          child: ExplainEscalationCard(
            busy: busy,
            controller: explanationCtrl,
            proposedEta: proposedEta,
            onEta: (v) => setState(() => proposedEta = v),
            onSubmit: () => _escalation(
              () => api.submitEscalationExplanation(t.id, explanationCtrl.text.trim(), proposedEta),
              'Explanation submitted',
            ),
          ),
        ),
      if (d.escalation?.explanation != null && t.status == 'ESCALATED')
        KeyedSubtree(
          key: _reviewKey,
          child: ReviewEscalationCard(
            escalation: d.escalation!,
            busy: busy,
            canReview: p.canReview,
            onReview: (r) => _escalation(
              () => api.reviewEscalation(t.id, r),
              r == 'ACCEPTED' ? 'Escalation accepted' : 'Escalation rejected',
            ),
          ),
        ),
      if (p.canProvideInput && t.status == 'WAITING_FOR_INPUT')
        KeyedSubtree(
          key: _inputKey,
          child: ProvideInputCard(
            task: t,
            controller: payloadCtrl,
            busy: busy,
            onSubmit: () {
              final v = payloadCtrl.text.trim();
              if (v.isEmpty) return toast('Enter the requested information');
              _act('provide_input', {'inputPayload': v});
            },
          ),
        ),
    ];

    return RefreshIndicator(
      color: Brand.navy,
      backgroundColor: Brand.lime,
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: [
        _hero(d, need, me),
        if (action.isNotEmpty) ...[
          const SizedBox(height: 20),
          const BrandSectionTitle(title: 'Action needed'),
          for (var i = 0; i < action.length; i++) ...[if (i > 0) const SizedBox(height: 10), action[i]],
        ],
        const SizedBox(height: 20),
        const BrandSectionTitle(title: 'Details'),
        _detailsCard(d, need),
        if (t.parentId == null) ...[
          const SizedBox(height: 20),
          _subtasks(d, me),
        ],
        if (fileAttachments.isNotEmpty) ...[
          const SizedBox(height: 20),
          BrandSectionTitle(
            title: 'Attachments',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Tap to inspect', style: TextStyle(fontSize: 11, color: Brand.onVariant)),
              const SizedBox(width: 8),
              CountBubble(fileAttachments.length),
            ]),
          ),
          BrandCard(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < fileAttachments.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: fileAttachments[i].isImage
                      ? AttachmentTile(attachment: fileAttachments[i])
                      : _FileRow(attachment: fileAttachments[i], index: i),
                ),
            ]),
          ),
        ],
        _members(d),
      ]),
    );
  }

  /// Navy hero: chips, title, people, due/ETA, SLA and the primary actions.
  Widget _hero(TaskDetail d, _Need? need, Me? me) {
    final t = d.task;
    final p = d.permissions;
    final overdue = isTaskOverdue(t);
    final etaHistory = d.activity.where((a) => a.type == 'ETA_CHANGED').toList();
    final canReassign = canReassignTask(t, me);
    final breached = t.slaBreachedAt != null;
    final sla = t.status == 'ASSIGNED' && (breached || t.slaDeadlineAt != null);
    final actionable = need != null || p.canAcknowledge;
    final etaSub = t.etaAt == null
        ? (t.status == 'ASSIGNED' ? 'Required on accept' : null)
        : [fmtTime(t.etaAt), if (etaHistory.isNotEmpty) 'history (${etaHistory.length})'].join(' · ');

    return HeroCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: HeroEyebrow(['Task #${t.id}', if (t.typeName != null) t.typeName!].join(' · '))),
          if (actionable) ...[const SizedBox(width: 8), const Flexible(child: LivePill(label: 'ACTION NEEDED'))],
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _StatusChip(status: t.status, onTap: () => _openStatus(t)),
          _priorityChip(t.priority),
          if (t.isBlocked) const _Chip('Blocked', fg: Color(0xFFFCD34D), bg: Color(0x33F59E0B), icon: Icons.block_rounded),
          if (t.reopenCount > 0)
            _Chip('Reopened ×${t.reopenCount}', fg: Colors.white, bg: Colors.white.withValues(alpha: 0.1), icon: Icons.replay_rounded),
          if (t.projectName != null)
            _Chip(
              t.projectName!,
              fg: Colors.white,
              bg: Colors.white.withValues(alpha: 0.1),
              border: Colors.white.withValues(alpha: 0.12),
              icon: Icons.folder_open_outlined,
              iconColor: Brand.lime,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(projectId: t.projectId!))),
            ),
        ]),
        const SizedBox(height: 12),
        SelectableText(t.title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.2, color: Colors.white)),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _HeroFact(
              icon: Icons.person_outline_rounded,
              label: 'From',
              avatar: t.creatorName,
              value: t.creatorName == null ? '—' : displayName(t.creatorName),
              sub: _roleOf(t.creatorName) ?? (t.createdAt == null ? null : 'Created ${timeAgo(t.createdAt)}'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _HeroFact(
              icon: Icons.assignment_ind_outlined,
              label: 'Assignee',
              avatar: t.assigneeName ?? t.teamName,
              value: t.assigneeName != null ? displayName(t.assigneeName) : (t.teamName != null ? 'Team: ${t.teamName}' : '—'),
              sub: t.assigneeName != null ? (_roleOf(t.assigneeName) ?? t.teamName) : null,
              trailing: canReassign ? Icons.edit_outlined : null,
              onTap: canReassign
                  ? () async {
                      if (await showReassignSheet(context, t) == true) _load();
                    }
                  : null,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _HeroFact(
              icon: Icons.event_outlined,
              label: 'Due date',
              value: fmtDate(t.dueAt),
              sub: t.dueAt == null ? null : (overdue ? 'Overdue · ${fmtTime(t.dueAt)}' : fmtTime(t.dueAt)),
              danger: overdue,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _HeroFact(
              icon: Icons.hourglass_bottom_rounded,
              label: 'Current ETA',
              value: t.etaAt == null ? 'Not specified' : fmtDate(t.etaAt),
              sub: etaSub,
              accent: true,
              trailing: etaHistory.isEmpty ? null : (showEtaHistory ? Icons.expand_less_rounded : Icons.expand_more_rounded),
              onTap: etaHistory.isEmpty ? null : () => setState(() => showEtaHistory = !showEtaHistory),
            ),
          ),
        ]),
        if (showEtaHistory && etaHistory.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final h in etaHistory)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.only(left: 10),
                  decoration: const BoxDecoration(border: Border(left: BorderSide(color: Brand.lime, width: 3))),
                  child: Text(
                    '${h.actorName ?? 'System'}: ${fmtDateTime(toDate(h.meta['from']))} → ${fmtDateTime(toDate(h.meta['to']))} · ${timeAgo(h.createdAt)}',
                    style: const TextStyle(fontSize: 11.5, color: _onNavySoft),
                  ),
                ),
            ]),
          ),
        if (sla) ...[
          const SizedBox(height: 12),
          Row(children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: breached ? _red : Brand.lime, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                breached
                    ? 'No response · acceptance window breached'
                    : '${p.canAcknowledge ? 'New task waiting for acceptance' : 'Waiting for acceptance'} · ${countdown(t.slaDeadlineAt)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: breached ? _onNavyRed : Colors.white),
              ),
            ),
          ]),
        ],
        _actions(d),
      ]),
    );
  }

  Widget _priorityChip(String priority) => switch (priority) {
        'URGENT' => const _Chip('Urgent', fg: Colors.white, bg: _red, icon: Icons.priority_high_rounded),
        'HIGH' => const _Chip('High', fg: _redInk, bg: _redSoft, icon: Icons.priority_high_rounded),
        _ => _Chip(titleCase(priority), fg: Colors.white, bg: Colors.white.withValues(alpha: 0.1), icon: Icons.flag_outlined),
      };

  /// White "Details" card: description, extra facts, batch links and notes.
  Widget _detailsCard(TaskDetail d, _Need? need) {
    final t = d.task;
    final p = d.permissions;
    final descAttachments = d.attachments.where((a) => a.context == 'description').toList();
    const valueStyle = TextStyle(fontSize: 12.5, color: Brand.navy, fontWeight: FontWeight.w600);

    Widget line(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(
              width: 104,
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Brand.onVariant)),
            ),
            Expanded(child: value),
          ]),
        );
    Widget text(String v) => Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: valueStyle);

    final lines = <Widget>[
      if (t.typeName != null) line('Task type', text(t.typeName!)),
      if (t.createdAt != null) line('Created', text(fmtDateTime(t.createdAt))),
      if (t.acknowledgedAt != null) line('Accepted', text(fmtDateTime(t.acknowledgedAt))),
      if (t.doneAt != null) line('Done at', text(fmtDateTime(t.doneAt))),
      if (t.parentId != null)
        line(
          'Parent task',
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () => _onLink('/tasks/${t.parentId}'),
              child: Text('#${t.parentId}', style: valueStyle.copyWith(decoration: TextDecoration.underline)),
            ),
          ),
        ),
    ];

    return BrandCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (t.description.trim().isNotEmpty)
          DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 13, height: 1.5, color: Brand.onVariant),
            child: RichBody(RegExp(r'<[a-zA-Z/][^>]*>').hasMatch(t.description) ? htmlToPlainText(t.description) : t.description,
                onLink: _onLink),
          )
        else
          const Text('No description', style: TextStyle(fontSize: 12.5, color: Brand.faint, fontStyle: FontStyle.italic)),
        for (final a in descAttachments)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: a.isImage ? AttachmentTile(attachment: a, compact: true) : _FileRow(attachment: a, index: 0),
          ),
        if (lines.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: Brand.outline)),
          ...lines,
        ],
        if (d.batchTasks.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 4, children: [
            const Text('Part of a batch:', style: TextStyle(fontSize: 12, color: Brand.onVariant)),
            for (final b in d.batchTasks)
              InkWell(
                onTap: () => _onLink('/tasks/${b.id}'),
                child: Text('#${b.id} ${b.title}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Brand.navy, decoration: TextDecoration.underline)),
              ),
          ]),
        ],
        if (t.isBlocked && need?.kind != 'blocked')
          _Notice(title: 'Blocked', text: t.blockedReason!, fg: _amberInk, bg: _amberSoft, icon: Icons.block_rounded),
        if (t.status == 'REJECTED' && t.cancelReason != null && need?.kind != 'rejected')
          _Notice(title: 'Rejected', text: t.cancelReason!, fg: _redInk, bg: _redSoft, icon: Icons.cancel_outlined),
        if (t.status == 'DISCUSS' && t.discussReason != null && need?.kind != 'discuss')
          _Notice(title: 'Discuss', text: t.discussReason!, fg: Brand.navy, bg: Brand.limeLight, icon: Icons.forum_outlined),
        if (t.inputRequestNote != null && p.canViewInputRequest && need?.kind != 'input')
          _Notice(title: 'Information requested', text: t.inputRequestNote!, fg: _amberInk, bg: _amberSoft, icon: Icons.key_outlined),
        if (t.inputPayload != null && p.canViewInputPayload)
          _Notice(title: 'Provided data', text: t.inputPayload!, fg: Brand.navy, bg: Brand.limeLight, icon: Icons.check_circle_outline_rounded),
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
    final watching = d.members.where((m) => m.role == 'WATCHER').length;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        BrandSectionTitle(
          title: 'Collaborators & Watchers',
          tag: watching > 0 ? '$watching watching' : null,
          count: d.members.isEmpty ? null : d.members.length,
        ),
        BrandCard(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (d.members.isNotEmpty)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final m in d.members)
                    Container(
                      padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
                      decoration: BoxDecoration(
                        color: Brand.surface,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: Brand.outline),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Avatar(m.userName, size: 24),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(displayName(m.userName),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Brand.navy)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: m.role == 'WATCHER' ? Brand.surfaceMid : Brand.limeLight,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(titleCase(m.role), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Brand.navy)),
                        ),
                        if (p.canManageMembers)
                          InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => _act('remove_member', {'userId': m.userId}),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.close_rounded, size: 16, color: _red),
                            ),
                          )
                        else
                          const SizedBox(width: 4),
                      ]),
                    ),
                ]),
              if (canAdd)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('add-member'),
                    style: TextButton.styleFrom(foregroundColor: Brand.navy, padding: const EdgeInsets.symmetric(horizontal: 4)),
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 19),
                    label: const Text('Add collaborator or watcher',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    onPressed: () => _addMember(candidates),
                  ),
                ),
          ]),
        ),
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

  /// Primary bar (lime primary, outlined secondary, square reject/status button)
  /// followed by the remaining actions.
  Widget _actions(TaskDetail d) {
    final t = d.task;
    final p = d.permissions;
    VoidCallback? on(VoidCallback f) => busy ? null : f;
    final acts = <_Act>[
      if (p.canAcknowledge)
        _Act(
          key: const Key('detail-accept'),
          label: 'Accept + Set ETA',
          icon: Icons.verified_outlined,
          kind: _Kind.primary,
          onPressed: on(() => _accept(t)),
        ),
      if (p.canDiscuss)
        _Act(
          id: 'discuss',
          label: 'Discuss',
          icon: Icons.chat_bubble_outline_rounded,
          onPressed: on(() => _reasonAction('discuss', 'What should be discussed? (optional)', optional: true)),
        ),
      if (p.canReject)
        _Act(
          id: 'reject',
          label: 'Reject',
          icon: Icons.close_rounded,
          kind: _Kind.danger,
          onPressed: on(() => _reasonAction('reject', 'Why reject this task?')),
        ),
      if (p.canStart)
        _Act(
          key: const Key('detail-start'),
          label: t.status == 'ESCALATED' ? 'Mark in progress' : 'Start',
          icon: Icons.play_arrow_rounded,
          kind: _Kind.primary,
          onPressed: on(() => _act('start')),
        ),
      if (p.canRequestInput)
        _Act(
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
        _Act(
          label: 'Continue working',
          icon: Icons.play_circle_outline_rounded,
          kind: _Kind.primary,
          onPressed: on(() => _act('resume_after_input')),
        ),
      if (p.canDone)
        _Act(
          key: const Key('detail-done'),
          label: 'Mark done',
          icon: Icons.check_rounded,
          kind: _Kind.primary,
          onPressed: on(() => _act('done')),
        ),
      if (p.canEditEta)
        _Act(
          label: 'Edit ETA',
          icon: Icons.schedule_rounded,
          onPressed: on(() async {
            final v = await pickDateTime(context, initial: t.etaAt ?? DateTime.now());
            if (v != null) _act('update_eta', {'etaAt': v.millisecondsSinceEpoch});
          }),
        ),
      if (p.canBlock && !t.isBlocked)
        _Act(label: 'Blocked', icon: Icons.block_rounded, onPressed: on(() => _reasonAction('block', 'What is blocking you?'))),
      if (t.isBlocked && p.canUnblock) _Act(label: 'Unblock', icon: Icons.lock_open_rounded, onPressed: on(() => _act('unblock'))),
      if (p.canReopen)
        _Act(label: 'Reopen', icon: Icons.replay_rounded, onPressed: on(() => _reasonAction('reopen', 'Why reopen this task?'))),
      if (p.canCancel)
        _Act(
          label: 'Cancel task',
          icon: Icons.delete_outline_rounded,
          kind: _Kind.danger,
          onPressed: on(() => _reasonAction('cancel', 'Why cancel this task?')),
        ),
    ];
    if (acts.isEmpty) return const SizedBox.shrink();

    final primary = acts.where((a) => a.kind == _Kind.primary).firstOrNull;
    final secondary = acts.where((a) => a.id == 'discuss').firstOrNull ?? acts.where((a) => a.kind == _Kind.secondary).firstOrNull;
    final hasBar = primary != null || secondary != null;
    final reject = hasBar ? acts.where((a) => a.id == 'reject').firstOrNull : null;
    final rest = acts.where((a) => a != primary && a != secondary && a != reject).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (hasBar)
          Row(children: [
            if (primary != null) Expanded(flex: 3, child: _ActionButton(act: primary, style: _Style.lime)),
            if (primary != null && secondary != null) const SizedBox(width: 8),
            if (secondary != null) Expanded(flex: 2, child: _ActionButton(act: secondary, style: _Style.ghost)),
            const SizedBox(width: 8),
            _SquareButton(
              tooltip: reject != null ? 'Reject' : 'Change status',
              icon: reject != null ? Icons.close_rounded : Icons.more_horiz_rounded,
              danger: reject != null,
              onPressed: reject != null ? reject.onPressed : on(() => _openStatus(t)),
            ),
          ]),
        if (rest.isNotEmpty) ...[
          if (hasBar) const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in rest)
              _ActionButton(
                act: a,
                compact: true,
                style: switch (a.kind) {
                  _Kind.primary => _Style.lime,
                  _Kind.danger => _Style.danger,
                  _Kind.secondary => _Style.ghost,
                },
              ),
          ]),
        ],
      ]),
    );
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
              const BrandSectionTitle(title: 'Accept & set ETA', padding: EdgeInsets.only(bottom: 6)),
              Text('You are accepting "${t.title}". An ETA is mandatory.',
                  maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Brand.onVariant)),
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
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.lime,
                  foregroundColor: Brand.navy,
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  if (eta == null) return toast('Set your ETA — it is mandatory');
                  Navigator.pop(ctx, true);
                },
                child: const Text('Accept with this ETA', style: TextStyle(fontWeight: FontWeight.w800)),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      BrandSectionTitle(
        title: 'Subtasks',
        tag: d.subtasks.isEmpty ? null : '$done/${d.subtasks.length} completed',
        count: d.subtasks.length,
      ),
      BrandCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (d.subtasks.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99), border: Border.all(color: Brand.navy, width: 1.5)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(value: pct / 100, minHeight: 6, backgroundColor: Colors.white, color: Brand.lime),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (d.subtasks.isEmpty) const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('No subtasks yet.', style: TextStyle(color: Brand.onVariant, fontSize: 12.5)),
            ),
          for (final s in d.subtasks)
            Container(
              key: ValueKey('subtask-${s.id}'),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Brand.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Brand.outline),
              ),
              child: Row(children: [
                Checkbox(
                  value: s.status == 'DONE',
                  fillColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? Brand.navy : Colors.white),
                  checkColor: Brand.lime,
                  side: const BorderSide(color: Brand.onVariant, width: 1.5),
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
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              decoration: s.status == 'DONE' ? TextDecoration.lineThrough : null,
                              color: s.status == 'DONE' ? Brand.faint : Brand.navy,
                            )),
                        const SizedBox(height: 3),
                        Row(children: [
                          Icon(
                              s.status == 'DONE'
                                  ? Icons.check_circle_outline_rounded
                                  : (s.assigneeName == null ? Icons.schedule_rounded : Icons.account_circle_outlined),
                              size: 14,
                              color: Brand.onVariant),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              s.status == 'DONE'
                                  ? [
                                      s.assigneeName == null ? 'Completed' : 'Completed by ${firstName(s.assigneeName)}',
                                      if (s.doneAt != null) fmtDateTime(s.doneAt),
                                    ].join(' · ')
                                  : (s.assigneeName == null ? 'Unassigned' : 'Assignee: ${displayName(s.assigneeName)}'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: Brand.onVariant),
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
                    icon: const Icon(Icons.person_outline_rounded, size: 19, color: Brand.onVariant),
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
                style: TextButton.styleFrom(foregroundColor: Brand.navy, padding: const EdgeInsets.symmetric(horizontal: 4)),
                onPressed: () async {
                  final ids = await showComposer(context, presetParentId: d.task.id);
                  if (ids != null) _load();
                },
                icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                label: const Text('Add Subtask', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _activityPanel(TaskDetail d) {
    if (d.activity.isEmpty) return const Center(child: Text('No activity yet.', style: TextStyle(color: Brand.onVariant)));
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
                decoration: BoxDecoration(
                  color: Brand.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Brand.outline),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: displayName(a.actorName ?? 'System'), style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.navy)),
                          TextSpan(text: ' ${activityTypeLabel(a.type)}'),
                        ]),
                        style: const TextStyle(fontSize: 12.5, color: Brand.onVariant),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(timeAgo(a.createdAt), style: const TextStyle(fontSize: 11.5, color: Brand.onVariant)),
                  ]),
                  if (a.detail.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(a.detail, style: const TextStyle(fontSize: 12, color: Brand.onVariant)),
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

/// "Suresh Kumar (Sales Head)" -> "Sales Head".
String? _roleOf(String? name) => RegExp(r'\(([^)]+)\)\s*$').firstMatch(name ?? '')?.group(1);

final _cardDecoration = BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: Brand.outline),
  boxShadow: [BoxShadow(color: Brand.navy.withValues(alpha: 0.04), blurRadius: 3, offset: const Offset(0, 1))],
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
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Brand.outline))),
            child: Row(children: [
              IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 21, color: Brand.navy),
                onPressed: () => Navigator.maybePop(context),
              ),
              const AppLogo(size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: Brand.navy)),
              ),
              ...actions,
            ]),
          ),
        ),
      );
}

/// Lime status chip on the navy hero; opens the status sheet.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.onTap});
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        key: ValueKey('status-$status'),
        color: Brand.lime,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Brand.navy, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(statusLabel(status),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Brand.navy)),
              ),
              const Icon(Icons.arrow_drop_down_rounded, size: 17, color: Brand.navy),
            ]),
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.fg, required this.bg, this.icon, this.iconColor, this.onTap, this.border});
  final String label;
  final Color fg;
  final Color bg;
  final Color? border;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: iconColor ?? fg), const SizedBox(width: 4)],
        Flexible(
          child: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ),
      ]),
    );
    if (onTap == null) return chip;
    return Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(99), onTap: onTap, child: chip));
  }
}

enum _Kind { primary, secondary, danger }

/// Button styles on the navy hero.
enum _Style { lime, ghost, danger }

class _Act {
  const _Act({this.key, this.id, required this.label, required this.icon, required this.onPressed, this.kind = _Kind.secondary});
  final Key? key;
  final String? id;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final _Kind kind;
}

class _ActionButton extends StatelessWidget {
  _ActionButton({required this.act, required this.style, this.compact = false}) : super(key: act.key);
  final _Act act;
  final _Style style;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, side) = switch (style) {
      _Style.lime => (Brand.lime, Brand.navy, BorderSide.none),
      _Style.ghost => (Colors.white.withValues(alpha: 0.08), Colors.white, BorderSide(color: Colors.white.withValues(alpha: 0.16))),
      _Style.danger => (_red.withValues(alpha: 0.18), _onNavyRed, BorderSide(color: _red.withValues(alpha: 0.35))),
    };
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg.withValues(alpha: style == _Style.lime ? 0.5 : 0.04),
        disabledForegroundColor: fg.withValues(alpha: 0.5),
        minimumSize: Size(0, compact ? 36 : 44),
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 10 : 12), side: side),
        textStyle: TextStyle(fontSize: compact ? 12 : 13, fontWeight: style == _Style.lime ? FontWeight.w800 : FontWeight.w700),
        elevation: 0,
      ),
      onPressed: act.onPressed,
      icon: Icon(act.icon, size: compact ? 16 : 18),
      label: Text(act.label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.tooltip, required this.icon, required this.onPressed, this.danger = false});
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: danger ? _red.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.08),
          foregroundColor: danger ? _onNavyRed : Colors.white,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.04),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.4),
          fixedSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: danger ? _red.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.16)),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      );
}

/// Translucent fact tile on the navy hero (From / Assignee / Due date / Current ETA).
class _HeroFact extends StatelessWidget {
  const _HeroFact({
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
  Widget build(BuildContext context) => Material(
        color: Colors.white.withValues(alpha: 0.07),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: accent ? Brand.lime.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.08)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 13, color: accent ? Brand.lime : Colors.white.withValues(alpha: 0.6)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: accent ? Brand.lime : Colors.white.withValues(alpha: 0.6),
                      )),
                ),
                if (trailing != null) Icon(trailing, size: 14, color: Colors.white.withValues(alpha: 0.7)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                if (avatar != null) ...[Avatar(avatar, size: 24), const SizedBox(width: 7)],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: danger ? _onNavyRed : Colors.white, height: 1.25)),
                    Text(sub ?? ' ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: danger ? _onNavyRed : _onNavySoft,
                          fontWeight: danger ? FontWeight.w600 : FontWeight.w400,
                          decoration: onTap != null && accent ? TextDecoration.underline : null,
                          decorationColor: _onNavySoft,
                        )),
                  ]),
                ),
              ]),
            ]),
          ),
        ),
      );
}

/// What the viewer has to do next ("Action needed" section).
class _Need {
  const _Need({required this.kind, required this.icon, required this.title, required this.text, this.label, this.run});
  final String kind;
  final IconData icon;
  final String title;
  final String text;
  final String? label;
  final void Function(BuildContext)? run;
}

/// Action card: red-tinted for escalations/rejections, lime-edged white otherwise.
class _NeedCard extends StatelessWidget {
  const _NeedCard({required this.need, required this.busy});
  final _Need need;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final hot = need.kind == 'explain' || need.kind == 'review' || need.kind == 'rejected';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hot ? _redPanel : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hot ? _red.withValues(alpha: 0.18) : Brand.limeDim),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: hot ? _red : Brand.navy, borderRadius: BorderRadius.circular(9)),
          child: Icon(need.icon, size: 17, color: hot ? Colors.white : Brand.lime),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(need.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: hot ? _redInk : Brand.navy)),
            const SizedBox(height: 3),
            SelectableText(need.text, style: const TextStyle(fontSize: 12.5, height: 1.4, color: Brand.onVariant)),
            if (need.label != null && need.run != null) ...[
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.lime,
                  foregroundColor: Brand.navy,
                  disabledBackgroundColor: Brand.lime.withValues(alpha: 0.5),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
                onPressed: busy ? null : () => need.run!(context),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(need.label!, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward_rounded, size: 16),
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Tinted note inside the Details card ("Blocked", "Information requested", …).
class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.text, required this.fg, required this.bg, required this.icon});
  final String title;
  final String text;
  final Color fg;
  final Color bg;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: fg.withValues(alpha: 0.15))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 17, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: fg)),
              const SizedBox(height: 3),
              SelectableText(text, style: const TextStyle(fontSize: 12.5, height: 1.4, color: Brand.navy)),
            ]),
          ),
        ]),
      );
}

/// File row: lime/navy icon tile, name + size, navy round open/download button.
class _FileRow extends StatelessWidget {
  const _FileRow({required this.attachment, required this.index});
  final Attachment attachment;
  final int index;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    final dark = index.isOdd;
    final ext = a.fileName.contains('.') ? a.fileName.split('.').last.toUpperCase() : null;
    final meta = [formatBytes(a.size), if (ext != null && ext.length <= 5) ext, if (a.uploaderName != null) displayName(a.uploaderName)]
        .where((s) => s.isNotEmpty)
        .join(' • ');
    return Material(
      color: Brand.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Brand.outline)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openAttachment(context, a),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: dark ? Brand.navy : Brand.lime, borderRadius: BorderRadius.circular(10)),
              child: Icon(a.isAudio ? Icons.graphic_eq_rounded : Icons.description_outlined, color: dark ? Brand.lime : Brand.navy, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.fileName,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: Brand.navy)),
                if (meta.isNotEmpty)
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Brand.onVariant)),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(color: Brand.navy, shape: BoxShape.circle),
              child: const Icon(Icons.download_rounded, size: 17, color: Colors.white),
            ),
          ]),
        ),
      ),
    );
  }
}
