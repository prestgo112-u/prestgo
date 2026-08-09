// T050 — Réglages publics : valeurs du serveur prioritaires, repli si l'appel
// échoue (porte G3).
//
// Voir contracts/settings-and-limits.md §1. Les valeurs de repli ne sont **jamais**
// la source de vérité une fois la route jointe : une modification faite au
// back-office doit ressortir au prochain démarrage.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/envelope_interceptor.dart';
import 'package:prestgo_mobile/core/settings/public_settings.dart';
import 'package:prestgo_mobile/core/settings/settings_repository.dart';

import '../support/recording_adapter.dart';

SettingsRepository buildRepository(
  (int, Object?) Function(RequestOptions, int) respond,
) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://x.test/api/v1'))
    ..httpClientAdapter = RecordingAdapter(respond)
    ..interceptors.add(const EnvelopeInterceptor());
  return SettingsRepository(ApiClient(dio));
}

void main() {
  group('Décodage', () {
    test('les six clés du service sont lues', () async {
      final SettingsRepository repository = buildRepository(
        (RequestOptions o, int _) => (
          200,
          <String, Object?>{
            'success': true,
            'data': <String, Object?>{
              'missionMinLeadTimeMinutes': 90,
              'missionCancellationNoticeHours': 12,
              'missionStartWindowMinutes': 45,
              'missionPendingExpiryHours': 48,
              'missionAutoCloseDays': 3,
              'reviewsWindowDays': 30,
            },
          },
        ),
      );

      final PublicSettings settings = await repository.fetch();

      expect(settings.missionMinLeadTimeMinutes, 90);
      expect(settings.missionCancellationNoticeHours, 12);
      expect(settings.missionStartWindowMinutes, 45);
      expect(settings.missionPendingExpiryHours, 48);
      expect(settings.missionAutoCloseDays, 3);
      expect(settings.reviewsWindowDays, 30);
      expect(settings.isFallback, isFalse);
    });

    test(
      'les valeurs du serveur priment sur les constantes de repli',
      () async {
        final SettingsRepository repository = buildRepository(
          (RequestOptions o, int _) => (
            200,
            <String, Object?>{
              'success': true,
              'data': <String, Object?>{'missionMinLeadTimeMinutes': 15},
            },
          ),
        );

        final PublicSettings settings = await repository.fetch();

        expect(settings.missionMinLeadTimeMinutes, 15);
        expect(
          settings.missionMinLeadTimeMinutes,
          isNot(PublicSettings.fallback.missionMinLeadTimeMinutes),
        );
      },
    );

    test(
      'une clé absente retombe sur son repli, sans perdre les autres',
      () async {
        final SettingsRepository repository = buildRepository(
          (RequestOptions o, int _) => (
            200,
            <String, Object?>{
              'success': true,
              'data': <String, Object?>{'reviewsWindowDays': 21},
            },
          ),
        );

        final PublicSettings settings = await repository.fetch();

        expect(settings.reviewsWindowDays, 21);
        expect(
          settings.missionStartWindowMinutes,
          PublicSettings.fallback.missionStartWindowMinutes,
        );
      },
    );

    test('une valeur transmise en chaîne est acceptée', () {
      final PublicSettings settings = PublicSettings.fromJson(
        const <String, Object?>{'missionMinLeadTimeMinutes': '120'},
      );
      expect(settings.missionMinLeadTimeMinutes, 120);
    });
  });

  group('Repli', () {
    test('les valeurs de repli sont celles du contrat', () {
      const PublicSettings fallback = PublicSettings.fallback;
      expect(fallback.missionMinLeadTimeMinutes, 60);
      expect(fallback.missionCancellationNoticeHours, 6);
      expect(fallback.missionStartWindowMinutes, 120);
      expect(fallback.missionPendingExpiryHours, 24);
      expect(fallback.missionAutoCloseDays, 7);
      expect(fallback.reviewsWindowDays, 14);
      expect(fallback.isFallback, isTrue);
    });

    test('un échec réseau ne bloque pas le démarrage', () async {
      final SettingsRepository repository = buildRepository(
        (RequestOptions o, int _) =>
            throw const SocketException('réseau indisponible'),
      );

      final PublicSettings settings = await repository.fetch();

      expect(settings, PublicSettings.fallback);
      expect(settings.isFallback, isTrue);
    });

    test('un 500 retombe sur le repli', () async {
      final SettingsRepository repository = buildRepository(
        (RequestOptions o, int _) => (
          500,
          <String, Object?>{'success': false, 'message': 'Erreur interne'},
        ),
      );

      expect(await repository.fetch(), PublicSettings.fallback);
    });

    test('une réponse sans contenu retombe sur le repli', () async {
      final SettingsRepository repository = buildRepository(
        (RequestOptions o, int _) => (200, <String, Object?>{'success': true}),
      );

      expect(await repository.fetch(), PublicSettings.fallback);
    });
  });

  group('Durées dérivées', () {
    test('sont cohérentes avec les valeurs brutes', () {
      const PublicSettings settings = PublicSettings(
        missionMinLeadTimeMinutes: 90,
        missionCancellationNoticeHours: 12,
        missionStartWindowMinutes: 45,
        missionPendingExpiryHours: 48,
        missionAutoCloseDays: 3,
        reviewsWindowDays: 30,
        isFallback: false,
      );

      expect(settings.minLeadTime, const Duration(minutes: 90));
      expect(settings.cancellationNotice, const Duration(hours: 12));
      expect(settings.startWindow, const Duration(minutes: 45));
      expect(settings.pendingExpiry, const Duration(hours: 48));
      expect(settings.autoCloseDelay, const Duration(days: 3));
      expect(settings.reviewsWindow, const Duration(days: 30));
    });
  });

  test('la route appelée est bien /settings/public', () async {
    final List<String> paths = <String>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://x.test/api/v1'))
      ..httpClientAdapter = RecordingAdapter((RequestOptions o, int _) {
        paths.add(o.path);
        return (
          200,
          <String, Object?>{'success': true, 'data': <String, Object?>{}},
        );
      })
      ..interceptors.add(const EnvelopeInterceptor());

    await SettingsRepository(ApiClient(dio)).fetch();

    expect(paths, <String>['/settings/public']);
    // Le préfixe de version est dans la base, jamais dans le chemin.
    expect(paths.single, isNot(contains('/api/v1')));
  });
}
