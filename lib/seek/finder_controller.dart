import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'proximity.dart';
import 'seek_platform.dart';

enum FinderState {
  /// Scanning, nothing heard from the device yet.
  searching,

  /// Hearing the device.
  tracking,

  /// Heard it before, but not for a while.
  lost,
}

/// Follows one device: smooths its RSSI, works out heat, distance and trend, and drives the
/// beep and vibration. The scan runs while this object is alive and is stopped by [dispose].
class FinderController extends ChangeNotifier {
  FinderController(this._platform, this.device, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final SeekPlatform _platform;
  final SeekDevice device;
  final DateTime Function() _now;

  final RssiFilter _filter = RssiFilter();
  final TrendTracker _trend = TrendTracker();
  StreamSubscription<ScanEvent>? _sub;
  Timer? _timer;

  DateTime? _lastSeen;
  DateTime _nextBeep = DateTime.fromMillisecondsSinceEpoch(0);
  int? _rawRssi;
  String? error;
  bool _beepOn = true;
  bool _vibrateOn = false;
  bool _tonePlaying = false;

  bool get beepOn => _beepOn;
  bool get vibrateOn => _vibrateOn;
  bool get tonePlaying => _tonePlaying;

  set beepOn(bool v) {
    _beepOn = v;
    notifyListeners();
  }

  set vibrateOn(bool v) {
    _vibrateOn = v;
    notifyListeners();
  }

  /// The latest raw reading in dBm.
  int? get rawRssi => _rawRssi;

  /// The smoothed reading in dBm.
  double? get smoothedRssi => _filter.value;

  DateTime? get lastSeen => _lastSeen;

  /// 0..1. Zero while there is no signal.
  double get heat {
    final r = _filter.value;
    if (r == null || state != FinderState.tracking) return 0;
    return heatOf(r);
  }

  Heat get heatLabel => Heat.of(heat);

  double? get distanceMeters {
    final r = _filter.value;
    return r == null ? null : estimateDistanceMeters(r);
  }

  Trend get trend => state == FinderState.tracking ? _trend.trend : Trend.steady;

  FinderState get state {
    if (_lastSeen == null) return FinderState.searching;
    return isSignalLost(_lastSeen, _now()) ? FinderState.lost : FinderState.tracking;
  }

  /// Seconds since the device was last heard, or null.
  int? get secondsSinceSeen {
    final t = _lastSeen;
    return t == null ? null : _now().difference(t).inSeconds;
  }

  /// Starts the scan and the 100 ms clock.
  Future<void> start() async {
    await _platform.keepAwake(true);
    _sub = _platform.scan().listen(_onEvent, onError: (Object e) {
      error = e.toString();
      notifyListeners();
    });
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  bool _matches(ScanEvent e) {
    if (e.address == device.address) return true;
    // Paired devices often advertise over BLE with another address; fall back to the name.
    return device.bonded && device.hasName && e.name.toLowerCase() == device.name.toLowerCase();
  }

  void _onEvent(ScanEvent e) {
    if (!_matches(e)) return;
    final t = _now();
    if (_lastSeen != null && isSignalLost(_lastSeen, t)) {
      // Found again after a gap: the old estimate is stale.
      _filter.reset();
      _trend.clear();
    }
    _lastSeen = t;
    _rawRssi = e.rssi;
    _trend.add(t, _filter.update(e.rssi));
  }

  int _ticks = 0;

  void _tick() {
    final t = _now();
    if (state == FinderState.tracking && (_beepOn || _vibrateOn) && !t.isBefore(_nextBeep)) {
      final gap = beepInterval(heat);
      if (gap != null) {
        _nextBeep = t.add(gap);
        if (_beepOn) _platform.beep();
        if (_vibrateOn) _platform.vibrate();
      }
    }
    // Repaint about 4 times a second.
    if (++_ticks % 3 == 0) notifyListeners();
  }

  /// Starts or stops the loud tone. Only ever called from a user tap.
  Future<void> toggleTone() async {
    _toneTimer?.cancel();
    if (_tonePlaying) {
      _tonePlaying = false;
      notifyListeners();
      await _platform.stopTone();
    } else {
      _tonePlaying = true;
      notifyListeners();
      await _platform.playTone();
      // The native side stops the tone by itself after 20 s; keep the button in step.
      _toneTimer = Timer(toneDuration, () {
        _tonePlaying = false;
        notifyListeners();
      });
    }
  }

  /// How long the native tone plays before it stops itself (see `Tone.MAX_MILLIS`).
  static const Duration toneDuration = Duration(seconds: 20);
  Timer? _toneTimer;

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _toneTimer?.cancel();
    _platform.stopTone();
    _platform.keepAwake(false);
    super.dispose();
  }
}
