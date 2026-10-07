import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fintrack/data/api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('PATCH and binary photo retry after token refresh', () async {
    var refreshes = 0, uploads = 0;
    final api =
        CloudApi(
            client: MockClient((request) async {
              if (request.url.path.endsWith('/refresh')) {
                refreshes++;
                return http.Response(
                  jsonEncode({'accessToken': 'new', 'refreshToken': 'rotated'}),
                  200,
                );
              }
              if (request.url.path.endsWith('/photo')) {
                uploads++;
                expect(request.headers['content-type'], 'image/jpeg');
                expect(request.bodyBytes, [255, 216, 255, 217]);
                if (request.headers['authorization'] == 'Bearer old') {
                  return http.Response('{"error":"Expired"}', 401);
                }
                return http.Response(
                  '{"image":"/api/v1/account/photo?v=2"}',
                  200,
                );
              }
              expect(request.method, 'PATCH');
              expect(request.headers['X-FinTrack-Finance-Version'], '2');
              expect(jsonDecode(request.body)['name'], 'Updated');
              return http.Response('{"name":"Updated"}', 200);
            }),
          )
          ..session = {
            'accessToken': 'old',
            'refreshToken': 'original',
            'user': {'id': 'test'},
          };
    await api.uploadPhoto([255, 216, 255, 217]);
    expect(uploads, 2);
    expect(refreshes, 1);
    expect(
      (await api.request(
        '/api/v1/account',
        method: 'PATCH',
        body: {'name': 'Updated'},
      ))['name'],
      'Updated',
    );
    api.client.close();
  });
  test(
    'origin change discards tokens without accessing ledger storage',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'fintrack-session': jsonEncode({
          'baseUrl': 'https://jaseelfintrack.vercel.app',
          'accessToken': 'private',
        }),
      });
      final api = CloudApi();
      await api.restore();
      expect(api.session, isNull);
      expect(await api.storage.read(key: 'fintrack-session'), isNull);
      api.client.close();
    },
  );
}
