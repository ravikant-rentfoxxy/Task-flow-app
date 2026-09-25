import 'package:get/get.dart';

import '../core/local_store.dart';
import 'realtime_controller.dart';

class ChatUnreadEntry {
  ChatUnreadEntry({
    required this.conversationId,
    required this.name,
    required this.preview,
    required this.count,
    required this.updatedAt,
  });

  final int conversationId;
  final String name;
  final String preview;
  final int count;
  final int updatedAt;

  Map<String, dynamic> toJson() =>
      {'id': conversationId, 'name': name, 'preview': preview, 'count': count, 'updatedAt': updatedAt};

  factory ChatUnreadEntry.fromJson(Map<String, dynamic> j) => ChatUnreadEntry(
        conversationId: (j['id'] as num).toInt(),
        name: j['name']?.toString() ?? 'Chat',
        preview: j['preview']?.toString() ?? 'New message',
        count: (j['count'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

/// Client-side unread counts for chat, driven by `chat:update` socket events
/// (the backend has no chat read-receipts). Persisted in Hive.
class ChatUnreadController extends GetxController {
  ChatUnreadController({this.store});

  final LocalStore? store;
  static const _key = 'chat_unread_v1';

  final _entries = <int, ChatUnreadEntry>{}.obs;
  int? activeConversationId;

  int get total => _entries.values.fold(0, (sum, e) => sum + e.count);

  List<ChatUnreadEntry> get entries =>
      _entries.values.where((e) => e.count > 0).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  int countFor(int conversationId) => _entries[conversationId]?.count ?? 0;

  void load() {
    final raw = store?.read(_key);
    if (raw is! List) return;
    for (final e in raw.whereType<Map>()) {
      final entry = ChatUnreadEntry.fromJson(Map<String, dynamic>.from(e));
      _entries[entry.conversationId] = entry;
    }
  }

  void handle(ChatUpdate u, int? meId) {
    if (meId == null || u.action != 'message') return;
    final m = u.message;
    final c = u.conversation;
    if (m == null || c == null || m.isDeleted || m.authorId == meId) return;
    if (activeConversationId == c.id) return;
    // Edits and reactions re-send the message; only count new ones.
    final prev = _entries[c.id];
    final createdAt = m.createdAt?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
    if (prev != null && createdAt <= prev.updatedAt) return;
    final body = m.body?.trim() ?? '';
    final preview = body.isNotEmpty ? body : (m.attachments.isNotEmpty ? '[Attachment]' : 'New message');
    _entries[c.id] = ChatUnreadEntry(
      conversationId: c.id,
      name: c.title,
      preview: preview.length > 120 ? preview.substring(0, 120) : preview,
      count: (prev?.count ?? 0) + 1,
      updatedAt: createdAt,
    );
    _save();
  }

  void setActive(int? conversationId) {
    activeConversationId = conversationId;
    if (conversationId != null) markRead(conversationId);
  }

  void markRead(int conversationId) {
    if (_entries.remove(conversationId) == null) return;
    _save();
  }

  void clear() {
    _entries.clear();
    activeConversationId = null;
    _save();
  }

  void _save() => store?.write(_key, _entries.values.map((e) => e.toJson()).toList());
}
