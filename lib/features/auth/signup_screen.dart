import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'auth_layout.dart';
import 'auth_style.dart';

/// Email + password sign-up. On success it pops back to the login screen with
/// the new account's email so it can be filled in.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, this.initialEmail = ''});
  final String initialEmail;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  late final email = TextEditingController(text: widget.initialEmail);
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool obscure = true;
  bool obscureConfirm = true;
  String? error;

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  String? _validate() {
    final e = email.text.trim();
    if (e.isEmpty || password.text.isEmpty || confirm.text.isEmpty) return 'Fill in all fields';
    if (!_emailPattern.hasMatch(e)) return 'Enter a valid email address';
    if (password.text.length < 8) return 'Password must be at least 8 characters';
    if (password.text != confirm.text) return 'Passwords do not match';
    return null;
  }

  /// Validates locally only — no API call — then returns to login with the email.
  void _submit() {
    final invalid = _validate();
    if (invalid != null) return setState(() => error = invalid);
    toast('Account created. Sign in to continue.');
    Navigator.pop(context, email.text.trim());
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Widget _visibilityToggle(bool hidden, VoidCallback onPressed) => IconButton(
    tooltip: hidden ? 'Show password' : 'Hide password',
    icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 22, color: AuthUi.icon),
    onPressed: onPressed,
  );

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Create account',
      subtitle: 'Sign up with your work email to get started',
      heroTitle: 'Join your team\nin a few seconds.',
      onBack: () => Navigator.maybePop(context),
      form: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthLabel('Work email'),
            TextField(
              key: const Key('signup-email'),
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              style: AuthUi.inputText,
              decoration: AuthUi.input(hint: 'you@company.com'),
            ),
            const SizedBox(height: 12),
            const AuthLabel('Password'),
            TextField(
              key: const Key('signup-password'),
              controller: password,
              obscureText: obscure,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              style: AuthUi.inputText,
              decoration: AuthUi.input(hint: '••••••••', suffix: _visibilityToggle(obscure, () => setState(() => obscure = !obscure))),
            ),
            const SizedBox(height: 12),
            const AuthLabel('Confirm password'),
            TextField(
              key: const Key('signup-confirm'),
              controller: confirm,
              obscureText: obscureConfirm,
              autofillHints: const [AutofillHints.newPassword],
              onSubmitted: (_) => _submit(),
              style: AuthUi.inputText,
              decoration: AuthUi.input(
                hint: '••••••••',
                suffix: _visibilityToggle(obscureConfirm, () => setState(() => obscureConfirm = !obscureConfirm)),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 20),
              InfoBanner(key: const Key('signup-error'), text: error!, fg: TF.coral, bg: TF.coralSoft, icon: Icons.error_outline_rounded),
            ],
            const SizedBox(height: 24),
            AuthUi.primaryButton(key: const Key('signup-submit'), label: 'Create account', arrow: false, onPressed: _submit),
            const SizedBox(height: 14),
            AuthSwitchLink(
              linkKey: const Key('signup-to-login'),
              prompt: 'Already have an account?',
              action: 'Sign in',
              onPressed: () => Navigator.maybePop(context),
            ),
          ],
        ),
      ),
    );
  }
}
