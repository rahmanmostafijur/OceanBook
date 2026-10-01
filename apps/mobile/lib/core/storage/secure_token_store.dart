import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ob_core/ob_core.dart';
import 'package:uuid/uuid.dart';

/// Tokens in the platform keystore (Android Keystore / iOS Keychain), never in plain preferences.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'ob.auth.tokens';
  final FlutterSecureStorage _storage;

  @override
  Future<AuthTokens?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return AuthTokens.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      await clear(); // corrupt or outdated format: start a fresh session rather than crash
      return null;
    }
  }

  @override
  Future<void> write(AuthTokens tokens) => _storage.write(key: _key, value: jsonEncode(tokens.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// A random id for this install (the backend's device record). Created once, kept in secure storage.
/// Not a hardware identifier, and it is reset when the app is reinstalled.
class InstallationIdStore {
  InstallationIdStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'ob.installation_id';
  final FlutterSecureStorage _storage;

  Future<String> readOrCreate() async {
    final existing = await _storage.read(key: _key);
    if (existing != null) return existing;
    final created = 'ob-${const Uuid().v4()}';
    await _storage.write(key: _key, value: created);
    return created;
  }
}
