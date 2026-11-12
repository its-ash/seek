import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../seek/device_store.dart';
import '../seek/seek_platform.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store, required this.platform});

  final DeviceStore store;
  final SeekPlatform platform;

  @override
  Widget build(BuildContext context) {
    return UiScaffold(
      appBar: const UiAppBar(title: 'Settings'),
      scrollable: true,
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          return UiColumn(
            gap: UiSpace.lg,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UiListGroup(
                header: 'Devices',
                children: [
                  UiSwitchTile(
                    'Hide unnamed devices',
                    subtitle: 'Skip nearby devices that do not send a name.',
                    icon: Icons.filter_alt_rounded,
                    value: store.hideUnnamed,
                    onChanged: (v) => store.hideUnnamed = v,
                  ),
                  UiListTile(
                    'Bluetooth settings',
                    subtitle: 'Pair or connect a device.',
                    icon: Icons.bluetooth_rounded,
                    chevron: true,
                    onTap: platform.openBluetoothSettings,
                  ),
                ],
              ),
              UiListGroup(
                header: 'About the distance',
                footer: 'Distance comes from Bluetooth signal strength. Walls, your body and the device\'s '
                    'antenna change it a lot, so treat it as a rough guide and follow the meter.',
                children: const [
                  UiListTile(
                    'Private',
                    subtitle: 'No account, no location tracking. The only network call is the update check.',
                    icon: Icons.lock_outline_rounded,
                  ),
                ],
              ),
              const UiAppearanceSection(),
              const UiUpdateSection(storeId: 'seek'),
              const UiDeveloperSection(),
            ],
          );
        },
      ),
    );
  }
}
