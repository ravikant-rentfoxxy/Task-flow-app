import 'dart:async';

import 'package:get/get.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/config.dart';
import '../core/format.dart';
import '../models/models.dart';

class ChatUpdate {
  ChatUpdate({required this.action, this.conversation, this.message});
  final String action;
  final Conversation? conversation;
  final ChatMessage? message;

  factory ChatUpdate.fromJson(Map<String, dynamic> j) => ChatUpdate(
        action: j['action']?.toString() ?? '',
        conversation: j['conversation'] is Map ? Conversation.fromJson(Map<String, dynamic>.from(j['conversation'])) : null,
        message: j['message'] is Map ? ChatMessage.fromJson(Map<String, dynamic>.from(j['message'])) : null,
      );
}

class TypingEvent {
  TypingEvent({required this.conversationId, required this.userId, required this.userName, required this.typing});
  final int conversationId;
  final int userId;
  final String userName;
  final bool typing;
}

class Presence {
  const Presence(this.users);
  final List<({int id, String name})> users;
  Set<int> get ids => users.map((u) => u.id).toSet();
}

/// Socket.IO connection to TMS_BE, fanned out as broadcast streams.
///
/// Screens also refresh on a timer, so the app keeps working if the socket is down.
class RealtimeController extends GetxController {
  final _taskChanged = StreamController<void>.broadcast();
  final _notification = StreamController<String?>.broadcast();
  final _chat = StreamController<ChatUpdate>.broadcast();
  final _typing = StreamController<TypingEvent>.broadcast();

  io.Socket? _socket;
  final _presence = const Presence([]).obs;
  final connected = false.obs;

  Presence get presence => _presence.value;
  Stream<void> get taskChanged => _taskChanged.stream;
  Stream<String?> get notifications => _notification.stream;
  Stream<ChatUpdate> get chat => _chat.stream;
  Stream<TypingEvent> get typing => _typing.stream;

  void connect({required String apiBase, required String cookie}) {
    disconnect();
    if (cookie.isEmpty) return;
    final socket = io.io(
      AppConfig.socketOrigin(apiBase),
      io.OptionBuilder()
          .setPath('/api/socket.io')
          .setTransports(['websocket'])
          .setExtraHeaders({'Cookie': cookie})
          .enableReconnection()
          .disableAutoConnect()
          .build(),
    );
    socket.onConnect((_) => connected.value = true);
    socket.onDisconnect((_) => connected.value = false);
    socket.on('task:changed', (_) => _taskChanged.add(null));
    socket.on('notification:new', (data) {
      final title = data is Map && data['notification'] is Map ? data['notification']['title']?.toString() : null;
      _notification.add(title);
    });
    socket.on('admin:notification', (data) => _notification.add(data is Map ? data['title']?.toString() : null));
    socket.on('presence:update', (data) {
      if (data is! Map) return;
      final list = data['onlineUserList'];
      if (list is List) {
        _presence.value = Presence(
            list.whereType<Map>().map((u) => (id: asInt(u['id']) ?? 0, name: u['name']?.toString() ?? '')).toList());
      } else if (data['onlineUsers'] is List) {
        _presence.value =
            Presence((data['onlineUsers'] as List).map((id) => (id: asInt(id) ?? 0, name: 'User #$id')).toList());
      }
    });
    socket.on('chat:update', (data) {
      if (data is Map) _chat.add(ChatUpdate.fromJson(Map<String, dynamic>.from(data)));
    });
    socket.on('chat:typing', (data) {
      if (data is! Map) return;
      _typing.add(TypingEvent(
        conversationId: asInt(data['conversationId']) ?? 0,
        userId: asInt(data['userId']) ?? 0,
        userName: data['userName']?.toString() ?? '',
        typing: data['typing'] == true,
      ));
    });
    socket.connect();
    _socket = socket;
  }

  void joinConversation(int id) => _socket?.emit('chat:join', {'conversationId': id});
  void leaveConversation(int id) => _socket?.emit('chat:leave', {'conversationId': id});
  void sendTyping(int id, bool typing) => _socket?.emit('chat:typing', {'conversationId': id, 'typing': typing});

  /// Lets local actions (e.g. sending a message) flow through the same path as socket events.
  void publishChat(ChatUpdate u) => _chat.add(u);
  void publishTaskChanged() => _taskChanged.add(null);

  void disconnect() {
    // Detach handlers first: dispose() emits "disconnect" synchronously while
    // the widget tree may be unmounting.
    _socket?.clearListeners();
    _socket?.dispose();
    _socket = null;
    connected.value = false;
    _presence.value = const Presence([]);
  }

  @override
  void onClose() {
    disconnect();
    _taskChanged.close();
    _notification.close();
    _chat.close();
    _typing.close();
    super.onClose();
  }
}
