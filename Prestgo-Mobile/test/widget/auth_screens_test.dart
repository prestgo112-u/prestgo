// T081 — Écrans clés du parcours de compte : connexion, code, réinitialisation.
//
// Ce que ces tests protègent, écran par écran :
//   • **connexion** — le message technique du service ne fuit jamais à l'écran, un
//     compte non actif reçoit une issue, et un débit dépassé ferme le bouton au lieu
//     de rejouer ;
//   • **code** — l'envoi part tout seul à l'arrivée, le renvoi est bridé à un par
//     minute, et la saisie se ferme quand le code est brûlé ;
//   • **réinitialisation** — le jeton se colle, et l'écran annonce que toutes les
//     sessions vont tomber.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/features/auth/data/dto/otp_dto.dart';
import 'package:prestgo_mobile/features/auth/presentation/login/login_screen.dart';
import 'package:prestgo_mobile/features/auth/presentation/password/reset_password_screen.dart';
import 'package:prestgo_mobile/features/auth/presentation/verify/verify_screen.dart';

import '../support/fixtures.dart';
import '../support/screen_harness.dart';

ScreenHarness harnessFor(String file, String caseName) {
  final (int status, Map<String, Object?> body) = fixture(file, caseName);
  return ScreenHarness((RequestOptions options, int index) => (status, body));
}

Future<void> fillLogin(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Adresse email'),
    'client.demo@prestgo.test',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Mot de passe'),
    'prestgo123!',
  );
}

void main() {
  group('Connexion', () {
    testWidgets(
      'porte d’entrée de l’application, elle offre ses deux sorties',
      (WidgetTester tester) async {
        final ScreenHarness harness = harnessFor(
          'auth/login',
          'invalidCredentials',
        );
        await harness.pump(tester, const LoginScreen());

        // Cet écran est le premier que voit un visiteur. Il doit donc porter les
        // deux issues : créer un compte, et consulter sans en avoir un — la
        // consultation libre de spec.md §89-90 n'est plus le point d'entrée, elle
        // est une sortie offerte depuis ici.
        expect(find.text('Créer un compte'), findsOneWidget);
        expect(find.text('Découvrir sans compte'), findsOneWidget);

        await harness.dispose(tester);
      },
    );

    testWidgets(
      'un refus d’identifiants n’affiche jamais le message technique',
      (WidgetTester tester) async {
        final ScreenHarness harness = harnessFor(
          'auth/login',
          'invalidCredentials',
        );
        await harness.pump(tester, const LoginScreen());

        await fillLogin(tester);
        await tester.tap(find.text('Se connecter'));
        await tester.pumpAndSettle();

        expect(
          find.text(ApiFallbackMessages.invalidCredentials),
          findsOneWidget,
        );
        expect(find.text('Invalid credentials'), findsNothing);

        await harness.dispose(tester);
      },
    );

    testWidgets('un compte non actif reçoit une issue, pas un reproche', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = harnessFor(
        'auth/login',
        'accountNotActive',
      );
      await harness.pump(tester, const LoginScreen());

      await fillLogin(tester);
      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();

      expect(find.text(ApiFallbackMessages.accountNotActive), findsOneWidget);
      expect(
        find.text('Vérifier mon compte avec un code'),
        findsOneWidget,
        reason:
            'sans cette sortie, l’utilisateur est dans une impasse (FR-006)',
      );

      await harness.dispose(tester);
    });

    testWidgets('un débit dépassé ferme le bouton et ne rejoue rien', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = harnessFor('auth/login', 'rateLimited');
      await harness.pump(tester, const LoginScreen());

      await fillLogin(tester);
      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();

      expect(
        harness.adapter.countFor('/auth/login'),
        1,
        reason: 'rejouer un 429 ne ferait qu’aggraver le débit (porte G4)',
      );
      expect(find.textContaining('Réessayez dans'), findsOneWidget);

      final FilledButton button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Se connecter'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);

      await harness.dispose(tester);
    });

    testWidgets('un formulaire vide n’atteint pas le réseau', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = harnessFor(
        'auth/login',
        'invalidCredentials',
      );
      await harness.pump(tester, const LoginScreen());

      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();

      expect(harness.adapter.calls, isEmpty);
      expect(find.text('Renseignez votre adresse email.'), findsOneWidget);

      await harness.dispose(tester);
    });

    testWidgets('le mot de passe est masqué par défaut', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = harnessFor(
        'auth/login',
        'invalidCredentials',
      );
      await harness.pump(tester, const LoginScreen());

      expect(find.byTooltip('Afficher le mot de passe'), findsOneWidget);
      await tester.tap(find.byTooltip('Afficher le mot de passe'));
      await tester.pump();
      expect(find.byTooltip('Masquer le mot de passe'), findsOneWidget);

      await harness.dispose(tester);
    });
  });

  group('Code de vérification', () {
    Widget screen({
      VerificationOrigin origin = VerificationOrigin.activation,
    }) => VerifyScreen(
      target: '+2250700000042',
      purpose: OtpPurpose.phoneVerification,
      origin: origin,
    );

    testWidgets('le code part dès l’arrivée sur l’écran (FR-002)', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = harnessFor('auth/otp_send', 'sent');
      await harness.pump(tester, screen());
      await tester.pumpAndSettle();

      expect(harness.adapter.countFor('/auth/otp/send'), 1);
      expect(find.textContaining('Valable encore'), findsOneWidget);

      await harness.dispose(tester);
    });

    testWidgets('un contact modifié ne redemande pas de code', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = harnessFor('auth/otp_send', 'sent');
      await harness.pump(
        tester,
        screen(origin: VerificationOrigin.contactChange),
      );
      await tester.pumpAndSettle();

      expect(
        harness.adapter.calls,
        isEmpty,
        reason:
            '`PATCH /me` en a déjà envoyé un : en redemander invaliderait celui '
            'que l’utilisateur est peut-être en train de lire',
      );

      await harness.dispose(tester);
    });

    testWidgets('le renvoi est fermé pendant une minute', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = harnessFor('auth/otp_send', 'sent');
      await harness.pump(tester, screen());
      await tester.pumpAndSettle();

      expect(find.textContaining('Renvoyer le code dans'), findsOneWidget);
      final TextButton resend = tester.widget<TextButton>(
        find.ancestor(
          of: find.textContaining('Renvoyer le code'),
          matching: find.byType(TextButton),
        ),
      );
      expect(resend.onPressed, isNull);

      await harness.dispose(tester);
    });

    testWidgets('un code faux donne un message unique et laisse réessayer', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = ScreenHarness((
        RequestOptions options,
        int index,
      ) {
        if (options.path == '/auth/otp/send') {
          return fixture('auth/otp_send', 'sent');
        }
        return fixture('auth/otp_verify', 'invalidCode');
      });
      await harness.pump(tester, screen());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '000000');
      await tester.pumpAndSettle();

      expect(find.text('Code invalide ou expiré'), findsOneWidget);
      final TextField input = tester.widget<TextField>(find.byType(TextField));
      expect(input.enabled, isTrue, reason: 'il reste quatre essais');

      await harness.dispose(tester);
    });

    testWidgets('un code brûlé ferme la saisie', (WidgetTester tester) async {
      final ScreenHarness harness = ScreenHarness((
        RequestOptions options,
        int index,
      ) {
        if (options.path == '/auth/otp/send') {
          return fixture('auth/otp_send', 'sent');
        }
        return fixture('auth/otp_verify', 'tooManyAttempts');
      });
      await harness.pump(tester, screen());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '000000');
      await tester.pumpAndSettle();

      expect(
        find.text('Trop de tentatives sur ce code. Demandez-en un nouveau.'),
        findsOneWidget,
      );
      final TextField input = tester.widget<TextField>(find.byType(TextField));
      expect(input.enabled, isFalse);

      await harness.dispose(tester);
    });

    testWidgets('la saisie n’accepte que des chiffres, six au plus', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = harnessFor('auth/otp_send', 'sent');
      await harness.pump(tester, screen());
      await tester.pumpAndSettle();

      final TextField input = tester.widget<TextField>(find.byType(TextField));
      expect(input.maxLength, 6);
      expect(
        input.inputFormatters,
        contains(isA<FilteringTextInputFormatter>()),
      );

      await harness.dispose(tester);
    });
  });

  group('Réinitialisation du mot de passe', () {
    testWidgets('le jeton se colle depuis le presse-papiers', (
      WidgetTester tester,
    ) async {
      const String token =
          '4f2a8c1e6b9d3705f1a4c7e0b2d5f8a3c6e9b1d4f7092a5c8e0b3d6f9a2c5e81';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async => call.method == 'Clipboard.getData'
            ? <String, Object?>{'text': token}
            : null,
      );

      final ScreenHarness harness = harnessFor(
        'auth/password_reset',
        'resetDone',
      );
      await harness.pump(tester, const ResetPasswordScreen());

      await tester.tap(find.text('Coller'));
      await tester.pumpAndSettle();

      expect(find.text(token), findsOneWidget);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      await harness.dispose(tester);
    });

    testWidgets('un fragment de jeton n’atteint pas le réseau', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = harnessFor(
        'auth/password_reset',
        'resetDone',
      );
      await harness.pump(tester, const ResetPasswordScreen(token: 'abc'));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nouveau mot de passe'),
        'nouveau123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirmez le mot de passe'),
        'nouveau123',
      );
      await tester.tap(find.text('Changer mon mot de passe'));
      await tester.pumpAndSettle();

      expect(harness.adapter.calls, isEmpty);
      expect(find.text('Ce jeton semble incomplet.'), findsOneWidget);

      await harness.dispose(tester);
    });

    testWidgets('une confirmation différente est refusée localement', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = harnessFor(
        'auth/password_reset',
        'resetDone',
      );
      await harness.pump(tester, ResetPasswordScreen(token: 'a' * 64));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nouveau mot de passe'),
        'nouveau123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirmez le mot de passe'),
        'autre1234',
      );
      await tester.tap(find.text('Changer mon mot de passe'));
      await tester.pumpAndSettle();

      expect(harness.adapter.calls, isEmpty);
      expect(
        find.text('Les deux mots de passe ne correspondent pas.'),
        findsOneWidget,
      );

      await harness.dispose(tester);
    });

    testWidgets('l’écran annonce la fermeture de toutes les sessions', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = harnessFor(
        'auth/password_reset',
        'resetDone',
      );
      await harness.pump(tester, const ResetPasswordScreen());

      expect(
        find.text('Toutes vos sessions ouvertes seront fermées.'),
        findsOneWidget,
      );

      await harness.dispose(tester);
    });
  });
}
