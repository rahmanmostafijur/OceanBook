import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'api_models.dart';
import 'interceptors.dart';
import 'session.dart';

typedef Decoder<T> = T Function(Object? json);

/// The only way app code talks to `/api/v1`. Widgets never see Dio, raw JSON or HTTP status codes:
/// they get typed data or an [ApiFailure].
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.tokens,
    required ClientIdentity identity,
    required String Function() locale,
    SessionEvents? events,
    HttpClientAdapter? adapter,
    Duration retryBaseDelay = const Duration(milliseconds: 400),
  }) : events = events ?? SessionEvents(),
       _dio = Dio(
         BaseOptions(
           baseUrl: baseUrl,
           connectTimeout: const Duration(seconds: 10),
           receiveTimeout: const Duration(seconds: 20),
           contentType: Headers.jsonContentType,
           responseType: ResponseType.json,
         ),
       ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
    final refreshDio = Dio(_dio.options.copyWith())..httpClientAdapter = _dio.httpClientAdapter;
    refreshDio.interceptors.add(ClientHeadersInterceptor(identity: identity, locale: locale));
    _dio.interceptors.addAll([
      ClientHeadersInterceptor(identity: identity, locale: locale),
      AuthInterceptor(
        dio: _dio,
        refreshDio: refreshDio,
        tokens: tokens,
        events: this.events,
        refreshPath: '/auth/refresh',
      ),
      SafeRetryInterceptor(dio: _dio, baseDelay: retryBaseDelay),
    ]);
  }

  final Dio _dio;
  final TokenStore tokens;
  final SessionEvents events;
  static const _uuid = Uuid();

  /// A fresh key for operations the server deduplicates (purchase verify, quiz submit, ...).
  static String newIdempotencyKey() => _uuid.v7();

  Future<ApiResponse<T>> get<T>(String path, {required Decoder<T> decode, Map<String, Object?>? query}) =>
      _send(path, 'GET', decode: decode, query: query);

  Future<ApiResponse<T>> post<T>(
    String path, {
    required Decoder<T> decode,
    Object? body,
    String? idempotencyKey,
    Map<String, String>? headers,
    bool authenticated = true,
  }) => _send(
    path,
    'POST',
    decode: decode,
    body: body,
    idempotencyKey: idempotencyKey,
    headers: headers,
    authenticated: authenticated,
  );

  Future<ApiResponse<T>> patch<T>(
    String path, {
    required Decoder<T> decode,
    Object? body,
    Map<String, String>? headers,
  }) => _send(path, 'PATCH', decode: decode, body: body, headers: headers);

  Future<ApiResponse<T>> put<T>(String path, {required Decoder<T> decode, Object? body}) =>
      _send(path, 'PUT', decode: decode, body: body);

  /// For 204 responses.
  Future<void> delete(String path, {Map<String, String>? headers}) =>
      _send<void>(path, 'DELETE', decode: (_) {}, headers: headers);

  Future<void> postNoContent(String path, {Object? body, Map<String, String>? headers}) =>
      _send<void>(path, 'POST', decode: (_) {}, body: body, headers: headers);

  Future<ApiResponse<T>> _send<T>(
    String path,
    String method, {
    required Decoder<T> decode,
    Object? body,
    Map<String, Object?>? query,
    String? idempotencyKey,
    Map<String, String>? headers,
    bool authenticated = true,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        path,
        data: body,
        queryParameters: query == null
            ? null
            : {
                for (final e in query.entries)
                  if (e.value != null) e.key: e.value,
              },
        options: Options(
          method: method,
          headers: {...?headers, 'Idempotency-Key': ?idempotencyKey},
          extra: {if (!authenticated) skipAuthExtra: true},
        ),
      );
      return _decodeSuccess(response, decode);
    } on DioException catch (e) {
      throw _failureFrom(e);
    }
  }

  ApiResponse<T> _decodeSuccess<T>(Response<Object?> response, Decoder<T> decode) {
    final requestId = response.headers.value('x-request-id');
    if (response.statusCode == 204 || response.data == null || response.data == '') {
      return ApiResponse(data: decode(null), requestId: requestId);
    }
    final body = response.data;
    if (body is! Map<String, Object?> || !body.containsKey('data')) {
      throw UnexpectedResponseFailure(status: response.statusCode, detail: 'missing envelope', requestId: requestId);
    }
    final meta = body['meta'] as Map<String, Object?>?;
    try {
      return ApiResponse(
        data: decode(body['data']),
        requestId: (meta?['request_id'] as String?) ?? requestId,
        page: PageMeta.fromJson(meta?['page'] as Map<String, Object?>?),
      );
    } on Object catch (e) {
      throw UnexpectedResponseFailure(status: response.statusCode, detail: 'decode: $e', requestId: requestId);
    }
  }

  ApiFailure _failureFrom(DioException e) {
    final response = e.response;
    final requestId = response?.headers.value('x-request-id') ?? e.requestOptions.headers['X-Request-ID'] as String?;
    if (response == null) {
      return NetworkFailure(reason: e.type.name, requestId: requestId);
    }
    final body = response.data;
    if (body is Map<String, Object?> && body['errors'] is List) {
      final errors = [
        for (final item in body['errors']! as List)
          if (item is Map<String, Object?>) ApiErrorItem.fromJson(item),
      ];
      final failure = ServerFailure(
        status: response.statusCode ?? 0,
        errors: errors,
        requestId: ((body['meta'] as Map<String, Object?>?)?['request_id'] as String?) ?? requestId,
        retryAfter: _retryAfter(response.headers.value('retry-after')),
      );
      if (response.statusCode == 401 &&
          const {ApiErrorCode.tokenRevoked, ApiErrorCode.tokenExpired}.contains(failure.code)) {
        return SessionExpiredFailure(requestId: failure.requestId);
      }
      return failure;
    }
    return UnexpectedResponseFailure(
      status: response.statusCode,
      detail: 'non-envelope error body',
      requestId: requestId,
    );
  }

  static Duration? _retryAfter(String? value) {
    final seconds = int.tryParse(value ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }
}
