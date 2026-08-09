// Providers transverses du socle, hors réseau et hors session.
//
// Ils sont regroupés ici pour qu'un écran n'ait qu'un seul import à faire pour
// atteindre les réglages, la connectivité, la remontée d'incident et l'envoi de
// fichier.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/config/app_environment.dart';
import 'package:prestgo_mobile/core/connectivity/offline_gate.dart';
import 'package:prestgo_mobile/core/error/error_reporter.dart';
import 'package:prestgo_mobile/core/files/file_upload_service.dart';
import 'package:prestgo_mobile/core/settings/public_settings.dart';
import 'package:prestgo_mobile/core/settings/settings_repository.dart';

final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>(
      (Ref ref) => SettingsRepository(ref.watch(apiClientProvider)),
    );

/// Les six réglages du service, lus **une fois** au démarrage.
///
/// L'amorçage remplace cette valeur par celle obtenue auprès du service (T041) ;
/// tant qu'il ne l'a pas fait, ce sont les valeurs de repli qui circulent. Aucun
/// écran ne recopie ces valeurs dans une constante (porte G3).
final Provider<PublicSettings> publicSettingsProvider =
    Provider<PublicSettings>((Ref ref) => PublicSettings.fallback);

final Provider<OfflineGate> offlineGateProvider = Provider<OfflineGate>(
  (Ref ref) => OfflineGate(),
);

/// Vrai tant qu'un transport réseau est disponible.
///
/// Alimente la bannière permanente et la désactivation des actions d'écriture.
final StreamProvider<bool> isOnlineProvider = StreamProvider<bool>((Ref ref) {
  final OfflineGate gate = ref.watch(offlineGateProvider);
  return gate.onlineChanges();
});

final Provider<ErrorReporter> errorReporterProvider = Provider<ErrorReporter>((
  Ref ref,
) {
  final AppEnvironment environment = ref.watch(appEnvironmentProvider);
  return ErrorReporter(enabled: environment.reportsIncidents);
});

final Provider<FileUploadService> fileUploadServiceProvider =
    Provider<FileUploadService>(
      (Ref ref) => FileUploadService(ref.watch(apiClientProvider)),
    );
