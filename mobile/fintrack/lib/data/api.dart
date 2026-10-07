import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../domain/finance.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

class CloudApi {
  final http.Client client;
  final FlutterSecureStorage storage;
  Data? session;
  String baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://fintrack.eucodes.tech',
  );
  Future<void>? _refreshing;
  CloudApi({http.Client? client, FlutterSecureStorage? storage})
    : client = client ?? http.Client(),
      storage = storage ?? const FlutterSecureStorage();
  Future<void> restore() async {
    final saved = await storage.read(key: 'fintrack-session');
    if (saved != null) {
      final restored = jsonDecode(saved) as Data;
      if (restored['baseUrl'] == baseUrl) {
        session = restored;
      } else {
        await storage.delete(key: 'fintrack-session');
      }
    }
  }

  Future<Data> _send(
    String path,
    String method,
    Data? body, {
    bool authenticated = true,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-FinTrack-Finance-Version': '2',
      if (authenticated && session != null)
        'Authorization': 'Bearer ${session!['accessToken']}',
    };
    final uri = Uri.parse('$baseUrl$path');
    final response =
        await (method == 'GET'
                ? client.get(uri, headers: headers)
                : method == 'DELETE'
                ? client.delete(
                    uri,
                    headers: headers,
                    body: jsonEncode(body ?? {}),
                  )
                : method == 'PATCH'
                ? client.patch(
                    uri,
                    headers: headers,
                    body: jsonEncode(body ?? {}),
                  )
                : client.post(
                    uri,
                    headers: headers,
                    body: jsonEncode(body ?? {}),
                  ))
            .timeout(const Duration(seconds: 25));
    Data data;
    try {
      data = jsonDecode(response.body) as Data;
    } catch (_) {
      throw ApiException(
        response.statusCode,
        'The server is unavailable or needs the FinTrack API update.',
      );
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        text(data, 'error', 'Request failed'),
      );
    }
    return data;
  }

  Future<Data> request(String path, {String method = 'GET', Data? body}) async {
    try {
      return await _send(path, method, body);
    } on ApiException catch (e) {
      if (e.status != 401 || session == null) rethrow;
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
      await _refreshing;
      return _send(path, method, body);
    }
  }

  Future<void> _refresh() async {
    try {
      final tokens = await _send('/api/v1/auth/refresh', 'POST', {
        'refreshToken': session!['refreshToken'],
      }, authenticated: false);
      session!.addAll(tokens);
      await _persist();
    } on ApiException catch (error) {
      if (error.status == 401) {
        session = null;
        await storage.delete(key: 'fintrack-session');
      }
      rethrow;
    }
  }

  Future<void> _persist() =>
      storage.write(key: 'fintrack-session', value: jsonEncode(session));
  Future<void> login(
    String email,
    String password, {
    bool register = false,
    String name = '',
  }) async {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && !(kDebugMode && uri.scheme == 'http'))) {
      throw ApiException(400, 'FinTrack server configuration is invalid.');
    }
    session = await _send(
      '/api/v1/auth/${register ? 'register' : 'login'}',
      'POST',
      {'email': email, 'password': password, 'name': name},
      authenticated: false,
    );
    session!['baseUrl'] = baseUrl;
    await _persist();
  }

  Future<void> updateUser(Data profile) async {
    session?['user'] = {
      ...Map<String, dynamic>.from(session?['user'] ?? {}),
      'name': profile['name'],
      'email': profile['email'],
      'image': profile['image'],
    };
    await _persist();
  }

  Future<Data> uploadPhoto(List<int> bytes) async {
    Future<Data> send() async {
      final response = await client
          .post(
            Uri.parse('$baseUrl/api/v1/account/photo'),
            headers: {
              'Authorization': 'Bearer ${session?['accessToken']}',
              'Content-Type': 'image/jpeg',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(response.body) as Data;
      if (response.statusCode >= 400) {
        throw ApiException(
          response.statusCode,
          text(data, 'error', 'Upload failed'),
        );
      }
      return data;
    }

    try {
      return await send();
    } on ApiException catch (e) {
      if (e.status != 401 || session == null) rethrow;
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
      await _refreshing;
      return send();
    }
  }

  Future<void> logout() async {
    try {
      await _send('/api/v1/auth/logout', 'POST', {
        'refreshToken': session?['refreshToken'],
      }, authenticated: false);
    } catch (_) {
      /* Local logout always remains available. */
    }
    session = null;
    await storage.delete(key: 'fintrack-session');
  }
}
