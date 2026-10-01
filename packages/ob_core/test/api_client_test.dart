import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';

import 'support/fake_http.dart';

void main() {
  late FakeAdapter adapter;
  late InMemoryTokenStore store;
  late ApiClient client;

  setUp(() {
    adapter = FakeAdapter((_) => json(200, envelope(null)));
    store = InMemoryTokenStore();
    client = ApiClient(
      baseUrl: 'https://api.test/api/v1',
      tokens: store,
      identity: const ClientIdentity(installationId: 'install-1234', appVersion: '0.1.0', platform: 'android'),
      locale: () => 'bn',
      adapter: adapter,
      retryBaseDelay: const Duration(milliseconds: 1),
    );
  });

  test('decodes the envelope and cursor pagination', () async {
    adapter.handler = (_) => json(200, envelope([1, 2], page: {'next_cursor': 'abc', 'has_more': true, 'limit': 2}));
    final response = await client.get('/books', decode: (j) => (j! as List).cast<int>());
    expect(response.data, [1, 2]);
    expect(response.requestId, 'req_server');
    final page = response.page! as CursorPageMeta;
    expect((page.nextCursor, page.hasMore, page.limit), ('abc', true, 2));
  });

  test('sends request id, device, version, language and bearer headers', () async {
    await store.write(tokens('access-1', 'refresh-1'));
    await client.get('/me', decode: (_) {});
    final headers = adapter.requests.single.headers;
    expect(headers['X-Request-ID'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(headers['X-Device-Id'], 'install-1234');
    expect(headers['X-App-Version'], '0.1.0');
    expect(headers['Accept-Language'], 'bn');
    expect(headers['Authorization'], 'Bearer access-1');
  });

  test('maps the error envelope to ServerFailure with code, field errors and Retry-After', () async {
    adapter.handler = (_) => json(
      429,
      errorBody('RATE_LIMITED', field: 'email'),
      headers: {
        'retry-after': ['30'],
      },
    );
    await expectLater(
      client.post('/auth/login', decode: (_) {}, body: {}, authenticated: false),
      throwsA(
        isA<ServerFailure>()
            .having((f) => f.code, 'code', ApiErrorCode.rateLimited)
            .having((f) => f.fieldErrors, 'fields', {'email': 'x'})
            .having((f) => f.retryAfter, 'retryAfter', const Duration(seconds: 30))
            .having((f) => f.requestId, 'requestId', 'req_err'),
      ),
    );
  });

  test('unknown codes from a newer server do not crash', () async {
    adapter.handler = (_) => json(400, errorBody('SOMETHING_NEW'));
    await expectLater(
      client.get('/x', decode: (_) {}),
      throwsA(isA<ServerFailure>().having((f) => f.code, 'code', ApiErrorCode.unknown)),
    );
  });

  test('non-envelope bodies are UnexpectedResponseFailure', () async {
    adapter.handler = (_) => ResponseBody.fromString('<html>gateway</html>', 500);
    await expectLater(client.get('/x', decode: (_) {}), throwsA(isA<UnexpectedResponseFailure>()));
  });

  test('concurrent TOKEN_EXPIRED responses trigger exactly one refresh, then replay', () async {
    await store.write(tokens('old-access', 'refresh-1'));
    var refreshCalls = 0;
    adapter.handler = (request) {
      if (request.path.endsWith('/auth/refresh')) {
        refreshCalls++;
        expect(request.headers['Authorization'], isNull); // refresh never sends the expired access token
        expect((request.data as Map)['refresh_token'], 'refresh-1');
        return json(200, envelope(tokenPair('new-access', 'refresh-2')));
      }
      return request.headers['Authorization'] == 'Bearer new-access'
          ? json(200, envelope('ok'))
          : json(401, errorBody('TOKEN_EXPIRED'));
    };
    final events = <SessionEvent>[];
    client.events.stream.listen(events.add);

    final results = await Future.wait([
      for (var i = 0; i < 3; i++) client.get('/me', decode: (j) => j! as String),
    ]);

    expect(results.map((r) => r.data), ['ok', 'ok', 'ok']);
    expect(refreshCalls, 1); // a second refresh with the rotated token would kill the session
    expect((await store.read())!.refreshToken, 'refresh-2');
    expect(events, contains(SessionEvent.refreshed));
  });

  test('revoked session clears tokens and emits expired', () async {
    await store.write(tokens('access', 'refresh'));
    adapter.handler = (_) => json(401, errorBody('TOKEN_REVOKED'));
    final events = <SessionEvent>[];
    client.events.stream.listen(events.add);
    await expectLater(client.get('/me', decode: (_) {}), throwsA(isA<SessionExpiredFailure>()));
    await Future<void>.delayed(Duration.zero);
    expect(await store.read(), isNull);
    expect(events, [SessionEvent.expired]);
  });

  test('failed refresh ends the session', () async {
    await store.write(tokens('old', 'stale-refresh'));
    adapter.handler = (request) => request.path.endsWith('/auth/refresh')
        ? json(401, errorBody('TOKEN_REVOKED'))
        : json(401, errorBody('TOKEN_EXPIRED'));
    await expectLater(client.get('/me', decode: (_) {}), throwsA(isA<SessionExpiredFailure>()));
    expect(await store.read(), isNull);
  });

  test('GET is retried on 503; POST without an idempotency key is not', () async {
    var calls = 0;
    adapter.handler = (_) => ++calls < 3 ? json(503, errorBody('SERVICE_UNAVAILABLE')) : json(200, envelope('ok'));
    expect((await client.get('/books', decode: (j) => j)).data, 'ok');
    expect(calls, 3);

    calls = 0;
    adapter.handler = (_) {
      calls++;
      return json(503, errorBody('SERVICE_UNAVAILABLE'));
    };
    await expectLater(client.post('/attempts', decode: (_) {}, body: {}), throwsA(isA<ServerFailure>()));
    expect(calls, 1);
  });

  test('POST with an idempotency key is retried with the same key', () async {
    var calls = 0;
    adapter.handler = (_) => ++calls < 2 ? json(503, errorBody('SERVICE_UNAVAILABLE')) : json(200, envelope('ok'));
    final key = ApiClient.newIdempotencyKey();
    await client.post('/purchases/verify', decode: (_) {}, body: {}, idempotencyKey: key);
    expect(adapter.requests.map((r) => r.headers['Idempotency-Key']).toSet(), {key});
  });

  test('connection errors become NetworkFailure after retries', () async {
    adapter.handler = (request) => throw DioException.connectionError(requestOptions: request, reason: 'offline');
    await expectLater(client.get('/books', decode: (_) {}), throwsA(isA<NetworkFailure>()));
    expect(adapter.requests, hasLength(3)); // first try + 2 retries
  });

  group('LocalizedText', () {
    test('resolves requested -> bn -> en -> first', () {
      const text = LocalizedText({'bn': 'পদার্থবিজ্ঞান', 'en': 'Physics'});
      expect(text.resolve('en'), 'Physics');
      expect(text.resolve('bn'), 'পদার্থবিজ্ঞান');
      expect(text.resolve('fr'), 'পদার্থবিজ্ঞান');
      expect(const LocalizedText({'en': 'Only English'}).resolve('bn'), 'Only English');
      expect(LocalizedText.fromJson('server resolved').resolve('en'), 'server resolved');
    });
  });
}
