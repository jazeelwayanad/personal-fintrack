import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fintrack/data/api.dart';
import 'package:fintrack/data/upi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  CloudApi apiFor(http.Client client) => CloudApi(client: client)
    ..session = {
      'user': {'id': 'test-owner'},
      'accessToken': 'test-token',
    };

  test(
    'manual recording reuses its request key after a lost response',
    () async {
      final requests = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (requests.length == 1) throw http.ClientException('Connection lost');
        return http.Response('{"status":"recorded_manually"}', 200);
      });
      final input = {
        'expectedRevision': 3,
        'paymentMethodId': 'bank',
        'postingDate': '2026-11-18',
      };
      final first = apiFor(client);
      await expectLater(
        recordUpiExpense(first, 'attempt', input),
        throwsA(isA<http.ClientException>()),
      );
      final restarted = apiFor(client);
      await recordUpiExpense(restarted, 'attempt', input);
      expect(requests[1], requests[0]);
      await recordUpiExpense(restarted, 'attempt', {
        ...input,
        'paymentMethodId': 'cash',
      });
      expect(
        requests[2]['idempotencyKey'],
        isNot(requests[0]['idempotencyKey']),
      );
      client.close();
    },
  );

  test(
    'retains a returned app result and retries it without reopening payment',
    () async {
      var launches = 0;
      var reports = 0;
      String? firstKey;
      final api = apiFor(
        MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response('{"status":"awaiting_confirmation"}', 200);
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['result'] == 'claim') {
            return http.Response('{"launchAllowed":true}', 200);
          }
          reports++;
          expect(body['result'], 'success');
          firstKey ??= body['idempotencyKey'] as String;
          expect(body['idempotencyKey'], firstKey);
          if (reports == 1) throw http.ClientException('Response lost');
          return http.Response('{"status":"awaiting_confirmation"}', 200);
        }),
      );
      await expectLater(
        handoffUpi(api, 'attempt', 'upi://pay?pa=test@bank', (_) async {
          launches++;
          return 'success';
        }),
        throwsA(isA<http.ClientException>()),
      );
      await retryUpiOutcome(api);
      expect(launches, 1);
      expect(reports, 2);
      expect(await api.storage.readAll(), isEmpty);
      api.client.close();
    },
  );

  test('recovers an interrupted native handoff as unknown', () async {
    var result = '';
    final api = apiFor(
      MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response('{"status":"awaiting_confirmation"}', 200);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['result'] == 'claim') {
          return http.Response('{"launchAllowed":true}', 200);
        }
        result = body['result'] as String;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      handoffUpi(api, 'attempt', 'upi://pay?pa=test@bank', (_) async {
        throw StateError('Process interrupted');
      }),
      throwsStateError,
    );
    await retryUpiOutcome(api);
    expect(result, 'unknown');
    expect(await api.storage.readAll(), isEmpty);
    api.client.close();
  });

  test('does not launch after the server declines the handoff claim', () async {
    final api = apiFor(
      MockClient(
        (request) async => http.Response(
          request.method == 'GET'
              ? '{"status":"awaiting_confirmation"}'
              : '{"launchAllowed":false}',
          200,
        ),
      ),
    );
    var launches = 0;
    expect(
      await handoffUpi(api, 'attempt', 'upi://pay?pa=test@bank', (_) async {
        launches++;
        return 'success';
      }),
      'unknown',
    );
    expect(launches, 0);
    api.client.close();
  });
}
