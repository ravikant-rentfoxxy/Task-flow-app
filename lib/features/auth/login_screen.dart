import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../state/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'auth_style.dart';
import 'reset_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool obscure = true;
  String? error;

  Future<void> _submit() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter your email and password');
      return;
    }
    setState(() => (busy = true, error = null));
    try {
      await Get.find<AuthController>().login(email.text, password.text);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e, 'Login failed'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Opens the reset flow; after a successful reset we're back here with the email filled in.
  Future<void> _openReset() async {
    final resetEmail = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => ResetPasswordScreen(initialEmail: email.text.trim())));
    if (resetEmail == null || !mounted) return;
    setState(() {
      email.text = resetEmail;
      password.clear();
      error = null;
    });
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 900;
          final form = Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Welcome back',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: AuthUi.ink),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Sign in with your work email to continue',
                    style: TextStyle(fontSize: 15.5, color: AuthUi.muted),
                  ),
                  const SizedBox(height: 28),
                  const _Label('Work email'),
                  TextField(
                    key: const Key('login-email'),
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    style: AuthUi.inputText,
                    decoration: AuthUi.input(hint: 'you@rentfoxxy.com'),
                  ),
                  const SizedBox(height: 20),
                  const _Label('Password'),
                  TextField(
                    key: const Key('login-password'),
                    controller: password,
                    obscureText: obscure,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    style: AuthUi.inputText,
                    decoration: AuthUi.input(
                      hint: '••••••••',
                      suffix: IconButton(
                        tooltip: obscure ? 'Show password' : 'Hide password',
                        icon: Icon(
                          obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          size: 22,
                          color: AuthUi.icon,
                        ),
                        onPressed: () => setState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const Key('reset-password'),
                      style: TextButton.styleFrom(
                        foregroundColor: AuthUi.ink,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      onPressed: _openReset,
                      child: const Text('Forgot password?'),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    InfoBanner(
                      key: const Key('login-error'),
                      text: error!,
                      fg: TF.coral,
                      bg: TF.coralSoft,
                      icon: Icons.error_outline_rounded,
                    ),
                  ],
                  const SizedBox(height: 24),
                  AuthUi.primaryButton(
                    key: const Key('login-submit'),
                    label: busy ? 'Signing in…' : 'Sign in',
                    busy: busy,
                    arrow: false,
                    onPressed: busy ? null : _submit,
                  ),
                ],
              ),
            ),
          );
          if (wide) {
            return Row(
              children: [
                const Expanded(child: _Hero()),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: form),
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
                const SliverToBoxAdapter(child: _BrandHeader()),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Container(
                    alignment: Alignment.topCenter,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(_sheetRadius)),
                    ),
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: form),
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

class _Label extends StatelessWidget {
  const _Label(this.text);
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

const _sheetRadius = 40.0;

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
  const _BrandHeader();

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
                        style: TextStyle(fontFamily: kBrandFont, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: AuthUi.ink),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your workspace, signed in',
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: AuthUi.ink.withValues(alpha: 0.72)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Hero extends StatelessWidget {
  const _Hero();

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
              const Row(
                children: [
                  AuthLogoTile(size: 48),
                  SizedBox(width: 14),
                  Text(
                    'WORK PLUS',
                    style: TextStyle(fontFamily: kBrandFont, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AuthUi.ink),
                  ),
                ],
              ),
              const Spacer(),
              const Text(
                'Every task accepted,\ntracked and delivered.',
                style: TextStyle(color: AuthUi.ink, fontSize: 38, fontWeight: FontWeight.w800, height: 1.12, letterSpacing: -1.2),
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
