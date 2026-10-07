import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uuid/uuid.dart';
import 'package:fintrack/data/api.dart';
import 'package:fintrack/domain/finance.dart';
import 'package:fintrack/ui/profile_photo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('isolated production account syncs between two native clients', (
    tester,
  ) async {
    if (!const bool.fromEnvironment('RUN_LIVE_TESTS')) return;
    final runId = const Uuid().v4(), email = 'release-v120-$runId@example.test';
    final password = 'Isolated-release-$runId';
    final first = CloudApi(), second = CloudApi();
    await first.login(
      email,
      password,
      register: true,
      name: 'Isolated release test',
    );
    // The release runner removes only this temporary account after validation.
    debugPrint('RELEASE_TEST_ACCOUNT:$email');
    final category = 'test-$runId-category',
        method = 'test-$runId-bank',
        plan = 'test-$runId-recharge';
    Map<String, dynamic> change(String id, String kind, Data data) => {
      'id': id,
      'kind': kind,
      'data': data,
      'deleted': false,
      'baseRevision': 0,
    };
    Future<Data> push(List<Data> changes) => first.request(
      '/api/v1/sync',
      method: 'POST',
      body: {'id': const Uuid().v4(), 'changes': changes},
    );
    final initial = await push([
      change(category, 'category', {
        'name': 'Recharge',
        'type': 'expense',
        'color': '#2563EB',
        'icon': '',
      }),
      change(method, 'paymentMethod', {'name': 'Test bank', 'icon': ''}),
      change(plan, 'plan', {
        'name': '28-day recharge',
        'type': 'expense',
        'planType': 'recharge',
        'amount': 29900,
        'categoryId': category,
        'startDate': todayIndia(),
        'recurrence': 'custom',
        'intervalDays': 28,
        'reminders': false,
      }),
    ]);
    expect(initial['accepted'], true);
    await second.login(email, password);
    final before = await second.request('/api/v1/sync?cursor=0');
    expect(
      (before['records'] as List).where((r) => r['id'] == plan),
      hasLength(1),
    );
    final oid = '$plan:${todayIndia()}';
    expect(
      (await push([
        change(oid, 'occurrence', {
          'planId': plan,
          'name': '28-day recharge',
          'type': 'expense',
          'amount': 29900,
          'categoryId': category,
          'date': todayIndia(),
          'reminders': false,
          'status': 'pending',
        }),
        change('payment:$oid', 'transaction', {
          'type': 'expense',
          'amount': 29900,
          'categoryId': category,
          'paymentMethodId': method,
          'date': todayIndia(),
          'occurrenceId': oid,
        }),
      ]))['accepted'],
      true,
    );
    final after = await second.request('/api/v1/sync?cursor=0');
    final records = (after['records'] as List)
        .map((r) => Doc.fromJson(Map<String, dynamic>.from(r)))
        .toList();
    expect(summary(records, todayIndia())['expenses'], 29900);
    expect(
      occurrences(
        records,
        todayIndia(),
        addDays(todayIndia(), 28),
      ).where((o) => !o.paid).single.doc.data['date'],
      addDays(todayIndia(), 28),
    );
    final profile = await first.request(
      '/api/v1/account',
      method: 'PATCH',
      body: {
        'name': 'Isolated release test',
        'email': email,
        'phone': '+91 90000 00000',
      },
    );
    expect(profile['phone'], '+91 90000 00000');
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 600, 800),
      ui.Paint()..color = const ui.Color(0xff073b3b),
    );
    final picture = recorder.endRecording(),
        image = await picture.toImage(600, 800);
    final source = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    final photo = await first.uploadPhoto(await prepareProfilePhoto(source));
    expect(photo['image'], isNotNull);
    expect((await second.request('/api/v1/account'))['image'], photo['image']);
    await first.request('/api/v1/account/photo', method: 'DELETE');
    expect((await second.request('/api/v1/account'))['image'], isNull);
    image.dispose();
    picture.dispose();
    await first.logout();
    await second.logout();
    first.client.close();
    second.client.close();
  });
}
