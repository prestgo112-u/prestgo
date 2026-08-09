// Appareils connectés — réglages (opération 58, complément de T196).
//
// Consultation seule : l'enregistrement et le désenregistrement appartiennent au
// cycle de vie du jeton (`core/push/push_service.dart`), jamais à un écran. Le
// jeton lui-même n'apparaît nulle part — le service ne le renvoie pas.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/widgets/empty_view.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/notifications/data/device_repository.dart';
import 'package:prestgo_mobile/features/notifications/domain/registered_device.dart';

final FutureProvider<List<RegisteredDevice>> devicesProvider =
    FutureProvider<List<RegisteredDevice>>(
      (Ref ref) => ref.watch(deviceRepositoryProvider).devices(),
    );

class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<RegisteredDevice>> devices = ref.watch(
      devicesProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Appareils connectés')),
      body: devices.when(
        loading: () => const LoadingView(label: 'Chargement des appareils…'),
        error: (Object error, StackTrace _) => ErrorView(
          message: error is ApiException
              ? error.message
              : ApiFallbackMessages.unknown,
          onRetry: () => ref.invalidate(devicesProvider),
        ),
        data: (List<RegisteredDevice> items) {
          if (items.isEmpty) {
            return const EmptyView(
              icon: Icons.devices_other_outlined,
              title: 'Aucun appareil enregistré',
              description:
                  'Un appareil s’enregistre à la connexion, si vous acceptez '
                  'les notifications.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(devicesProvider),
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) =>
                  _DeviceTile(device: items[index]),
            ),
          );
        },
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});

  final RegisteredDevice device;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? lastSeenAt = device.lastSeenAt;

    return ListTile(
      leading: Icon(switch (device.platform) {
        'ios' => Icons.phone_iphone,
        'web' => Icons.laptop_outlined,
        _ => Icons.phone_android,
      }),
      title: Text(switch (device.platform) {
        'ios' => 'Appareil iOS',
        'web' => 'Navigateur web',
        _ => 'Appareil Android',
      }),
      subtitle: lastSeenAt == null
          ? null
          : Text('Vu ${DateLabels.age(DateTime.now().difference(lastSeenAt))}'),
      trailing: device.active
          ? Chip(
              label: const Text('Actif'),
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
              backgroundColor: theme.colorScheme.secondaryContainer,
            )
          : Chip(
              label: const Text('Inactif'),
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
    );
  }
}
