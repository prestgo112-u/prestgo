// Charge utile de notification — réexport du modèle du socle (T195).
//
// Le modèle vit dans `core/push/` : la fonction de routage du socle en dépend, et
// le socle n'importe aucune fonctionnalité (même mouvement que le catalogue,
// réexporté par `features/search/domain/catalog.dart` depuis `lib/shared/`).

export 'package:prestgo_mobile/core/push/notification_payload.dart';
