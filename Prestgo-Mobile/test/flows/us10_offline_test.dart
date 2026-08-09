// Point d'entrée sans appareil du parcours US10 (T238).
//
// Le portier réseau est substitué (aucun greffon de connectivité en test) et
// le service simulé se coupe sur commande ; bannière, verrou d'écriture,
// cache et rafraîchissement à la reconnexion sont le code livré. Ces
// scénarios tournent donc tels quels sous `flutter test`, et sont vérifiés à
// chaque intégration.

import '../../integration_test/flows/us10_offline.dart';

void main() => runUs10Scenarios();
