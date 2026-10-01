import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../data/taskflow_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'auth_style.dart';

/// Two-step reset: request an emailed 6-digit code, then set a new password.
/// On success it pops back to the login screen with the reset email.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.initialEmail = ''});
  final String initialEmail;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late final email = TextEditingController(text: widget.initialEmail);
  final otp = TextEditingController();
  final pass = TextEditingController();
  final confirm = TextEditingController();
  final otpFocus = FocusNode();
  bool codeStep = false;
  bool busy = false;
  bool obscureNew = true;
  bool obscureConfirm = true;
  String? error;
  String? message;
  int resendIn = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    for (final c in [otp, pass, confirm]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [email, otp, pass, confirm]) {
      c.dispose();
    }
    otpFocus.dispose();
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

  /// Reset & Sign In stays disabled until the code and both passwords are entered.
  bool get _canReset => otp.text.trim().length == 6 && pass.text.isNotEmpty && confirm.text.isNotEmpty;

  Future<void> _reset() async {
    if (!_canReset) return;
    if (pass.text != confirm.text) return setState(() => error = 'New passwords do not match');
    setState(() => (busy = true, error = null));
    try {
      await Get.find<TaskFlowApi>().resetPassword(
        email: email.text.trim(),
        otp: otp.text.trim(),
        newPassword: pass.text,
        confirmPassword: confirm.text,
      );
      toast('Password updated. Sign in with your new password.');
      if (mounted) Navigator.pop(context, email.text.trim());
    } catch (e) {
      setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _back() {
    if (codeStep && !busy) return setState(() => (codeStep = false, error = null));
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !codeStep,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AuthUi.bg,
        appBar: AuthTopBar(title: codeStep ? 'Security Verification' : 'Forgot Password', onBack: _back),
        body: SafeArea(
          top: false,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: codeStep ? _codeStep() : _emailStep()),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorBanner() => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: InfoBanner(text: error!, fg: TF.coral, bg: TF.coralSoft, icon: Icons.error_outline_rounded),
  );

  // ── Step 1: email ────────────────────────────────────────────────────────

  Widget _emailStep() => Column(
    key: const ValueKey('email-step'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      const Center(child: _ResetBadge()),
      const SizedBox(height: 22),
      const Text(
        'Reset password',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: AuthUi.ink),
      ),
      const SizedBox(height: 10),
      const Text(
        'Enter your RentFoxxy work email and we will send you a 6-digit verification code.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15.5, height: 1.5, color: AuthUi.muted),
      ),
      const SizedBox(height: 24),
      const _RecoveryIllustration(),
      const SizedBox(height: 28),
      const Row(
        children: [
          Expanded(
            child: Text(
              'Work Email',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AuthUi.ink),
            ),
          ),
          Text(
            'Domain required',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AuthUi.olive),
          ),
        ],
      ),
      const SizedBox(height: 10),
      TextField(
        key: const Key('reset-email'),
        controller: email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        onSubmitted: (_) => busy ? null : _request(),
        style: AuthUi.inputText,
        decoration: AuthUi.input(hint: 'you@rentfoxxy.com', icon: Icons.mail_outline_rounded, outlined: true),
      ),
      const SizedBox(height: 18),
      const _InfoTile(
        title: 'Immediate delivery',
        text: 'Codes are sent immediately. You can request a resend after 30 seconds once submitted.',
      ),
      if (error != null) _errorBanner(),
      const SizedBox(height: 28),
      AuthUi.primaryButton(
        key: const Key('reset-submit'),
        label: busy ? 'Please wait…' : 'Send 6-Digit Code',
        busy: busy,
        onPressed: busy ? null : _request,
      ),
      const SizedBox(height: 24),
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Remember your password?', style: TextStyle(fontSize: 15, color: AuthUi.muted)),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AuthUi.ink,
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.underline,
                decorationThickness: 2,
              ),
            ),
            onPressed: () => Navigator.maybePop(context),
            child: const Text('Sign in'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Center(
        child: AuthPill(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 19, color: AuthUi.ink),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Encrypted Code Request',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: AuthUi.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  // ── Step 2: code + new password ─────────────────────────────────────────

  Widget _codeStep() {
    final p = pass.text;
    final criteria = [
      ('At least 6 characters', p.length >= 6),
      ('One number & symbol', RegExp(r'\d').hasMatch(p) && RegExp(r'[^A-Za-z0-9]').hasMatch(p)),
      ('Passwords match', p.isNotEmpty && p == confirm.text),
    ];
    return Column(
      key: const ValueKey('code-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const AuthPill(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Text(
                'STEP 2 OF 2',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AuthUi.olive),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: Color(0xFF8DB50F), shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            const Flexible(
              child: Text(
                'Security check',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AuthUi.olive),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Enter 6-digit code',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: AuthUi.ink),
        ),
        const SizedBox(height: 8),
        const Text('We sent a verification code to', style: TextStyle(fontSize: 15.5, color: AuthUi.muted)),
        const SizedBox(height: 2),
        Text(
          email.text.trim(),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AuthUi.ink),
        ),
        const SizedBox(height: 22),
        AuthCard(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'VERIFICATION CODE',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: AuthUi.muted),
                  ),
                ),
                TextButton.icon(
                  key: const Key('reset-change-email'),
                  style: TextButton.styleFrom(
                    foregroundColor: AuthUi.olive,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  onPressed: busy ? null : _back,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Change email'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _OtpBoxes(controller: otp, focusNode: otpFocus),
            if (message != null) ...[
              const SizedBox(height: 14),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AuthUi.muted),
              ),
            ],
            const SizedBox(height: 18),
            Center(
              child: _ResendPill(seconds: resendIn, onResend: busy ? null : () => _request(resend: true)),
            ),
            const SizedBox(height: 8),
            const Text(
              'You can resend the code after 30 seconds',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, letterSpacing: 0.2, color: AuthUi.muted),
            ),
          ],
        ),
        const SizedBox(height: 18),
        AuthCard(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  margin: const EdgeInsets.only(top: 4, right: 14),
                  decoration: BoxDecoration(
                    color: AuthUi.limeSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AuthUi.limeLine),
                  ),
                  child: const Icon(Icons.lock_reset_rounded, color: AuthUi.ink, size: 24),
                ),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create new password',
                        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AuthUi.ink),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Must be different from previously used passwords',
                        style: TextStyle(fontSize: 14.5, height: 1.4, color: AuthUi.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const _FieldTitle('New Password'),
            TextField(
              key: const Key('reset-new'),
              controller: pass,
              obscureText: obscureNew,
              autofillHints: const [AutofillHints.newPassword],
              style: AuthUi.inputText,
              decoration: AuthUi.input(
                hint: 'New password (min 6)',
                outlined: true,
                suffix: _EyeButton(obscure: obscureNew, onTap: () => setState(() => obscureNew = !obscureNew)),
              ),
            ),
            const SizedBox(height: 14),
            _StrengthMeter(password: p),
            const SizedBox(height: 18),
            const _FieldTitle('Confirm New Password'),
            TextField(
              key: const Key('reset-confirm'),
              controller: confirm,
              obscureText: obscureConfirm,
              onSubmitted: (_) => busy || !_canReset ? null : _reset(),
              style: AuthUi.inputText,
              decoration: AuthUi.input(
                hint: 'Confirm new password',
                outlined: true,
                suffix: _EyeButton(obscure: obscureConfirm, onTap: () => setState(() => obscureConfirm = !obscureConfirm)),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              decoration: BoxDecoration(
                color: AuthUi.field,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AuthUi.limeLine),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SECURITY CRITERIA',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: AuthUi.muted),
                  ),
                  const SizedBox(height: 10),
                  for (final (label, ok) in criteria)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            size: 20,
                            color: ok ? AuthUi.ink : AuthUi.faint,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: ok ? FontWeight.w500 : FontWeight.w400,
                                color: ok ? AuthUi.ink : AuthUi.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (error != null) _errorBanner(),
        const SizedBox(height: 24),
        AuthUi.primaryButton(
          key: const Key('reset-submit'),
          label: busy ? 'Please wait…' : 'Reset & Sign In',
          busy: busy,
          onPressed: busy || !_canReset ? null : _reset,
        ),
      ],
    );
  }
}

// ── Pieces ────────────────────────────────────────────────────────────────

/// Navy disc with a lime reset icon, lime glow ring and a shield badge.
class _ResetBadge extends StatelessWidget {
  const _ResetBadge();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 168,
    height: 168,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AuthUi.lime.withValues(alpha: 0.22),
            border: Border.all(color: AuthUi.lime.withValues(alpha: 0.7), width: 2),
            boxShadow: [BoxShadow(color: AuthUi.lime.withValues(alpha: 0.45), blurRadius: 30)],
          ),
        ),
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            color: AuthUi.ink,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: AuthUi.ink.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: const Icon(Icons.lock_reset_rounded, color: AuthUi.lime, size: 54),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AuthUi.lime,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: const Icon(Icons.verified_user_outlined, color: AuthUi.ink, size: 20),
          ),
        ),
      ],
    ),
  );
}

/// Drawn stand-in for the mock-up's photo: a code-request card on a soft desk.
class _RecoveryIllustration extends StatelessWidget {
  const _RecoveryIllustration();

  @override
  Widget build(BuildContext context) => Container(
    height: 200,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE9EBEF), Color(0xFFC9CDD6), Color(0xFF545B6A)],
        stops: [0, 0.55, 1],
      ),
      boxShadow: [BoxShadow(color: AuthUi.ink.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 8))],
    ),
    child: Stack(
      children: [
        Positioned(
          right: 28,
          top: 22,
          child: Transform.rotate(
            angle: 0.12,
            child: Container(
              width: 172,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: AuthUi.ink.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10))],
              ),
              child: Column(
                children: [
                  const Text(
                    'Password Reset Request',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AuthUi.label),
                  ),
                  const SizedBox(height: 8),
                  const Icon(Icons.mark_email_unread_outlined, color: AuthUi.ink, size: 26),
                  const SizedBox(height: 6),
                  const Text(
                    'A 6-digit code has been sent to your work email.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 8.5, color: AuthUi.muted),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 16,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AuthUi.ink, borderRadius: BorderRadius.circular(4)),
                    child: const Text(
                      'Open Email App',
                      style: TextStyle(fontSize: 8, color: AuthUi.lime, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 30,
          top: 36,
          child: Transform.rotate(
            angle: -0.5,
            child: Container(
              width: 110,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
                border: const Border(bottom: BorderSide(color: AuthUi.limeDeep, width: 6)),
              ),
              child: const Icon(Icons.lock_outline_rounded, color: AuthUi.faint, size: 18),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AuthUi.ink.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: AuthUi.lime.withValues(alpha: 0.5)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mark_email_unread_outlined, size: 20, color: AuthUi.lime),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Secure Recovery Token',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AuthUi.field,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AuthUi.limeLine),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(color: AuthUi.ink, shape: BoxShape.circle),
          child: const Icon(Icons.info_outline_rounded, color: AuthUi.lime, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AuthUi.ink),
              ),
              const SizedBox(height: 4),
              Text(text, style: const TextStyle(fontSize: 14.5, height: 1.4, color: AuthUi.label)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _FieldTitle extends StatelessWidget {
  const _FieldTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, letterSpacing: 0.1, color: AuthUi.ink),
    ),
  );
}

class _EyeButton extends StatelessWidget {
  const _EyeButton({required this.obscure, required this.onTap});
  final bool obscure;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: obscure ? 'Show password' : 'Hide password',
    icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 22, color: AuthUi.icon),
    onPressed: onTap,
  );
}

/// Six digit boxes drawn over one invisible [TextField], so paste, autofill
/// and backspace behave like a normal input.
class _OtpBoxes extends StatelessWidget {
  const _OtpBoxes({required this.controller, required this.focusNode});
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final code = controller.text;
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) => SizedBox(
        height: 64,
        child: Stack(
          children: [
            Row(
              children: [
                for (var i = 0; i < 6; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: _box(i, code, focusNode.hasFocus))],
              ],
            ),
            Positioned.fill(
              child: TextField(
                key: const Key('reset-otp'),
                controller: controller,
                focusNode: focusNode,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                showCursor: false,
                enableInteractiveSelection: false,
                style: const TextStyle(color: Colors.transparent, fontSize: 1),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  counterText: '',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _box(int i, String code, bool focused) {
    final active = focused && i == code.length.clamp(0, 5) && code.length < 6;
    final digit = i < code.length ? code[i] : null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? Colors.white : (digit != null ? AuthUi.limeSoft : AuthUi.field),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: active ? AuthUi.ink : AuthUi.limeLine, width: active ? 2 : 1),
        boxShadow: active ? [BoxShadow(color: AuthUi.lime.withValues(alpha: 0.9), spreadRadius: 3)] : null,
      ),
      child: digit != null
          ? Text(
              digit,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AuthUi.ink),
            )
          : active
          ? Container(width: 2, height: 28, color: AuthUi.ink)
          : Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(color: Color(0xFFC7CBD3), shape: BoxShape.circle),
            ),
    );
  }
}

class _ResendPill extends StatelessWidget {
  const _ResendPill({required this.seconds, required this.onResend});
  final int seconds;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    final waiting = seconds > 0;
    return Material(
      color: waiting ? AuthUi.limeSoft : AuthUi.ink,
      shape: StadiumBorder(side: BorderSide(color: waiting ? AuthUi.limeLine : AuthUi.ink)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: waiting ? null : onResend,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(waiting ? Icons.timer_outlined : Icons.refresh_rounded, size: 20, color: waiting ? AuthUi.olive : AuthUi.lime),
              const SizedBox(width: 10),
              if (waiting)
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 15, color: AuthUi.label, fontWeight: FontWeight.w500),
                      children: [
                        const TextSpan(text: 'Resend code in '),
                        TextSpan(
                          text: '0:${seconds.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: AuthUi.ink),
                        ),
                      ],
                    ),
                  ),
                )
              else
                const Text(
                  'Resend code',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four-segment meter: navy segments, with the last lit lime at full strength.
class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.password});
  final String password;

  @override
  Widget build(BuildContext context) {
    final p = password;
    final score = p.isEmpty
        ? 0
        : [
            p.length >= 8,
            RegExp(r'\d').hasMatch(p),
            RegExp(r'[^A-Za-z0-9]').hasMatch(p),
            RegExp(r'[a-z]').hasMatch(p) && RegExp(r'[A-Z]').hasMatch(p),
          ].where((x) => x).length.clamp(1, 4);
    final (label, color) = switch (score) {
      0 => ('', AuthUi.faint),
      1 => ('Weak', TF.coral),
      2 => ('Fair', TF.amber),
      3 => ('Good', AuthUi.ink),
      _ => ('Strong', AuthUi.ink),
    };
    Color segment(int i) {
      if (i >= score) return const Color(0xFFE6E8EC);
      if (score == 4 && i == 3) return AuthUi.lime;
      return score <= 2 ? color : AuthUi.ink;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Strength Meter', style: TextStyle(fontSize: 13.5, letterSpacing: 0.2, color: AuthUi.muted)),
            ),
            if (score > 0) ...[
              Icon(score == 4 ? Icons.verified_outlined : Icons.shield_outlined, size: 18, color: score == 4 ? AuthUi.olive : color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 6,
                  decoration: BoxDecoration(color: segment(i), borderRadius: BorderRadius.circular(3)),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
