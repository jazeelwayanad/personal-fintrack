import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/ui/patterns.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('branded loading respects reduced motion $reduced', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: const Scaffold(
              body: BrandLoading(label: 'Opening FinTrack…'),
            ),
          ),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Opening FinTrack…'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        reduced ? 1 : null,
      );
    });
  }
}
