// Racine de l'application.
//
// Le `ProviderScope` est remonté avec une clé neuve à chaque incrément du signal de
// session : c'est la recréation du conteneur d'état exigée par SC-012. Tout provider
// encore vivant est abandonné avec l'ancien conteneur, ce qui garantit qu'aucune
// donnée du compte précédent ne reste consultable.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` n'est pas exporté par l'entrée principale de flutter_riverpod 3.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/push_driver.dart';
import 'package:prestgo_mobile/app/router.dart';
import 'package:prestgo_mobile/app/theme/app_theme.dart';
import 'package:prestgo_mobile/core/connectivity/offline_banner.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/l10n/generated/app_localizations.dart';

/// Enveloppe le `ProviderScope` et le recrée sur demande.
class PrestgoApp extends StatelessWidget {
  const PrestgoApp({super.key, this.overrides = const <Override>[]});

  /// Surcharges de providers posées par l'amorçage (environnement, réglages
  /// publics) et par les tests.
  final List<Override> overrides;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: sessionResetSignal,
    builder: (BuildContext context, int generation, Widget? child) =>
        ProviderScope(
          key: ValueKey<int>(generation),
          overrides: overrides,
          child: const _PrestgoMaterialApp(),
        ),
  );
}

class _PrestgoMaterialApp extends ConsumerWidget {
  const _PrestgoMaterialApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(goRouterProvider);

    // Le pilote push vit au-dessus du routeur : enregistrement de l'appareil à
    // chaque connexion, points d'entrée, bannière au premier plan (T199-T203).
    return PushDriver(
      child: MaterialApp.router(
        routerConfig: router,
        title: 'PRESTGO',
        debugShowCheckedModeBanner: false,
        // La bannière hors ligne coiffe TOUS les écrans — c'est ce qui la
        // rend permanente (US10, T233).
        builder: (BuildContext context, Widget? child) =>
            GlobalOfflineBanner(child: child ?? const SizedBox.shrink()),
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        // Locale unique : les messages métier viennent du service, déjà en
        // français (FR-088). Seuls les libellés de l'application sont traduits.
        locale: const Locale(AppFormats.languageCode),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }
}
