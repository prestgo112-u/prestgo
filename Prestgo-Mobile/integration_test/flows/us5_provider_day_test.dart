// Point d'entrée sur appareil du parcours US5 (T177).
//
// Les scénarios eux-mêmes vivent dans us5_provider_day.dart, partagés avec le
// point d'entrée sans appareil de `test/flows/`.

import 'package:integration_test/integration_test.dart';

import 'us5_provider_day.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  runUs5Scenarios();
}
