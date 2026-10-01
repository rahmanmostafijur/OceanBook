import 'dart:async';

import 'package:meta/meta.dart';

/// Tokens from the backend (`TokenPairOut`). The access token is short-lived (15 min); the refresh
/// token rotates on every refresh and must be replaced atomically.
@immutable
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.accessTokenExpiresAt,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
    required this.deviceId,
  });

  factory AuthTokens.fromJson(Map<String, Object?> json) => AuthTokens(
    accessToken: json['access_token']! as String,
    accessTokenExpiresAt: DateTime.parse(json['access_token_expires_at']! as String),
    refreshToken: json['refresh_token']! as String,
    refreshTokenExpiresAt: DateTime.parse(json['refresh_token_expires_at']! as String),
    deviceId: json['device_id']! as String,
  );

  final String accessToken;
  final DateTime accessTokenExpiresAt;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;
  final String deviceId;

  Map<String, Object?> toJson() => {
    'access_token': accessToken,
    'access_token_expires_at': accessTokenExpiresAt.toIso8601String(),
    'refresh_token': refreshToken,
    'refresh_token_expires_at': refreshTokenExpiresAt.toIso8601String(),
    'device_id': deviceId,
  };
}

/// Where tokens live. Mobile: platform secure storage (Keystore/Keychain). Web admin: memory only
/// (tokens are never written to browser storage).
abstract interface class TokenStore {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens tokens);
  Future<void> clear();
}

class InMemoryTokenStore implements TokenStore {
  AuthTokens? _tokens;

  @override
  Future<AuthTokens?> read() async => _tokens;

  @override
  Future<void> write(AuthTokens tokens) async => _tokens = tokens;

  @override
  Future<void> clear() async => _tokens = null;
}

/// Client-side facts sent with every request. The installation id identifies this app install (the
/// backend's device record); it is random, not a hardware identifier.
@immutable
class ClientIdentity {
  const ClientIdentity({required this.installationId, required this.appVersion, required this.platform});

  final String installationId;
  final String appVersion;
  final String platform; // 'android' | 'ios' | 'web' (the backend's device platform values)
}

/// Broadcasts session changes so the router can redirect to sign-in when a session ends anywhere.
class SessionEvents {
  final StreamController<SessionEvent> _controller = StreamController<SessionEvent>.broadcast();

  Stream<SessionEvent> get stream => _controller.stream;

  void emit(SessionEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  Future<void> dispose() => _controller.close();
}

enum SessionEvent { signedIn, refreshed, expired, signedOut }
