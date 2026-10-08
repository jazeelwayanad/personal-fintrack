import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Short, quiet movement; accessibility settings remove transforms and fades.
bool reduceMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);

CustomTransitionPage<void> finPage(LocalKey key, Widget child) =>
    CustomTransitionPage<void>(
      key: key,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (reduceMotion(context)) return child;
        final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: curved.drive(
              Tween(begin: const Offset(.025, 0), end: Offset.zero),
            ),
            child: child,
          ),
        );
      },
    );

/// Apply to controls whose hit target must remain unchanged during a press.
class FinPress extends StatefulWidget {
  final Widget child;
  const FinPress({super.key, required this.child});
  @override
  State<FinPress> createState() => _FinPressState();
}

class _FinPressState extends State<FinPress> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => setState(() => pressed = true),
    onPointerUp: (_) => setState(() => pressed = false),
    onPointerCancel: (_) => setState(() => pressed = false),
    child: AnimatedScale(
      scale: pressed && !reduceMotion(context) ? .97 : 1,
      duration: reduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      child: widget.child,
    ),
  );
}
