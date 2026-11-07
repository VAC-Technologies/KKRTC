import 'package:flutter/material.dart';

import 'core/constants/app_strings.dart';
import 'core/storage/app_state_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/splash_screen.dart';

class KKRTCApp extends StatelessWidget {
  const KKRTCApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppStateStorage.themeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: AppStrings.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          home: const SplashScreen(),
        );
      },
    );
  }
}
