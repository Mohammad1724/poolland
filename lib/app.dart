import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/repository.dart';
import 'ui/home_shell.dart';
import 'ui/onboarding.dart';
import 'ui/theme.dart';

class VpnLedgerApp extends StatelessWidget {
  const VpnLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppRepository>(
      create: (_) => AppRepository(),
      child: Consumer<AppRepository>(
        builder: (context, repo, _) {
          final s = repo.settings;
          return MaterialApp(
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
            themeMode: switch (s.themeMode) {
              'dark' => ThemeMode.dark,
              'light' => ThemeMode.light,
              _ => ThemeMode.system,
            },
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            ),
            home: s.setupDone ? const HomeShell() : const OnboardingPage(),
          );
        },
      ),
    );
  }
}
