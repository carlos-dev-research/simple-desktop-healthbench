// T-home (spec 001 FR-002, FR-010, FR-011; US5).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/app.dart';
import 'package:healthbench/core/app_info.dart';
import 'package:healthbench/ui/home_screen.dart';

void main() {
  // The minimum window size (FR-011), in logical pixels.
  const minimumSize = Size(960, 640);

  Future<void> pumpAt(
    WidgetTester tester,
    Size size,
    Brightness brightness,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(const HealthBenchApp());
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'shows name and version at the minimum size (${brightness.name})',
      (tester) async {
        await pumpAt(tester, minimumSize, brightness);

        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.text(appName), findsOneWidget);
        expect(find.text('Version $appVersion'), findsOneWidget);
        // Layout overflow is reported as an exception and would fail the test.
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('follows the system appearance (${brightness.name})', (
      tester,
    ) async {
      await pumpAt(tester, minimumSize, brightness);

      final context = tester.element(find.byType(HomeScreen));
      expect(Theme.of(context).brightness, brightness);
    });
  }

  testWidgets('window title is the app name', (tester) async {
    await pumpAt(tester, minimumSize, Brightness.light);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, appName);
  });
}
