import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/taskflow_api.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 900;
        final form = Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (!wide) ...[const _Logo(size: 56), const SizedBox(height: 22)],
                  Text('Welcome back', style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: 6),
                  const Text('Sign in with your RentFoxxy work email.', style: TextStyle(color: TF.muted, fontSize: 15)),
                  const SizedBox(height: 28),
                  const FieldLabel('Email'),
                  TextField(
                    key: const Key('login-email'),
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: 'you@rentfoxxy.com', prefixIcon: Icon(Icons.alternate_email_rounded, size: 20)),
                  ),
                  const SizedBox(height: 14),
                  const FieldLabel('Password'),
                  TextField(
                    key: const Key('login-password'),
                    controller: password,
                    obscureText: obscure,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: '••••••••',
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                        onPressed: () => setState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 14),
                    InfoBanner(key: const Key('login-error'), text: error!, fg: TF.coral, bg: TF.coralSoft, icon: Icons.error_outline_rounded),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    key: const Key('login-submit'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: busy ? null : _submit,
                    child: Text(busy ? 'Signing in…' : 'Sign in'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    key: const Key('reset-password'),
                    onPressed: () => showAppSheet(context, builder: (_) => ResetPasswordSheet(initialEmail: email.text.trim())),
                    child: const Text('Forgot password?'),
                  ),
                ]),
              ),
            ),
          ),
        );
        if (!wide) return SafeArea(child: form);
        return Row(children: [
          Expanded(child: _Hero()),
          Expanded(child: form),
        ]);
      }),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({this.size = 48, this.light = false});
  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: light ? Colors.white : TF.ink, borderRadius: BorderRadius.circular(size * 0.3)),
          child: Icon(Icons.check_rounded, color: light ? TF.primary : const Color(0xFF7FE0C4), size: size * 0.6),
        ),
        const SizedBox(width: 12),
        Text('TaskFlow', style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: light ? Colors.white : TF.ink)),
      ]);
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(color: TF.primary, borderRadius: BorderRadius.circular(28)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Logo(size: 48, light: true),
          const Spacer(),
          const Text('Every task accepted,\ntracked and delivered.',
              style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -1)),
          const SizedBox(height: 16),
          Text('30-minute response SLAs, ETAs, escalations and team chat — in one place.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 16)),
          const SizedBox(height: 28),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in ['Accept + ETA', 'Escalations', 'Reports', 'Chat'])
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
                child: Text(s, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
          ]),
        ]),
      );
}

/// Two-step reset: request an emailed 6-digit code, then set a new password.
class ResetPasswordSheet extends StatefulWidget {
  const ResetPasswordSheet({super.key, this.initialEmail = ''});
  final String initialEmail;

  @override
  State<ResetPasswordSheet> createState() => _ResetPasswordSheetState();
}

class _ResetPasswordSheetState extends State<ResetPasswordSheet> {
  late final email = TextEditingController(text: widget.initialEmail);
  final otp = TextEditingController();
  final pass = TextEditingController();
  final confirm = TextEditingController();
  bool codeStep = false;
  bool busy = false;
  String? error;
  String? message;
  int resendIn = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _request({bool resend = false}) async {
    setState(() => (busy = true, error = null));
    try {
      final m = await Get.find<TaskFlowApi>().forgotPassword(email.text.trim());
      toast(resend ? 'Verification code resent' : 'Verification code sent');
      setState(() {
        message = m;
        codeStep = true;
        otp.clear();
        resendIn = 30;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || resendIn <= 1) t.cancel();
        if (mounted) setState(() => resendIn = resendIn > 0 ? resendIn - 1 : 0);
      });
    } catch (e) {
      setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _reset() async {
    if (pass.text != confirm.text) return setState(() => error = 'New passwords do not match');
    setState(() => (busy = true, error = null));
    try {
      await Get.find<TaskFlowApi>().resetPassword(
            email: email.text.trim(),
            otp: otp.text.trim(),
            newPassword: pass.text,
            confirmPassword: confirm.text,
          );
      toast('Password updated');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Reset password', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            codeStep
                ? 'Enter the 6-digit code sent to ${email.text.trim()} and choose a new password.'
                : 'Enter your work email. We will send a 6-digit verification code.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (!codeStep) ...[
            TextField(key: const Key('reset-email'), controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'Email')),
          ] else ...[
            if (message != null) ...[InfoBanner(text: message!), const SizedBox(height: 12)],
            TextField(
              key: const Key('reset-otp'),
              controller: otp,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, letterSpacing: 10, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(hintText: '000000', counterText: ''),
            ),
            Align(
              child: resendIn > 0
                  ? Text('Resend code in ${resendIn}s', style: const TextStyle(color: TF.muted, fontSize: 12.5))
                  : TextButton(onPressed: busy ? null : () => _request(resend: true), child: const Text('Resend code')),
            ),
            TextField(key: const Key('reset-new'), controller: pass, obscureText: true, decoration: const InputDecoration(hintText: 'New password (min 6)')),
            const SizedBox(height: 10),
            TextField(key: const Key('reset-confirm'), controller: confirm, obscureText: true, decoration: const InputDecoration(hintText: 'Confirm new password')),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            InfoBanner(text: error!, fg: TF.coral, bg: TF.coralSoft, icon: Icons.error_outline_rounded),
          ],
          const SizedBox(height: 16),
          Row(children: [
            OutlinedButton(
              onPressed: busy ? null : () => codeStep ? setState(() => (codeStep = false, error = null)) : Navigator.pop(context),
              child: Text(codeStep ? 'Back' : 'Cancel'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                key: const Key('reset-submit'),
                onPressed: busy ? null : (codeStep ? _reset : _request),
                child: Text(busy ? 'Please wait…' : (codeStep ? 'Update password' : 'Send code')),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
