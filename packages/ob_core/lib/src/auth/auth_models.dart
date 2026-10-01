import 'package:meta/meta.dart';

/// The signed-in account as the server describes it (`UserOut`). Credentials are never held here.
@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.displayName,
    required this.locale,
    required this.signInMethods,
    required this.mfaEnabled,
    this.email,
    this.phone,
  });

  factory AppUser.fromJson(Map<String, Object?> json) => AppUser(
    id: json['id']! as String,
    displayName: json['display_name']! as String,
    locale: (json['locale'] as String?) ?? 'bn',
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    signInMethods: [for (final m in (json['sign_in_methods'] as List?) ?? const <Object?>[]) '$m'],
    mfaEnabled: (json['mfa_enabled'] as bool?) ?? false,
  );

  final String id;
  final String displayName;
  final String locale;
  final String? email;
  final String? phone;
  final List<String> signInMethods;
  final bool mfaEnabled;
}

/// Where the user is in the sign-in flow. Guests can browse and practise (owner decision); features
/// that persist or need identity ask for sign-in.
@immutable
sealed class AuthState {
  const AuthState();
}

final class AuthSignedOut extends AuthState {
  const AuthSignedOut();
}

final class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.user);
  final AppUser user;
}

/// Password/phone/social step passed; a second factor is required before any tokens exist.
final class AuthMfaPending extends AuthState {
  const AuthMfaPending({required this.mfaToken, required this.methods});
  final String mfaToken;
  final List<String> methods;
}

/// Result of a primary sign-in step (mirrors the backend's `status` discriminator).
sealed class SignInOutcome {
  const SignInOutcome();
}

final class SignedIn extends SignInOutcome {
  const SignedIn(this.user);
  final AppUser user;
}

final class MfaRequired extends SignInOutcome {
  const MfaRequired({required this.mfaToken, required this.methods});
  final String mfaToken;
  final List<String> methods;
}

@immutable
class OtpSent {
  const OtpSent({required this.resendAfter, required this.expiresIn});
  final Duration resendAfter;
  final Duration expiresIn;
}

/// Data access contract for authentication. Implemented over the API; faked in tests.
abstract interface class AuthRepository {
  Future<AppUser?> restoreSession();
  Future<SignInOutcome> signInWithPassword({required String email, required String password});
  Future<SignInOutcome> register({required String email, required String password, required String displayName});
  Future<OtpSent> startPhoneSignIn(String phone);
  Future<SignInOutcome> verifyPhoneSignIn({required String phone, required String code, String? displayName});
  Future<AppUser> completeMfa({required String mfaToken, String? code, String? recoveryCode});
  Future<void> signOut();
}
