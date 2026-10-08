import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fintrack/data/api.dart';
import 'package:fintrack/data/ledger.dart';
import 'package:fintrack/main.dart';
import 'package:fintrack/ui/editor.dart';
import 'package:fintrack/ui/screens.dart';
import 'package:fintrack/domain/finance.dart';

class ProfileApi extends CloudApi {
  @override
  Future<Data> request(
    String path, {
    String method = 'GET',
    Data? body,
  }) async => {
    'name': 'FinTrack Tester',
    'email': 'tester@example.com',
    'phone': '',
    'image': null,
    'photoUploadEnabled': false,
  };
  @override
  Future<void> updateUser(Data profile) async {}
}

void main() {
  setUp(() {
    router.go('/');
  });
  testWidgets('login validates input and offers registration', (tester) async {
    final ledger = Ledger(CloudApi());
    await tester.pumpWidget(MaterialApp(home: LoginScreen(ledger: ledger)));
    expect(find.text('FinTrack'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Use at least 8 characters'), findsOneWidget);
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Server connection'), findsNothing);
    ledger.dispose();
  });

  testWidgets('tabs preserve history and system Back returns to Home', (
    tester,
  ) async {
    final api = CloudApi()
      ..session = {
        'user': {'id': 'navigation-test'},
      };
    final ledger = Ledger(api)..loading = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [ledgerProvider.overrideWith((ref) => ledger)],
        child: const FinTrackApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FinScreen), findsOneWidget);

    await tester.tap(find.text('Plans').last);
    await tester.pumpAndSettle();
    expect(find.byType(FinScreen), findsOneWidget);
    expect(find.text('Scheduled income and expenses'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    await tester.tap(find.text('Plans').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activity').last);
    await tester.pumpAndSettle();
    expect(find.text('Your ledger'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Scheduled income and expenses'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Hello, there.'), findsOneWidget);
  });

  testWidgets('account icon opens profile with sign out at the end', (
    tester,
  ) async {
    final api = ProfileApi()
      ..session = {
        'user': {
          'id': 'account-test',
          'name': 'FinTrack Tester',
          'email': 'tester@example.com',
        },
      };
    final ledger = Ledger(api)..loading = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [ledgerProvider.overrideWith((ref) => ledger)],
        child: const FinTrackApp(),
      ),
    );
    await tester.tap(find.byTooltip('My account'));
    await tester.pumpAndSettle();
    expect(find.text('My account'), findsOneWidget);
    expect(find.text('FinTrack Tester'), findsOneWidget);
    expect(find.text('tester@example.com'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byTooltip('Edit profile'));
    await tester.pumpAndSettle();
    expect(find.text('Edit profile'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('My account'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
  });

  testWidgets('all finance screens fit a compact phone', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final api = CloudApi()
      ..session = {
        'user': {'id': 'layout-test'},
      };
    final ledger = Ledger(api)..loading = false;
    ledger.records = [
      Doc('category', 'category', {
        'name': 'Internet and subscriptions',
        'type': 'expense',
        'color': '#2563EB',
      }),
      Doc('monthly', 'plan', {
        'name': 'Monthly broadband',
        'type': 'expense',
        'planType': 'expense',
        'categoryId': 'category',
        'amount': 100000,
        'startDate': todayIndia(),
        'recurrence': 'monthly',
        'reminders': false,
      }),
      Doc('budget:category', 'budget', {
        'categoryId': 'category',
        'amount': 200000,
      }),
    ];
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [ledgerProvider.overrideWith((ref) => ledger)],
        child: const FinTrackApp(),
      ),
    );
    for (final width in [360.0, 390.0, 430.0, 768.0]) {
      tester.view.physicalSize = Size(width, 720);
      for (final tab in ['Plans', 'Activity', 'Reports', 'Settings', 'Home']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$tab overflowed at $width',
        );
      }
    }
  });

  testWidgets('delete confirmation uses the custom sheet and honors cancel', (
    tester,
  ) async {
    bool? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                accepted = await confirm(
                  context,
                  'Remove this transaction?',
                  title: 'Delete this item?',
                  action: 'Delete',
                  destructive: true,
                );
              },
              child: const Text('Open confirmation'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open confirmation'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this item?'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(accepted, isFalse);
  });

  testWidgets('record editor fits a narrow Android screen', (tester) async {
    tester.view.physicalSize = const Size(360, 600);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
    final ledger = Ledger(CloudApi());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => editRecord(context, ledger, 'plan'),
              child: const Text('Add a plan'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add a plan'));
    await tester.pumpAndSettle();
    expect(find.text('Add plan'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Add a plan'), findsOneWidget);
    ledger.dispose();
  });
}
