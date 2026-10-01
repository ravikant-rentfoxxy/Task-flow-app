import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Branded launch screen shown while the saved session is restored:
/// lime band with soft circles, the Work+ logo popping in, the wordmark and
/// tagline sliding up, and three navy dots pulsing near the bottom.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();
  late final _dots = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  late final _logoScale = CurvedAnimation(parent: _intro, curve: const Interval(0, 0.6, curve: Curves.elasticOut));
  late final _logoFade = CurvedAnimation(parent: _intro, curve: const Interval(0, 0.3, curve: Curves.easeOut));
  late final _text = CurvedAnimation(parent: _intro, curve: const Interval(0.35, 0.85, curve: Curves.easeOutCubic));
  late final _footer = CurvedAnimation(parent: _intro, curve: const Interval(0.7, 1, curve: Curves.easeOut));

  @override
  void dispose() {
    _intro.dispose();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
    child: Scaffold(
      backgroundColor: Brand.lime,
      body: Stack(
        fit: StackFit.expand, // content spans the full width so it centres
        children: [
          const Positioned.fill(child: _Circles()),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(flex: 5),
                FadeTransition(
                  opacity: _logoFade,
                  child: ScaleTransition(scale: _logoScale, child: const _Logo()),
                ),
                const SizedBox(height: 26),
                AnimatedBuilder(
                  animation: _text,
                  builder: (context, child) => Opacity(
                    opacity: _text.value,
                    child: Transform.translate(offset: Offset(0, 18 * (1 - _text.value)), child: child),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        FittedBox(
                          child: Text(
                            'WORK PLUS',
                            style: TextStyle(
                              fontFamily: kBrandFont,
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                              color: Brand.navy,
                            ),
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Every task accepted, tracked and delivered.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: Color(0xB80F172A)),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 6),
                FadeTransition(
                  opacity: _footer,
                  child: _PulseDots(animation: _dots),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Logo in a soft white ring with a navy shadow.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: 0.85),
      boxShadow: [BoxShadow(color: Brand.navy.withValues(alpha: 0.18), blurRadius: 30, offset: const Offset(0, 12))],
    ),
    child: const AppLogo(size: 104),
  );
}

/// The same soft circles as the login header.
class _Circles extends StatelessWidget {
  const _Circles();

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        right: -120,
        top: -110,
        child: _circle(300),
      ),
      Positioned(
        left: -90,
        top: 220,
        child: _circle(190),
      ),
      Positioned(
        right: -60,
        bottom: -80,
        child: _circle(220),
      ),
    ],
  );

  static Widget _circle(double size) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(color: Brand.limeDim, shape: BoxShape.circle),
  );
}

/// Three dots that grow and fade in turn.
class _PulseDots extends StatelessWidget {
  const _PulseDots({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Builder(
            builder: (context) {
              // Each dot peaks a third of a cycle after the previous one.
              final t = (animation.value - i / 3) % 1;
              final pulse = t < 0.5 ? t * 2 : (1 - t) * 2;
              return Transform.scale(
                scale: 0.7 + 0.3 * pulse,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: Brand.navy.withValues(alpha: 0.35 + 0.65 * pulse),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          ),
        ],
      ],
    ),
  );
}
