import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fintrack/data/api.dart';
import 'package:fintrack/data/ledger.dart';
import 'package:fintrack/main.dart';
import 'package:fintrack/ui/editor.dart';
import 'package:fintrack/ui/screens.dart';

void main() {
  testWidgets('login validates input and offers registration', (tester) async {
    final ledger = Ledger(CloudApi());
    await tester.pumpWidget(MaterialApp(home: LoginScreen(ledger: ledger)));
    expect(find.text('FinTrack'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Use at least 8 characters'), findsOneWidget);
    await tester.tap(find.text('Create an account'));
    await tester.pump();
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Server connection'), findsNothing);
    ledger.dispose();
  });

  testWidgets('bottom tabs switch without stacking an animated page', (
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
    await tester.pump();
    expect(find.byType(FinScreen), findsOneWidget);

    await tester.tap(find.text('Plans').last);
    await tester.pump();
    expect(find.byType(FinScreen), findsOneWidget);
    expect(find.text('Scheduled income and expenses'), findsOneWidget);
  });

  testWidgets('account icon opens profile with sign out at the end', (
    tester,
  ) async {
    final api = CloudApi()
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
    await tester.pump();
    expect(find.text('My account'), findsOneWidget);
    expect(find.text('FinTrack Tester'), findsOneWidget);
    expect(find.text('tester@example.com'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byTooltip('Back to home'));
    await tester.pump();
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [ledgerProvider.overrideWith((ref) => ledger)],
        child: const FinTrackApp(),
      ),
    );
    for (final tab in ['Plans', 'Activity', 'Reports', 'Settings', 'Home']) {
      await tester.tap(find.text(tab).last);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$tab overflowed');
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
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
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
    ledger.dispose();
  });
}
