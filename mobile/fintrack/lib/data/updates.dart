import 'dart:convert';
import 'package:http/http.dart' as http;

const appVersion = '1.2.3';
const releaseRepository = 'jazeelwayanad/personal-fintrack';

bool newerVersion(String candidate, String installed) {
  List<int>? parts(String value) => RegExp(r'^\d+\.\d+\.\d+$').hasMatch(value)
      ? value.split('.').map(int.parse).toList()
      : null;
  final next = parts(candidate), current = parts(installed);
  if (next == null || current == null) return false;
  for (var i = 0; i < 3; i++) {
    if (next[i] != current[i]) return next[i] > current[i];
  }
  return false;
}

class AppRelease {
  final String version;
  final Uri download;
  const AppRelease(this.version, this.download);

  static Future<AppRelease> latest({http.Client? client}) async {
    final connection = client ?? http.Client();
    try {
      final response = await connection
          .get(
            Uri.https(
              'api.github.com',
              '/repos/$releaseRepository/releases/latest',
            ),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw StateError('Release unavailable');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = data['tag_name'] as String;
      final version = tag.startsWith('v') ? tag.substring(1) : tag;
      if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
          data['draft'] == true ||
          data['prerelease'] == true) {
        throw StateError('Unsupported release');
      }
      final asset = (data['assets'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere(
            (item) =>
                item['name'] == 'FinTrack-$version.apk' &&
                item['state'] == 'uploaded',
          );
      final download = Uri.parse(asset['browser_download_url'] as String);
      if (download.toString() !=
          'https://github.com/$releaseRepository/releases/download/v$version/FinTrack-$version.apk') {
        throw StateError('Unexpected download destination');
      }
      return AppRelease(version, download);
    } finally {
      if (client == null) connection.close();
    }
  }
}
