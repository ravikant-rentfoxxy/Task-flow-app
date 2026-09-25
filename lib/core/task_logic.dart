import '../models/models.dart';

const statusLabels = <String, String>{
  'ASSIGNED': 'Accept response',
  'DISCUSS': 'Discuss',
  'ACKNOWLEDGED': 'Accepted',
  'IN_PROGRESS': 'In progress',
  'WAITING_FOR_INPUT': 'Waiting for input',
  'INPUT_PROVIDED': 'Data provided',
  'DONE': 'Done',
  'CANCELLED': 'Cancelled',
  'REJECTED': 'Rejected',
  'ESCALATED': 'Escalated',
};

const priorities = ['URGENT', 'HIGH', 'NORMAL', 'LOW'];

const closedStatuses = {'DONE', 'CANCELLED', 'REJECTED'};

String statusLabel(String status) => statusLabels[status] ?? status;

String activityTypeLabel(String type) =>
    type == 'ACKNOWLEDGED' ? 'accepted' : type.toLowerCase().replaceAll('_', ' ');

String titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

bool isTaskOverdue(Task t, {DateTime? now}) {
  final due = t.dueAt;
  return due != null && due.isBefore(now ?? DateTime.now()) && !closedStatuses.contains(t.status);
}

bool isDueInWindow(Task t, DateTime start, DateTime end) {
  final due = t.dueAt;
  return due != null && !due.isBefore(start) && !due.isAfter(end);
}

/// Assignee flagged discuss / waiting for input / reject / blocked — creator should act.
bool taskNeedsAssignerAction(Task t) =>
    t.status == 'DISCUSS' || t.status == 'WAITING_FOR_INPUT' || t.status == 'REJECTED' || t.isBlocked;

bool taskNeedsEscalationReview(Task t) => t.status == 'ESCALATED' && t.escalationReviewPending;

/// "Action needed" badge for the creator (discuss/block/reject) or Admin/CEO (escalation review).
bool taskNeedsActionForViewer(Task t, Me? viewer) {
  if (viewer == null) return false;
  if (viewer.isAdminOrCeo && taskNeedsEscalationReview(t)) return true;
  if (!taskNeedsAssignerAction(t)) return false;
  return t.creatorId == viewer.id || viewer.isAdminOrCeo;
}

/// Creator, Admin or CEO may change the assignee (and the parent's creator for subtasks).
bool canReassignTask(Task t, Me? viewer, {Task? parent}) {
  if (viewer == null) return false;
  if (closedStatuses.contains(t.status)) return false;
  if (viewer.isAdminOrCeo) return true;
  if (t.creatorId == viewer.id) return true;
  return parent?.creatorId == viewer.id;
}

bool canCreateSubtask(Task t) => t.parentId == null && !closedStatuses.contains(t.status);

bool canDeleteTask(Me? viewer) => viewer?.isAdminOrCeo ?? false;

/// Who to chat with about a task: assignee → creator; everyone else → assignee.
int? chatTargetForTask(Task t, int? viewerId) {
  if (viewerId == null) return null;
  int? target;
  if (t.assigneeId == viewerId) {
    target = t.creatorId;
  } else if (t.assigneeId != null) {
    target = t.assigneeId;
  }
  if (target == null || target == viewerId) return null;
  return target;
}

int subtaskPercent(int done, int total) {
  if (total <= 0) return 0;
  final d = done.clamp(0, total);
  return (100 * d / total).round();
}

String taskViewLink(int taskId) => '[Tap to view](/tasks/$taskId)';

/// Chat message body used when attaching a task to a chat.
String buildTaskMentionBody(Task t, [String userMessage = '']) {
  final lines = <String>['📋 Task', '', t.title.isEmpty ? 'Task' : t.title, '', taskViewLink(t.id)];
  final desc = t.description.trim();
  if (desc.isNotEmpty) lines.addAll(['', desc]);
  final extra = userMessage.trim();
  if (extra.isNotEmpty) lines.addAll(['', extra]);
  return lines.join('\n').trim();
}

/// Chat message sent after creating a task from the chat screen.
String buildTaskCreatedMessage(List<int> ids, {String? title, String? description, List<String>? lines}) {
  final out = <String>['📋 New task assigned'];
  if (ids.length > 1 && (lines?.isNotEmpty ?? false)) {
    for (var i = 0; i < lines!.length && i < ids.length; i++) {
      out.addAll(['', '${i + 1}. ${lines[i]}', taskViewLink(ids[i])]);
    }
  } else if (ids.isNotEmpty) {
    out.addAll(['', title ?? lines?.first ?? 'New task', taskViewLink(ids.first)]);
  }
  final desc = description?.trim() ?? '';
  if (desc.isNotEmpty) out.addAll(['', desc]);
  return out.join('\n').trim();
}

const notificationIcons = <String, String>{
  'ASSIGNED': '📥',
  'DISCUSS': '💬',
  'REJECTED': '✖️',
  'SLA_WARNING': '⏰',
  'SLA_BREACH': '🚨',
  'ESCALATED': '🔺',
  'EXPLANATION': '📝',
  'REVIEW': '⚖️',
  'DONE': '✅',
  'SUBTASK_DONE': '☑️',
  'COMMENT': '💬',
  'ETA_CHANGED': '🕒',
  'DUE_CHANGED': '📅',
  'DUE_SOON': '⏳',
  'REOPENED': '↩️',
  'CANCELLED': '🚫',
  'BLOCKED': '🚧',
  'ACKNOWLEDGED': '👍',
  'PROJECT': '📁',
  'SUBTASK': '➕',
};

const taskActionToast = <String, String>{
  'acknowledge': 'Task accepted',
  'discuss': 'Marked for discussion',
  'reject': 'Task rejected',
  'start': 'Task started',
  'done': 'Task marked done',
  'block': 'Task marked blocked',
  'unblock': 'Task unblocked',
  'reopen': 'Task reopened',
  'cancel': 'Task cancelled',
  'update_eta': 'ETA updated',
  'add_member': 'Member added',
  'remove_member': 'Member removed',
  'reassign': 'Assignee updated',
  'request_input': 'Input requested',
  'provide_input': 'Information provided',
  'resume_after_input': 'Continuing work',
};

/// Text split into plain runs and `[label](href)` links (task descriptions, chat bodies).
sealed class TextPart {}

class PlainPart extends TextPart {
  PlainPart(this.text);
  final String text;
}

class LinkPart extends TextPart {
  LinkPart(this.label, this.href);
  final String label;
  final String href;
}

class MentionPart extends TextPart {
  MentionPart(this.name);
  final String name;
}

final _inlineToken = RegExp(r'(@\[[^\]]+\]\(user:\d+\)|\[[^\]]+\]\([^)]+\))');

List<TextPart> parseRichText(String text) {
  final parts = <TextPart>[];
  var last = 0;
  for (final m in _inlineToken.allMatches(text)) {
    if (m.start > last) parts.add(PlainPart(text.substring(last, m.start)));
    final token = m.group(0)!;
    final mention = RegExp(r'^@\[([^\]]+)\]\(user:\d+\)$').firstMatch(token);
    final link = RegExp(r'^\[([^\]]+)\]\(([^)]+)\)$').firstMatch(token);
    if (mention != null) {
      parts.add(MentionPart(mention.group(1)!));
    } else if (link != null) {
      parts.add(LinkPart(link.group(1)!.trim(), link.group(2)!.trim()));
    } else {
      parts.add(PlainPart(token));
    }
    last = m.end;
  }
  if (last < text.length) parts.add(PlainPart(text.substring(last)));
  return parts;
}

/// `/tasks/12` → 12.
int? taskIdFromHref(String href) => int.tryParse(RegExp(r'^/tasks/(\d+)$').firstMatch(href)?.group(1) ?? '');

String decodeMentionsForDisplay(String text) =>
    text.replaceAllMapped(RegExp(r'@\[([^\]]+)\]\(user:\d+\)'), (m) => '@${m.group(1)}');

/// Turn visible `@Name` snippets into stored mention tokens before sending to a group.
String encodeMentionsForSend(String text, List<({int id, String name})> members) {
  if (members.isEmpty) return text;
  var result = decodeMentionsForDisplay(text);
  final sorted = [...members]..sort((a, b) => b.name.split(' (').first.length.compareTo(a.name.split(' (').first.length));
  for (final m in sorted) {
    final display = m.name.split(' (').first;
    if (display.isEmpty) continue;
    result = result.replaceAllMapped(
      RegExp('@${RegExp.escape(display)}(?=\$|[\\s.,!?;:])'),
      (_) => '@[$display](user:${m.id})',
    );
  }
  return result;
}
