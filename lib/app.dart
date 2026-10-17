import 'package:flutter/material.dart';

import 'core/app_info.dart';
import 'ui/home_screen.dart';

/// Root widget: Material 3 in light and dark, following the system
/// appearance (spec 001 FR-010).
class HealthBenchApp extends StatelessWidget {
  const HealthBenchApp({super.key});

  static const Color _seedColor = Colors.teal;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
