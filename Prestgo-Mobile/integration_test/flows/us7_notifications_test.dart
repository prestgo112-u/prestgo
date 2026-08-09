// Point d'entrée « sur appareil » du parcours US7.
//
// Les scénarios eux-mêmes sont dans `us7_notifications.dart` : ils sont aussi
// déroulés sans appareil par `test/flows/us7_notifications_test.dart`, ce qui
// les place dans le périmètre de `flutter test` — donc de l'intégration continue.
//
// Exécution : `flutter test integration_test/flows/us7_notifications_test.dart -d <appareil>`.

import 'package:integration_test/integration_test.dart';

import 'us7_notifications.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  runUs7Scenarios();
}
