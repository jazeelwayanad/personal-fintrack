import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';
import 'api.dart';

class PushNotifications {
  final CloudApi api;
  final void Function(String) navigate;
  final local = FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? refresh;
  StreamSubscription<RemoteMessage>? foreground, opened;
  bool ready = false;
  PushNotifications(this.api, this.navigate);
  Future<void> initialize() async {
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
    if (projectId.isEmpty || ready) return;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
          appId: String.fromEnvironment('FIREBASE_APP_ID'),
          messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
          projectId: projectId,
        ),
      );
    }
    await local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (r) => navigate(r.payload ?? '/plans'),
    );
    await local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'fintrack_reminders',
            'Payment reminders',
            description: 'Upcoming and overdue FinTrack payments',
            importance: Importance.high,
          ),
        );
    foreground = FirebaseMessaging.onMessage.listen((message) {
      if (api.session == null || message.notification == null) return;
      unawaited(
        local.show(
          id: 1,
          title: message.notification!.title,
          body: message.notification!.body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'fintrack_reminders',
              'Payment reminders',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          payload: message.data['route'] ?? '/plans',
        ),
      );
    });
    opened = FirebaseMessaging.onMessageOpenedApp.listen(
      (m) => navigate(m.data['route'] ?? '/plans'),
    );
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) navigate(initial.data['route'] ?? '/plans');
    refresh = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      if (api.session != null) unawaited(register(token).catchError((_) {}));
    });
    ready = true;
  }

  Future<void> enable() async {
    await initialize();
    if (!ready) {
      throw ApiException(
        503,
        'Firebase setup is still needed for push notifications. Your in-app reminders are available.',
      );
    }
    final permission = await FirebaseMessaging.instance.requestPermission();
    if (permission.authorizationStatus != AuthorizationStatus.authorized) {
      throw ApiException(
        400,
        'Allow notifications in Android settings to receive reminders.',
      );
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) {
      throw ApiException(503, 'No notification token is available yet.');
    }
    await register(token);
  }

  Future<String> deviceId() async {
    final key = 'fintrack-device-${api.session?['user']['id']}';
    var id = await api.storage.read(key: key);
    if (id == null) {
      id = const Uuid().v4();
      await api.storage.write(key: key, value: id);
    }
    return id;
  }

  Future<void> register(String token) async {
    await api.request(
      '/api/v1/devices',
      method: 'POST',
      body: {'id': await deviceId(), 'platform': 'android', 'token': token},
    );
  }

  Future<void> logout() async {
    try {
      await api.request(
        '/api/v1/devices',
        method: 'DELETE',
        body: {'id': await deviceId()},
      );
    } catch (_) {}
    if (ready) {
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
    }
    await local.cancelAll();
  }

  Future<void> dispose() async {
    await refresh?.cancel();
    await foreground?.cancel();
    await opened?.cancel();
  }
}
