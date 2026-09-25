import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/task_logic.dart';
import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Runs a PATCH /tasks/:id action. Handles the "open subtasks" override prompt.
/// Returns true when the task changed.
Future<bool> runTaskAction(BuildContext context, int taskId, String action, [Map<String, dynamic> extra = const {}]) async {
  final api = Get.find<TaskFlowApi>();
  try {
    await api.taskAction(taskId, action, extra);
    toast(taskActionToast[action] ?? 'Task updated');
    return true;
  } on ApiException catch (e) {
    if (e.code == 'OPEN_SUBTASKS' && context.mounted) {
      final reason = await promptText(
        context,
        title: 'Open subtasks',
        message: '${e.message}\n\nCreator/Admin override — enter a reason:',
        confirmLabel: 'Override',
      );
      if (reason != null && context.mounted) {
        return runTaskAction(context, taskId, action, {...extra, 'overrideReason': reason});
      }
      return false;
    }
    toastError(e, 'Action failed');
    return false;
  }
}

Future<bool?> showStatusSheet(BuildContext context, Task task) =>
    showAppSheet<bool>(context, builder: (_) => StatusSheet(task: task));

enum _View { actions, ack, reason, eta, requestInput }

class StatusSheet extends StatefulWidget {
  const StatusSheet({super.key, required this.task});
  final Task task;

  @override
  State<StatusSheet> createState() => _StatusSheetState();
}

class _StatusSheetState extends State<StatusSheet> {
  TaskDetail? detail;
  String? error;
  bool busy = false;
  _View view = _View.actions;
  String pendingAction = '';
  final reasonCtrl = TextEditingController();
  final explanationCtrl = TextEditingController();
  final requestCtrl = TextEditingController();
  final payloadCtrl = TextEditingController();
  DateTime? eta;
  DateTime? proposedEta;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Get.find<TaskFlowApi>().task(widget.task.id);
      if (mounted) setState(() => detail = d);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e, 'Failed to load task'));
    }
  }

  Future<void> _act(String action, [Map<String, dynamic> extra = const {}]) async {
    setState(() => busy = true);
    final ok = await runTaskAction(context, widget.task.id, action, extra);
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) Navigator.pop(context, true);
  }

  Future<void> _escalation(Future<void> Function(TaskFlowApi api) run, String success) async {
    setState(() => busy = true);
    try {
      await run(Get.find<TaskFlowApi>());
      toast(success);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      toastError(e);
      if (mounted) setState(() => busy = false);
    }
  }

  void _openReason(String action) => setState(() {
        pendingAction = action;
        reasonCtrl.clear();
        view = _View.reason;
      });

  String get _reasonTitle => switch (pendingAction) {
        'block' => 'What is blocking you?',
        'reopen' => 'Why reopen this task?',
        'reject' => 'Why reject this task?',
        'discuss' => 'What should be discussed? (optional)',
        _ => 'Why cancel this task?',
      };

  @override
  Widget build(BuildContext context) {
    final t = detail?.task ?? widget.task;
    final perm = detail?.permissions;
    final esc = detail?.escalation;
    final isEscalated = t.status == 'ESCALATED';
    final showReview = perm != null && perm.canReview && (esc?.explanation?.isNotEmpty ?? false) && isEscalated;
    final showProvide = perm != null && perm.canProvideInput && t.status == 'WAITING_FOR_INPUT';
    final showResume = perm != null && perm.canResumeAfterInput && t.status == 'INPUT_PROVIDED';
    final title = perm?.mustExplain == true
        ? 'Explanation required'
        : showReview
            ? 'Review escalation'
            : showProvide
                ? 'Provide information'
                : showResume
                    ? 'Review provided data'
                    : 'Change status';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(t.title, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          Row(children: [
            Text('CURRENT  ', style: Theme.of(context).textTheme.labelSmall),
            StatusPill(t.status),
          ]),
          const SizedBox(height: 16),
          if (error != null) InfoBanner(text: error!, fg: TF.coral, bg: TF.coralSoft, icon: Icons.error_outline),
          if (detail == null && error == null) const SkeletonList(count: 2, height: 46),
          if (perm != null) ...[
            if (perm.mustExplain) _explainCard(),
            if (showReview) _reviewCard(esc!),
            if (showProvide) _provideCard(t),
            if (showResume) _resumeCard(t),
            if (t.status == 'WAITING_FOR_INPUT' && perm.canActAsAssignee && !showProvide)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InfoBanner(
                  icon: Icons.hourglass_top_rounded,
                  text: 'Waiting for the task creator or Admin to provide: ${t.inputRequestNote ?? 'requested information'}',
                ),
              ),
            if (!perm.mustExplain && !showProvide && !showResume) _body(t, perm),
          ],
        ]),
      ),
    );
  }

  Widget _body(Task t, TaskPermissions perm) {
    switch (view) {
      case _View.actions:
        final buttons = _actionButtons(t, perm);
        if (buttons.isEmpty) {
          return Text('No status changes available for you on this task.', style: Theme.of(context).textTheme.bodySmall);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final b in buttons) Padding(padding: const EdgeInsets.only(bottom: 8), child: b),
        ]);
      case _View.ack:
        return _form(
          intro: 'An ETA is mandatory when accepting this task.',
          field: DateTimeField(
            value: eta,
            onChanged: (d) => setState(() => eta = d),
            label: 'Pick your ETA',
            quick: const [('eod', 'Today EOD'), ('24h', '+24 hours'), ('48h', '+2 days')],
          ),
          submitLabel: 'Accept',
          onSubmit: () {
            if (eta == null) return toast('Set your ETA — it is mandatory');
            _act('acknowledge', {'etaAt': eta!.millisecondsSinceEpoch});
          },
        );
      case _View.reason:
        return _form(
          intro: _reasonTitle,
          field: TextField(key: const Key('reason-field'), controller: reasonCtrl, minLines: 3, maxLines: 5),
          submitLabel: 'Confirm',
          onSubmit: () {
            final r = reasonCtrl.text.trim();
            if (pendingAction == 'discuss') {
              _act('discuss', {if (r.isNotEmpty) 'reason': r});
              return;
            }
            if (r.isEmpty) return toast('A reason is required');
            _act(pendingAction, {'reason': r});
          },
        );
      case _View.eta:
        return _form(
          intro: t.status == 'ESCALATED' ? 'The due date will be updated to match this ETA.' : 'Pick a new ETA.',
          field: DateTimeField(value: eta, onChanged: (d) => setState(() => eta = d), label: 'Pick ETA'),
          submitLabel: 'Save ETA',
          onSubmit: () {
            if (eta == null) return toast('Pick an ETA');
            _act('update_eta', {'etaAt': eta!.millisecondsSinceEpoch});
          },
        );
      case _View.requestInput:
        return _form(
          intro: 'Describe exactly what you need (credentials, access, files, etc.). This will be visible to the person who provides it.',
          field: TextField(
            key: const Key('request-input-field'),
            controller: requestCtrl,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(hintText: 'Example: Need SMTP host, port, user and app password'),
          ),
          submitLabel: 'Send request',
          onSubmit: () {
            final note = requestCtrl.text.trim();
            if (note.length < 10) return toast('Describe what you need (at least 10 characters)');
            _act('request_input', {'inputRequestNote': note});
          },
        );
    }
  }

  List<Widget> _actionButtons(Task t, TaskPermissions perm) {
    Widget primary(String label, VoidCallback onTap, {Color? color, IconData? icon}) => FilledButton.icon(
          key: ValueKey('action-$label'),
          style: color == null ? null : FilledButton.styleFrom(backgroundColor: color),
          onPressed: busy ? null : onTap,
          icon: Icon(icon ?? Icons.arrow_forward_rounded, size: 18),
          label: Text(label),
        );
    Widget secondary(String label, VoidCallback onTap, {bool danger = false, IconData? icon}) => OutlinedButton.icon(
          key: ValueKey('action-$label'),
          style: danger ? OutlinedButton.styleFrom(foregroundColor: TF.coral) : null,
          onPressed: busy ? null : onTap,
          icon: Icon(icon ?? Icons.chevron_right_rounded, size: 18),
          label: Text(label),
        );
    void editEta() => setState(() {
          eta = t.etaAt;
          view = _View.eta;
        });

    final out = <Widget>[];
    if (t.status == 'ESCALATED') {
      if (perm.canReject) out.add(secondary('Reject', () => _openReason('reject'), danger: true, icon: Icons.close_rounded));
      if (perm.canDone) out.add(primary('Mark done', () => _act('done'), color: TF.green, icon: Icons.check_rounded));
      if (perm.canCancel) out.add(secondary('Cancel task', () => _openReason('cancel'), danger: true, icon: Icons.cancel_outlined));
      if (perm.canStart) out.add(primary('Mark in progress', () => _act('start'), icon: Icons.play_arrow_rounded));
      if (perm.canEditEta) out.add(secondary('Update ETA', editEta, icon: Icons.schedule_rounded));
      return out;
    }
    if (perm.canAcknowledge) {
      out.add(primary('Accept + ETA', () => setState(() {
            eta = null;
            view = _View.ack;
          }), icon: Icons.handshake_outlined));
    }
    if (perm.canDiscuss) out.add(secondary('Discuss', () => _openReason('discuss'), icon: Icons.forum_outlined));
    if (perm.canReject) out.add(secondary('Reject', () => _openReason('reject'), danger: true, icon: Icons.close_rounded));
    if (perm.canStart) out.add(primary('Start', () => _act('start'), icon: Icons.play_arrow_rounded));
    if (perm.canRequestInput) {
      out.add(secondary('Request information', () => setState(() => view = _View.requestInput), icon: Icons.help_outline_rounded));
    }
    if (perm.canDone) out.add(primary('Mark done', () => _act('done'), color: TF.green, icon: Icons.check_rounded));
    if (perm.canBlock && !t.isBlocked) out.add(secondary('Mark blocked', () => _openReason('block'), icon: Icons.block_rounded));
    if (t.isBlocked && perm.canUnblock) out.add(secondary('Unblock', () => _act('unblock'), icon: Icons.lock_open_rounded));
    if (perm.canReopen) out.add(secondary('Reopen', () => _openReason('reopen'), icon: Icons.replay_rounded));
    if (perm.canCancel) out.add(secondary('Cancel task', () => _openReason('cancel'), danger: true, icon: Icons.cancel_outlined));
    if (perm.canEditEta) out.add(secondary('Update ETA', editEta, icon: Icons.schedule_rounded));
    return out;
  }

  Widget _form({required String intro, required Widget field, required String submitLabel, required VoidCallback onSubmit}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(intro, style: const TextStyle(fontWeight: FontWeight.w600, color: TF.inkSoft)),
      const SizedBox(height: 12),
      field,
      const SizedBox(height: 16),
      Row(children: [
        OutlinedButton(onPressed: busy ? null : () => setState(() => view = _View.actions), child: const Text('Back')),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            key: const Key('status-submit'),
            onPressed: busy ? null : onSubmit,
            child: Text(busy ? 'Saving…' : submitLabel),
          ),
        ),
      ]),
    ]);
  }

  Widget _explainCard() => ExplainEscalationCard(
        busy: busy,
        controller: explanationCtrl,
        proposedEta: proposedEta,
        onEta: (d) => setState(() => proposedEta = d),
        onSubmit: () => _escalation(
          (api) => api.submitEscalationExplanation(widget.task.id, explanationCtrl.text.trim(), proposedEta),
          'Explanation submitted',
        ),
      );

  Widget _reviewCard(Escalation esc) => ReviewEscalationCard(
        escalation: esc,
        busy: busy,
        canReview: true,
        onReview: (r) => _escalation(
          (api) => api.reviewEscalation(widget.task.id, r),
          r == 'ACCEPTED' ? 'Escalation accepted' : 'Escalation rejected',
        ),
      );

  Widget _provideCard(Task t) => ProvideInputCard(
        task: t,
        controller: payloadCtrl,
        busy: busy,
        onSubmit: () {
          final p = payloadCtrl.text.trim();
          if (p.isEmpty) return toast('Enter the requested information');
          _act('provide_input', {'inputPayload': p});
        },
      );

  Widget _resumeCard(Task t) => Surface(
        color: TF.greenSoft,
        borderColor: TF.green.withValues(alpha: 0.3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Data provided', style: TextStyle(fontWeight: FontWeight.w800, color: TF.green)),
          if (t.inputRequestNote != null) ...[
            const SizedBox(height: 6),
            Text('Request: ${t.inputRequestNote}', style: const TextStyle(fontSize: 12.5, color: TF.inkSoft)),
          ],
          if (t.inputPayload != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              child: SelectableText(t.inputPayload!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(onPressed: busy ? null : () => _act('resume_after_input'), child: const Text('Continue working')),
        ]),
      );
}

class ExplainEscalationCard extends StatelessWidget {
  const ExplainEscalationCard({
    super.key,
    required this.busy,
    required this.controller,
    required this.proposedEta,
    required this.onEta,
    required this.onSubmit,
  });

  final bool busy;
  final TextEditingController controller;
  final DateTime? proposedEta;
  final ValueChanged<DateTime?> onEta;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Surface(
        color: TF.coralSoft,
        borderColor: TF.coral.withValues(alpha: 0.35),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Icon(Icons.warning_amber_rounded, color: TF.coral, size: 20),
            SizedBox(width: 8),
            Text('Explanation required', style: TextStyle(fontWeight: FontWeight.w800, color: TF.coral, fontSize: 15)),
          ]),
          const SizedBox(height: 6),
          const Text(
            'Submit a written explanation (min 20 characters) and propose a new ETA before doing anything else.',
            style: TextStyle(fontSize: 13, color: TF.inkSoft),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('explanation-field'),
            controller: controller,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(hintText: 'Why was this task delayed?'),
          ),
          const SizedBox(height: 10),
          DateTimeField(value: proposedEta, onChanged: onEta, label: 'Proposed new ETA'),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('submit-explanation'),
            style: FilledButton.styleFrom(backgroundColor: TF.coral),
            onPressed: busy ? null : onSubmit,
            child: Text(busy ? 'Submitting…' : 'Submit explanation'),
          ),
        ]),
      );
}

class ReviewEscalationCard extends StatelessWidget {
  const ReviewEscalationCard({super.key, required this.escalation, required this.busy, required this.canReview, required this.onReview});

  final Escalation escalation;
  final bool busy;
  final bool canReview;
  final ValueChanged<String> onReview;

  @override
  Widget build(BuildContext context) => Surface(
        color: TF.amberSoft,
        borderColor: TF.amber.withValues(alpha: 0.35),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Escalation explanation', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF8A5A0B))),
          const SizedBox(height: 6),
          SelectableText(escalation.explanation ?? '', style: const TextStyle(color: TF.ink)),
          const SizedBox(height: 6),
          Text(
            'Proposed ETA: ${fmtDateTime(escalation.proposedEtaAt)} · submitted ${timeAgo(escalation.explanationAt)}',
            style: const TextStyle(fontSize: 12, color: TF.muted),
          ),
          if (canReview) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton(
                  key: const Key('review-accept'),
                  onPressed: busy ? null : () => onReview('ACCEPTED'),
                  child: const Text('Accept & re-plan'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const Key('review-reject'),
                  style: FilledButton.styleFrom(backgroundColor: TF.coral),
                  onPressed: busy ? null : () => onReview('REJECTED'),
                  child: const Text('Reject'),
                ),
              ),
            ]),
          ],
          if (escalation.reviewStatus != null && escalation.reviewStatus != 'PENDING') ...[
            const SizedBox(height: 8),
            Text(escalation.reviewStatus!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          ],
        ]),
      );
}

class ProvideInputCard extends StatelessWidget {
  const ProvideInputCard({super.key, required this.task, required this.controller, required this.busy, required this.onSubmit});

  final Task task;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Surface(
        color: const Color(0xFFE0F4F8),
        borderColor: const Color(0xFF0E7490).withValues(alpha: 0.3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Information requested', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0E7490))),
          if (task.inputRequestNote != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              child: SelectableText(task.inputRequestNote!),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            key: const Key('provide-input-field'),
            controller: controller,
            minLines: 4,
            maxLines: 8,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(hintText: 'SMTP_HOST=smtp.gmail.com\nSMTP_PORT=587'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('submit-input'),
            onPressed: busy ? null : onSubmit,
            child: Text(busy ? 'Saving…' : 'Submit information'),
          ),
        ]),
      );
}
