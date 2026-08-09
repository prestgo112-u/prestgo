// Point d'entrée sur appareil du parcours US4 (T162).
//
// Les scénarios eux-mêmes vivent dans us4_provider_onboarding.dart, partagés
// avec le point d'entrée sans appareil de `test/flows/`.

import 'package:integration_test/integration_test.dart';

import 'us4_provider_onboarding.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  runUs4Scenarios();
}
