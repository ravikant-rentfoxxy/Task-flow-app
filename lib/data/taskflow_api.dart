import '../core/api_client.dart';
import '../models/models.dart';

Json _map(dynamic d) => d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};

List<T> _list<T>(dynamic raw, T Function(Json) f) =>
    raw is List ? raw.whereType<Map>().map((e) => f(Map<String, dynamic>.from(e))).toList() : <T>[];

/// Query for GET /tasks.
class TaskQuery {
  const TaskQuery({
    this.filter = 'mine',
    this.status = '',
    this.q = '',
    this.assigneeId,
    this.teamId,
    this.dueFrom,
    this.dueTo,
    this.projectId,
    this.page = 1,
    this.limit = 15,
  });

  final String filter;
  final String status;
  final String q;
  final int? assigneeId;
  final int? teamId;
  final int? dueFrom;
  final int? dueTo;
  final int? projectId;
  final int page;
  final int limit;

  Map<String, dynamic> toQuery() => {
        'filter': filter,
        'status': status,
        'q': q,
        'assigneeId': assigneeId,
        'teamId': teamId,
        'dueFrom': dueFrom,
        'dueTo': dueTo,
        'projectId': projectId,
        'page': page,
        'limit': limit,
      };
}

class NewTask {
  NewTask({
    this.title = '',
    this.description = '',
    this.assigneeId,
    this.teamId,
    this.priority = 'NORMAL',
    required this.dueAt,
    this.projectId,
    this.parentId,
    this.boardId,
    this.taskTypeId,
    this.multiple = false,
    this.lines = const [],
    this.attachmentIds = const [],
    this.collaboratorIds = const [],
    this.watcherIds = const [],
  });

  final String title;
  final String description;
  final int? assigneeId;
  final int? teamId;
  final String priority;
  final DateTime dueAt;
  final int? projectId;
  final int? parentId;
  final int? boardId;
  final int? taskTypeId;
  final bool multiple;
  final List<String> lines;
  final List<int> attachmentIds;
  final List<int> collaboratorIds;
  final List<int> watcherIds;

  Json toJson() => {
        'title': title,
        'description': description,
        'assigneeId': assigneeId,
        'teamId': teamId,
        'priority': priority,
        'dueAt': dueAt.millisecondsSinceEpoch,
        'projectId': projectId,
        'parentId': parentId,
        'boardId': boardId,
        'taskTypeId': taskTypeId,
        'multiple': multiple,
        'lines': lines,
        'attachmentIds': attachmentIds,
        'descriptionAttachmentIds': <int>[],
        'collaboratorIds': collaboratorIds,
        'watcherIds': watcherIds,
      };
}

class ChatSendResult {
  ChatSendResult(this.message, this.conversation);
  final ChatMessage message;
  final Conversation conversation;
}

/// Typed wrapper over every TMS_BE endpoint the app uses.
class TaskFlowApi {
  TaskFlowApi(this.client);

  final ApiClient client;

  // ---- Auth ----------------------------------------------------------------

  Future<void> login(String email, String password) async {
    final d = _map(await client.post('/auth/login', {'email': email, 'password': password}));
    await client.saveTokens(d['accessToken']?.toString(), d['refreshToken']?.toString());
  }

  Future<void> logout() async {
    try {
      await client.post('/auth/logout');
    } catch (_) {}
    await client.clearTokens();
  }

  Future<String> forgotPassword(String email) async {
    final d = _map(await client.post('/auth/forgot-password', {'email': email}));
    return d['message']?.toString() ?? 'If an account exists for this email, a verification code has been sent.';
  }

  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
    required String confirmPassword,
  }) =>
      client.post('/auth/reset-password', {
        'email': email,
        'otp': otp,
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
      });

  Future<({Me me, int unread})> me() async {
    final d = _map(await client.get('/me'));
    return (me: Me.fromJson(_map(d['user'])), unread: (d['unread'] as num?)?.toInt() ?? 0);
  }

  // ---- Directory -------------------------------------------------------------

  Future<List<AppUser>> users() async => _list(_map(await client.get('/users'))['users'], AppUser.fromJson);

  Future<List<Team>> teams() async => _list(_map(await client.get('/teams'))['teams'], Team.fromJson);

  Future<List<TaskType>> taskTypes({int? userId, int? teamId, bool manage = false}) async {
    final d = _map(await client.get('/task-types', query: {
      'userId': userId,
      'teamId': teamId,
      if (manage) 'manage': 1,
    }));
    return _list(d['types'], TaskType.fromJson);
  }

  // ---- Tasks -----------------------------------------------------------------

  Future<TaskPage> tasks(TaskQuery q) async {
    final d = _map(await client.get('/tasks', query: q.toQuery()));
    final tasks = _list(d['tasks'], Task.fromJson);
    return TaskPage(tasks, Pagination.fromJson(d['pagination'] is Map ? _map(d['pagination']) : null, fallbackTotal: tasks.length));
  }

  Future<TaskDetail> task(int id) async => TaskDetail.fromJson(_map(await client.get('/tasks/$id')));

  /// Returns the created task ids.
  Future<List<int>> createTask(NewTask t) async {
    final d = _map(await client.post('/tasks', t.toJson()));
    final ids = d['ids'];
    if (ids is List) return ids.map((e) => (e as num).toInt()).toList();
    if (d['id'] != null) return [(d['id'] as num).toInt()];
    return [];
  }

  Future<void> taskAction(int id, String action, [Json extra = const {}]) =>
      client.patch('/tasks/$id', {'action': action, ...extra});

  Future<void> deleteTask(int id) => client.delete('/tasks/$id');

  Future<void> submitEscalationExplanation(int id, String explanation, DateTime? proposedEta) =>
      client.post('/tasks/$id/escalation', {
        'explanation': explanation,
        if (proposedEta != null) 'proposedEtaAt': proposedEta.millisecondsSinceEpoch,
      });

  Future<void> reviewEscalation(int id, String result) => client.post('/tasks/$id/escalation', {'review': result});

  Future<List<Comment>> comments(int taskId) async =>
      _list(_map(await client.get('/tasks/$taskId/comments'))['comments'], Comment.fromJson);

  Future<void> addComment(int taskId, String content, {int? parentId}) =>
      client.post('/tasks/$taskId/comments', {'content': content, 'parentCommentId': parentId});

  Future<void> editComment(int taskId, int commentId, String content) =>
      client.patch('/tasks/$taskId/comments/$commentId', {'content': content});

  Future<void> toggleCommentReaction(int taskId, int commentId, String emoji) =>
      client.post('/tasks/$taskId/comments/$commentId/reactions', {'emoji': emoji});

  // ---- Projects --------------------------------------------------------------

  Future<List<Project>> projects() async => _list(_map(await client.get('/projects'))['projects'], Project.fromJson);

  Future<void> createProject(String name, String description) =>
      client.post('/projects', {'name': name, 'description': description});

  Future<ProjectDetail> project(int id) async => ProjectDetail.fromJson(_map(await client.get('/projects/$id')));

  Future<void> updateProject(int id, Json body) => client.patch('/projects/$id', body);

  // ---- Uploads ---------------------------------------------------------------

  Future<Attachment> upload(List<int> bytes, String filename, {String? mimeType, int? projectId}) async {
    final d = await client.upload('/uploads',
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
        fields: {if (projectId != null) 'projectId': '$projectId'});
    return Attachment.fromJson(d);
  }

  Future<void> deleteUpload(int id) => client.delete('/uploads/$id');

  // ---- Notifications ---------------------------------------------------------

  Future<List<AppNotification>> notifications() async =>
      _list(_map(await client.get('/notifications'))['notifications'], AppNotification.fromJson);

  Future<void> markNotificationsRead({List<int>? ids, bool all = false}) =>
      client.post('/notifications', all ? {'all': true} : {'ids': ids ?? []});

  Future<void> clearNotifications() => client.post('/notifications/clear');

  // ---- Reports ---------------------------------------------------------------

  Future<Report> report(Map<String, dynamic> query) async =>
      Report.fromJson(_map(await client.get('/reports', query: query)));

  Future<List<Task>> reportDrill(Map<String, dynamic> query) async =>
      _list(_map(await client.get('/reports', query: query))['tasks'], Task.fromJson);

  // ---- Admin -----------------------------------------------------------------

  Future<void> createUser(Json body) => client.post('/users', body);
  Future<void> updateUser(int id, Json body) => client.patch('/users', {'id': id, ...body});
  Future<void> deleteUser(int id) => client.delete('/users', query: {'id': id});

  Future<void> createTeam(String name, int? managerId) => client.post('/teams', {'name': name, 'managerId': managerId});
  Future<void> updateTeam(int id, Json body) => client.patch('/teams', {'id': id, ...body});
  Future<void> deleteTeam(int id) => client.delete('/teams', query: {'id': id});

  Future<void> createTaskType(int teamId, String name) => client.post('/task-types', {'teamId': teamId, 'name': name});
  Future<void> updateTaskType(int id, Json body) => client.patch('/task-types', {'id': id, ...body});
  Future<void> deleteTaskType(int id) => client.delete('/task-types', query: {'id': id});

  // ---- Chat ------------------------------------------------------------------

  Future<List<ChatTarget>> chatTargets() async =>
      _list(_map(await client.get('/chat/targets'))['targets'], ChatTarget.fromJson);

  Future<List<Conversation>> conversations() async =>
      _list(_map(await client.get('/chat/conversations'))['conversations'], Conversation.fromJson);

  Future<List<Conversation>> chatGroups() async =>
      _list(_map(await client.get('/chat/groups'))['groups'], Conversation.fromJson);

  Future<({Conversation conversation, List<ChatMessage> messages})> openChat(int userId) async {
    final d = _map(await client.post('/chat/open', {'userId': userId}));
    return (
      conversation: Conversation.fromJson(_map(d['conversation'])),
      messages: _list(d['messages'], ChatMessage.fromJson),
    );
  }

  Future<({Conversation conversation, List<ChatMessage> messages})> messages(int conversationId) async {
    final d = _map(await client.get('/chat/conversations/$conversationId/messages'));
    return (
      conversation: Conversation.fromJson(_map(d['conversation'])),
      messages: _list(d['messages'], ChatMessage.fromJson),
    );
  }

  Future<ChatSendResult> sendMessage(int conversationId, String body, {int? parentId, List<int> attachmentIds = const []}) async {
    final d = _map(await client.post('/chat/conversations/$conversationId/messages', {
      'body': body,
      'parentMessageId': parentId,
      'attachmentIds': attachmentIds,
    }));
    return ChatSendResult(ChatMessage.fromJson(_map(d['message'])), Conversation.fromJson(_map(d['conversation'])));
  }

  Future<ChatSendResult> editMessage(int messageId, String body) async {
    final d = _map(await client.patch('/chat/messages/$messageId', {'body': body}));
    return ChatSendResult(ChatMessage.fromJson(_map(d['message'])), Conversation.fromJson(_map(d['conversation'])));
  }

  Future<ChatSendResult> deleteMessage(int messageId) async {
    final d = _map(await client.delete('/chat/messages/$messageId'));
    return ChatSendResult(ChatMessage.fromJson(_map(d['message'])), Conversation.fromJson(_map(d['conversation'])));
  }

  Future<ChatSendResult> toggleMessageReaction(int messageId, String emoji) async {
    final d = _map(await client.post('/chat/messages/$messageId/reactions', {'emoji': emoji}));
    return ChatSendResult(ChatMessage.fromJson(_map(d['message'])), Conversation.fromJson(_map(d['conversation'])));
  }

  Future<Conversation> createGroup(String name, List<int> memberIds) async {
    final d = _map(await client.post('/chat/groups', {'name': name, 'memberIds': memberIds}));
    return Conversation.fromJson(_map(d['group']));
  }

  Future<({Conversation group, List<AppUser> members, bool canManage})> groupDetail(int id) async {
    final d = _map(await client.get('/chat/groups/$id'));
    return (
      group: Conversation.fromJson(_map(d['group'])),
      members: _list(d['members'], AppUser.fromJson),
      canManage: d['canManage'] == true,
    );
  }

  Future<Conversation> updateGroup(int id, {String? name, List<int>? memberIds}) async {
    final d = _map(await client.patch('/chat/groups/$id', {
      'name': ?name,
      'memberIds': ?memberIds,
    }));
    return Conversation.fromJson(_map(d['group']));
  }

  // ---- Boards (Scribble) -----------------------------------------------------

  Future<List<Board>> boards() async => _list(_map(await client.get('/boards'))['boards'], Board.fromJson);

  Future<int> saveBoard({int? id, required String name, required Object scene}) async {
    final d = _map(await client.post('/boards', {'id': ?id, 'name': name, 'scene': scene}));
    return (d['id'] as num).toInt();
  }

  Future<void> deleteBoard(int id) => client.delete('/boards', query: {'id': id});
}
