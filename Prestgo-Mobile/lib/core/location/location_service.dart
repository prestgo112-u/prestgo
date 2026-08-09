// Position de l'appareil.
//
// Deux écrans en dépendent, pour des raisons différentes : la recherche s'en sert
// pour trier par distance (FR-023), le formulaire d'adresse pour poser un marqueur
// (FR-019). Les deux doivent fonctionner **sans** elle : un refus de permission n'est
// pas une erreur, c'est un choix de l'utilisateur.
//
// D'où la forme du résultat : jamais d'exception, toujours un [LocationResult] qui
// dit ce qui s'est passé et propose un repli. Le repli est le centre d'Abidjan —
// l'utilisateur déplace ensuite le marqueur, ce qui est de toute façon le geste
// attendu.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Point géographique, sans dépendance à une bibliothèque de carte.
class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() =>
      'GeoPoint(${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)})';
}

/// Repli employé quand la position réelle est indisponible.
///
/// Le Plateau, centre d'Abidjan : la plateforme n'opère qu'en Côte d'Ivoire au
/// lancement, et un marqueur posé au milieu de l'océan ne serait déplaçable qu'au
/// prix d'une navigation absurde.
const GeoPoint kAbidjanCenter = GeoPoint(latitude: 5.32, longitude: -4.02);

/// Ce qui s'est passé lors de la demande de position.
enum LocationOutcome {
  granted,

  /// Refus ponctuel : reproposer plus tard a du sens.
  denied,

  /// Refus définitif : seuls les réglages du système peuvent le lever.
  deniedForever,

  /// Localisation désactivée sur l'appareil, indépendamment de l'application.
  serviceDisabled,

  /// Permission accordée mais position introuvable (intérieur, délai dépassé).
  unavailable,
}

class LocationResult {
  const LocationResult({required this.outcome, this.point});

  final LocationOutcome outcome;

  /// Position réelle, ou `null`. L'appelant décide de retomber sur
  /// [kAbidjanCenter] — ce qui a du sens pour un marqueur, mais pas pour un tri par
  /// distance, qui doit alors rester indisponible.
  final GeoPoint? point;

  bool get isGranted => outcome == LocationOutcome.granted && point != null;

  /// Message expliquant pourquoi la position manque, ou `null` si elle est là.
  String? get explanation => switch (outcome) {
    LocationOutcome.granted => null,
    LocationOutcome.denied =>
      'Autorisez la localisation pour trier par distance.',
    LocationOutcome.deniedForever =>
      'La localisation est refusée. Activez-la dans les réglages de votre '
          'téléphone.',
    LocationOutcome.serviceDisabled =>
      'La localisation est désactivée sur votre téléphone.',
    LocationOutcome.unavailable =>
      'Position introuvable pour le moment. Réessayez à l’extérieur.',
  };
}

class LocationService {
  const LocationService();

  /// Demande la position courante.
  ///
  /// Ne lève jamais : toute défaillance devient un [LocationOutcome].
  Future<LocationResult> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(outcome: LocationOutcome.serviceDisabled);
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult(outcome: LocationOutcome.deniedForever);
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult(outcome: LocationOutcome.denied);
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          // Une position au mètre près n'apporte rien à un rayon de 10 km, et
          // coûterait plusieurs secondes d'attente et de batterie.
          timeLimit: Duration(seconds: 10),
        ),
      );
      return LocationResult(
        outcome: LocationOutcome.granted,
        point: GeoPoint(
          latitude: position.latitude,
          longitude: position.longitude,
        ),
      );
    } on Object {
      // Délai dépassé, capteur indisponible, plateforme sans localisation : du
      // point de vue de l'écran, c'est la même chose.
      return const LocationResult(outcome: LocationOutcome.unavailable);
    }
  }
}

final Provider<LocationService> locationServiceProvider =
    Provider<LocationService>((Ref ref) => const LocationService());
