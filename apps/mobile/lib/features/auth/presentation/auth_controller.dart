import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';

import '../../../core/network/api_providers.dart';
import '../../../core/settings/app_settings.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthApiRepository(
    api: ref.watch(apiClientProvider),
    tokens: ref.watch(tokenStoreProvider),
    installationId: ref.watch(installationIdProvider),
    platform: Platform.isIOS ? 'ios' : 'android',
    locale: () => ref.read(localeProvider).languageCode,
  );
});

/// Session state for the whole app. Restores on start; a server-side revocation anywhere (refresh
/// failure, TOKEN_REVOKED) moves it to signed-out, and the router reacts.
class AuthController extends AsyncNotifier<AuthState> {
  StreamSubscription<SessionEvent>? _events;

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<AuthState> build() async {
    _events = ref.watch(sessionEventsProvider).stream.listen((event) {
      if (event == SessionEvent.expired) state = const AsyncData(AuthSignedOut());
    });
    ref.onDispose(() => _events?.cancel());
    final user = await _repo.restoreSession();
    return user == null ? const AuthSignedOut() : AuthSignedIn(user);
  }

  Future<void> signInWithPassword(String email, String password) =>
      _run(() => _repo.signInWithPassword(email: email, password: password));

  Future<void> register(String email, String password, String displayName) =>
      _run(() => _repo.register(email: email, password: password, displayName: displayName));

  Future<OtpSent> startPhone(String phone) => _repo.startPhoneSignIn(phone);

  Future<void> verifyPhone(String phone, String code, {String? displayName}) =>
      _run(() => _repo.verifyPhoneSignIn(phone: phone, code: code, displayName: displayName));

  Future<void> completeMfa({String? code, String? recoveryCode}) async {
    final pending = state.value;
    if (pending is! AuthMfaPending) return;
    final user = await _repo.completeMfa(mfaToken: pending.mfaToken, code: code, recoveryCode: recoveryCode);
    state = AsyncData(AuthSignedIn(user));
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = const AsyncData(AuthSignedOut());
  }

  /// Runs a primary sign-in step. Errors propagate to the calling screen (shown inline), so a failed
  /// attempt never wipes the current state.
  Future<void> _run(Future<SignInOutcome> Function() step) async {
    final outcome = await step();
    state = AsyncData(switch (outcome) {
      SignedIn(:final user) => AuthSignedIn(user),
      MfaRequired(:final mfaToken, :final methods) => AuthMfaPending(mfaToken: mfaToken, methods: methods),
    });
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);
