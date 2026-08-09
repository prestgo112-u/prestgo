// Formulaire d'adresse, avec sélecteur de position (T107, FR-019).
//
// La position est **obligatoire** : c'est elle qui permet de vérifier qu'une adresse
// tombe dans la zone d'intervention d'un prestataire. Une adresse sans coordonnées
// rend la réservation impossible — le service la refuse, et cet écran ne doit pas
// permettre d'en créer une.
//
// D'où le sélecteur, en deux gestes complémentaires :
//   1. « Ma position » pose le marqueur là où se trouve l'appareil ;
//   2. la carte permet de l'**ajuster** — on saisit rarement l'adresse depuis le
//      seuil de la porte.
//
// Refus de permission : ce n'est pas une erreur. Le marqueur part du centre
// d'Abidjan et l'utilisateur le déplace, ce qui est de toute façon le geste attendu.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/location/location_service.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/core/validation/validators.dart';
import 'package:prestgo_mobile/features/profile/domain/address.dart';
import 'package:prestgo_mobile/features/profile/presentation/addresses_controller.dart';

class AddressFormScreen extends ConsumerStatefulWidget {
  const AddressFormScreen({this.address, super.key});

  /// `null` pour une création.
  final Address? address;

  @override
  ConsumerState<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends ConsumerState<AddressFormScreen>
    with FormSubmissionMixin<AddressFormScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final MapController _map = MapController();

  late final TextEditingController _label = TextEditingController(
    text: widget.address?.label ?? '',
  );
  late final TextEditingController _city = TextEditingController(
    text: widget.address?.city ?? 'Abidjan',
  );
  late final TextEditingController _commune = TextEditingController(
    text: widget.address?.commune ?? '',
  );
  late final TextEditingController _details = TextEditingController(
    text: widget.address?.details ?? '',
  );

  /// Position courante du marqueur.
  ///
  /// Part de l'adresse en cours de modification, ou du centre d'Abidjan pour une
  /// création — jamais d'un point nul, qui poserait le marqueur en plein océan.
  late GeoPoint _point = widget.address == null
      ? kAbidjanCenter
      : GeoPoint(
          latitude: widget.address!.latitude,
          longitude: widget.address!.longitude,
        );

  bool _locating = false;
  String? _locationNotice;

  bool get _isEditing => widget.address != null;

  @override
  void dispose() {
    _label.dispose();
    _city.dispose();
    _commune.dispose();
    _details.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _useCurrentPosition() async {
    setState(() {
      _locating = true;
      _locationNotice = null;
    });

    final LocationResult result = await ref
        .read(locationServiceProvider)
        .current();
    if (!mounted) {
      return;
    }

    final GeoPoint? point = result.point;
    setState(() {
      _locating = false;
      // Un refus n'est pas une erreur : on l'explique, et le marqueur reste
      // déplaçable à la main.
      _locationNotice = result.explanation;
      if (point != null) {
        _point = point;
      }
    });

    if (point != null) {
      _map.move(LatLng(point.latitude, point.longitude), 16);
    }
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) {
      return;
    }
    // Verrou de dernier recours : le marqueur a toujours une position, mais une
    // adresse sans coordonnées valides ne doit jamais partir.
    final String? invalidPosition = Validators.coordinates(
      latitude: _point.latitude,
      longitude: _point.longitude,
    );
    if (invalidPosition != null) {
      showFormError(invalidPosition);
      return;
    }

    final AddressDraft draft = AddressDraft(
      label: _label.text.trim(),
      city: _city.text.trim(),
      commune: _commune.text.trim().isEmpty ? null : _commune.text.trim(),
      details: _details.text.trim().isEmpty ? null : _details.text.trim(),
      latitude: _point.latitude,
      longitude: _point.longitude,
    );

    final Address? saved = await submit<Address>(
      () => _isEditing
          ? ref.read(addressesProvider.notifier).edit(widget.address!.id, draft)
          : ref.read(addressesProvider.notifier).create(draft),
    );

    if (saved == null || !mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isEditing ? 'Adresse mise à jour.' : 'Adresse ajoutée.'),
      ),
    );
    context.pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Modifier l’adresse' : 'Nouvelle adresse'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          if (formError case final String error) ...<Widget>[
            _Banner(message: error, isError: true),
            const SizedBox(height: 12),
          ],

          // --- Sélecteur de position ------------------------------------------
          Text('Où intervenir ?', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 220,
              child: FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: LatLng(_point.latitude, _point.longitude),
                  initialZoom: 15,
                  // Toucher la carte déplace le marqueur : c'est l'ajustement
                  // qu'exige FR-019.
                  onTap: (TapPosition tap, LatLng position) => setState(() {
                    _point = GeoPoint(
                      latitude: position.latitude,
                      longitude: position.longitude,
                    );
                  }),
                ),
                children: <Widget>[
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'ci.prestgo.mobile',
                  ),
                  MarkerLayer(
                    markers: <Marker>[
                      Marker(
                        point: LatLng(_point.latitude, _point.longitude),
                        child: Icon(
                          Icons.location_on,
                          size: 40,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _locating ? null : _useCurrentPosition,
                  icon: const Icon(Icons.my_location, size: 18),
                  label: Text(_locating ? 'Localisation…' : 'Ma position'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${_point.latitude.toStringAsFixed(5)}, '
                  '${_point.longitude.toStringAsFixed(5)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          if (_locationNotice case final String notice) ...<Widget>[
            const SizedBox(height: 4),
            Text(notice, style: theme.textTheme.bodySmall),
          ],
          Text(
            'Touchez la carte pour ajuster le point exact.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          const Divider(height: 32),

          // --- Champs ---------------------------------------------------------
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextFormField(
                  controller: _label,
                  maxLength: ContentLimits.addressLabelMaxLength,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Libellé',
                    hintText: 'Domicile, Bureau…',
                    counterText: '',
                    errorText: fieldErrors['label'],
                  ),
                  validator: (String? value) => (value ?? '').trim().isEmpty
                      ? 'Donnez un nom à cette adresse.'
                      : null,
                  onChanged: (_) => clearFieldError('label'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _city,
                  maxLength: ContentLimits.addressCityMaxLength,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Ville',
                    counterText: '',
                    errorText: fieldErrors['city'],
                  ),
                  validator: (String? value) => (value ?? '').trim().isEmpty
                      ? 'Indiquez la ville.'
                      : null,
                  onChanged: (_) => clearFieldError('city'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _commune,
                  maxLength: ContentLimits.addressCommuneMaxLength,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Commune (facultatif)',
                    counterText: '',
                    errorText: fieldErrors['commune'],
                  ),
                  onChanged: (_) => clearFieldError('commune'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _details,
                  maxLength: ContentLimits.addressDetailsMaxLength,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Précisions (facultatif)',
                    hintText: 'Étage, portail, point de repère…',
                    errorText: fieldErrors['details'],
                  ),
                  onChanged: (_) => clearFieldError('details'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          FilledButton(
            onPressed: isSubmitting ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: isSubmitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text(_isEditing ? 'Enregistrer' : 'Ajouter cette adresse'),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isError
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isError
                ? theme.colorScheme.onErrorContainer
                : theme.colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
