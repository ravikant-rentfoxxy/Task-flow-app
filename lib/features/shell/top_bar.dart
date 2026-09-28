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
  Size get preferredSize => Size.fromHeight(68 + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Brand.line))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(height: 67, child: _BrandRow(subtitle: title, actions: actions)), // 68 minus the 1px border
            ?bottom,
          ]),
        ),
      ),
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

/// White header with the TF tile, "TaskFlow" and the screen name, plus bell and account.
/// White header with the TF tile, "TaskFlow" and the screen name, plus bell and account.
class BrandTopBar extends StatelessWidget implements PreferredSizeWidget {
  const BrandTopBar({super.key, required this.subtitle});
  final String subtitle;

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SafeArea(
      bottom: false,
      child: Container(
        height: 68,
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Brand.line))),
        child: _BrandRow(subtitle: subtitle),
      ),
    ),
  );
}

/// Back (when pushed) · TF tile · TaskFlow / [subtitle] ······ [actions] · bell · account.
class _BrandRow extends StatelessWidget {
  const _BrandRow({required this.subtitle, this.actions = const []});
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
    child: Row(
      children: [
        // Pushed screens (e.g. Reports from More) get a back arrow.
        if (ModalRoute.of(context)?.canPop ?? false)
          IconButton(
            tooltip: 'Back',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Brand.inkSoft),
            onPressed: () => Navigator.maybePop(context),
          ),
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Brand.ink, borderRadius: BorderRadius.circular(11)),
          child: const Text('TF', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TaskFlow',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: Brand.ink, height: 1.1),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: Brand.muted, letterSpacing: 0.2),
              ),
            ],
          ),
        ),
        ...actions,
        const NotificationBell(),
        const AccountButton(),
        const SizedBox(width: 4),
      ],
    ),
  );
}

/// AppBar title for pushed pages: small TF tile + [child] (usually the page name).
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key, required this.child});
  BrandTitle.text(String text, {super.key}) : child = Text(text, overflow: TextOverflow.ellipsis);
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Brand.ink, borderRadius: BorderRadius.circular(9)),
        child: const Text('TF', style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800)),
      ),
      const SizedBox(width: 10),
      Flexible(child: child),
    ],
  );
}
