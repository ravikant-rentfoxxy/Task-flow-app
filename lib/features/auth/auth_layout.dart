import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'auth_style.dart';

const _sheetRadius = 40.0;

/// Signed-out page frame shared by login and sign-up: a lime hero beside the
/// form on wide screens, otherwise a lime brand header with the form on a
/// white sheet.
///
/// Passing [title] switches the phone header to a compact one (back button,
/// small logo, then the title in the lime band) so sub-screens such as
/// sign-up don't look like the login page; on wide screens the title sits
/// above the form instead.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.form,
    this.tagline = 'Your workspace, signed in',
    this.heroTitle = 'Every task accepted,\ntracked and delivered.',
    this.title,
    this.subtitle,
    this.onBack,
  });
  final Widget form;
  final String tagline;
  final String heroTitle;
  final String? title;
  final String? subtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 900;
          if (wide) {
            return Row(
              children: [
                Expanded(
                  child: _Hero(title: heroTitle, onBack: onBack),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (title != null) ...[
                                Text(
                                  title!,
                                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: AuthUi.ink),
                                ),
                                if (subtitle != null) ...[
                                  const SizedBox(height: 6),
                                  Text(subtitle!, style: const TextStyle(fontSize: 15.5, color: AuthUi.muted)),
                                ],
                                const SizedBox(height: 28),
                              ],
                              form,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          // White sheet with rounded top corners overlapping the lime header.
          return ColoredBox(
            color: AuthUi.lime,
            child: CustomScrollView(
              physics: const ClampingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: title == null
                      ? _BrandHeader(tagline: tagline, onBack: onBack)
                      : _CompactHeader(title: title!, subtitle: subtitle, onBack: onBack),
                ),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Container(
                    alignment: Alignment.topCenter,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(_sheetRadius)),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Padding(padding: const EdgeInsets.fromLTRB(24, 28, 24, 32), child: form),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Bold field label above an auth input.
class AuthLabel extends StatelessWidget {
  const AuthLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: AuthUi.ink),
    ),
  );
}

/// "Don't have an account? Sign up" style prompt + inline link.
class AuthSwitchLink extends StatelessWidget {
  const AuthSwitchLink({super.key, required this.prompt, required this.action, required this.onPressed, this.linkKey});
  final String prompt;
  final String action;
  final VoidCallback? onPressed;
  final Key? linkKey;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text('$prompt ', style: const TextStyle(fontSize: 15, color: AuthUi.muted)),
      TextButton(
        key: linkKey,
        style: TextButton.styleFrom(
          foregroundColor: AuthUi.ink,
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        onPressed: onPressed,
        child: Text(action),
      ),
    ],
  );
}

class _BackButton extends StatelessWidget {
  const _BackButton(this.onPressed);
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('auth-back'),
    tooltip: 'Back',
    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22, color: AuthUi.ink),
    onPressed: onPressed,
  );
}

/// Soft background blobs on the lime band.
class _Blobs extends StatelessWidget {
  const _Blobs();

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        right: -110,
        top: -125,
        child: Container(
          width: 260,
          height: 260,
          decoration: const BoxDecoration(color: AuthUi.limeDeep, shape: BoxShape.circle),
        ),
      ),
      Positioned(
        left: -70,
        top: 80,
        child: Container(
          width: 150,
          height: 150,
          decoration: const BoxDecoration(color: AuthUi.limeDeep, shape: BoxShape.circle),
        ),
      ),
    ],
  );
}

/// Lime band with logo, wordmark and tagline; the form sheet sits below it.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.tagline, this.onBack});
  final String tagline;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Container(
      color: AuthUi.lime,
      child: Stack(
        children: [
          const Positioned.fill(child: _Blobs()),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              child: Center(
                child: Column(
                  children: [
                    const AuthLogoTile(size: 66),
                    const SizedBox(height: 18),
                    const FittedBox(
                      child: Text(
                        'WORK PLUS',
                        style: TextStyle(
                          fontFamily: kBrandFont,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          color: AuthUi.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tagline,
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: AuthUi.ink.withValues(alpha: 0.72)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onBack != null)
            SafeArea(
              bottom: false,
              child: Padding(padding: const EdgeInsets.all(8), child: _BackButton(onBack!)),
            ),
        ],
      ),
    ),
  );
}

/// Short lime band: back · small logo · wordmark, then a left-aligned page
/// title. Used instead of [_BrandHeader] when the page has its own title.
class _CompactHeader extends StatelessWidget {
  const _CompactHeader({required this.title, this.subtitle, this.onBack});
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Container(
      color: AuthUi.lime,
      child: Stack(
        children: [
          const Positioned.fill(child: _Blobs()),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 24, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (onBack != null) _BackButton(onBack!) else const SizedBox(width: 16),
                      const AuthLogoTile(size: 34),
                      const SizedBox(width: 10),
                      const Text(
                        'WORK PLUS',
                        style: TextStyle(
                          fontFamily: kBrandFont,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: AuthUi.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            height: 1.1,
                            color: AuthUi.ink,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            subtitle!,
                            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: AuthUi.ink.withValues(alpha: 0.72)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.title, this.onBack});
  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(16),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(color: AuthUi.lime, borderRadius: BorderRadius.circular(32)),
    child: Stack(
      children: [
        const Positioned.fill(child: _Blobs()),
        Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (onBack != null) ...[_BackButton(onBack!), const SizedBox(width: 6)],
                  const AuthLogoTile(size: 48),
                  const SizedBox(width: 14),
                  const Text(
                    'WORK PLUS',
                    style: TextStyle(
                      fontFamily: kBrandFont,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: AuthUi.ink,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(color: AuthUi.ink, fontSize: 38, fontWeight: FontWeight.w800, height: 1.12, letterSpacing: -1.2),
              ),
              const SizedBox(height: 16),
              Text(
                '30-minute response SLAs, ETAs, escalations and team chat — in one place.',
                style: TextStyle(color: AuthUi.ink.withValues(alpha: 0.72), fontSize: 16),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in ['Accept + ETA', 'Escalations', 'Reports', 'Chat'])
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(color: AuthUi.ink, borderRadius: BorderRadius.circular(99)),
                      child: Text(
                        s,
                        style: const TextStyle(color: AuthUi.lime, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
