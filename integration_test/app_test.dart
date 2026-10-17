// T-launch (spec 001 FR-001, FR-009): the real app starts on the desktop
// device and shows its name and version.
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/app_info.dart';
import 'package:healthbench/main.dart' as app;
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app launches and shows its name and version', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    expect(find.text(appName), findsOneWidget);
    expect(find.text('Version $appVersion'), findsOneWidget);
  });
}
