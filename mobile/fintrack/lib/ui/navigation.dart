import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

void navigateTo(BuildContext context, String destination) {
  final router = GoRouter.of(context);
  final current = GoRouterState.of(context).uri;
  final target = Uri.parse(destination);
  if (current.path == target.path &&
      (target.query.isEmpty || current == target)) {
    return;
  }
  if (destination == '/') {
    while (router.canPop()) {
      router.pop();
    }
    router.go('/');
  } else {
    router.push(destination);
  }
}

void navigateBack(BuildContext context) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
  } else {
    router.go('/');
  }
}
