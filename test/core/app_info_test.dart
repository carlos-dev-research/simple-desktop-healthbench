// T-core (spec 001 FR-002, FR-009).
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/app_info.dart';

void main() {
  test('appName is the display name', () {
    expect(appName, 'HealthBench Evals');
  });

  test('appVersion is a semantic version', () {
    expect(appVersion, matches(RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$')));
  });
}
