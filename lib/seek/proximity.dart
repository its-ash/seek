import 'dart:math' as math;

/// One-dimensional Kalman filter for RSSI. Raw readings jump by 5 to 10 dB; this smooths them
/// while still following real movement.
class RssiFilter {
  RssiFilter({this.processNoise = 0.8, this.measurementNoise = 6.0});

  /// How fast the true value is expected to change per reading (higher = follows faster).
  final double processNoise;

  /// How noisy a single reading is (higher = trusts readings less).
  final double measurementNoise;

  double? _estimate;
  double _variance = 0;

  /// The smoothed value, or null before the first reading.
  double? get value => _estimate;

  /// Feeds one reading in dBm and returns the new smoothed value.
  double update(num reading) {
    final z = reading.toDouble();
    final x = _estimate;
    if (x == null) {
      _estimate = z;
      _variance = measurementNoise;
      return z;
    }
    final predicted = _variance + processNoise;
    final gain = predicted / (predicted + measurementNoise);
    _estimate = x + gain * (z - x);
    _variance = (1 - gain) * predicted;
    return _estimate!;
  }

  void reset() {
    _estimate = null;
    _variance = 0;
  }
}

/// Rough distance in metres from the smoothed RSSI with the log-distance path loss model:
/// `d = 10 ^ ((txPower - rssi) / (10 * n))`. [txPower] is the RSSI at 1 m (about -59 dBm for
/// phones and earbuds) and [pathLoss] is `n` (2 in free space, 2 to 3 indoors).
/// Walls, bodies and the device's antenna change this a lot, so always show it as approximate.
double estimateDistanceMeters(double rssi, {double txPower = -59, double pathLoss = 2.4}) {
  final d = math.pow(10, (txPower - rssi) / (10 * pathLoss)).toDouble();
  return d.clamp(0.1, 50.0);
}

/// A short, honest label: "< 1 m", "about 2 m", "> 15 m".
String formatDistance(double meters) {
  if (meters < 1) return '< 1 m';
  if (meters >= 15) return '> 15 m';
  if (meters < 5) {
    final half = (meters * 2).round() / 2;
    return 'about ${half == half.roundToDouble() ? half.round().toString() : half.toString()} m';
  }
  return 'about ${meters.round()} m';
}

/// 0 (cold, barely heard) to 1 (hot, right next to you), from the smoothed RSSI.
/// -95 dBm or less is 0, -45 dBm or more is 1, with a gentle curve so "warm" is easy to see.
double heatOf(double rssi) {
  const cold = -95.0;
  const hot = -45.0;
  final t = ((rssi - cold) / (hot - cold)).clamp(0.0, 1.0);
  return math.pow(t, 1.15).toDouble();
}

/// The heat as a word.
enum Heat {
  freezing('Freezing'),
  cold('Cold'),
  cool('Cool'),
  warm('Warm'),
  hot('Hot'),
  burning('Right here');

  const Heat(this.label);

  final String label;

  static Heat of(double heat) {
    if (heat < 0.12) return freezing;
    if (heat < 0.3) return cold;
    if (heat < 0.5) return cool;
    if (heat < 0.7) return warm;
    if (heat < 0.88) return hot;
    return burning;
  }
}

/// Time between beeps for a heat of 0..1: slow (1.6 s) when cold, fast (0.12 s) when hot.
/// Returns null when [heat] is below [minHeat], so a very weak signal stays silent.
Duration? beepInterval(double heat, {double minHeat = 0.05}) {
  if (heat < minHeat) return null;
  final t = math.pow(heat.clamp(0.0, 1.0), 1.6).toDouble();
  final ms = 1600 + (120 - 1600) * t;
  return Duration(milliseconds: ms.round());
}

enum Trend { closer, farther, steady }

/// Compares the smoothed RSSI now with a few seconds ago to say if you are getting closer.
class TrendTracker {
  TrendTracker({this.window = const Duration(seconds: 4), this.threshold = 2.5});

  /// How far back to look.
  final Duration window;

  /// Smallest change in dB that counts as movement.
  final double threshold;

  final List<(DateTime, double)> _samples = [];

  void add(DateTime time, double smoothedRssi) {
    _samples.add((time, smoothedRssi));
    _samples.removeWhere((s) => time.difference(s.$1) > window);
  }

  void clear() => _samples.clear();

  /// The trend over the window. [steady] until there are readings spanning at least 1.5 s.
  Trend get trend {
    if (_samples.length < 2) return Trend.steady;
    final first = _samples.first;
    final last = _samples.last;
    if (last.$1.difference(first.$1) < const Duration(milliseconds: 1500)) return Trend.steady;
    final delta = last.$2 - first.$2;
    if (delta >= threshold) return Trend.closer;
    if (delta <= -threshold) return Trend.farther;
    return Trend.steady;
  }
}

/// The signal counts as lost when nothing was heard for this long.
const Duration signalLostAfter = Duration(seconds: 8);

bool isSignalLost(DateTime? lastSeen, DateTime now) =>
    lastSeen == null || now.difference(lastSeen) > signalLostAfter;
