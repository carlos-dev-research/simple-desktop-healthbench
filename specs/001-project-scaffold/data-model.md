# Data model: 001 project scaffold

This feature has no domain entities (spec: *Key entities: none*).

The only shared values are two constants in `lib/core/app_info.dart`:

| Name | Value | Rule |
|---|---|---|
| `appName` | `'HealthBench Evals'` | Must match the native display names (contract rule PR-8) |
| `appVersion` | `'0.1.0'` | Must equal `pubspec.yaml` `version:` without the `+build` part (contract rule PR-2) |
