import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fintrack/data/updates.dart';

Map<String, dynamic> releaseData({String? url}) => {
  'tag_name': 'v1.2.4',
  'draft': false,
  'prerelease': false,
  'assets': [
    {
      'name': 'FinTrack-1.2.4.apk',
      'state': 'uploaded',
      'browser_download_url':
          url ??
          'https://github.com/$releaseRepository/releases/download/v1.2.4/FinTrack-1.2.4.apk',
    },
  ],
};
void main() {
  test('updates compare numeric versions and never offer a downgrade', () {
    expect(newerVersion('1.2.10', '1.2.9'), isTrue);
    expect(newerVersion('1.3.0', '1.2.9'), isTrue);
    expect(newerVersion('1.2.3', '1.2.3'), isFalse);
    expect(newerVersion('1.2.2', '1.2.3'), isFalse);
    expect(newerVersion('1.2.4-beta', '1.2.3'), isFalse);
  });
  test(
    'release check uses public endpoint without ledger credentials',
    () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.github.com/repos/$releaseRepository/releases/latest',
        );
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response(jsonEncode(releaseData()), 200);
      });
      expect((await AppRelease.latest(client: client)).version, '1.2.4');
    },
  );
  test('rejects APKs hosted outside the approved repository', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(releaseData(url: 'https://example.com/FinTrack-1.2.4.apk')),
        200,
      ),
    );
    await expectLater(AppRelease.latest(client: client), throwsStateError);
  });
  test('release errors and missing assets are recoverable failures', () async {
    await expectLater(
      AppRelease.latest(
        client: MockClient((_) async => http.Response('', 429)),
      ),
      throwsStateError,
    );
    final data = releaseData()..['assets'] = [];
    await expectLater(
      AppRelease.latest(
        client: MockClient((_) async => http.Response(jsonEncode(data), 200)),
      ),
      throwsStateError,
    );
  });
  test('draft and prerelease builds are excluded', () async {
    for (final field in ['draft', 'prerelease']) {
      final data = releaseData()..[field] = true;
      await expectLater(
        AppRelease.latest(
          client: MockClient((_) async => http.Response(jsonEncode(data), 200)),
        ),
        throwsStateError,
      );
    }
  });
}
