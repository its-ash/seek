import 'package:flutter/services.dart';

import 'models.dart';

/// Everything the app needs from Android. A fake implements this in tests.
abstract class SeekPlatform {
  Future<BtStatus> status();

  /// Asks for the Bluetooth permissions. True when granted.
  Future<bool> requestPermissions();

  Future<void> openBluetoothSettings();

  /// Paired devices.
  Future<List<SeekDevice>> bonded();

  /// Starts a scan when listened to and stops it when the subscription is cancelled.
  /// Errors carry a [PlatformException] code: `PERMISSION`, `BLUETOOTH_OFF` or `SCAN_FAILED`.
  Stream<ScanEvent> scan({bool classic = true});

  /// A short beep on the phone speaker.
  Future<void> beep({int ms = 80});

  Future<void> vibrate({int ms = 60});

  /// A loud warbling tone on the media output (a connected Bluetooth device if there is one).
  Future<void> playTone();

  Future<void> stopTone();

  /// Keeps the screen on while the finder is open.
  Future<void> keepAwake(bool on);
}

/// Talks to `MainActivity.kt`.
class MethodChannelSeekPlatform implements SeekPlatform {
  static const _control = MethodChannel('com.itsash.seek/control');
  static const _scan = EventChannel('com.itsash.seek/scan');

  @override
  Future<BtStatus> status() async {
    final m = await _control.invokeMapMethod<String, Object?>('status') ?? const {};
    return BtStatus(
      supported: m['supported'] == true,
      enabled: m['enabled'] == true,
      permitted: m['permitted'] == true,
    );
  }

  @override
  Future<bool> requestPermissions() async => await _control.invokeMethod<bool>('requestPermissions') ?? false;

  @override
  Future<void> openBluetoothSettings() => _control.invokeMethod<void>('openBluetoothSettings');

  @override
  Future<List<SeekDevice>> bonded() async {
    final list = await _control.invokeListMethod<Map<Object?, Object?>>('bonded') ?? const [];
    return [for (final m in list) SeekDevice.fromBonded(m)];
  }

  @override
  Stream<ScanEvent> scan({bool classic = true}) {
    return _scan
        .receiveBroadcastStream({'classic': classic})
        .map((e) => ScanEvent.fromMap(e as Map<Object?, Object?>));
  }

  @override
  Future<void> beep({int ms = 80}) => _control.invokeMethod<void>('beep', {'ms': ms});

  @override
  Future<void> vibrate({int ms = 60}) => _control.invokeMethod<void>('vibrate', {'ms': ms});

  @override
  Future<void> playTone() => _control.invokeMethod<void>('playTone');

  @override
  Future<void> stopTone() => _control.invokeMethod<void>('stopTone');

  @override
  Future<void> keepAwake(bool on) => _control.invokeMethod<void>('keepAwake', {'on': on});
}
