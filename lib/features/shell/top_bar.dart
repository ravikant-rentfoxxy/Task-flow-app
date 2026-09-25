import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/format.dart';
import '../../state/chat_unread_controller.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../notifications/notifications_screen.dart';

class TopBar extends StatelessWidget implements PreferredSizeWidget {
  const TopBar({super.key, required this.title, this.actions = const [], this.bottom});

  final String title;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      bottom: bottom,
      actions: [...actions, const NotificationBell(), const AccountButton(), const SizedBox(width: 8)],
    );
  }
}

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final unread = Get.find<AuthController>().unread + Get.find<ChatUnreadController>().total;
      return IconButton(
      key: const Key('notification-bell'),
      tooltip: 'Notifications',
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      icon: Badge(
        isLabelVisible: unread > 0,
        backgroundColor: TF.coral,
        label: Text(unread > 9 ? '9+' : '$unread', key: const Key('notification-count')),
        child: const Icon(Icons.notifications_none_rounded),
      ),
    );
    });
  }
}

class AccountButton extends StatelessWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context) => Obx(() => _build(context));

  Widget _build(BuildContext context) {
    final session = Get.find<AuthController>();
    final me = session.me;
    if (me == null) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      key: const Key('account-menu'),
      tooltip: 'Account',
      offset: const Offset(0, 48),
      onSelected: (v) async {
        if (v == 'logout') {
          Get.find<ChatUnreadController>().clear();
          await session.logout();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(displayName(me.name), style: const TextStyle(fontWeight: FontWeight.w700, color: TF.ink)),
            Text(me.email, style: const TextStyle(fontSize: 12, color: TF.muted)),
            const SizedBox(height: 6),
            Pill(me.roleLabel, fg: TF.primaryDeep, bg: TF.primarySoft),
          ]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          key: Key('logout'),
          value: 'logout',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.logout_rounded, color: TF.coral),
            title: Text('Log out', style: TextStyle(color: TF.coral)),
          ),
        ),
      ],
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Avatar(me.name, size: 34, dark: true)),
    );
  }
}
