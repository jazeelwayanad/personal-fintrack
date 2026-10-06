import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/data/api.dart';
import 'package:fintrack/data/ledger.dart';
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
    ledger.dispose();
  });
}
