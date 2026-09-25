import 'dart:convert';

import '../core/format.dart';

typedef Json = Map<String, dynamic>;

List<T> _list<T>(dynamic raw, T Function(Json) f) =>
    raw is List ? raw.whereType<Map>().map((e) => f(Map<String, dynamic>.from(e))).toList() : <T>[];

class Me {
  Me({required this.id, required this.name, required this.email, required this.role, this.teamId, this.team});

  final int id;
  final String name;
  final String email;
  final String role;
  final int? teamId;
  final String? team;

  bool get isAdmin => role == 'ADMIN';
  bool get isCeo => role == 'CEO';
  bool get isAdminOrCeo => isAdmin || isCeo;
  bool get isManager => role == 'MANAGER';
  bool get canManage => isAdminOrCeo || isManager;

  String get roleLabel => const {
        'ADMIN': 'Super Admin',
        'CEO': 'CEO',
        'MANAGER': 'Manager',
        'MEMBER': 'Member',
        'QA': 'QA',
      }[role] ??
      role;

  Json toJson() => {'id': id, 'name': name, 'email': email, 'role': role, 'team_id': teamId, 'team': team};

  factory Me.fromJson(Json j) => Me(
        id: asInt(j['id'])!,
        name: asStr(j['name']) ?? '',
        email: asStr(j['email']) ?? '',
        role: asStr(j['role']) ?? 'MEMBER',
        teamId: asInt(j['team_id']),
        team: asStr(j['team']),
      );
}

class AppUser {
  AppUser({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.role = 'MEMBER',
    this.teamId,
    this.teamName,
    this.isActive = true,
  });

  final int id;
  final String name;
  final String? email;
  final String? phone;
  final String role;
  final int? teamId;
  final String? teamName;
  final bool isActive;

  factory AppUser.fromJson(Json j) => AppUser(
        id: asInt(j['id'])!,
        name: asStr(j['name']) ?? '',
        email: asStr(j['email']),
        phone: asStr(j['phone']),
        role: asStr(j['role']) ?? 'MEMBER',
        teamId: asInt(j['team_id']),
        teamName: asStr(j['team_name']),
        isActive: j['is_active'] == null ? true : asBool(j['is_active']),
      );
}

class Team {
  Team({required this.id, required this.name, this.managerId, this.managerName, this.memberCount = 0});

  final int id;
  final String name;
  final int? managerId;
  final String? managerName;
  final int memberCount;

  factory Team.fromJson(Json j) => Team(
        id: asInt(j['id'])!,
        name: asStr(j['name']) ?? '',
        managerId: asInt(j['manager_id']),
        managerName: asStr(j['manager_name']),
        memberCount: asInt(j['member_count']) ?? 0,
      );
}

class TaskType {
  TaskType({
    required this.id,
    required this.name,
    this.teamId,
    this.teamName,
    this.isActive = true,
    this.usedCount = 0,
  });

  final int id;
  final String name;
  final int? teamId;
  final String? teamName;
  final bool isActive;
  final int usedCount;

  factory TaskType.fromJson(Json j) => TaskType(
        id: asInt(j['id'])!,
        name: asStr(j['name']) ?? '',
        teamId: asInt(j['team_id']),
        teamName: asStr(j['team_name']),
        isActive: j['is_active'] == null ? true : asBool(j['is_active']),
        usedCount: asInt(j['used_count']) ?? 0,
      );
}

class Task {
  Task({
    required this.id,
    required this.title,
    this.description = '',
    this.status = 'ASSIGNED',
    this.priority = 'NORMAL',
    this.creatorId,
    this.assigneeId,
    this.assignedTeamId,
    this.projectId,
    this.parentId,
    this.taskTypeId,
    this.dueAt,
    this.etaAt,
    this.acknowledgedAt,
    this.doneAt,
    this.createdAt,
    this.slaDeadlineAt,
    this.slaBreachedAt,
    this.cancelReason,
    this.discussReason,
    this.blockedReason,
    this.inputRequestNote,
    this.inputPayload,
    this.reopenCount = 0,
    this.subtaskCount = 0,
    this.subtaskDone = 0,
    this.commentCount = 0,
    this.memberCount = 0,
    this.escalationReviewPending = false,
    this.assigneeName,
    this.creatorName,
    this.teamName,
    this.projectName,
    this.typeName,
  });

  final int id;
  final String title;
  final String description;
  final String status;
  final String priority;
  final int? creatorId;
  final int? assigneeId;
  final int? assignedTeamId;
  final int? projectId;
  final int? parentId;
  final int? taskTypeId;
  final DateTime? dueAt;
  final DateTime? etaAt;
  final DateTime? acknowledgedAt;
  final DateTime? doneAt;
  final DateTime? createdAt;
  final DateTime? slaDeadlineAt;
  final DateTime? slaBreachedAt;
  final String? cancelReason;
  final String? discussReason;
  final String? blockedReason;
  final String? inputRequestNote;
  final String? inputPayload;
  final int reopenCount;
  final int subtaskCount;
  final int subtaskDone;
  final int commentCount;
  final int memberCount;
  final bool escalationReviewPending;
  final String? assigneeName;
  final String? creatorName;
  final String? teamName;
  final String? projectName;
  final String? typeName;

  bool get isBlocked => blockedReason?.trim().isNotEmpty ?? false;

  /// Assignee label: person, team, or unassigned.
  String get who => assigneeName ?? (teamName != null ? 'Team $teamName' : 'Unassigned');

  factory Task.fromJson(Json j) => Task(
        id: asInt(j['id'])!,
        title: asStr(j['title']) ?? '',
        description: asStr(j['description']) ?? '',
        status: asStr(j['status']) ?? 'ASSIGNED',
        priority: asStr(j['priority']) ?? 'NORMAL',
        creatorId: asInt(j['creator_id']),
        assigneeId: asInt(j['assignee_id']),
        assignedTeamId: asInt(j['assigned_team_id']),
        projectId: asInt(j['project_id']),
        parentId: asInt(j['parent_id']),
        taskTypeId: asInt(j['task_type_id']),
        dueAt: toDate(j['due_at']),
        etaAt: toDate(j['eta_at']),
        acknowledgedAt: toDate(j['acknowledged_at']),
        doneAt: toDate(j['done_at']),
        createdAt: toDate(j['created_at']),
        slaDeadlineAt: toDate(j['sla_deadline_at']),
        slaBreachedAt: toDate(j['sla_breached_at']),
        cancelReason: asStr(j['cancel_reason']),
        discussReason: asStr(j['discuss_reason']),
        blockedReason: asStr(j['blocked_reason']),
        inputRequestNote: asStr(j['input_request_note']),
        inputPayload: asStr(j['input_payload']),
        reopenCount: asInt(j['reopen_count']) ?? 0,
        subtaskCount: asInt(j['subtask_count']) ?? 0,
        subtaskDone: asInt(j['subtask_done']) ?? 0,
        commentCount: asInt(j['comment_count']) ?? 0,
        memberCount: asInt(j['member_count']) ?? 0,
        escalationReviewPending: asBool(j['escalation_review_pending']),
        assigneeName: asStr(j['assignee_name']),
        creatorName: asStr(j['creator_name']),
        teamName: asStr(j['team_name']),
        projectName: asStr(j['project_name']),
        typeName: asStr(j['type_name']),
      );
}

class Pagination {
  Pagination({this.page = 1, this.limit = 15, this.total = 0, this.totalPages = 1});

  final int page;
  final int limit;
  final int total;
  final int totalPages;

  factory Pagination.fromJson(Json? j, {int fallbackTotal = 0}) => Pagination(
        page: asInt(j?['page']) ?? 1,
        limit: asInt(j?['limit']) ?? 15,
        total: asInt(j?['total']) ?? fallbackTotal,
        totalPages: asInt(j?['totalPages']) ?? 1,
      );
}

class TaskPage {
  TaskPage(this.tasks, this.pagination);
  final List<Task> tasks;
  final Pagination pagination;
}

class TaskMember {
  TaskMember({required this.userId, required this.userName, required this.role});
  final int userId;
  final String userName;
  final String role;

  factory TaskMember.fromJson(Json j) => TaskMember(
        userId: asInt(j['user_id'])!,
        userName: asStr(j['user_name']) ?? '',
        role: asStr(j['role']) ?? 'COLLABORATOR',
      );
}

class Activity {
  Activity({
    required this.id,
    required this.type,
    this.actorName,
    this.meta = const {},
    this.createdAt,
    this.taskId,
    this.taskTitle,
  });

  final int id;
  final String type;
  final String? actorName;
  final Json meta;
  final DateTime? createdAt;
  final int? taskId;
  final String? taskTitle;

  String get detail => (meta['reason'] ?? meta['note'] ?? meta['message'] ?? '').toString();

  factory Activity.fromJson(Json j) {
    Json meta = {};
    final raw = j['meta'];
    if (raw is Map) {
      meta = Map<String, dynamic>.from(raw);
    } else if (raw is String && raw.isNotEmpty) {
      try {
        meta = Map<String, dynamic>.from(_decodeJson(raw) as Map);
      } catch (_) {}
    }
    return Activity(
      id: asInt(j['id'])!,
      type: asStr(j['type']) ?? '',
      actorName: asStr(j['actor_name']),
      meta: meta,
      createdAt: toDate(j['created_at']),
      taskId: asInt(j['task_id']),
      taskTitle: asStr(j['task_title']),
    );
  }
}

class Attachment {
  Attachment({
    required this.id,
    required this.fileName,
    required this.mimeType,
    this.size,
    this.context,
    this.uploaderName,
    this.createdAt,
  });

  final int id;
  final String fileName;
  final String mimeType;
  final int? size;
  final String? context;
  final String? uploaderName;
  final DateTime? createdAt;

  bool get isImage => mimeType.startsWith('image/');
  bool get isAudio => mimeType.startsWith('audio/');

  factory Attachment.fromJson(Json j) => Attachment(
        id: asInt(j['id'])!,
        fileName: asStr(j['file_name'] ?? j['fileName']) ?? 'file',
        mimeType: asStr(j['mime_type'] ?? j['mimeType']) ?? 'application/octet-stream',
        size: asInt(j['size']),
        context: asStr(j['context']),
        uploaderName: asStr(j['uploader_name']),
        createdAt: toDate(j['created_at']),
      );
}

class Escalation {
  Escalation({this.explanation, this.proposedEtaAt, this.explanationAt, this.reviewStatus});
  final String? explanation;
  final DateTime? proposedEtaAt;
  final DateTime? explanationAt;
  final String? reviewStatus;

  factory Escalation.fromJson(Json j) => Escalation(
        explanation: asStr(j['explanation']),
        proposedEtaAt: toDate(j['proposed_eta_at']),
        explanationAt: toDate(j['explanation_at']),
        reviewStatus: asStr(j['review_status']),
      );
}

/// Server-computed permissions for the viewer on one task.
class TaskPermissions {
  TaskPermissions(this._raw);
  final Json _raw;

  bool _b(String k) => asBool(_raw[k]);

  bool get canActAsAssignee => _b('canActAsAssignee');
  bool get canManageMembers => _b('canManageMembers');
  bool get canComment => _raw['canComment'] == null ? true : _b('canComment');
  bool get canAcknowledge => _b('canAcknowledge');
  bool get canDiscuss => _b('canDiscuss');
  bool get canReject => _b('canReject');
  bool get canStart => _b('canStart');
  bool get canDone => _b('canDone');
  bool get canRequestInput => _b('canRequestInput');
  bool get canProvideInput => _b('canProvideInput');
  bool get canResumeAfterInput => _b('canResumeAfterInput');
  bool get canViewInputRequest => _b('canViewInputRequest');
  bool get canViewInputPayload => _b('canViewInputPayload');
  bool get canEditEta => _b('canEditEta');
  bool get canReopen => _b('canReopen');
  bool get canCancel => _b('canCancel');
  bool get canBlock => _b('canBlock');
  bool get canUnblock => _b('canUnblock');
  bool get mustExplain => _b('mustExplain');
  bool get canReview => _b('canReview');
  bool get canAddSubtask => _b('canAddSubtask');
  bool get canDelete => _b('canDelete');
  bool get canViewActivity => _b('canViewActivity');
}

class TaskDetail {
  TaskDetail({
    required this.task,
    required this.members,
    required this.subtasks,
    required this.activity,
    required this.attachments,
    required this.escalation,
    required this.batchTasks,
    required this.permissions,
  });

  final Task task;
  final List<TaskMember> members;
  final List<Task> subtasks;
  final List<Activity> activity;
  final List<Attachment> attachments;
  final Escalation? escalation;
  final List<Task> batchTasks;
  final TaskPermissions permissions;

  factory TaskDetail.fromJson(Json j) => TaskDetail(
        task: Task.fromJson(Map<String, dynamic>.from(j['task'] as Map)),
        members: _list(j['members'], TaskMember.fromJson),
        subtasks: _list(j['subtasks'], Task.fromJson),
        activity: _list(j['activity'], Activity.fromJson),
        attachments: _list(j['attachments'], Attachment.fromJson),
        escalation: j['escalation'] is Map ? Escalation.fromJson(Map<String, dynamic>.from(j['escalation'])) : null,
        batchTasks: _list(j['batchTasks'], Task.fromJson),
        permissions: TaskPermissions(j['permissions'] is Map ? Map<String, dynamic>.from(j['permissions']) : {}),
      );
}

class Reaction {
  Reaction({required this.emoji, required this.count, required this.mine});
  final String emoji;
  final int count;
  final bool mine;

  factory Reaction.fromJson(Json j) => Reaction(
        emoji: asStr(j['emoji']) ?? '',
        count: asInt(j['count']) ?? 0,
        mine: asBool(j['mine']),
      );
}

class Comment {
  Comment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.content,
    this.parentId,
    this.edited = false,
    this.createdAt,
    this.reactions = const [],
  });

  final int id;
  final int authorId;
  final String authorName;
  final String content;
  final int? parentId;
  final bool edited;
  final DateTime? createdAt;
  final List<Reaction> reactions;

  factory Comment.fromJson(Json j) => Comment(
        id: asInt(j['id'])!,
        authorId: asInt(j['author_id']) ?? 0,
        authorName: asStr(j['author_name']) ?? '',
        content: asStr(j['content'] ?? j['body']) ?? '',
        parentId: asInt(j['parent_comment_id']),
        edited: asBool(j['edited']),
        createdAt: toDate(j['created_at']),
        reactions: _list(j['reactions'], Reaction.fromJson),
      );
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.taskId,
    this.readAt,
    this.createdAt,
  });

  final int id;
  final String type;
  final String title;
  final String? body;
  final int? taskId;
  final DateTime? readAt;
  final DateTime? createdAt;

  bool get isRead => readAt != null;

  factory AppNotification.fromJson(Json j) => AppNotification(
        id: asInt(j['id'])!,
        type: asStr(j['type']) ?? '',
        title: asStr(j['title']) ?? '',
        body: asStr(j['body']),
        taskId: asInt(j['task_id']),
        readAt: toDate(j['read_at']),
        createdAt: toDate(j['created_at']),
      );
}

class Project {
  Project({
    required this.id,
    required this.name,
    this.description,
    this.ownerId,
    this.ownerName,
    this.createdAt,
    this.memberCount = 0,
    this.openTasks = 0,
  });

  final int id;
  final String name;
  final String? description;
  final int? ownerId;
  final String? ownerName;
  final DateTime? createdAt;
  final int memberCount;
  final int openTasks;

  factory Project.fromJson(Json j) => Project(
        id: asInt(j['id'])!,
        name: asStr(j['name']) ?? '',
        description: asStr(j['description']),
        ownerId: asInt(j['owner_id']),
        ownerName: asStr(j['owner_name']),
        createdAt: toDate(j['created_at']),
        memberCount: asInt(j['member_count']) ?? 0,
        openTasks: asInt(j['open_tasks']) ?? 0,
      );
}

class ProjectNote {
  ProjectNote({required this.id, required this.body, this.pinned = false, this.authorName, this.createdAt});
  final int id;
  final String body;
  final bool pinned;
  final String? authorName;
  final DateTime? createdAt;

  factory ProjectNote.fromJson(Json j) => ProjectNote(
        id: asInt(j['id'])!,
        body: asStr(j['body']) ?? '',
        pinned: asBool(j['pinned']),
        authorName: asStr(j['author_name']),
        createdAt: toDate(j['created_at']),
      );
}

class ProjectDetail {
  ProjectDetail({
    required this.project,
    required this.members,
    required this.notes,
    required this.tasks,
    required this.files,
    required this.activity,
    required this.canManage,
  });

  final Project project;
  final List<AppUser> members;
  final List<ProjectNote> notes;
  final List<Task> tasks;
  final List<Attachment> files;
  final List<Activity> activity;
  final bool canManage;

  factory ProjectDetail.fromJson(Json j) => ProjectDetail(
        project: Project.fromJson(Map<String, dynamic>.from(j['project'] as Map)),
        members: _list(j['members'], AppUser.fromJson),
        notes: _list(j['notes'], ProjectNote.fromJson),
        tasks: _list(j['tasks'], Task.fromJson),
        files: _list(j['files'], Attachment.fromJson),
        activity: _list(j['activity'], Activity.fromJson),
        canManage: asBool(j['canManage']),
      );
}

class ChatTarget {
  ChatTarget({required this.id, required this.name, this.email, this.role, this.teamName, this.conversationId, this.lastMessageAt});
  final int id;
  final String name;
  final String? email;
  final String? role;
  final String? teamName;
  final int? conversationId;
  final DateTime? lastMessageAt;

  factory ChatTarget.fromJson(Json j) => ChatTarget(
        id: asInt(j['id'])!,
        name: asStr(j['name']) ?? '',
        email: asStr(j['email']),
        role: asStr(j['role']),
        teamName: asStr(j['team_name']),
        conversationId: asInt(j['conversation_id']),
        lastMessageAt: toDate(j['last_message_at']),
      );
}

class Conversation {
  Conversation({
    required this.id,
    this.kind = 'direct',
    this.name,
    this.memberUserId,
    this.memberName,
    this.memberEmail,
    this.memberRole,
    this.memberCount,
    this.memberList = const [],
    this.lastMessageAt,
    this.lastMessagePreview,
  });

  final int id;
  final String kind;
  final String? name;
  final int? memberUserId;
  final String? memberName;
  final String? memberEmail;
  final String? memberRole;
  final int? memberCount;
  final List<({int id, String name})> memberList;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;

  bool get isGroup => kind == 'group';
  String get title => isGroup ? (name ?? memberName ?? 'Group') : (memberName ?? name ?? 'Chat');

  factory Conversation.fromJson(Json j) {
    final rawMembers = j['member_list'];
    return Conversation(
      id: asInt(j['id'])!,
      kind: asStr(j['kind']) ?? 'direct',
      name: asStr(j['name'] ?? j['group_name']),
      memberUserId: asInt(j['member_user_id']),
      memberName: asStr(j['member_name']),
      memberEmail: asStr(j['member_email']),
      memberRole: asStr(j['member_role']),
      memberCount: asInt(j['member_count']),
      memberList: rawMembers is List
          ? rawMembers
              .whereType<Map>()
              .map((m) => (id: asInt(m['id']) ?? 0, name: asStr(m['name']) ?? ''))
              .toList()
          : const [],
      lastMessageAt: toDate(j['last_message_at']),
      lastMessagePreview: asStr(j['last_message_preview']),
    );
  }
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.authorId,
    required this.authorName,
    this.parentId,
    this.body,
    this.edited = false,
    this.deletedAt,
    this.createdAt,
    this.reactions = const [],
    this.attachments = const [],
  });

  final int id;
  final int conversationId;
  final int authorId;
  final String authorName;
  final int? parentId;
  final String? body;
  final bool edited;
  final DateTime? deletedAt;
  final DateTime? createdAt;
  final List<Reaction> reactions;
  final List<Attachment> attachments;

  bool get isDeleted => deletedAt != null;

  factory ChatMessage.fromJson(Json j) => ChatMessage(
        id: asInt(j['id'])!,
        conversationId: asInt(j['conversation_id']) ?? 0,
        authorId: asInt(j['author_id']) ?? 0,
        authorName: asStr(j['author_name']) ?? '',
        parentId: asInt(j['parent_message_id']),
        body: asStr(j['body']),
        edited: asBool(j['edited']),
        deletedAt: toDate(j['deleted_at']),
        createdAt: toDate(j['created_at']),
        reactions: _list(j['reactions'], Reaction.fromJson),
        attachments: _list(j['attachments'], Attachment.fromJson),
      );
}

class Board {
  Board({required this.id, required this.name, this.scene, this.updatedAt});
  final int id;
  final String name;
  final String? scene;
  final DateTime? updatedAt;

  factory Board.fromJson(Json j) => Board(
        id: asInt(j['id'])!,
        name: asStr(j['name']) ?? 'Untitled board',
        scene: j['scene'] is String ? j['scene'] as String : (j['scene'] == null ? null : _encodeJson(j['scene'])),
        updatedAt: toDate(j['updated_at']),
      );
}

class ReportSummary {
  ReportSummary(this._raw);
  final Json _raw;
  int _i(String k) => asInt(_raw[k]) ?? 0;

  int get open => _i('open');
  int get overdue => _i('overdue');
  int get noResponse => _i('noResponse');
  int get escalatedAwaiting => _i('escalatedAwaiting');
  int get escalatedPendingReview => _i('escalatedPendingReview');
  int get dueThisWeek => _i('dueThisWeek');
  int get done => _i('done');
  int? get onTimePct => asInt(_raw['onTimePct']);
  int? get avgResponseMin => asInt(_raw['avgResponseMin']);
  int get attention => overdue + noResponse + escalatedAwaiting + escalatedPendingReview;
}

class ReportPerson {
  ReportPerson(this.raw);
  final Json raw;
  int _i(String k) => asInt(raw[k]) ?? 0;

  int get id => _i('id');
  String get name => asStr(raw['name']) ?? '';
  String? get role => asStr(raw['role']);
  String? get teamName => asStr(raw['team_name']);
  int get open => _i('open');
  int get overdue => _i('overdue');
  int get noResponse => _i('no_response');
  int get escalations => _i('escalations');
  int get done => _i('done');
  int get doneSelf => _i('done_self');
  int get assignedOut => _i('assigned_out');
  int get doneByAssignee => _i('done_by_assignee');
  int get doneOnTime => _i('done_ontime');
  int? get avgResponseMin => asInt(raw['avg_response_min']);
  int? get onTimePct => done > 0 ? (100 * doneOnTime / done).round() : null;
}

class ReportType {
  ReportType(this.raw);
  final Json raw;
  int _i(String k) => asInt(raw[k]) ?? 0;

  int get id => _i('id');
  String get name => asStr(raw['name']) ?? '';
  String? get teamName => asStr(raw['team_name']);
  int get total => _i('total');
  int get open => _i('open');
  int get overdue => _i('overdue');
  int get noResponse => _i('no_response');
  int get done => _i('done');
}

class Report {
  Report({required this.summary, required this.people, required this.byType, required this.scope});
  final ReportSummary summary;
  final List<ReportPerson> people;
  final List<ReportType> byType;
  final String scope;

  String get scopeLabel => switch (scope) {
        'MEMBER' || 'QA' => 'Your tasks',
        'MANAGER' => 'Your team',
        _ => 'Entire organization',
      };

  bool get isPersonal => scope == 'MEMBER' || scope == 'QA';

  factory Report.fromJson(Json j) => Report(
        summary: ReportSummary(j['summary'] is Map ? Map<String, dynamic>.from(j['summary']) : {}),
        people: _list(j['people'], ReportPerson.new),
        byType: _list(j['byType'], ReportType.new),
        scope: asStr(j['scope']) ?? 'MEMBER',
      );
}

dynamic _decodeJson(String s) => jsonDecode(s);
String _encodeJson(dynamic v) => jsonEncode(v);
