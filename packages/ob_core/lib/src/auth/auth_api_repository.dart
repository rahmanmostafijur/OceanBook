import '../api/api_client.dart';
import '../api/api_models.dart';
import '../api/session.dart';
import 'auth_models.dart';

/// [AuthRepository] over `/api/v1/auth` and `/me`. Stores tokens only after the server issues them.
class AuthApiRepository implements AuthRepository {
  AuthApiRepository({
    required this.api,
    required this.tokens,
    required this.installationId,
    required this.platform,
    required this.locale,
  });

  final ApiClient api;
  final TokenStore tokens;
  final String installationId;
  final String platform;
  final String Function() locale;

  Map<String, Object?> get _device => {'installation_id': installationId, 'platform': platform};

  @override
  Future<AppUser?> restoreSession() async {
    if (await tokens.read() == null) return null;
    try {
      return (await api.get('/me', decode: (j) => AppUser.fromJson(j! as Map<String, Object?>))).data;
    } on SessionExpiredFailure {
      return null;
    }
  }

  @override
  Future<SignInOutcome> signInWithPassword({required String email, required String password}) =>
      _signIn('/auth/login', {'email': email, 'password': password, 'device': _device});

  @override
  Future<SignInOutcome> register({required String email, required String password, required String displayName}) =>
      _signIn('/auth/register', {
        'email': email,
        'password': password,
        'display_name': displayName,
        'locale': locale(),
        'device': _device,
      });

  @override
  Future<OtpSent> startPhoneSignIn(String phone) async {
    final response = await api.post(
      '/auth/phone/start',
      authenticated: false,
      body: {'phone': phone, 'installation_id': installationId, 'locale': locale()},
      decode: (j) {
        final m = j! as Map<String, Object?>;
        return OtpSent(
          resendAfter: Duration(seconds: (m['resend_after_seconds']! as num).toInt()),
          expiresIn: Duration(seconds: (m['expires_in_seconds']! as num).toInt()),
        );
      },
    );
    return response.data;
  }

  @override
  Future<SignInOutcome> verifyPhoneSignIn({required String phone, required String code, String? displayName}) =>
      _signIn('/auth/phone/verify', {
        'phone': phone,
        'code': code,
        'device': _device,
        'locale': locale(),
        'display_name': ?displayName,
      });

  @override
  Future<AppUser> completeMfa({required String mfaToken, String? code, String? recoveryCode}) async {
    final outcome = await _signIn('/auth/mfa/verify', {
      'mfa_token': mfaToken,
      'code': ?code,
      'recovery_code': ?recoveryCode,
    });
    return switch (outcome) {
      SignedIn(:final user) => user,
      MfaRequired() => throw const UnexpectedResponseFailure(status: 200, detail: 'MFA asked twice'),
    };
  }

  @override
  Future<void> signOut() async {
    try {
      await api.postNoContent('/auth/logout');
    } on ApiFailure {
      // Sign-out always succeeds locally; the server session expires on its own if unreachable.
    } finally {
      await tokens.clear();
    }
  }

  Future<SignInOutcome> _signIn(String path, Map<String, Object?> body) async {
    final response = await api.post(path, authenticated: false, body: body, decode: (j) => j! as Map<String, Object?>);
    final data = response.data;
    if (data['status'] == 'mfa_required') {
      return MfaRequired(
        mfaToken: data['mfa_token']! as String,
        methods: [for (final m in data['methods']! as List) '$m'],
      );
    }
    await tokens.write(AuthTokens.fromJson(data));
    return SignedIn(AppUser.fromJson(data['user']! as Map<String, Object?>));
  }
}
