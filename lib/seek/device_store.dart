import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'seek_platform.dart';

/// The device list: paired devices first, then nearby devices from the scan.
/// The scan runs only between [start] and [stop].
class DeviceStore extends ChangeNotifier {
  DeviceStore(this._platform, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final SeekPlatform _platform;
  final DateTime Function() _now;

  /// Nearby devices not heard for this long are dropped from the list.
  static const Duration nearbyExpiry = Duration(seconds: 90);

  final Map<String, SeekDevice> _paired = {};
  final Map<String, SeekDevice> _nearby = {};
  StreamSubscription<ScanEvent>? _sub;
  Timer? _tick;

  BtStatus? status;
  String? error;
  bool scanning = false;
  bool _hideUnnamed = true;

  bool get hideUnnamed => _hideUnnamed;
  set hideUnnamed(bool value) {
    if (_hideUnnamed == value) return;
    _hideUnnamed = value;
    notifyListeners();
  }

  DateTime get now => _now();

  /// Paired devices: the ones heard most recently first, then by name.
  List<SeekDevice> get paired {
    final list = _paired.values.toList();
    list.sort((a, b) {
      final sa = a.lastSeen, sb = b.lastSeen;
      if (sa != null && sb != null) return sb.compareTo(sa);
      if (sa != null) return -1;
      if (sb != null) return 1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return list;
  }

  /// Nearby devices that are not paired, strongest signal first.
  List<SeekDevice> get nearby {
    final list = _nearby.values.where((d) => !_hideUnnamed || d.hasName).toList();
    list.sort((a, b) => (b.rssi ?? -127).compareTo(a.rssi ?? -127));
    return list;
  }

  /// How many nearby devices the "hide unnamed" filter is hiding.
  int get hiddenCount => _hideUnnamed ? _nearby.values.where((d) => !d.hasName).length : 0;

  Future<void> refresh() async {
    try {
      status = await _platform.status();
      if (status!.ready) {
        final bonded = await _platform.bonded();
        final keep = {for (final d in bonded) d.address};
        _paired.removeWhere((a, _) => !keep.contains(a));
        for (final d in bonded) {
          final old = _paired[d.address];
          _paired[d.address] = old == null ? d : old.copyWith(name: d.name, kind: d.kind);
        }
      }
    } on PlatformException catch (e) {
      error = e.message ?? e.code;
    }
    notifyListeners();
  }

  Future<void> requestPermission() async {
    await _platform.requestPermissions();
    await refresh();
    if (status?.ready ?? false) await start();
  }

  Future<void> openBluetoothSettings() => _platform.openBluetoothSettings();

  /// Starts the scan (after checking permissions and that Bluetooth is on).
  Future<void> start() async {
    await refresh();
    if (!(status?.ready ?? false) || scanning) return;
    error = null;
    scanning = true;
    _sub = _platform.scan().listen(_onEvent, onError: _onError);
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _prune();
      notifyListeners();
    });
    notifyListeners();
  }

  /// Stops the scan. Safe to call twice.
  void stop() {
    _sub?.cancel();
    _sub = null;
    _tick?.cancel();
    _tick = null;
    if (scanning) {
      scanning = false;
      notifyListeners();
    }
  }

  void _onEvent(ScanEvent e) {
    final when = _now();
    final direct = _paired[e.address];
    if (direct != null) {
      _paired[e.address] = direct.copyWith(
        rssi: e.rssi,
        lastSeen: when,
        name: direct.hasName ? null : e.name,
      );
      return;
    }
    // A paired device that advertises under another (BLE) address: match it by name.
    if (e.name.trim().isNotEmpty) {
      for (final entry in _paired.entries) {
        if (entry.value.name.toLowerCase() == e.name.toLowerCase()) {
          _paired[entry.key] = entry.value.copyWith(rssi: e.rssi, lastSeen: when);
          return;
        }
      }
    }
    final old = _nearby[e.address];
    _nearby[e.address] = SeekDevice(
      address: e.address,
      name: e.name.trim().isNotEmpty ? e.name : (old?.name ?? ''),
      kind: e.kind == DeviceKind.other ? (old?.kind ?? e.kind) : e.kind,
      bonded: e.bonded,
      rssi: e.rssi,
      lastSeen: when,
    );
  }

  void _onError(Object error) {
    this.error = error is PlatformException ? (error.message ?? error.code) : '$error';
    stop();
    refresh();
  }

  void _prune() {
    final cutoff = _now().subtract(nearbyExpiry);
    _nearby.removeWhere((_, d) => d.lastSeen != null && d.lastSeen!.isBefore(cutoff));
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
