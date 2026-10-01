import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'session.dart';

const _uuid = Uuid();
const skipAuthExtra = 'ob.skipAuth';
const _retriedAfterRefreshExtra = 'ob.retriedAfterRefresh';
const _retryCountExtra = 'ob.retryCount';

/// X-Request-ID (UUIDv7, matches server correlation), device, version and language headers.
class ClientHeadersInterceptor extends Interceptor {
  ClientHeadersInterceptor({required this.identity, required this.locale});

  final ClientIdentity identity;
  final String Function() locale;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers
      ..putIfAbsent('X-Request-ID', _uuid.v7)
      ..['X-Device-Id'] = identity.installationId
      ..['X-App-Version'] = identity.appVersion
      ..['Accept-Language'] = locale();
    handler.next(options);
  }
}

/// Bearer auth with single-flight refresh.
///
/// The backend rotates refresh tokens and treats a reused token as theft (the whole session dies), so
/// concurrent 401s must share ONE refresh call; requests that failed with TOKEN_EXPIRED wait for it and
/// are replayed once. Any other 401 (revoked, invalid) ends the session immediately.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.dio,
    required this.refreshDio,
    required this.tokens,
    required this.events,
    required this.refreshPath,
  });

  final Dio dio;

  /// A bare client (headers only, no auth interceptor) so the refresh call can never re-enter this
  /// interceptor and deadlock or recurse.
  final Dio refreshDio;
  final TokenStore tokens;
  final SessionEvents events;
  final String refreshPath;
  Future<AuthTokens?>? _refreshing;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra[skipAuthExtra] != true) {
      final current = await tokens.read();
      if (current != null) options.headers['Authorization'] = 'Bearer ${current.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    final request = err.requestOptions;
    if (response?.statusCode != 401 || request.extra[skipAuthExtra] == true) {
      return handler.next(err);
    }
    final code = _firstErrorCode(response?.data);
    if (code != 'TOKEN_EXPIRED' || request.extra[_retriedAfterRefreshExtra] == true) {
      if (code == 'TOKEN_REVOKED' || code == 'TOKEN_EXPIRED') await _expire();
      return handler.next(err);
    }
    final refreshed = await (_refreshing ??= _refresh().whenComplete(() => _refreshing = null));
    if (refreshed == null) return handler.next(err);
    try {
      request.extra[_retriedAfterRefreshExtra] = true;
      request.headers['Authorization'] = 'Bearer ${refreshed.accessToken}';
      handler.resolve(await dio.fetch<Object?>(request));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  Future<AuthTokens?> _refresh() async {
    final current = await tokens.read();
    if (current == null) {
      await _expire();
      return null;
    }
    try {
      final response = await refreshDio.post<Map<String, Object?>>(
        refreshPath,
        data: {'refresh_token': current.refreshToken},
      );
      final data = response.data?['data'] as Map<String, Object?>?;
      if (data == null) throw StateError('refresh response without data');
      final next = AuthTokens.fromJson(data);
      await tokens.write(next);
      events.emit(SessionEvent.refreshed);
      return next;
    } on DioException catch (e) {
      // A network failure keeps the session (the user may simply be offline); an auth failure ends it.
      if (e.response?.statusCode == 401) await _expire();
      return null;
    }
  }

  Future<void> _expire() async {
    await tokens.clear();
    events.emit(SessionEvent.expired);
  }
}

/// Retries transient failures with exponential backoff and jitter, but only when retrying is safe:
/// idempotent methods, or requests carrying an Idempotency-Key the server deduplicates.
class SafeRetryInterceptor extends Interceptor {
  SafeRetryInterceptor({required this.dio, this.maxRetries = 2, this.baseDelay = const Duration(milliseconds: 400)});

  final Dio dio;
  final int maxRetries;
  final Duration baseDelay;
  final math.Random _random = math.Random();

  bool _isSafe(RequestOptions o) =>
      const {'GET', 'HEAD', 'OPTIONS'}.contains(o.method.toUpperCase()) || o.headers.containsKey('Idempotency-Key');

  bool _isTransient(DioException e) =>
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      const {502, 503, 504}.contains(e.response?.statusCode);

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    final attempt = (request.extra[_retryCountExtra] as int?) ?? 0;
    if (!_isSafe(request) || !_isTransient(err) || attempt >= maxRetries) return handler.next(err);
    final backoff = baseDelay * math.pow(2, attempt) + Duration(milliseconds: _random.nextInt(250));
    await Future<void>.delayed(backoff);
    request.extra[_retryCountExtra] = attempt + 1;
    try {
      handler.resolve(await dio.fetch<Object?>(request));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }
}

String? _firstErrorCode(Object? body) {
  if (body is Map && body['errors'] is List && (body['errors'] as List).isNotEmpty) {
    final first = (body['errors'] as List).first;
    if (first is Map) return first['code'] as String?;
  }
  return null;
}
