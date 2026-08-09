// Point d'entrée sans appareil du parcours US8 (T218).
//
// Le transport HTTP, la base locale, le stockage sécurisé et le sélecteur de
// fichier sont substitués ; tout le reste — routeur, gardien, dépôts, écrans —
// est le code livré. Ces scénarios tournent donc tels quels sous
// `flutter test`, et sont vérifiés à chaque intégration.

import '../../integration_test/flows/us8_provider_offer.dart';

void main() => runUs8Scenarios();
