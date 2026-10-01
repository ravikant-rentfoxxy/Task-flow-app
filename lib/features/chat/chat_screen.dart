import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/task_logic.dart';
import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../state/chat_unread_controller.dart';
import '../../state/realtime_controller.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/attachments.dart';
import '../../widgets/brand_ui.dart';
import '../../widgets/common.dart';
import '../../widgets/files.dart';
import '../shell/top_bar.dart';
import '../tasks/composer_sheet.dart';
import '../tasks/task_detail_screen.dart';

void openChatWithUser(BuildContext context, int userId, {Task? attachTask}) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadScreen(userId: userId, attachTask: attachTask)));
}

void openChatConversation(BuildContext context, int conversationId) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadScreen(conversationId: conversationId)));
}

/// Chat tab: conversations, groups and people.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<Conversation>? conversations;
  List<ChatTarget> targets = [];
  String? error;
  String query = '';
  ({int? conversationId, int? userId})? selected;
  StreamSubscription<ChatUpdate>? _sub;

  TaskFlowApi get api => Get.find<TaskFlowApi>();

  @override
  void initState() {
    super.initState();
    _load();
    _sub = Get.find<RealtimeController>().chat.listen((u) {
      final c = u.conversation;
      if (c == null || conversations == null) return;
      setState(() {
        conversations = [c, ...conversations!.where((x) => x.id != c.id)]
          ..sort((a, b) => (b.lastMessageAt ?? DateTime(0)).compareTo(a.lastMessageAt ?? DateTime(0)));
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([api.conversations(), api.chatTargets()]);
      if (!mounted) return;
      setState(() {
        conversations = r[0] as List<Conversation>;
        targets = r[1] as List<ChatTarget>;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    }
  }

  void _open(BuildContext context, bool wide, {int? conversationId, int? userId}) {
    if (wide) {
      setState(() => selected = (conversationId: conversationId, userId: userId));
    } else if (conversationId != null) {
      openChatConversation(context, conversationId);
    } else {
      openChatWithUser(context, userId!);
    }
  }

  Future<void> _newGroup() async {
    final g = await showGroupForm(context);
    if (g != null) {
      await _load();
      if (mounted) openChatConversation(context, g.id);
    }
  }

  @override
  Widget build(BuildContext context) => Obx(() => _reactiveBuild(context));

  Widget _reactiveBuild(BuildContext context) {
    final me = Get.find<AuthController>().me;
    final unread = Get.find<ChatUnreadController>();
    final online = Get.find<RealtimeController>().presence.ids;
    final q = query.trim().toLowerCase();
    final convs = (conversations ?? []).where((c) => q.isEmpty || c.title.toLowerCase().contains(q)).toList();
    final withConv = (conversations ?? []).where((c) => !c.isGroup).map((c) => c.memberUserId).toSet();
    final people = targets.where((t) => !withConv.contains(t.id) && (q.isEmpty || t.name.toLowerCase().contains(q))).toList();
    final live = Get.find<RealtimeController>().connected.value;
    final onlineCount = targets.where((t) => t.id != me?.id && online.contains(t.id)).length;

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final list = RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
          _ChatHero(
            live: live,
            unread: unread.total,
            chats: conversations?.length,
            onlineCount: onlineCount,
            onSearch: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 18),
          if (conversations == null && error == null) const SkeletonList(height: 62),
          if (error != null && conversations == null) ErrorView(message: error!, onRetry: _load),
          if (convs.isNotEmpty) ...[
            BrandSectionTitle(title: 'Recent', count: convs.length),
            for (final conv in convs)
              _ConvTile(
                key: ValueKey('conv-${conv.id}'),
                title: conv.title,
                subtitle: conv.isGroup
                    ? '${conv.memberCount ?? conv.memberList.length} members · ${conv.lastMessagePreview ?? ''}'
                    : (conv.lastMessagePreview ?? conv.memberRole ?? ''),
                time: conv.lastMessageAt,
                group: conv.isGroup,
                online: !conv.isGroup && online.contains(conv.memberUserId),
                unread: unread.countFor(conv.id),
                selected: wide && selected?.conversationId == conv.id,
                onTap: () {
                  unread.markRead(conv.id);
                  _open(context, wide, conversationId: conv.id);
                },
              ),
          ],
          if (people.isNotEmpty) ...[
            BrandSectionTitle(title: 'People', count: people.length, padding: EdgeInsets.only(top: convs.isEmpty ? 0 : 10, bottom: 10)),
            for (final t in people)
              _ConvTile(
                key: ValueKey('person-${t.id}'),
                title: t.name,
                subtitle: [t.teamName, t.role].whereType<String>().join(' · '),
                online: online.contains(t.id),
                selected: wide && selected?.userId == t.id,
                onTap: () => _open(context, wide, userId: t.id),
              ),
          ],
          if (conversations != null && convs.isEmpty && people.isEmpty)
            const EmptyState(icon: Icons.forum_outlined, title: 'No chats found'),
        ]),
      );

      return Scaffold(
        backgroundColor: Brand.surface,
        appBar: TopBar(title: 'Chat', actions: [
          if (me?.isAdminOrCeo ?? false)
            IconButton(key: const Key('new-group'), tooltip: 'New group', onPressed: _newGroup, icon: const Icon(Icons.group_add_outlined)),
        ]),
        body: !wide
            ? list
            : Row(children: [
                SizedBox(width: 340, child: list),
                const VerticalDivider(width: 1, color: Brand.outline),
                Expanded(
                  child: selected == null
                      ? const Center(child: EmptyState(icon: Icons.forum_outlined, title: 'Select a chat', message: 'Pick a conversation or a person to start.'))
                      : ChatThread(
                          key: ValueKey('thread-${selected!.conversationId}-${selected!.userId}'),
                          conversationId: selected!.conversationId,
                          userId: selected!.userId,
                          showHeader: true,
                          onConversation: (_) => _load(),
                        ),
                ),
              ]),
      );
    });
  }
}

/// Navy hero for the chat list: live pill, unread summary and the search field.
class _ChatHero extends StatelessWidget {
  const _ChatHero({required this.live, required this.unread, required this.chats, required this.onlineCount, required this.onSearch});
  final bool live;
  final int unread;
  final int? chats;
  final int onlineCount;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)));
    final facts = [
      if (chats != null) '$chats ${chats == 1 ? 'conversation' : 'conversations'}',
      '$onlineCount online',
    ].join(' · ');
    return HeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (live) ...[const LivePill(), const SizedBox(width: 10)],
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: HeroEyebrow(facts)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const HeroTitle('Messages', maxLines: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              if (unread > 0) ...[
                Container(
                  constraints: const BoxConstraints(minWidth: 26),
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Brand.lime, borderRadius: BorderRadius.circular(99)),
                  child: Text('$unread', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Brand.navy)),
                ),
                const SizedBox(width: 8),
              ] else ...[
                const Icon(Icons.check_circle_rounded, size: 18, color: Brand.lime),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  unread > 0 ? (unread == 1 ? 'unread message' : 'unread messages') : "You're all caught up",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('chat-search'),
            style: const TextStyle(fontSize: 13, color: Colors.white),
            cursorColor: Brand.lime,
            decoration: InputDecoration(
              hintText: 'Search people or groups…',
              hintStyle: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.55)),
              prefixIcon: Icon(Icons.search_rounded, size: 20, color: Colors.white.withValues(alpha: 0.7)),
              fillColor: Colors.white.withValues(alpha: 0.08),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: border,
              enabledBorder: border,
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Brand.lime, width: 1.4)),
            ),
            onChanged: onSearch,
          ),
        ],
      ),
    );
  }
}

class _ConvTile extends StatelessWidget {
  const _ConvTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.time,
    this.group = false,
    this.online = false,
    this.unread = 0,
    this.selected = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final DateTime? time;
  final bool group;
  final bool online;
  final int unread;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: selected ? Brand.limeLight : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? Brand.limeDim : (unread > 0 ? Brand.navy.withValues(alpha: 0.25) : Brand.outline)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            if (unread > 0 || selected)
              Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 3, color: selected ? Brand.navy : Brand.lime)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  group
                      ? Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: Brand.navy, borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.groups_2_rounded, color: Brand.lime, size: 20),
                        )
                      : Avatar(title, size: 40, online: online),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayName(title),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w700, fontSize: 14, color: Brand.navy),
                              ),
                            ),
                            if (time != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                timeAgo(time),
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500,
                                  color: unread > 0 ? Brand.navy : TF.faint,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                decodeMentionsForDisplay(subtitle).replaceAll('\n', ' '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: unread > 0 ? Brand.navy : Brand.onVariant),
                              ),
                            ),
                            if (unread > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                constraints: const BoxConstraints(minWidth: 20),
                                height: 20,
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: Brand.navy, borderRadius: BorderRadius.circular(99)),
                                child: Text(
                                  unread > 9 ? '9+' : '$unread',
                                  style: const TextStyle(color: Brand.lime, fontSize: 10.5, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ChatThreadScreen extends StatelessWidget {
  const ChatThreadScreen({super.key, this.conversationId, this.userId, this.attachTask});
  final int? conversationId;
  final int? userId;
  final Task? attachTask;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Brand.surface,
        body: SafeArea(
          child: ChatThread(conversationId: conversationId, userId: userId, attachTask: attachTask, showHeader: true, showBack: true),
        ),
      );
}

class _PendingUpload {
  _PendingUpload(this.attachment);
  final Attachment attachment;
}

class ChatThread extends StatefulWidget {
  const ChatThread({
    super.key,
    this.conversationId,
    this.userId,
    this.attachTask,
    this.showHeader = true,
    this.showBack = false,
    this.onConversation,
  });

  final int? conversationId;
  final int? userId;
  final Task? attachTask;
  final bool showHeader;
  final bool showBack;
  final ValueChanged<Conversation>? onConversation;

  @override
  State<ChatThread> createState() => _ChatThreadState();
}

class _ChatThreadState extends State<ChatThread> {
  Conversation? conv;
  List<ChatMessage> messages = [];
  String? error;
  bool loading = true;
  bool busy = false;
  final input = TextEditingController();
  final scroll = ScrollController();
  ChatMessage? replyTo;
  Task? attached;
  final List<_PendingUpload> pending = [];
  final Map<int, String> typingUsers = {};
  StreamSubscription<ChatUpdate>? _chatSub;
  StreamSubscription<TypingEvent>? _typingSub;
  Timer? _typingTimer;
  bool _typingSent = false;
  late final RealtimeController _realtime;
  late final ChatUnreadController _unread;

  TaskFlowApi get api => Get.find<TaskFlowApi>();

  @override
  void initState() {
    super.initState();
    _realtime = Get.find<RealtimeController>();
    _unread = Get.find<ChatUnreadController>();
    attached = widget.attachTask;
    _load();
    _chatSub = _realtime.chat.listen(_apply);
    final meId = Get.find<AuthController>().me?.id;
    _typingSub = _realtime.typing.listen((e) {
      if (e.conversationId != conv?.id || e.userId == meId) return;
      setState(() => e.typing ? typingUsers[e.userId] = e.userName : typingUsers.remove(e.userId));
    });
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _typingSub?.cancel();
    _typingTimer?.cancel();
    if (conv != null) {
      if (_typingSent) _realtime.sendTyping(conv!.id, false);
      _realtime.leaveConversation(conv!.id);
    }
    if (_unread.activeConversationId == conv?.id) _unread.setActive(null);
    for (final p in pending) {
      api.deleteUpload(p.attachment.id).catchError((_) {});
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = widget.conversationId != null ? await api.messages(widget.conversationId!) : await api.openChat(widget.userId!);
      if (!mounted) return;
      setState(() {
        conv = r.conversation;
        messages = _sorted(r.messages);
        loading = false;
        error = null;
      });
      _realtime.joinConversation(r.conversation.id);
      _unread.setActive(r.conversation.id);
      widget.onConversation?.call(r.conversation);
      _scrollToEnd();
    } catch (e) {
      if (mounted) setState(() => (error = errorText(e), loading = false));
    }
  }

  List<ChatMessage> _sorted(List<ChatMessage> list) => [...list]
    ..sort((a, b) {
      final c = (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0));
      return c != 0 ? c : a.id.compareTo(b.id);
    });

  void _apply(ChatUpdate u) {
    if (conv == null || u.conversation?.id != conv!.id) return;
    setState(() {
      if (u.conversation != null && u.action == 'group') conv = u.conversation;
      final m = u.message;
      if (m != null) {
        final i = messages.indexWhere((x) => x.id == m.id);
        final atEnd = i < 0;
        if (atEnd) {
          messages = _sorted([...messages, m]);
        } else {
          messages = [...messages]..[i] = m;
        }
        if (atEnd) _scrollToEnd();
      }
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  void _onTyping(String _) {
    setState(() {});
    if (conv == null) return;
    if (!_typingSent) {
      _typingSent = true;
      _realtime.sendTyping(conv!.id, true);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _typingSent = false;
      if (conv != null) _realtime.sendTyping(conv!.id, false);
    });
  }

  Future<void> _send([String? override]) async {
    if (conv == null) return;
    final raw = (override ?? input.text).trim();
    if (raw.isEmpty && pending.isEmpty && attached == null) return;
    final text = conv!.isGroup ? encodeMentionsForSend(raw, conv!.memberList) : raw;
    final body = attached != null ? buildTaskMentionBody(attached!, text) : text;
    setState(() => busy = true);
    try {
      final r = await api.sendMessage(conv!.id, body, parentId: replyTo?.id, attachmentIds: pending.map((p) => p.attachment.id).toList());
      if (override == null) input.clear();
      setState(() {
        pending.clear();
        replyTo = null;
        attached = null;
      });
      _realtime.publishChat(ChatUpdate(action: 'message', conversation: r.conversation, message: r.message));
    } catch (e) {
      toastError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _attach() async {
    final files = await pickFilesAsBytes();
    for (final f in files) {
      try {
        final a = await api.upload(f.bytes, f.name);
        if (mounted) setState(() => pending.add(_PendingUpload(Attachment(id: a.id, fileName: f.name, mimeType: a.mimeType, size: f.bytes.length))));
      } catch (e) {
        toastError(e, 'Upload failed');
      }
    }
  }

  Future<void> _react(ChatMessage m, String emoji) async {
    try {
      final r = await api.toggleMessageReaction(m.id, emoji);
      _apply(ChatUpdate(action: 'reaction', conversation: r.conversation, message: r.message));
    } catch (e) {
      toastError(e);
    }
  }

  Future<void> _edit(ChatMessage m) async {
    final v = await promptText(context, title: 'Edit message', initial: decodeMentionsForDisplay(m.body ?? ''), confirmLabel: 'Save');
    if (v == null || conv == null) return;
    try {
      final r = await api.editMessage(m.id, conv!.isGroup ? encodeMentionsForSend(v, conv!.memberList) : v);
      _apply(ChatUpdate(action: 'message', conversation: r.conversation, message: r.message));
    } catch (e) {
      toastError(e);
    }
  }

  Future<void> _delete(ChatMessage m) async {
    if (!await confirmDialog(context, title: 'Delete message?', message: 'This message will be removed for everyone.', confirmLabel: 'Delete', destructive: true)) return;
    try {
      final r = await api.deleteMessage(m.id);
      _apply(ChatUpdate(action: 'message', conversation: r.conversation, message: r.message));
    } catch (e) {
      toastError(e);
    }
  }

  Future<void> _assignTask() async {
    final uid = conv?.memberUserId;
    if (uid == null) return;
    final r = await showComposerDetailed(context, presetAssigneeId: uid);
    if (r == null || r.ids.isEmpty) return;
    await _send(buildTaskCreatedMessage(r.ids, title: r.title, description: r.description, lines: r.lines));
    toast('Task created and sent in chat');
  }

  void _onLink(String href) {
    final id = taskIdFromHref(href);
    if (id != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: id)));
    } else {
      launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
    }
  }

  void _messageMenu(ChatMessage m, bool mine) {
    showAppSheet(
      context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (final e in ['👍', '❤️', '😂', '🎉', '😮', '🙏'])
                InkWell(
                  key: ValueKey('msg-react-$e'),
                  borderRadius: BorderRadius.circular(99),
                  onTap: () {
                    Navigator.pop(ctx);
                    _react(m, e);
                  },
                  child: Padding(padding: const EdgeInsets.all(8), child: Text(e, style: const TextStyle(fontSize: 22))),
                ),
            ]),
          ),
          const Divider(),
          ListTile(
            key: const Key('msg-reply'),
            leading: const Icon(Icons.reply_rounded),
            title: const Text('Reply'),
            onTap: () {
              Navigator.pop(ctx);
              setState(() => replyTo = m);
            },
          ),
          if (mine) ...[
            ListTile(
              key: const Key('msg-edit'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(ctx);
                _edit(m);
              },
            ),
            ListTile(
              key: const Key('msg-delete'),
              leading: const Icon(Icons.delete_outline_rounded, color: TF.coral),
              title: const Text('Delete', style: TextStyle(color: TF.coral)),
              onTap: () {
                Navigator.pop(ctx);
                _delete(m);
              },
            ),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Obx(() => _reactiveBuild(context));

  Widget _reactiveBuild(BuildContext context) {
    final me = Get.find<AuthController>().me;
    final online = Get.find<RealtimeController>().presence.ids;
    final c = conv;

    return Column(children: [
      if (widget.showHeader)
        Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Brand.outline))),
          child: Row(children: [
            if (widget.showBack) const BackButton(),
            if (c != null) ...[
              c.isGroup
                  ? Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: Brand.navy, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.groups_2_rounded, color: Brand.lime, size: 20),
                    )
                  : Avatar(c.title, size: 38, online: online.contains(c.memberUserId)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    displayName(c.title),
                    key: const Key('thread-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Brand.navy),
                  ),
                  Text(
                    typingUsers.isNotEmpty
                        ? '${typingUsers.values.map(firstName).join(', ')} typing…'
                        : c.isGroup
                            ? c.memberList.map((m) => firstName(m.name)).join(', ')
                            : (online.contains(c.memberUserId) ? 'Online' : (c.memberEmail ?? c.memberRole ?? '')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: typingUsers.isNotEmpty || (!c.isGroup && online.contains(c.memberUserId)) ? FontWeight.w700 : FontWeight.w500,
                      color: typingUsers.isNotEmpty ? Brand.navy : (!c.isGroup && online.contains(c.memberUserId) ? TF.green : Brand.onVariant),
                    ),
                  ),
                ]),
              ),
              if (!c.isGroup)
                IconButton(
                  key: const Key('chat-assign-task'),
                  tooltip: 'Assign a task',
                  style: IconButton.styleFrom(backgroundColor: Brand.lime, foregroundColor: Brand.navy),
                  icon: const Icon(Icons.add_task_rounded, size: 20),
                  onPressed: _assignTask,
                ),
              if (c.isGroup && (me?.isAdminOrCeo ?? false))
                IconButton(
                  key: const Key('manage-group'),
                  tooltip: 'Manage group',
                  style: IconButton.styleFrom(backgroundColor: Brand.surfaceLow, foregroundColor: Brand.navy),
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  onPressed: () async {
                    final g = await showGroupForm(context, group: c);
                    if (g != null) setState(() => conv = g);
                  },
                ),
            ] else
              const Expanded(child: Text('Loading…')),
          ]),
        ),
      Expanded(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? ErrorView(message: error!, onRetry: _load)
                : messages.isEmpty
                    ? const Center(child: EmptyState(icon: Icons.waving_hand_outlined, title: 'Say hello', message: 'No messages yet.'))
                    : ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        itemCount: messages.length,
                        itemBuilder: (ctx, i) {
                          final m = messages[i];
                          final prev = i > 0 ? messages[i - 1] : null;
                          final showDay = m.createdAt != null &&
                              (prev?.createdAt == null || !DateUtils.isSameDay(prev!.createdAt, m.createdAt));
                          return Column(children: [
                            if (showDay)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Pill(fmtDayLabel(m.createdAt!), fg: Brand.onVariant, bg: Brand.surfaceMid),
                              ),
                            _bubble(m, m.authorId == me?.id),
                          ]);
                        },
                      ),
      ),
      _composer(),
    ]);
  }

  Widget _bubble(ChatMessage m, bool mine) {
    final parent = m.parentId == null ? null : messages.where((x) => x.id == m.parentId).firstOrNull;
    final isGroup = conv?.isGroup ?? false;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GestureDetector(
          key: ValueKey('msg-${m.id}'),
          onLongPress: m.isDeleted ? null : () => _messageMenu(m, mine),
          onSecondaryTap: m.isDeleted ? null : () => _messageMenu(m, mine),
          child: Container(
            margin: EdgeInsets.only(bottom: 6, left: mine ? 48 : 0, right: mine ? 0 : 48),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            decoration: BoxDecoration(
              color: m.isDeleted ? Brand.surfaceLow : (mine ? Brand.navy : Colors.white),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
              border: mine && !m.isDeleted ? null : Border.all(color: Brand.outline),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (isGroup && !mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(displayName(m.authorName), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Brand.onVariant)),
                ),
              if (parent != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  decoration: BoxDecoration(
                    color: mine ? Colors.white.withValues(alpha: 0.10) : Brand.surfaceLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border(left: BorderSide(color: mine ? Brand.lime : Brand.limeDim, width: 3)),
                  ),
                  child: Text(
                    '${displayName(parent.authorName)}: ${decodeMentionsForDisplay(parent.body ?? '')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: mine ? Colors.white70 : TF.muted),
                  ),
                ),
              if (m.isDeleted)
                const Text('Message deleted', style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: Brand.onVariant))
              else ...[
                if ((m.body ?? '').isNotEmpty)
                  RichBody(
                    m.body!,
                    onLink: _onLink,
                    linkColor: mine ? Brand.lime : Brand.navy,
                    style: TextStyle(fontSize: 13, height: 1.4, color: mine ? Colors.white : Brand.navy),
                  ),
                for (final a in m.attachments)
                  Padding(padding: const EdgeInsets.only(top: 6), child: SizedBox(width: 260, child: AttachmentTile(attachment: a, compact: true))),
              ],
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  '${fmtTime(m.createdAt)}${m.edited && !m.isDeleted ? ' · edited' : ''}',
                  style: TextStyle(fontSize: 10.5, color: mine && !m.isDeleted ? Colors.white.withValues(alpha: 0.6) : TF.faint),
                ),
              ]),
              if (m.reactions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(spacing: 4, runSpacing: 4, children: [
                    for (final r in m.reactions)
                      InkWell(
                        onTap: () => _react(m, r.emoji),
                        borderRadius: BorderRadius.circular(99),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: r.mine ? Brand.limeLight : Colors.white,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: r.mine ? Brand.limeDim : Brand.outline),
                          ),
                          child: Text('${r.emoji} ${r.count}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Brand.navy)),
                        ),
                      ),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _composer() {
    final mention = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(input.text);
    final members = conv?.isGroup == true ? conv!.memberList.where((m) => m.id != Get.find<AuthController>().me?.id).toList() : <({int id, String name})>[];
    final suggestions = mention == null
        ? <({int id, String name})>[]
        : members.where((m) => m.name.toLowerCase().contains(mention.group(1)!.toLowerCase())).take(6).toList();

    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Brand.outline))),
      padding: const EdgeInsets.fromLTRB(8, 8, 10, 10),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (suggestions.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final s in suggestions)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 6),
                    child: ActionChip(
                      avatar: Avatar(s.name, size: 22),
                      label: Text(displayName(s.name)),
                      onPressed: () {
                        final t = input.text;
                        final start = t.lastIndexOf('@');
                        input.text = '${t.substring(0, start)}@${displayName(s.name)} ';
                        input.selection = TextSelection.collapsed(offset: input.text.length);
                        setState(() {});
                      },
                    ),
                  ),
              ]),
            ),
          if (attached != null)
            _chip(Icons.task_alt_rounded, 'Task: ${attached!.title}', () => setState(() => attached = null), key: const Key('attached-task')),
          if (replyTo != null)
            _chip(Icons.reply_rounded, 'Replying to ${displayName(replyTo!.authorName)}', () => setState(() => replyTo = null)),
          for (final p in pending)
            _chip(Icons.attach_file_rounded, p.attachment.fileName, () {
              api.deleteUpload(p.attachment.id).catchError((_) {});
              setState(() => pending.remove(p));
            }),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(
              key: const Key('chat-attach'),
              tooltip: 'Attach',
              color: Brand.navy,
              onPressed: conv == null ? null : _attach,
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
            Expanded(
              child: TextField(
                key: const Key('chat-input'),
                controller: input,
                minLines: 1,
                maxLines: 5,
                onChanged: _onTyping,
                style: const TextStyle(fontSize: 13, color: Brand.navy),
                decoration: InputDecoration(
                  hintText: 'Message…',
                  fillColor: Brand.surfaceLow,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Brand.outline)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Brand.outline)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Brand.navy, width: 1.4)),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              key: const Key('chat-send'),
              style: IconButton.styleFrom(
                backgroundColor: Brand.navy,
                foregroundColor: Brand.lime,
                disabledBackgroundColor: Brand.surfaceMid,
                disabledForegroundColor: TF.faint,
                minimumSize: const Size(46, 46),
              ),
              onPressed: busy || conv == null || (input.text.trim().isEmpty && pending.isEmpty && attached == null) ? null : () => _send(),
              icon: const Icon(Icons.send_rounded, size: 20),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _chip(IconData icon, String label, VoidCallback onRemove, {Key? key}) => Container(
        key: key,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(10, 4, 2, 4),
        decoration: BoxDecoration(color: Brand.limeLight, borderRadius: BorderRadius.circular(10), border: Border.all(color: Brand.limeDim)),
        child: Row(children: [
          Icon(icon, size: 16, color: Brand.navy),
          const SizedBox(width: 6),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Brand.navy))),
          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close_rounded, size: 17), onPressed: onRemove),
        ]),
      );
}

/// Create (no [group]) or edit a group chat. Admin/CEO only.
Future<Conversation?> showGroupForm(BuildContext context, {Conversation? group}) =>
    showAppSheet<Conversation>(context, expand: true, builder: (_) => _GroupForm(group: group));

class _GroupForm extends StatefulWidget {
  const _GroupForm({this.group});
  final Conversation? group;

  @override
  State<_GroupForm> createState() => _GroupFormState();
}

class _GroupFormState extends State<_GroupForm> {
  final name = TextEditingController();
  List<AppUser> users = [];
  final Set<int> selected = {};
  bool busy = false;
  String q = '';

  @override
  void initState() {
    super.initState();
    final api = Get.find<TaskFlowApi>();
    name.text = widget.group?.name ?? '';
    api.users().then((u) {
      if (mounted) setState(() => users = u.where((x) => x.isActive).toList());
    }).catchError((Object e) {
      toastError(e);
    });
    if (widget.group != null) {
      api.groupDetail(widget.group!.id).then((d) {
        if (mounted) setState(() => selected.addAll(d.members.map((m) => m.id)));
      }).catchError((Object e) {
      toastError(e);
    });
    }
  }

  Future<void> _save() async {
    final api = Get.find<TaskFlowApi>();
    setState(() => busy = true);
    try {
      final g = widget.group == null
          ? await api.createGroup(name.text.trim(), selected.toList())
          : await api.updateGroup(widget.group!.id, name: name.text.trim(), memberIds: selected.toList());
      toast(widget.group == null ? 'Group created' : 'Group updated');
      if (mounted) Navigator.pop(context, g);
    } catch (e) {
      toastError(e);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = Get.find<AuthController>().me;
    final list = users.where((u) => u.id != me?.id && (q.isEmpty || u.name.toLowerCase().contains(q.toLowerCase()))).toList();
    return Column(children: [
      SheetTitle(widget.group == null ? 'New group' : 'Manage group', subtitle: '${selected.length} selected'),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(children: [
          TextField(key: const Key('group-name'), controller: name, decoration: const InputDecoration(hintText: 'Group name'), onChanged: (_) => setState(() {})),
          const SizedBox(height: 8),
          TextField(decoration: const InputDecoration(hintText: 'Search people…', prefixIcon: Icon(Icons.search_rounded, size: 20)), onChanged: (v) => setState(() => q = v)),
        ]),
      ),
      Expanded(
        child: ListView(children: [
          for (final u in list)
            CheckboxListTile(
              key: ValueKey('group-member-${u.id}'),
              value: selected.contains(u.id),
              onChanged: (v) => setState(() => v == true ? selected.add(u.id) : selected.remove(u.id)),
              secondary: Avatar(u.name),
              title: Text(u.name),
              subtitle: Text([u.teamName, u.role].whereType<String>().join(' · ')),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('group-save'),
              onPressed: busy || name.text.trim().isEmpty || selected.isEmpty ? null : _save,
              child: Text(widget.group == null ? 'Create group' : 'Save changes'),
            ),
          ),
        ),
      ),
    ]);
  }
}
