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

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final list = RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
          TextField(
            key: const Key('chat-search'),
            decoration: InputDecoration(
              hintText: 'Search people or groups…',
              prefixIcon: const Icon(Icons.search_rounded, size: 22),
              fillColor: TF.surface,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: TF.line)),
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 12),
          if (conversations == null && error == null) const SkeletonList(height: 62),
          if (error != null && conversations == null) ErrorView(message: error!, onRetry: _load),
          if (convs.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.fromLTRB(4, 4, 4, 6), child: Text('RECENT', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1, color: TF.primaryDeep))),
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
            const Padding(padding: EdgeInsets.fromLTRB(4, 14, 4, 6), child: Text('PEOPLE', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1, color: TF.primaryDeep))),
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
        appBar: TopBar(title: 'Chat', actions: [
          if (me?.isAdminOrCeo ?? false)
            IconButton(key: const Key('new-group'), tooltip: 'New group', onPressed: _newGroup, icon: const Icon(Icons.group_add_outlined)),
        ]),
        body: !wide
            ? list
            : Row(children: [
                SizedBox(width: 340, child: list),
                const VerticalDivider(width: 1),
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
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? TF.primary.withValues(alpha: 0.35) : TF.line),
          boxShadow: Brand.shadow,
        ),
        child: Material(
        color: selected ? TF.primarySoft : TF.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              group
                  ? Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: TF.violetSoft, borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.groups_2_rounded, color: TF.violet),
                    )
                  : Avatar(title, size: 42, online: online),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(displayName(title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w700, fontSize: 14.5)),
                    ),
                    if (time != null) Text(timeAgo(time), style: const TextStyle(fontSize: 11, color: TF.faint)),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    Expanded(
                      child: Text(decodeMentionsForDisplay(subtitle).replaceAll('\n', ' '),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: TF.muted)),
                    ),
                    if (unread > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: TF.primary, borderRadius: BorderRadius.circular(99)),
                        child: Text(unread > 9 ? '9+' : '$unread',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                  ]),
                ]),
              ),
            ]),
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
                  child: Padding(padding: const EdgeInsets.all(8), child: Text(e, style: const TextStyle(fontSize: 26))),
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
          decoration: const BoxDecoration(color: TF.surface, border: Border(bottom: BorderSide(color: TF.line))),
          child: Row(children: [
            if (widget.showBack) const BackButton(),
            if (c != null) ...[
              c.isGroup
                  ? Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: TF.violetSoft, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.groups_2_rounded, color: TF.violet, size: 20),
                    )
                  : Avatar(c.title, size: 38, online: online.contains(c.memberUserId)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(displayName(c.title), key: const Key('thread-title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                  Text(
                    typingUsers.isNotEmpty
                        ? '${typingUsers.values.map(firstName).join(', ')} typing…'
                        : c.isGroup
                            ? c.memberList.map((m) => firstName(m.name)).join(', ')
                            : (online.contains(c.memberUserId) ? 'Online' : (c.memberEmail ?? c.memberRole ?? '')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: typingUsers.isNotEmpty ? TF.primary : TF.muted),
                  ),
                ]),
              ),
              if (!c.isGroup)
                IconButton(key: const Key('chat-assign-task'), tooltip: 'Assign a task', icon: const Icon(Icons.add_task_rounded), onPressed: _assignTask),
              if (c.isGroup && (me?.isAdminOrCeo ?? false))
                IconButton(
                  key: const Key('manage-group'),
                  tooltip: 'Manage group',
                  icon: const Icon(Icons.settings_outlined),
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
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
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
                                child: Pill(fmtDayLabel(m.createdAt!), fg: TF.muted, bg: TF.sunken),
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
              color: m.isDeleted ? TF.sunken : (mine ? TF.primary : TF.surface),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
              border: mine ? null : Border.all(color: TF.line),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (isGroup && !mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(displayName(m.authorName), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: TF.violet)),
                ),
              if (parent != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  decoration: BoxDecoration(
                    color: mine ? Colors.white.withValues(alpha: 0.15) : TF.paper,
                    borderRadius: BorderRadius.circular(8),
                    border: Border(left: BorderSide(color: mine ? Colors.white70 : TF.primary, width: 3)),
                  ),
                  child: Text(
                    '${displayName(parent.authorName)}: ${decodeMentionsForDisplay(parent.body ?? '')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: mine ? Colors.white70 : TF.muted),
                  ),
                ),
              if (m.isDeleted)
                const Text('Message deleted', style: TextStyle(fontStyle: FontStyle.italic, color: TF.muted))
              else ...[
                if ((m.body ?? '').isNotEmpty)
                  RichBody(
                    m.body!,
                    onLink: _onLink,
                    linkColor: mine ? Colors.white : TF.primary,
                    style: TextStyle(fontSize: 14.5, height: 1.4, color: mine ? Colors.white : TF.ink),
                  ),
                for (final a in m.attachments)
                  Padding(padding: const EdgeInsets.only(top: 6), child: SizedBox(width: 260, child: AttachmentTile(attachment: a, compact: true))),
              ],
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  '${fmtTime(m.createdAt)}${m.edited && !m.isDeleted ? ' · edited' : ''}',
                  style: TextStyle(fontSize: 10.5, color: mine && !m.isDeleted ? Colors.white70 : TF.faint),
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
                            color: r.mine ? TF.amberSoft : Colors.white,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: TF.line),
                          ),
                          child: Text('${r.emoji} ${r.count}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: TF.ink)),
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
      decoration: const BoxDecoration(color: TF.surface, border: Border(top: BorderSide(color: TF.line))),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
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
            IconButton(key: const Key('chat-attach'), tooltip: 'Attach', onPressed: conv == null ? null : _attach, icon: const Icon(Icons.add_circle_outline_rounded)),
            Expanded(
              child: TextField(
                key: const Key('chat-input'),
                controller: input,
                minLines: 1,
                maxLines: 5,
                onChanged: _onTyping,
                decoration: const InputDecoration(hintText: 'Message…'),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              key: const Key('chat-send'),
              style: IconButton.styleFrom(backgroundColor: TF.primary, minimumSize: const Size(46, 46)),
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
        decoration: BoxDecoration(color: TF.primarySoft, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(icon, size: 16, color: TF.primaryDeep),
          const SizedBox(width: 6),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: TF.primaryDeep))),
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
