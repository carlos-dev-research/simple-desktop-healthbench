// The app shell: name and version always visible, two views, the notes, and
// no overflow at the minimum window size in light and dark (spec 001 FR-002,
// FR-010, FR-011; spec 003 FR-001, FR-016).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/app.dart';
import 'package:healthbench/core/app_info.dart';
import 'package:healthbench/ui/state/providers.dart';

import '../support/fixtures.dart';

void main() {
  const minimumSize = Size(960, 640);

  Future<void> pumpApp(WidgetTester tester, Brightness brightness) async {
    final dir = tempDir(addTearDown);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = minimumSize;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageDirectoryProvider.overrideWith((ref) async => dir.path),
        ],
        retry: (_, _) => null,
        child: const HealthBenchApp(),
      ),
    );
    await tester.pump();
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'Evals, small version and notes at the minimum size (${brightness.name})',
      (tester) async {
        await pumpApp(tester, brightness);
        expect(find.text('Evals'), findsOneWidget);
        expect(find.text('v$appVersion'), findsOneWidget);
        expect(find.textContaining('not medical advice'), findsOneWidget);
        expect(
          Theme.of(tester.element(find.text('Evals'))).brightness,
          brightness,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('New run'));
        await tester.pump();
        expect(find.text('New evaluation run'), findsOneWidget);
        expect(find.textContaining('not medical advice'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('window title is the app name', (tester) async {
    await pumpApp(tester, Brightness.light);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, appName);
  });

  testWidgets('switching between Runs and New run', (tester) async {
    await pumpApp(tester, Brightness.light);
    expect(find.text('New evaluation run'), findsNothing);
    await tester.tap(find.text('New run'));
    await tester.pump();
    expect(find.text('New evaluation run'), findsOneWidget);
    await tester.tap(find.text('Runs'));
    await tester.pump();
    expect(find.text('New evaluation run'), findsNothing);
  });
}
