// Séquence de démarrage.
//
// Ordre imposé par le contrat :
//   1. lire la configuration d'environnement ;
//   2. armer le rapport d'incident — **désactivé en `dev`** (R5) ;
//   3. lire les six réglages publics une seule fois, avec repli si l'appel échoue
//      (porte G3) ;
//   4. rendre l'application.
//
// La restauration de session (jetons → `GET /me` → aiguillage) se poursuit dans
// l'arbre de widgets, sur l'écran de démarrage : elle a besoin d'un conteneur
// durable, alors que celui de l'amorçage est libéré à l'étape 3.
//
// L'étape 3 n'est pas bloquante : `SettingsRepository` retombe sur ses valeurs de
// repli, et l'application démarre même hors ligne.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` n'est pas exporté par l'entrée principale de flutter_riverpod 3.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:prestgo_mobile/app/app.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/config/app_environment.dart';
import 'package:prestgo_mobile/core/core_providers.dart';
import 'package:prestgo_mobile/core/error/sentry_bootstrap.dart';
import 'package:prestgo_mobile/core/settings/public_settings.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final AppEnvironment environment = AppEnvironment.fromDefines();

  await runWithSentry(
    () async {
      // Conteneur temporaire : il sert à joindre les réglages avant que l'arbre de
      // widgets n'existe, puis il est libéré. Le conteneur de l'application est créé
      // par `PrestgoApp`, avec les surcharges obtenues ici.
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          appEnvironmentProvider.overrideWithValue(environment),
        ],
      );

      PublicSettings settings;
      try {
        settings = await container.read(settingsRepositoryProvider).fetch();
      } finally {
        container.dispose();
      }

      runApp(
        PrestgoApp(
          overrides: <Override>[
            appEnvironmentProvider.overrideWithValue(environment),
            publicSettingsProvider.overrideWithValue(settings),
          ],
        ),
      );
    },
    environment: environment.name.name,
    enabledByDefine: environment.sentryEnabled,
    dsn: environment.sentryDsn,
  );
}
