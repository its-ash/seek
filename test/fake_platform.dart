import 'dart:async';

import 'package:seek/seek/models.dart';
import 'package:seek/seek/seek_platform.dart';

/// In-memory platform for tests. Push scan events with [emit].
class FakePlatform implements SeekPlatform {
  FakePlatform({this.btStatus = const BtStatus(supported: true, enabled: true, permitted: true), this.pairedDevices = const []});

  BtStatus btStatus;
  List<SeekDevice> pairedDevices;

  late final StreamController<ScanEvent> _scan = StreamController<ScanEvent>.broadcast(
    onListen: () => scanListens++,
    onCancel: () => scanCancels++,
  );

  int scanListens = 0;
  int scanCancels = 0;
  int beeps = 0;
  int vibrations = 0;
  int tonesStarted = 0;
  int tonesStopped = 0;
  bool awake = false;

  void emit(ScanEvent e) => _scan.add(e);

  @override
  Future<BtStatus> status() async => btStatus;

  @override
  Future<bool> requestPermissions() async {
    btStatus = BtStatus(supported: btStatus.supported, enabled: btStatus.enabled, permitted: true);
    return true;
  }

  @override
  Future<void> openBluetoothSettings() async {}

  @override
  Future<List<SeekDevice>> bonded() async => pairedDevices;

  @override
  Stream<ScanEvent> scan({bool classic = true}) => _scan.stream;

  @override
  Future<void> beep({int ms = 80}) async => beeps++;

  @override
  Future<void> vibrate({int ms = 60}) async => vibrations++;

  @override
  Future<void> playTone() async => tonesStarted++;

  @override
  Future<void> stopTone() async => tonesStopped++;

  @override
  Future<void> keepAwake(bool on) async => awake = on;
}

ScanEvent event(String address, int rssi, {String name = '', DeviceKind kind = DeviceKind.other, bool bonded = false}) {
  return ScanEvent(address: address, name: name, rssi: rssi, source: SightingSource.le, kind: kind, bonded: bonded);
}
