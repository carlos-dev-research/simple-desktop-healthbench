// Single entry point for the integration tests. On desktop, each
// integration_test/*_test.dart file relaunches the app, and a second launch
// in the same `flutter test integration_test` session fails to attach on
// macOS. So the tests live in plain files, run here in one app launch.
import 'package:integration_test/integration_test.dart';

import 'launch.dart' as launch;
import 'network.dart' as network;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  launch.main();
  network.main();
}
