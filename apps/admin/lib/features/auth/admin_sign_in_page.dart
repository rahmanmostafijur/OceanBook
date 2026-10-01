import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/providers.dart';

String _message(ObLocalizations l10n, Object error) => switch (error) {
  ServerFailure(code: ApiErrorCode.invalidCredentials) => l10n.errorInvalidCredentials,
  ServerFailure(code: ApiErrorCode.rateLimited) => l10n.errorRateLimited,
  ServerFailure(code: ApiErrorCode.mfaInvalid) => l10n.errorMfaInvalid,
  ServerFailure(code: ApiErrorCode.accountSuspended) => l10n.errorAccountSuspended,
  NetworkFailure() => l10n.errorNetwork,
  _ => l10n.errorServer,
};

/// Staff sign-in: password first; the server then requires TOTP for staff (Phase 1 policy).
class AdminSignInPage extends ConsumerStatefulWidget {
  const AdminSignInPage({super.key});

  @override
  ConsumerState<AdminSignInPage> createState() => _AdminSignInPageState();
}

class _AdminSignInPageState extends ConsumerState<AdminSignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(adminAuthProvider.notifier).signIn(_email.text.trim(), _password.text);
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = _message(ObLocalizations.of(context), e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: AppSizes.maxFormWidth,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.adminSignInTitle, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.adminStaffOnly,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    TextField(
                      key: const Key('email'),
                      controller: _email,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(labelText: l10n.authEmail),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      key: const Key('password'),
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(labelText: l10n.authPassword, errorText: _error),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    FilledButton(
                      key: const Key('submit'),
                      onPressed: _busy ? null : _submit,
                      child: Text(l10n.actionSignIn),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminMfaPage extends ConsumerStatefulWidget {
  const AdminMfaPage({super.key});

  @override
  ConsumerState<AdminMfaPage> createState() => _AdminMfaPageState();
}

class _AdminMfaPageState extends ConsumerState<AdminMfaPage> {
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    try {
      await ref.read(adminAuthProvider.notifier).completeMfa(code: _code.text.trim());
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = _message(ObLocalizations.of(context), e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: AppSizes.maxFormWidth,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.authMfaTitle, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.md),
                  Text(l10n.authMfaPrompt),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    key: const Key('otp'),
                    controller: _code,
                    autofocus: true,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(labelText: l10n.authOtpCode, errorText: _error),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(key: const Key('verify'), onPressed: _submit, child: Text(l10n.actionContinue)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
