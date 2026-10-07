import 'dart:ui' as ui;
import 'package:fintrack/ui/profile_photo.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fintrack/main.dart';
import 'package:fintrack/data/api.dart';
import 'package:fintrack/data/database.dart';
import 'package:fintrack/data/ledger.dart';
import 'package:fintrack/domain/finance.dart';

class UiApi extends CloudApi {
  UiApi() {
    session = {
      'user': {
        'id': 'isolated-ui-test',
        'name': 'UI test ledger',
        'email': 'ui@example.test',
      },
    };
  }
  @override
  Future<Data> request(
    String path, {
    String method = 'GET',
    Data? body,
  }) async => {
    'name': 'UI test ledger',
    'email': 'ui@example.test',
    'phone': '+91 90000 00000',
    'image': null,
    'photoUploadEnabled': true,
  };
  @override
  Future<void> updateUser(Data profile) async {}
}

class UiLedger extends Ledger {
  UiLedger() : super(UiApi());
  @override
  Future<void> sync() async {
    status = 'Offline · isolated UI test';
    notifyListeners();
  }

  @override
  Future<void> save(List<Doc> docs, {bool autoSync = true}) =>
      super.save(docs, autoSync: false);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native photo compressor creates a square small JPEG', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 800, 1200),
      ui.Paint()..color = const ui.Color(0xff073b3b),
    );
    final picture = recorder.endRecording();
    final input = await picture.toImage(800, 1200);
    final source = (await input.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    final bytes = await prepareProfilePhoto(source);
    expect(bytes.length, lessThanOrEqualTo(128 * 1024));
    expect(bytes.take(2).toList(), [255, 216]);
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    expect(image.width, 384);
    expect(image.height, 384);
    image.dispose();
    codec.dispose();
    input.dispose();
    picture.dispose();
  });
  testWidgets('native screen parity, payment, and Android back history', (
    tester,
  ) async {
    final ledger = UiLedger()
      ..loading = false
      ..database = LedgerDatabase(NativeDatabase.memory());
    ledger.records = [
      Doc('opening', 'adjustment', {'amount': 500000, 'date': todayIndia()}),
      Doc('internet', 'category', {
        'name': 'Internet',
        'type': 'expense',
        'color': '#2563EB',
        'icon': '',
      }),
      Doc('salary', 'category', {
        'name': 'Income',
        'type': 'income',
        'color': '#74AA89',
        'icon': '',
      }),
      Doc('bank', 'paymentMethod', {'name': 'Bank account', 'icon': ''}),
      Doc('broadband', 'plan', {
        'name': 'Broadband',
        'type': 'expense',
        'planType': 'expense',
        'amount': 100000,
        'categoryId': 'internet',
        'startDate': todayIndia(),
        'recurrence': 'monthly',
        'reminders': true,
      }),
      Doc('mobile', 'plan', {
        'name': 'Mobile recharge',
        'type': 'expense',
        'planType': 'recharge',
        'amount': 50000,
        'categoryId': 'internet',
        'startDate': todayIndia(),
        'recurrence': 'custom',
        'intervalDays': 28,
        'reminders': true,
      }),
      Doc('budget:internet', 'budget', {
        'categoryId': 'internet',
        'amount': 200000,
      }),
    ];
    router.go('/');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [ledgerProvider.overrideWith((ref) => ledger)],
        child: const FinTrackApp(),
      ),
    );
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('home');
    await tester.tap(find.text('Plans').last);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('plans');
    await tester.tap(find.text('Activity').last);
    await tester.pumpAndSettle();
    expect(find.text('Your ledger'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'saved search');
    await tester.pump();
    await binding.takeScreenshot('activity');
    await tester.tap(find.text('Reports').last);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('reports');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('saved search'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Scheduled income and expenses'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Hello, UI test ledger.'), findsOneWidget);
    for (var i = 0; i < 12 && find.text('Mark paid').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('Mark paid').first);
    await tester.tap(find.text('Mark paid').first);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('payment-editor');
    await tester.ensureVisible(find.text('Save').last);
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(summary(ledger.records, todayIndia())['expenses'], 100000);
    expect(summary(ledger.records, todayIndia())['commitments'], 50000);
    expect(summary(ledger.records, todayIndia())['unallocated'], 300000);
    await binding.takeScreenshot('paid-budget');
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('settings');
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('My account'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('account');
    await tester.tap(find.byTooltip('Edit profile'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('account-edit');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Toggle theme'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('home-dark');
    expect(tester.takeException(), isNull);
    final database = ledger.database;
    ledger.database = null;
    await tester.pumpWidget(const SizedBox.shrink());
    await database?.close();
  });
}
