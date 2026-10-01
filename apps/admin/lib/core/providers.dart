import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';
import 'package:uuid/uuid.dart';

/// Admin configuration (`--dart-define`). Public values only.
abstract final class AdminConfig {
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000/api/v1');
  static const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');
}

class AdminLocale extends Notifier<Locale> {
  @override
  Locale build() => const Locale('en');

  void set(Locale locale) => state = locale;
}

final adminLocaleProvider = NotifierProvider<AdminLocale, Locale>(AdminLocale.new);

/// Memory only: staff tokens are never written to browser storage (12 C8). A reload signs out until the
/// HttpOnly refresh-cookie mode lands.
final adminTokenStoreProvider = Provider<TokenStore>((ref) => InMemoryTokenStore());

/// Per-tab browser "installation" id: the backend device record for this admin session.
final adminInstallationIdProvider = Provider<String>((ref) => 'web-${const Uuid().v4()}');

final adminSessionEventsProvider = Provider<SessionEvents>((ref) {
  final events = SessionEvents();
  ref.onDispose(events.dispose);
  return events;
});

final adminApiProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: AdminConfig.apiBaseUrl,
    tokens: ref.watch(adminTokenStoreProvider),
    events: ref.watch(adminSessionEventsProvider),
    identity: ClientIdentity(
      installationId: ref.watch(adminInstallationIdProvider),
      appVersion: AdminConfig.appVersion,
      platform: 'web',
    ),
    locale: () => ref.read(adminLocaleProvider).languageCode,
  );
});

final adminAuthRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthApiRepository(
    api: ref.watch(adminApiProvider),
    tokens: ref.watch(adminTokenStoreProvider),
    installationId: ref.watch(adminInstallationIdProvider),
    platform: 'web',
    locale: () => ref.read(adminLocaleProvider).languageCode,
  );
});

/// Staff session. Same domain and repository as mobile (packages/ob_core); the server decides what staff
/// may do (permissions + MFA session) on every request.
class AdminAuthController extends AsyncNotifier<AuthState> {
  StreamSubscription<SessionEvent>? _events;

  AuthRepository get _repo => ref.read(adminAuthRepositoryProvider);

  @override
  Future<AuthState> build() async {
    _events = ref.watch(adminSessionEventsProvider).stream.listen((event) {
      if (event == SessionEvent.expired) state = const AsyncData(AuthSignedOut());
    });
    ref.onDispose(() => _events?.cancel());
    final user = await _repo.restoreSession();
    return user == null ? const AuthSignedOut() : AuthSignedIn(user);
  }

  Future<void> signIn(String email, String password) async {
    final outcome = await _repo.signInWithPassword(email: email, password: password);
    state = AsyncData(switch (outcome) {
      SignedIn(:final user) => AuthSignedIn(user),
      MfaRequired(:final mfaToken, :final methods) => AuthMfaPending(mfaToken: mfaToken, methods: methods),
    });
  }

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
}

final adminAuthProvider = AsyncNotifierProvider<AdminAuthController, AuthState>(AdminAuthController.new);
