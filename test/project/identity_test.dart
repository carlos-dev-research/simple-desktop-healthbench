// PR-7 and PR-8: one application identifier and one display name on every OS
// (spec 001 FR-002, FR-003). The identifier decides where user data lives, so
// it must never drift.
import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

const _appId = 'io.github.carlos-dev-research.healthbench';
const _displayName = 'HealthBench Evals';
// Windows derives the data folder from these, so they stay fixed even if the
// display name changes.
const _windowsCompany = 'io.github.carlos-dev-research';
const _windowsProduct = 'healthbench';

void main() {
  final macInfo = readRepoFile('macos/Runner/Configs/AppInfo.xcconfig');
  final linuxCmake = readRepoFile('linux/CMakeLists.txt');
  final linuxApp = readRepoFile('linux/runner/my_application.cc');
  final windowsRc = readRepoFile('windows/runner/Runner.rc');
  final windowsMain = readRepoFile('windows/runner/main.cpp');

  group('PR-7 application identifier', () {
    test('macOS bundle identifier', () {
      expect(macInfo, contains('PRODUCT_BUNDLE_IDENTIFIER = $_appId\n'));
    });

    test('Linux application ID (hyphens kept)', () {
      expect(linuxCmake, contains('set(APPLICATION_ID "$_appId")'));
    });

    test('Windows company and product name', () {
      expect(
        windowsRc,
        contains('VALUE "CompanyName", "$_windowsCompany" "\\0"'),
      );
      expect(
        windowsRc,
        contains('VALUE "ProductName", "$_windowsProduct" "\\0"'),
      );
    });
  });

  group('PR-8 display name "$_displayName"', () {
    test('macOS product name', () {
      expect(macInfo, contains('PRODUCT_NAME = $_displayName\n'));
    });

    test('Windows window title and file description', () {
      expect(windowsMain, contains('window.Create(L"$_displayName"'));
      expect(
        windowsRc,
        contains('VALUE "FileDescription", "$_displayName" "\\0"'),
      );
    });

    test('Linux header bar and window title', () {
      expect(
        linuxApp,
        contains('gtk_header_bar_set_title(header_bar, "$_displayName")'),
      );
      expect(
        linuxApp,
        contains('gtk_window_set_title(window, "$_displayName")'),
      );
    });
  });
}
