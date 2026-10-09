import 'package:flutter/material.dart';

import '../../widgets/common.dart';

/// Signed-out screens palette (lime on navy), kept local so the rest of
/// the app keeps the TF theme.
class AuthUi {
  static const bg = Color(0xFFF7F8FA);
  static const ink = Color(0xFF111827);
  static const label = Color(0xFF374151);
  static const icon = Color(0xFF4B5563);
  static const muted = Color(0xFF6B7280);
  static const faint = Color(0xFF9CA3AF);
  static const lime = Color(0xFFCBF231);
  static const limeDeep = Color(0xFFBFE82A);
  static const limeSoft = Color(0xFFF2F7DF);
  static const limeLine = Color(0xFFE4F0A6);
  static const olive = Color(0xFF4D6B00);
  static const field = Color(0xFFF3F6E6);
  static const fieldLine = Color(0xFFE5E7EB);
  static const success = Color(0xFF3F7A12);

  static const inputText = TextStyle(fontSize: 16.5, color: ink, letterSpacing: 0.1);

  /// White field with a thin grey border when idle ([outlined] makes it lime).
  static InputDecoration input({required String hint, IconData? icon, Widget? suffix, bool outlined = false}) {
    final idle = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: outlined ? limeLine : fieldLine, width: 1.2),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: faint, fontSize: 16),
      filled: true,
      fillColor: Colors.white,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      prefixIcon: icon == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 14, right: 6),
              child: Icon(icon, size: 24, color: AuthUi.icon),
            ),
      prefixIconConstraints: const BoxConstraints(minWidth: 52),
      suffixIcon: suffix == null ? null : Padding(padding: const EdgeInsets.only(right: 6), child: suffix),
      border: idle,
      enabledBorder: idle,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: ink, width: 1.5),
      ),
    );
  }

  /// Full-width navy call-to-action with an optional lime trailing arrow.
  static Widget primaryButton({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    bool busy = false,
    bool arrow = true,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      boxShadow: onPressed == null
          ? null
          : [BoxShadow(color: ink.withValues(alpha: 0.22), blurRadius: 16, offset: const Offset(0, 8))],
    ),
    child: FilledButton(
      key: key,
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        disabledBackgroundColor: ink.withValues(alpha: 0.45),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white,
        minimumSize: const Size.fromHeight(58),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w700, letterSpacing: 0.1),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
          ),
          if (arrow && !busy) ...[
            const SizedBox(width: 12),
            Icon(Icons.arrow_forward_rounded, size: 22, color: onPressed == null ? Colors.white : lime),
          ],
        ],
      ),
    ),
  );
}

/// Work+ logo with a soft white ring.
class AuthLogoTile extends StatelessWidget {
  const AuthLogoTile({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(size > 48 ? 4 : 0),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xFFE9EBEE),
      boxShadow: [BoxShadow(color: AuthUi.ink.withValues(alpha: 0.14), blurRadius: 18, offset: const Offset(0, 6))],
    ),
    child: AppLogo(size: size),
  );
}

/// White rounded card with a faint shadow.
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.children, this.padding = const EdgeInsets.fromLTRB(20, 24, 20, 24)});
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFEFF1F4)),
      boxShadow: [BoxShadow(color: AuthUi.ink.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 10))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );
}

/// Small lime-tinted pill used for badges and footers.
class AuthPill extends StatelessWidget {
  const AuthPill({super.key, required this.child, this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 6)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: AuthUi.limeSoft,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: AuthUi.limeLine),
    ),
    child: child,
  );
}

/// Back · logo · Work Plus ········ title · avatar.
class AuthTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AuthTopBar({super.key, required this.title, this.onBack});
  final String title;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(65);

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.85),
    child: SafeArea(
      bottom: false,
      child: Container(
        height: 65,
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE9EBEF)))),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22, color: AuthUi.ink),
              onPressed: onBack ?? () => Navigator.maybePop(context),
            ),
            const SizedBox(width: 2),
            const AppLogo(size: 36),
            const SizedBox(width: 10),
            const Text(
              'Work Plus',
              style: TextStyle(fontFamily: kBrandFont, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: AuthUi.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, letterSpacing: 0.2, color: AuthUi.muted),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(color: AuthUi.ink, shape: BoxShape.circle),
              child: const Icon(Icons.person_outline_rounded, color: AuthUi.lime, size: 22),
            ),
            const SizedBox(width: 14),
          ],
        ),
      ),
    ),
  );
}
