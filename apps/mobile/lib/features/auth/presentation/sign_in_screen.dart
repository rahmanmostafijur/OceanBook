import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/failure_messages.dart';
import 'auth_controller.dart';

enum _Method { email, phone }

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({this.from, super.key});

  /// Where to return after signing in (set by the router redirect).
  final String? from;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  _Method _method = _Method.email;
  bool _creating = false;
  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  int _resendIn = 0;
  Timer? _timer;

  @override
  void dispose() {
    for (final c in [_email, _password, _name, _phone, _code]) {
      c.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _attempt(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      await action();
    } on ServerFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _error = failureMessage(ObLocalizations.of(context), f);
        _fieldErrors = f.fieldErrors;
      });
    } on ApiFailure catch (f) {
      if (!mounted) return;
      setState(() => _error = failureMessage(ObLocalizations.of(context), f));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitEmail() => _attempt(() async {
    final auth = ref.read(authControllerProvider.notifier);
    if (_creating) {
      await auth.register(_email.text.trim(), _password.text, _name.text.trim());
    } else {
      await auth.signInWithPassword(_email.text.trim(), _password.text);
    }
  });

  Future<void> _sendCode() => _attempt(() async {
    final sent = await ref.read(authControllerProvider.notifier).startPhone(_phone.text.trim());
    if (!mounted) return;
    setState(() {
      _codeSent = true;
      _resendIn = sent.resendAfter.inSeconds;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _resendIn <= 1) {
        t.cancel();
        if (mounted) setState(() => _resendIn = 0);
      } else {
        setState(() => _resendIn--);
      }
    });
  });

  Future<void> _verifyCode() =>
      _attempt(() => ref.read(authControllerProvider.notifier).verifyPhone(_phone.text.trim(), _code.text.trim()));

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppSizes.maxFormWidth),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.authWelcome, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.authSubtitle,
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    SegmentedButton<_Method>(
                      segments: [
                        ButtonSegment(
                          value: _Method.email,
                          label: Text(l10n.authEmail),
                          icon: const Icon(Icons.mail_outline),
                        ),
                        ButtonSegment(
                          value: _Method.phone,
                          label: Text(l10n.authPhone),
                          icon: const Icon(Icons.phone_iphone),
                        ),
                      ],
                      selected: {_method},
                      onSelectionChanged: (s) => setState(() {
                        _method = s.first;
                        _error = null;
                      }),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    if (_method == _Method.email) ..._emailFields(l10n) else ..._phoneFields(l10n),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                    if (AppConfig.googleSignInEnabled || AppConfig.appleSignInEnabled) ...[
                      const SizedBox(height: AppSpacing.xl),
                      const Divider(),
                      const SizedBox(height: AppSpacing.md),
                      if (AppConfig.googleSignInEnabled)
                        OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.g_mobiledata),
                          label: Text(l10n.authContinueWithGoogle),
                        ),
                      if (AppConfig.appleSignInEnabled) ...[
                        const SizedBox(height: AppSpacing.xs),
                        OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.apple),
                          label: Text(l10n.authContinueWithApple),
                        ),
                      ],
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    TextButton(onPressed: () => context.go('/'), child: Text(l10n.authGuestBrowse)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _emailFields(ObLocalizations l10n) => [
    if (_creating) ...[
      TextField(
        controller: _name,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.name],
        decoration: InputDecoration(labelText: l10n.authDisplayName, errorText: _fieldErrors['display_name']),
      ),
      const SizedBox(height: AppSpacing.md),
    ],
    TextField(
      key: const Key('email'),
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.email],
      decoration: InputDecoration(labelText: l10n.authEmail, errorText: _fieldErrors['email']),
    ),
    const SizedBox(height: AppSpacing.md),
    TextField(
      key: const Key('password'),
      controller: _password,
      obscureText: true,
      autofillHints: [_creating ? AutofillHints.newPassword : AutofillHints.password],
      onSubmitted: (_) => _submitEmail(),
      decoration: InputDecoration(labelText: l10n.authPassword, errorText: _fieldErrors['password']),
    ),
    const SizedBox(height: AppSpacing.xl),
    FilledButton(
      key: const Key('submit'),
      onPressed: _busy ? null : _submitEmail,
      child: _busy
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(_creating ? l10n.actionCreateAccount : l10n.actionSignIn),
    ),
    const SizedBox(height: AppSpacing.xs),
    TextButton(
      onPressed: () => setState(() => _creating = !_creating),
      child: Text(_creating ? l10n.actionSignIn : '${l10n.authNoAccount} ${l10n.actionCreateAccount}'),
    ),
  ];

  List<Widget> _phoneFields(ObLocalizations l10n) => [
    TextField(
      key: const Key('phone'),
      controller: _phone,
      keyboardType: TextInputType.phone,
      autofillHints: const [AutofillHints.telephoneNumber],
      decoration: InputDecoration(
        labelText: l10n.authPhone,
        hintText: l10n.authPhoneHint,
        errorText: _fieldErrors['phone'],
      ),
    ),
    const SizedBox(height: AppSpacing.md),
    if (_codeSent) ...[
      TextField(
        key: const Key('otp'),
        controller: _code,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        maxLength: 6,
        decoration: InputDecoration(labelText: l10n.authOtpCode),
      ),
      FilledButton(onPressed: _busy ? null : _verifyCode, child: Text(l10n.actionContinue)),
      const SizedBox(height: AppSpacing.xs),
      TextButton(
        onPressed: _busy || _resendIn > 0 ? null : _sendCode,
        child: Text(_resendIn > 0 ? l10n.authResendIn(_resendIn) : l10n.authSendCode),
      ),
    ] else
      FilledButton(key: const Key('send-code'), onPressed: _busy ? null : _sendCode, child: Text(l10n.authSendCode)),
  ];
}

/// Second factor (staff and users who enabled TOTP). Tokens do not exist until this succeeds.
class MfaScreen extends ConsumerStatefulWidget {
  const MfaScreen({super.key});

  @override
  ConsumerState<MfaScreen> createState() => _MfaScreenState();
}

class _MfaScreenState extends ConsumerState<MfaScreen> {
  final _code = TextEditingController();
  bool _recovery = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .completeMfa(code: _recovery ? null : _code.text.trim(), recoveryCode: _recovery ? _code.text.trim() : null);
    } on ApiFailure catch (f) {
      if (mounted) setState(() => _error = failureMessage(ObLocalizations.of(context), f));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.authMfaTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.maxFormWidth),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.authMfaPrompt),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _code,
                  autofocus: true,
                  keyboardType: _recovery ? TextInputType.text : TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  decoration: InputDecoration(
                    labelText: _recovery ? l10n.authRecoveryCode : l10n.authOtpCode,
                    errorText: _error,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(onPressed: _busy ? null : _submit, child: Text(l10n.actionContinue)),
                TextButton(
                  onPressed: () => setState(() => _recovery = !_recovery),
                  child: Text(_recovery ? l10n.authOtpCode : l10n.authMfaUseRecovery),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
