import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'data/api.dart';
import 'data/ledger.dart';
import 'ui/screens.dart';
import 'ui/motion.dart';

final ledgerProvider = ChangeNotifierProvider<Ledger>(
  (ref) => Ledger(CloudApi())..initialize(),
);
final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);
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
      routes: [
        for (final screen in [
          'plans',
          'transactions',
          'reports',
          'settings',
          'account',
        ])
          GoRoute(
            path: screen,
            pageBuilder: (context, state) => finPage(
              state.pageKey,
              FinScreen(
                screen: screen,
                occurrenceId: state.uri.queryParameters['occurrence'],
              ),
            ),
          ),
      ],
    ),
  ],
);

class FinTrackApp extends ConsumerWidget {
  const FinTrackApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ThemeData theme(Brightness brightness) {
      final dark = brightness == Brightness.dark;
      final colors =
          ColorScheme.fromSeed(
            seedColor: const Color(0xff073b3b),
            brightness: brightness,
          ).copyWith(
            primary: dark ? const Color(0xffbbddc4) : const Color(0xff073b3b),
            onPrimary: dark ? const Color(0xff171b19) : Colors.white,
            primaryContainer: dark
                ? const Color(0xff34483e)
                : const Color(0xffe6f4e9),
            onPrimaryContainer: dark ? Colors.white : const Color(0xff17372a),
            surface: dark ? const Color(0xff1c3535) : Colors.white,
            surfaceContainerLow: dark
                ? const Color(0xff253c3c)
                : const Color(0xfff0f2e9),
            surfaceContainerHighest: dark
                ? const Color(0xff253c3c)
                : const Color(0xfff0f2e9),
            onSurface: dark ? const Color(0xffedf4ef) : const Color(0xff073b3b),
            onSurfaceVariant: dark
                ? const Color(0xffafc1b5)
                : const Color(0xff5c6d6a),
          );
      return ThemeData(
        useMaterial3: true,
        fontFamily: 'Outfit',
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 14, height: 1.45),
          bodySmall: TextStyle(fontSize: 12, height: 1.4),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          headlineMedium: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            letterSpacing: -1.2,
          ),
        ),
        splashFactory: NoSplash.splashFactory,
        dialogTheme: DialogThemeData(
          backgroundColor: colors.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        chipTheme: ChipThemeData(
          side: BorderSide.none,
          showCheckmark: false,
          selectedColor: colors.primary,
          backgroundColor: colors.surfaceContainerLow,
          shape: const StadiumBorder(),
        ),
        colorScheme: colors,
        scaffoldBackgroundColor: dark
            ? const Color(0xff142929)
            : const Color(0xfff7f7f0),
        appBarTheme: AppBarTheme(
          backgroundColor: dark
              ? const Color(0xff142929)
              : const Color(0xfff7f7f0),
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: dark ? const Color(0xff253c3c) : const Color(0xfff0f2e9),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(100),
            borderSide: BorderSide(
              color: colors.primary.withValues(alpha: .5),
              width: 2,
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(100),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(100),
            borderSide: BorderSide.none,
          ),
        ),
        cardTheme: CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: dark ? const Color(0xff1c3535) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(100),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: dark ? const Color(0xff1c3535) : Colors.white,
          indicatorColor: colors.primary,
          elevation: 0,
          height: 74,
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
        ),
      );
    }

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
