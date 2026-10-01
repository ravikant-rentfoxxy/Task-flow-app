import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared lime-on-navy building blocks (dashboard style) used across screens.

const brandRed = Color(0xFFDC2626);
const brandRedSoft = Color(0xFFFEE2E2);
const brandRedInk = Color(0xFF991B1B);

/// Navy rounded card with soft lime glows — the top "hero" of a screen.
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 16)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Brand.navy,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [BoxShadow(color: Brand.navy.withValues(alpha: 0.10), blurRadius: 20, offset: const Offset(0, 6))],
    ),
    child: Stack(
      children: [
        Positioned(right: -50, top: -60, child: _glow(170, 0.10)),
        Positioned(right: 40, bottom: -70, child: _glow(120, 0.06)),
        Padding(padding: padding, child: child),
      ],
    ),
  );

  static Widget _glow(double size, double alpha) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: Brand.lime.withValues(alpha: alpha), shape: BoxShape.circle),
  );
}

/// Small uppercase label for use on [HeroCard] (white, 60%).
class HeroEyebrow extends StatelessWidget {
  const HeroEyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: Colors.white.withValues(alpha: 0.6)),
  );
}

/// Large white heading for use on [HeroCard].
class HeroTitle extends StatelessWidget {
  const HeroTitle(this.text, {super.key, this.maxLines = 2});
  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: Colors.white, height: 1.2),
  );
}

/// Lime pill with a navy dot, e.g. "LIVE".
class LivePill extends StatelessWidget {
  const LivePill({super.key, this.label = 'LIVE'});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(color: Brand.lime, borderRadius: BorderRadius.circular(99)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(color: Brand.navy, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: Brand.navy),
          ),
        ),
      ],
    ),
  );
}

/// Navy pill with lime text showing a count.
class CountBubble extends StatelessWidget {
  const CountBubble(this.count, {super.key});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 24),
    height: 22,
    padding: const EdgeInsets.symmetric(horizontal: 7),
    alignment: Alignment.center,
    decoration: BoxDecoration(color: Brand.navy, borderRadius: BorderRadius.circular(99)),
    child: Text(
      '$count',
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Brand.lime),
    ),
  );
}

/// Lime-light outlined tag (e.g. "30-min SLA", "open").
class LimeTag extends StatelessWidget {
  const LimeTag(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: Brand.limeLight,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Brand.limeDim),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Brand.navy),
    ),
  );
}

/// Lime accent bar · title · optional tag ······ count bubble or [trailing].
class BrandSectionTitle extends StatelessWidget {
  const BrandSectionTitle({super.key, required this.title, this.count, this.tag, this.trailing, this.padding = const EdgeInsets.only(bottom: 10)});
  final String title;
  final int? count;
  final String? tag;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(color: Brand.lime, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: Brand.navy),
                ),
              ),
              if (tag != null) ...[const SizedBox(width: 8), Flexible(child: LimeTag(tag!))],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!] else if (count != null) ...[const SizedBox(width: 8), CountBubble(count!)],
      ],
    ),
  );
}

/// White rounded card with the outline border (the standard surface).
class BrandCard extends StatelessWidget {
  const BrandCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap, this.borderColor});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: borderColor ?? Brand.outline)),
    clipBehavior: Clip.antiAlias,
    child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
  );
}

/// Small stat tile: icon square, big number, label, thin bar (dashboard counters).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.iconBg = Brand.lime,
    this.iconFg = Brand.navy,
    this.share,
    this.hot = false,
    this.onTap,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color iconBg;
  final Color iconFg;

  /// 0..1 fill of the thin bar; null hides it.
  final double? share;
  final bool hot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: hot ? brandRed.withValues(alpha: 0.3) : Brand.outline),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 15, color: iconFg),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1, letterSpacing: -0.6, color: hot ? brandRed : Brand.navy),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Brand.onVariant),
            ),
            if (share != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: share!.clamp(0, 1),
                  minHeight: 3,
                  color: hot ? brandRed : (iconBg == Brand.navy ? Brand.lime : (iconBg == Brand.surfaceMid ? Brand.navy : iconBg)),
                  backgroundColor: Brand.surfaceMid,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Segmented control on navy (lime selected). Each item: (key, label, selected, onTap).
class HeroSegments extends StatelessWidget {
  const HeroSegments({super.key, required this.items});
  final List<(Key?, String, bool, VoidCallback)> items;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    ),
    child: Row(
      children: [
        for (final (key, label, selected, onTap) in items)
          Expanded(
            child: GestureDetector(
              key: key,
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 32,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(color: selected ? Brand.lime : Colors.transparent, borderRadius: BorderRadius.circular(9)),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? Brand.navy : Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
