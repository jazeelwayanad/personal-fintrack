import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'data/api.dart';
import 'data/ledger.dart';
import 'ui/screens.dart';

final ledgerProvider = ChangeNotifierProvider<Ledger>(
  (ref) => Ledger(CloudApi())..initialize(),
);
final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FinTrackApp()));
}

final router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) => NoTransitionPage<void>(
        key: state.pageKey,
        child: const FinScreen(screen: 'home'),
      ),
    ),
    GoRoute(
      path: '/:screen',
      pageBuilder: (context, state) => NoTransitionPage<void>(
        key: state.pageKey,
        child: FinScreen(
          screen: state.pathParameters['screen'] ?? 'home',
          occurrenceId: state.uri.queryParameters['occurrence'],
        ),
      ),
    ),
  ],
);

class FinTrackApp extends ConsumerWidget {
  const FinTrackApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ThemeData theme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff7c3aed),
        brightness: brightness,
      ),
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xfff8f7fc)
          : const Color(0xff111018),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      cardTheme: const CardThemeData(margin: EdgeInsets.zero, elevation: 0),
    );
    return MaterialApp.router(
      title: 'FinTrack',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: ref.watch(themeProvider),
      routerConfig: router,
    );
  }
}
