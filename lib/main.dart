import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  // Riverpod 3 retries failed providers by default; errors should surface
  // at once instead (spec 003 research R7).
  runApp(ProviderScope(retry: (_, _) => null, child: const HealthBenchApp()));
}
