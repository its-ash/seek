import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../seek/device_store.dart';
import '../seek/models.dart';
import '../seek/seek_platform.dart';
import 'finder_screen.dart';
import 'kind_icon.dart';
import 'settings_screen.dart';

/// Paired devices, then nearby ones. The scan runs only while this screen is visible.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.platform});

  final SeekPlatform platform;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final DeviceStore _store = DeviceStore(widget.platform);
  late final AppLifecycleListener _lifecycle;
  bool _foreground = true;
  bool _covered = false; // another screen is on top

  @override
  void initState() {
    super.initState();
    _store.start();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _foreground = true;
        _sync();
      },
      onHide: () {
        _foreground = false;
        _sync();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _store.dispose();
    super.dispose();
  }

  void _sync() {
    if (_foreground && !_covered) {
      _store.start();
    } else {
      _store.stop();
    }
  }

  Future<void> _push(Widget page) async {
    _covered = true;
    _sync();
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    _covered = false;
    _sync();
  }

  Future<void> _openFinder(SeekDevice device) => _push(FinderScreen(platform: widget.platform, device: device));

  Future<void> _openSettings() => _push(SettingsScreen(store: _store, platform: widget.platform));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        return UiScaffold(
          appBar: UiAppBar(
            title: 'Seek',
            actions: [UiIconButton(Icons.settings_rounded, tooltip: 'Settings', onPressed: _openSettings)],
          ),
          scrollable: true,
          body: _body(context),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    final status = _store.status;
    if (status == null) {
      return const Padding(padding: EdgeInsets.only(top: UiSpace.xxl), child: Center(child: UiSpinner()));
    }
    if (!status.supported) {
      return const UiEmptyState(
        icon: Icons.bluetooth_disabled_rounded,
        title: 'No Bluetooth',
        message: 'This device has no Bluetooth, so Seek has nothing to search with.',
      );
    }
    if (!status.permitted) {
      return UiEmptyState(
        icon: Icons.bluetooth_searching_rounded,
        title: 'Allow Bluetooth access',
        message: 'Seek needs to see nearby Bluetooth devices to find your lost ones. '
            'It does not use or store your location.',
        action: UiButton('Allow', icon: Icons.check_rounded, onPressed: _store.requestPermission),
      );
    }
    if (!status.enabled) {
      return UiEmptyState(
        icon: Icons.bluetooth_disabled_rounded,
        title: 'Bluetooth is off',
        message: 'Turn Bluetooth on to search for your devices.',
        action: UiButton('Open Bluetooth settings', onPressed: _store.openBluetoothSettings),
      );
    }

    final now = _store.now;
    final paired = _store.paired;
    final nearby = _store.nearby;
    return UiColumn(
      gap: UiSpace.lg,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_store.error != null)
          UiAlert(_store.error!, status: UiStatus.danger, action: UiButton('Retry', onPressed: _store.start)),
        UiAlert(
          'Pick the device you lost. Earbuds often only advertise when they are out of the case, '
          'so open the case lid first.',
          icon: Icons.lightbulb_outline_rounded,
        ),
        if (_store.scanning) const UiProgressBar.indeterminate(),
        UiListGroup(
          header: 'Paired devices',
          footer: paired.isEmpty ? 'No paired devices. Pair the device in Bluetooth settings, or pick it below.' : null,
          children: [for (final d in paired) _tile(d, now)],
        ),
        UiListGroup(
          header: 'Nearby devices',
          footer: _nearbyFooter(nearby.length),
          children: [for (final d in nearby) _tile(d, now)],
        ),
        UiSwitchTile(
          'Hide unnamed devices',
          subtitle: _store.hiddenCount > 0 ? '${_store.hiddenCount} hidden' : 'Hides nameless Bluetooth noise',
          icon: Icons.filter_alt_rounded,
          value: _store.hideUnnamed,
          onChanged: (v) => _store.hideUnnamed = v,
        ),
      ],
    );
  }

  String? _nearbyFooter(int count) {
    if (count > 0) return null;
    return _store.scanning ? 'Searching for devices...' : 'Nothing found yet.';
  }

  Widget _tile(SeekDevice d, DateTime now) {
    final seen = d.ageSeconds(now);
    final recent = seen != null && seen < 10;
    return UiListTile(
      d.title,
      subtitle: d.lastSeen == null ? 'Not heard yet · ${d.kind.label}' : '${seenText(d, now)} · ${d.rssi} dBm',
      icon: iconForKind(d.kind),
      iconStatus: recent ? UiStatus.success : UiStatus.neutral,
      chevron: true,
      onTap: () => _openFinder(d),
    );
  }
}
