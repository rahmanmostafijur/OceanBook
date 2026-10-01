import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ob_core/ob_core.dart';

typedef Handler = ResponseBody Function(RequestOptions request);

/// Scripted HTTP layer: records every request and answers with the given handler.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  Handler handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    await Future<void>.delayed(const Duration(milliseconds: 5)); // let concurrent requests overlap
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(int status, Object body, {Map<String, List<String>> headers = const {}}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    ...headers,
  },
);

Map<String, Object?> envelope(Object? data, {Map<String, Object?>? page}) => {
  'data': data,
  'meta': {'request_id': 'req_server', 'page': page},
  'errors': <Object>[],
};

Map<String, Object?> errorBody(String code, {String message = 'x', String? field, Map<String, Object?>? details}) => {
  'data': null,
  'meta': {'request_id': 'req_err'},
  'errors': [
    {'code': code, 'message': message, 'field': field, 'details': details ?? <String, Object?>{}},
  ],
};

AuthTokens tokens(String access, String refresh) => AuthTokens(
  accessToken: access,
  accessTokenExpiresAt: DateTime.utc(2030),
  refreshToken: refresh,
  refreshTokenExpiresAt: DateTime.utc(2030),
  deviceId: 'device-1',
);

Map<String, Object?> tokenPair(String access, String refresh) => {
  'status': 'authenticated',
  'access_token': access,
  'access_token_expires_at': '2030-01-01T00:00:00Z',
  'refresh_token': refresh,
  'refresh_token_expires_at': '2030-01-01T00:00:00Z',
  'device_id': 'device-1',
};
