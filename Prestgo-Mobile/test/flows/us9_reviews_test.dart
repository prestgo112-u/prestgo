// Point d'entrée sans appareil du parcours US9 (T229).
//
// Le transport HTTP, la base locale et le stockage sécurisé sont substitués ;
// tout le reste — routeur, gardien, dépôts, écrans — est le code livré. Ces
// scénarios tournent donc tels quels sous `flutter test`, et sont vérifiés à
// chaque intégration.

import '../../integration_test/flows/us9_reviews.dart';

void main() => runUs9Scenarios();
