// Point d'entrée.
//
// Toute la séquence de démarrage vit dans `bootstrap.dart` : ce fichier ne fait que
// l'appeler, ce qui permet aux tests d'intégration de rejouer l'amorçage sans passer
// par `main`.

import 'package:prestgo_mobile/bootstrap.dart';

Future<void> main() => bootstrap();
