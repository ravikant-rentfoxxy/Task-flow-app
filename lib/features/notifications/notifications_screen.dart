import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/format.dart';
import '../../core/task_logic.dart';
import '../../data/taskflow_api.dart';
import '../../models/models.dart';
import '../../state/chat_unread_controller.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_ui.dart';
import '../../widgets/common.dart';
import '../chat/chat_screen.dart';
import '../tasks/task_detail_screen.dart';
import '../shell/top_bar.dart';

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
    final empty = list?.isEmpty ?? true;
    final groups = _group(list ?? const []);
    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: AppBar(title: BrandTitle.text('Notifications')),
      body: RefreshIndicator(
        color: Brand.navy,
        backgroundColor: Brand.lime,
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
          PageBody(
            maxWidth: 720,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              HeroCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const HeroEyebrow('Inbox'),
                  const SizedBox(height: 8),
                  Row(children: [
                    if (unread > 0) ...[
                      Container(
                        constraints: const BoxConstraints(minWidth: 34),
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: Brand.lime, borderRadius: BorderRadius.circular(10)),
                        child: Text('$unread', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Brand.navy)),
                      ),
                      const SizedBox(width: 10),
                    ] else ...[
                      const Icon(Icons.check_circle_rounded, size: 20, color: Brand.lime),
                      const SizedBox(width: 8),
                    ],
                    Expanded(child: HeroTitle(unread > 0 ? 'unread' : "You're all caught up", maxLines: 1)),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (list != null) '${list.length} ${list.length == 1 ? 'notification' : 'notifications'}',
                      if (chat.isNotEmpty) '${chat.length} unread ${chat.length == 1 ? 'chat' : 'chats'}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('mark-all-read'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Brand.lime,
                          foregroundColor: Brand.navy,
                          disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
                          disabledForegroundColor: Colors.white.withValues(alpha: 0.35),
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: empty
                            ? null
                            : () => api.markNotificationsRead(all: true).then((_) => _after('All notifications marked read')).catchError((Object e) => toastError(e)),
                        icon: const Icon(Icons.done_all_rounded, size: 17),
                        label: const Text('Mark all read', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('clear-notifications'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white.withValues(alpha: 0.35),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: empty
                            ? null
                            : () => api.clearNotifications().then((_) => _after('Notifications cleared')).catchError((Object e) => toastError(e)),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 17),
                        label: const Text('Clear', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 22),
              if (chat.isNotEmpty) ...[
                BrandSectionTitle(title: 'Chat', count: chat.length),
                for (final e in chat)
                  _Tile(
                    emoji: '💬',
                    title: e.name,
                    body: e.preview,
                    unread: true,
                    trailing: e.count > 1 ? CountBubble(e.count) : null,
                    onTap: () {
                      Get.find<ChatUnreadController>().markRead(e.conversationId);
                      openChatConversation(context, e.conversationId);
                    },
                  ),
                const SizedBox(height: 14),
              ],
              if (list == null && error == null) const SkeletonList(height: 64),
              if (error != null && list == null) ErrorView(message: error!, onRetry: _load),
              if (list != null && list.isEmpty && chat.isEmpty)
                const BrandCard(
                  child: EmptyState(icon: Icons.notifications_none_rounded, color: Brand.navy, title: 'No notifications', message: 'You are all caught up.'),
                ),
              for (final (title, group) in groups) ...[
                BrandSectionTitle(title: title, count: group.length),
                for (final n in group)
                  _Tile(
                    key: ValueKey('notification-${n.id}'),
                    emoji: notificationIcons[n.type] ?? '🔔',
                    title: n.title,
                    body: n.body,
                    time: timeAgo(n.createdAt),
                    unread: !n.isRead,
                    onTap: () => _open(n),
                  ),
                const SizedBox(height: 14),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  /// Splits notifications (already newest first) into Today / Yesterday / Earlier.
  static List<(String, List<AppNotification>)> _group(List<AppNotification> list) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final buckets = <String, List<AppNotification>>{'Today': [], 'Yesterday': [], 'Earlier': []};
    for (final n in list) {
      final c = n.createdAt?.toLocal();
      final key = c == null || c.isBefore(yesterday) ? 'Earlier' : (c.isBefore(today) ? 'Yesterday' : 'Today');
      buckets[key]!.add(n);
    }
    return [for (final e in buckets.entries) if (e.value.isNotEmpty) (e.key, e.value)];
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
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: unread ? Brand.limeDim : Brand.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: unread ? Brand.limeLight : Brand.surfaceLow, borderRadius: BorderRadius.circular(10)),
                  child: Text(emoji, style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600, color: Brand.navy, fontSize: 13.5, height: 1.3)),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 9,
                          height: 9,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(color: Brand.lime, shape: BoxShape.circle, border: Border.all(color: Brand.navy, width: 1.5)),
                        ),
                      ],
                    ]),
                    if (body != null && body!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(body!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, height: 1.35, color: Brand.onVariant)),
                    ],
                    if (time != null) ...[
                      const SizedBox(height: 4),
                      Text(time!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: TF.faint)),
                    ],
                  ]),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ]),
            ),
          ),
        ),
      );
}
