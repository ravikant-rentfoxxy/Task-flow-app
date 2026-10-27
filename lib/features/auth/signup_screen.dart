import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'auth_layout.dart';
import 'auth_style.dart';

/// Email + password sign-up. The email must be verified with a 6-digit code
/// before the password fields unlock. On success it pops back to the login
/// screen with the new account's email so it can be filled in.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, this.initialEmail = ''});
  final String initialEmail;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  late final email = TextEditingController(text: widget.initialEmail);
  final otp = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  final otpFocus = FocusNode();
  bool codeSent = false;
  bool verified = false;
  bool obscure = true;
  bool obscureConfirm = true;
  String? error;
  int resendIn = 0;
  Timer? _timer;

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void initState() {
    super.initState();
    otp.addListener(() => setState(() {}));
  }

  /// Sends (or resends) the verification code. Local only for now — no API
  /// call — so any 6-digit code is accepted by [_verify].
  void _sendCode({bool resend = false}) {
    final e = email.text.trim();
    if (!_emailPattern.hasMatch(e)) return setState(() => error = 'Enter a valid email address');
    toast(resend ? 'Verification code resent' : 'Verification code sent');
    setState(() {
      error = null;
      codeSent = true;
      otp.clear();
      resendIn = 30;
    });
    otpFocus.requestFocus();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || resendIn <= 1) t.cancel();
      if (mounted) setState(() => resendIn = resendIn > 0 ? resendIn - 1 : 0);
    });
  }

  void _verify() {
    if (otp.text.trim().length != 6) return setState(() => error = 'Enter the 6-digit code');
    _timer?.cancel();
    otpFocus.unfocus();
    toast('Email verified');
    setState(() => (verified = true, error = null));
  }

  /// Back to editing the email: drops the code and re-locks the password fields.
  void _changeEmail() {
    _timer?.cancel();
    otp.clear();
    password.clear();
    confirm.clear();
    setState(() => (codeSent = false, verified = false, resendIn = 0, error = null));
  }

  String? _validate() {
    if (!verified) return 'Verify your email first';
    if (password.text.isEmpty || confirm.text.isEmpty) return 'Fill in all fields';
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
    _timer?.cancel();
    for (final c in [email, otp, password, confirm]) {
      c.dispose();
    }
    otpFocus.dispose();
    super.dispose();
  }

  Widget _visibilityToggle(bool hidden, VoidCallback? onPressed) => IconButton(
    tooltip: hidden ? 'Show password' : 'Hide password',
    icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 22, color: AuthUi.icon),
    onPressed: onPressed,
  );

  Widget _emailSuffix() {
    if (verified) {
      return const Padding(
        padding: EdgeInsets.only(right: 10),
        child: Icon(Icons.verified_rounded, key: Key('signup-email-verified'), color: AuthUi.success, size: 22),
      );
    }
    if (codeSent) {
      return TextButton(key: const Key('signup-change-email'), onPressed: _changeEmail, child: const Text('Change'));
    }
    return TextButton(key: const Key('signup-send-code'), onPressed: _sendCode, child: const Text('Send code'));
  }

  List<Widget> _otpSection() => [
    const SizedBox(height: 16),
    const AuthLabel('Verification code'),
    Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 14, color: AuthUi.muted),
        children: [
          const TextSpan(text: 'Enter the 6-digit code sent to '),
          TextSpan(
            text: email.text.trim(),
            style: const TextStyle(fontWeight: FontWeight.w700, color: AuthUi.ink),
          ),
        ],
      ),
    ),
    const SizedBox(height: 12),
    AuthOtpBoxes(fieldKey: const Key('signup-otp'), controller: otp, focusNode: otpFocus),
    const SizedBox(height: 14),
    Row(
      children: [
        AuthResendPill(seconds: resendIn, onResend: () => _sendCode(resend: true)),
        const SizedBox(width: 12),
        Expanded(
          child: AuthUi.primaryButton(
            key: const Key('signup-verify'),
            label: 'Verify',
            arrow: false,
            onPressed: otp.text.trim().length == 6 ? _verify : null,
          ),
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final locked = !verified;
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
              readOnly: codeSent,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => codeSent ? null : _sendCode(),
              style: AuthUi.inputText,
              decoration: AuthUi.input(hint: 'you@company.com', suffix: _emailSuffix()),
            ),
            if (codeSent && !verified) ..._otpSection(),
            const SizedBox(height: 12),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: locked ? 0.5 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthLabel('Password'),
                  TextField(
                    key: const Key('signup-password'),
                    controller: password,
                    enabled: !locked,
                    obscureText: obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                    style: AuthUi.inputText,
                    decoration: AuthUi.input(
                      hint: locked ? 'Verify email to continue' : '••••••••',
                      suffix: _visibilityToggle(obscure, locked ? null : () => setState(() => obscure = !obscure)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const AuthLabel('Confirm password'),
                  TextField(
                    key: const Key('signup-confirm'),
                    controller: confirm,
                    enabled: !locked,
                    obscureText: obscureConfirm,
                    autofillHints: const [AutofillHints.newPassword],
                    onSubmitted: (_) => _submit(),
                    style: AuthUi.inputText,
                    decoration: AuthUi.input(
                      hint: locked ? 'Verify email to continue' : '••••••••',
                      suffix: _visibilityToggle(
                        obscureConfirm,
                        locked ? null : () => setState(() => obscureConfirm = !obscureConfirm),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 20),
              InfoBanner(key: const Key('signup-error'), text: error!, fg: TF.coral, bg: TF.coralSoft, icon: Icons.error_outline_rounded),
            ],
            const SizedBox(height: 24),
            AuthUi.primaryButton(
              key: const Key('signup-submit'),
              label: 'Create account',
              arrow: false,
              onPressed: verified ? _submit : null,
            ),
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
