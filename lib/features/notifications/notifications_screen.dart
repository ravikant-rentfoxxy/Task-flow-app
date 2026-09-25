import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/format.dart';
import '../../core/task_logic.dart';
import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../state/chat_unread_controller.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../chat/chat_screen.dart';
import '../tasks/task_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification>? items;
  String? error;

  TaskFlowApi get api => Get.find<TaskFlowApi>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final n = await api.notifications();
      if (mounted) setState(() => (items = n, error = null));
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    }
  }

  Future<void> _after(String message) async {
    await _load();
    if (mounted) await Get.find<AuthController>().refreshQuietly();
    toast(message);
  }

  Future<void> _open(AppNotification n) async {
    api.markNotificationsRead(ids: [n.id]).then((_) {
      if (mounted) Get.find<AuthController>().refreshQuietly();
    }).catchError((_) {});
    if (n.taskId != null) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: n.taskId!)));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) => Obx(() => _reactiveBuild(context));

  Widget _reactiveBuild(BuildContext context) {
    final chat = Get.find<ChatUnreadController>().entries;
    final list = items;
    final unread = (list ?? []).where((n) => !n.isRead).length + Get.find<ChatUnreadController>().total;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            key: const Key('mark-all-read'),
            onPressed: (list?.isEmpty ?? true)
                ? null
                : () => api.markNotificationsRead(all: true).then((_) => _after('All notifications marked read')).catchError((Object e) => toastError(e)),
            child: const Text('Mark read'),
          ),
          TextButton(
            key: const Key('clear-notifications'),
            onPressed: (list?.isEmpty ?? true)
                ? null
                : () => api.clearNotifications().then((_) => _after('Notifications cleared')).catchError((Object e) => toastError(e)),
            child: const Text('Clear', style: TextStyle(color: TF.muted)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          PageBody(
            maxWidth: 720,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (unread > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('$unread unread', style: const TextStyle(color: TF.muted, fontWeight: FontWeight.w600)),
                ),
              if (chat.isNotEmpty) ...[
                const SectionHeader(title: 'Chat', icon: Icons.forum_outlined, color: TF.sky),
                for (final e in chat)
                  _Tile(
                    emoji: '💬',
                    title: e.name,
                    body: e.preview,
                    unread: true,
                    trailing: e.count > 1 ? Pill('${e.count}', fg: Colors.white, bg: TF.ink) : null,
                    onTap: () {
                      Get.find<ChatUnreadController>().markRead(e.conversationId);
                      openChatConversation(context, e.conversationId);
                    },
                  ),
                const SizedBox(height: 12),
                const SectionHeader(title: 'Tasks', icon: Icons.task_alt_rounded),
              ],
              if (list == null && error == null) const SkeletonList(height: 64),
              if (error != null && list == null) ErrorView(message: error!, onRetry: _load),
              if (list != null && list.isEmpty && chat.isEmpty)
                const EmptyState(icon: Icons.notifications_none_rounded, title: 'No notifications', message: 'You are all caught up.'),
              for (final n in list ?? const <AppNotification>[])
                _Tile(
                  key: ValueKey('notification-${n.id}'),
                  emoji: notificationIcons[n.type] ?? '🔔',
                  title: n.title,
                  body: n.body,
                  time: timeAgo(n.createdAt),
                  unread: !n.isRead,
                  onTap: () => _open(n),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.emoji, required this.title, this.body, this.time, this.unread = false, this.onTap, this.trailing});

  final String emoji;
  final String title;
  final String? body;
  final String? time;
  final bool unread;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: unread ? TF.primarySoft.withValues(alpha: 0.6) : TF.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: unread ? TF.primary.withValues(alpha: 0.18) : TF.line),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500, color: TF.ink, fontSize: 14)),
                    if (body != null && body!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(body!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: TF.muted)),
                    ],
                    if (time != null) ...[
                      const SizedBox(height: 4),
                      Text(time!, style: const TextStyle(fontSize: 11.5, color: TF.faint)),
                    ],
                  ]),
                ),
                ?trailing,
              ]),
            ),
          ),
        ),
      );
}
