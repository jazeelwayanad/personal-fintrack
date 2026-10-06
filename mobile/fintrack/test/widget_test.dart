import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fintrack/data/api.dart';
import 'package:fintrack/data/ledger.dart';
import 'package:fintrack/main.dart';
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
}
