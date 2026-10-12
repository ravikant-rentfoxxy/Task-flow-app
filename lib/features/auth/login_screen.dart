import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'auth_layout.dart';
import 'auth_style.dart';
import 'reset_password_screen.dart';
import 'signup_screen.dart';

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

  /// Opens sign-up; after an account is created we're back here with the email filled in.
  Future<void> _openSignup() async {
    final signupEmail = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => SignupScreen(initialEmail: email.text.trim())));
    if (signupEmail == null || !mounted) return;
    setState(() {
      email.text = signupEmail;
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
    return AuthLayout(
      form: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Welcome back',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: AuthUi.ink),
            ),
            const SizedBox(height: 6),
            const Text('Sign in with your work email to continue', style: TextStyle(fontSize: 15.5, color: AuthUi.muted)),
            const SizedBox(height: 28),
            const AuthLabel('Work email'),
            TextField(
              key: const Key('login-email'),
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              style: AuthUi.inputText,
              decoration: AuthUi.input(hint: 'you@company.com'),
            ),
            const SizedBox(height: 20),
            const AuthLabel('Password'),
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
                  icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 22, color: AuthUi.icon),
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
              InfoBanner(key: const Key('login-error'), text: error!, fg: TF.coral, bg: TF.coralSoft, icon: Icons.error_outline_rounded),
            ],
            const SizedBox(height: 24),
            AuthUi.primaryButton(
              key: const Key('login-submit'),
              label: busy ? 'Signing in…' : 'Sign in',
              busy: busy,
              arrow: false,
              onPressed: busy ? null : _submit,
            ),
            const SizedBox(height: 14),
            AuthSwitchLink(
              linkKey: const Key('open-signup'),
              prompt: "Don't have an account?",
              action: 'Sign up',
              onPressed: busy ? null : _openSignup,
            ),
            const SizedBox(height: 8),
            const _PrivacyNote(),
          ],
        ),
      ),
    );
  }
}

/// "By signing in, you agree to our Privacy Policy." — the link opens in the
/// external browser.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  static final _url = Uri.parse('https://rentfoxxy.com/privacy-policy');

  Future<void> _open() async {
    if (!await launchUrl(_url, mode: LaunchMode.externalApplication)) toast('Could not open the privacy policy');
  }

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      const Text('By signing in, you agree to our ', style: TextStyle(fontSize: 13.5, color: AuthUi.muted)),
      InkWell(
        key: const Key('privacy-policy'),
        onTap: _open,
        borderRadius: BorderRadius.circular(4),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Privacy Policy',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AuthUi.ink, decoration: TextDecoration.underline),
          ),
        ),
      ),
      const Text('.', style: TextStyle(fontSize: 13.5, color: AuthUi.muted)),
    ],
  );
}
