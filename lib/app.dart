import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/repository.dart';
import 'ui/home_shell.dart';
import 'ui/onboarding.dart';
import 'ui/theme.dart';

class VpnLedgerApp extends StatefulWidget {
  const VpnLedgerApp({super.key});

  @override
  State<VpnLedgerApp> createState() => _VpnLedgerAppState();
}

class _VpnLedgerAppState extends State<VpnLedgerApp> {
  late final AppRepository _repo;
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _repo = AppRepository();
    _initialization = _repo.init();
  }

  @override
  void dispose() {
    _repo.dispose();
    super.dispose();
  }

  void _retryInitialization() {
    setState(() => _initialization = _repo.init());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _materialApp(home: const _StartupLoading());
        }

        if (snapshot.hasError) {
          return _materialApp(
            home: _StartupError(
              error: snapshot.error,
              onRetry: _retryInitialization,
            ),
          );
        }

        return ChangeNotifierProvider<AppRepository>.value(
          value: _repo,
          child: Consumer<AppRepository>(
            builder: (context, repo, _) {
              final settings = repo.settings;
              final themeMode = switch (settings.themeMode) {
                'dark' => ThemeMode.dark,
                'light' => ThemeMode.light,
                _ => ThemeMode.system,
              };

              return _materialApp(
                themeMode: themeMode,
                home: settings.setupDone
                    ? const HomeShell()
                    : const OnboardingPage(),
              );
            },
          ),
        );
      },
    );
  }

  MaterialApp _materialApp({
    required Widget home,
    ThemeMode themeMode = ThemeMode.system,
  }) =>
      MaterialApp(
        title: 'دفتر وی‌پی‌ان',
        debugShowCheckedModeBanner: false,
        locale: const Locale('fa', 'IR'),
        supportedLocales: const [Locale('fa', 'IR'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: home,
      );
}

class _StartupLoading extends StatelessWidget {
  const _StartupLoading();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'در حال آماده‌سازی برنامه…',
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      );
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 42),
                  const SizedBox(height: 12),
                  const Text(
                    'راه‌اندازی برنامه انجام نشد',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'پایگاه داده‌ی محلی باز نشد. دوباره تلاش کنید.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$error',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('تلاش دوباره'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
