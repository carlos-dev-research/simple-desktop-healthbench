import 'package:flutter/material.dart';

import '../core/app_info.dart';

/// Placeholder home screen: the app's name and version (spec 001 FR-002).
/// Evaluation features replace its content in later features.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                appName,
                style: textTheme.displaySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text('Version $appVersion', style: textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
