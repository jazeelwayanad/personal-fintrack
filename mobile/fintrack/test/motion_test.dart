import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/ui/motion.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'press feedback respects reduced motion $reduced and keeps taps',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: FinPress(
                  child: FilledButton(
                    onPressed: () => taps++,
                    child: const Text('Add transaction'),
                  ),
                ),
              ),
            ),
          ),
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(FilledButton)),
        );
        await tester.pump();
        final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
        expect(scale.scale, reduced ? 1 : .97);
        expect(
          scale.duration,
          reduced ? Duration.zero : const Duration(milliseconds: 100),
        );
        await gesture.up();
        await tester.pumpAndSettle();
        expect(taps, 1);
        expect(
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
          1,
        );
      },
    );
    testWidgets('page motion respects reduced motion $reduced', (tester) async {
      final page = finPage(const ValueKey('page'), const Text('Destination'));
      final animation = AnimationController(vsync: tester, value: .5);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Builder(
              builder: (context) => KeyedSubtree(
                key: const ValueKey('motion-root'),
                child: page.transitionsBuilder(
                  context,
                  animation,
                  animation,
                  page.child,
                ),
              ),
            ),
          ),
        ),
      );
      final destination = find.text('Destination');
      expect(destination, findsOneWidget);
      // Scope to the route content: MaterialApp can have its own transitions.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('motion-root')),
          matching: find.byType(SlideTransition),
        ),
        reduced ? findsNothing : findsOneWidget,
      );
      animation.dispose();
    });
  }
}
