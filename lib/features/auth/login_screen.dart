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
      backgroundColor: AuthUi.bg,
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 900;
          final form = Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!wide) ...[const _BrandHeader(), const SizedBox(height: 12)],
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Welcome back',
                              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: AuthUi.ink),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Sign in with your working email to continue',
                              style: TextStyle(fontSize: 15, color: AuthUi.ink.withValues(alpha: 0.7)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _FormCard(
                        children: [
                          const _Label('Work Email'),
                          TextField(
                            key: const Key('login-email'),
                            controller: email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            style: AuthUi.inputText,
                            decoration: AuthUi.input(hint: 'you@rentfoxxy.com', icon: Icons.mail_outline_rounded),
                          ),
                          const SizedBox(height: 18),
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
                              icon: Icons.lock_outline_rounded,
                              suffix: IconButton(
                                icon: Icon(
                                  obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  size: 22,
                                  color: AuthUi.icon,
                                ),
                                onPressed: () => setState(() => obscure = !obscure),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              key: const Key('reset-password'),
                              style: TextButton.styleFrom(
                                foregroundColor: AuthUi.link,
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
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
                          const SizedBox(height: 18),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(color: AuthUi.primary.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 6)),
                              ],
                            ),
                            child: FilledButton(
                              key: const Key('login-submit'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AuthUi.primary,
                                disabledBackgroundColor: AuthUi.primary.withValues(alpha: 0.6),
                                foregroundColor: Colors.white,
                                disabledForegroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(54),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                              ),
                              onPressed: busy ? null : _submit,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(busy ? 'Signing in…' : 'Sign In'),
                                  if (!busy) ...[const SizedBox(width: 10), const Icon(Icons.arrow_forward_rounded, size: 22)],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Thin track under the button; animates while signing in.
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: busy ? null : 0,
                              minHeight: 3,
                              color: AuthUi.primary,
                              backgroundColor: AuthUi.field,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          if (!wide) return SafeArea(child: form);
          return Row(
            children: [
              Expanded(child: _Hero()),
              Expanded(child: form),
            ],
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
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, letterSpacing: 0.2, color: AuthUi.label),
    ),
  );
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: AuthUi.primary.withValues(alpha: 0.07), blurRadius: 30, offset: const Offset(0, 12))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );
}

/// "TF" tile + status pill + wordmark, on a soft band.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
    decoration: BoxDecoration(color: AuthUi.band, borderRadius: BorderRadius.circular(20)),
    child: Column(
      children: [
        const AuthLogoTile(size: 72),
        const SizedBox(height: 12),
        Container(
          width: 24,
          height: 10,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0xFFE3E4F8), borderRadius: BorderRadius.circular(99)),
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(color: AuthUi.online, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(height: 6),
        const FittedBox(
          child: Text(
            'WORK PLUS',
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1, color: AuthUi.ink),
          ),
        ),
      ],
    ),
  );
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(40),
    decoration: BoxDecoration(color: AuthUi.primary, borderRadius: BorderRadius.circular(28)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            AuthLogoTile(size: 48, light: true),
            SizedBox(width: 12),
            Text(
              'WORK PLUS',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: Colors.white),
            ),
          ],
        ),
        const Spacer(),
        const Text(
          'Every task accepted,\ntracked and delivered.',
          style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -1),
        ),
        const SizedBox(height: 16),
        Text(
          '30-minute response SLAs, ETAs, escalations and team chat — in one place.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 16),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in ['Accept + ETA', 'Escalations', 'Reports', 'Chat'])
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
                child: Text(
                  s,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
