import 'package:flutter/material.dart';

/// Signed-out screens palette (indigo on lavender), kept local so the rest of
/// the app keeps the TF theme.
class AuthUi {
  static const bg = Color(0xFFF7F6FD);
  static const band = Color(0xFFF2F1FB);
  static const ink = Color(0xFF111827);
  static const label = Color(0xFF374151);
  static const icon = Color(0xFF4B5563);
  static const muted = Color(0xFF6B7280);
  static const field = Color(0xFFF0F1FE);
  static const fieldActive = Color(0xFFDEE1FB);
  static const primary = Color(0xFF4F46E5);
  static const link = Color(0xFF3B2FD9);
  static const online = Color(0xFF1F8A70);
  static const success = Color(0xFF0F6E4A);

  static const inputText = TextStyle(fontSize: 16.5, color: ink, letterSpacing: 0.1);

  static InputDecoration input({required String hint, IconData? icon, Widget? suffix, Color fill = field}) {
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none);
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 16),
      filled: true,
      fillColor: fill,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      prefixIcon: icon == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 12, right: 6),
              child: Icon(icon, size: 24, color: AuthUi.icon),
            ),
      prefixIconConstraints: const BoxConstraints(minWidth: 48),
      suffixIcon: suffix == null ? null : Padding(padding: const EdgeInsets.only(right: 6), child: suffix),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: primary.withValues(alpha: 0.7), width: 1.5),
      ),
    );
  }

  /// Full-width indigo call-to-action with a trailing arrow and soft glow.
  static Widget primaryButton({Key? key, required String label, required VoidCallback? onPressed, bool busy = false}) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 6))],
    ),
    child: FilledButton(
      key: key,
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        disabledBackgroundColor: primary.withValues(alpha: 0.6),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (!busy) ...[const SizedBox(width: 10), const Icon(Icons.arrow_forward_rounded, size: 22)],
        ],
      ),
    ),
  );
}

class AuthLogoTile extends StatelessWidget {
  const AuthLogoTile({super.key, this.size = 72, this.light = false});
  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: light ? Colors.white : AuthUi.ink,
      borderRadius: BorderRadius.circular(size * 0.24),
      border: Border.all(color: Colors.white, width: size > 48 ? 2 : 1),
      boxShadow: [BoxShadow(color: AuthUi.ink.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6))],
    ),
    child: Text(
      'TF',
      style: TextStyle(
        color: light ? AuthUi.primary : Colors.white,
        fontSize: size * 0.4,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
    ),
  );
}

/// White rounded card with a faint indigo shadow.
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.children, this.padding = const EdgeInsets.fromLTRB(20, 24, 20, 24)});
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: AuthUi.primary.withValues(alpha: 0.07), blurRadius: 30, offset: const Offset(0, 12))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );
}

/// Back · TF tile · TaskFlow ········ title · avatar.
class AuthTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AuthTopBar({super.key, required this.title, this.onBack});
  final String title;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.7),
    child: SafeArea(
      bottom: false,
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22, color: AuthUi.label),
              onPressed: onBack ?? () => Navigator.maybePop(context),
            ),
            const SizedBox(width: 4),
            const AuthLogoTile(size: 34),
            const SizedBox(width: 10),
            const Text(
              'TaskFlow',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AuthUi.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, letterSpacing: 0.2, color: AuthUi.label),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(color: AuthUi.primary, shape: BoxShape.circle),
              child: const Icon(Icons.person_outline_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
          ],
        ),
      ),
    ),
  );
}
