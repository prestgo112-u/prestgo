// Point d'entrée « sur appareil » du parcours US6.
//
// Les scénarios eux-mêmes sont dans `us6_messaging.dart` : ils sont aussi
// déroulés sans appareil par `test/flows/us6_messaging_test.dart`, ce qui
// les place dans le périmètre de `flutter test` — donc de l'intégration continue.
//
// Exécution : `flutter test integration_test/flows/us6_messaging_test.dart -d <appareil>`.

import 'package:integration_test/integration_test.dart';

import 'us6_messaging.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  runUs6Scenarios();
}
