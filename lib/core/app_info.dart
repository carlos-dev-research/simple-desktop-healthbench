/// Application identity shared by the core and the UI.
///
/// Pure Dart: nothing under `lib/core/` may import Flutter (project rule PR-1).
library;

/// Display name, also used as the window title on every OS (spec 001 FR-002).
const String appName = 'HealthBench Evals';

/// Must equal the `version:` in pubspec.yaml without the `+build` part
/// (project rule PR-2 checks this).
const String appVersion = '0.1.0';
