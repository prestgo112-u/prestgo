// Point d'entrée « sur appareil » du parcours US8.
//
// Les scénarios eux-mêmes sont dans `us8_provider_offer.dart` : ils sont aussi
// déroulés sans appareil par `test/flows/us8_provider_offer_test.dart`, ce qui
// les place dans le périmètre de `flutter test` — donc de l'intégration continue.
//
// Exécution : `flutter test integration_test/flows/us8_provider_offer_test.dart -d <appareil>`.

import 'package:integration_test/integration_test.dart';

import 'us8_provider_offer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  runUs8Scenarios();
}
