import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:seek/seek/proximity.dart';

void main() {
  group('RssiFilter', () {
    test('first reading is the estimate', () {
      final f = RssiFilter();
      expect(f.value, isNull);
      expect(f.update(-70), -70);
    });

    test('smooths noise around a steady value', () {
      final f = RssiFilter();
      final rng = math.Random(7);
      var rawErr = 0.0, smoothErr = 0.0;
      var smooth = 0.0;
      for (var i = 0; i < 200; i++) {
        final raw = -70 + (rng.nextDouble() - 0.5) * 16; // +-8 dB noise
        smooth = f.update(raw);
        if (i > 20) {
          rawErr += (raw + 70).abs();
          smoothErr += (smooth + 70).abs();
        }
      }
      expect(smoothErr, lessThan(rawErr * 0.6));
    });

    test('follows a real change', () {
      final f = RssiFilter();
      for (var i = 0; i < 20; i++) {
        f.update(-85);
      }
      for (var i = 0; i < 20; i++) {
        f.update(-55);
      }
      expect(f.value!, greaterThan(-60));
    });

    test('reset forgets the estimate', () {
      final f = RssiFilter()..update(-60);
      f.reset();
      expect(f.value, isNull);
      expect(f.update(-90), -90);
    });
  });

  group('distance', () {
    test('equals 1 m at the 1 m power', () {
      expect(estimateDistanceMeters(-59), closeTo(1.0, 1e-9));
    });

    test('grows as the signal gets weaker', () {
      expect(estimateDistanceMeters(-80), greaterThan(estimateDistanceMeters(-70)));
      expect(estimateDistanceMeters(-70), greaterThan(estimateDistanceMeters(-60)));
    });

    test('is clamped', () {
      expect(estimateDistanceMeters(-20), 0.1);
      expect(estimateDistanceMeters(-127), 50.0);
    });

    test('labels are rounded and honest', () {
      expect(formatDistance(0.3), '< 1 m');
      expect(formatDistance(1.9), 'about 2 m');
      expect(formatDistance(2.5), 'about 2.5 m');
      expect(formatDistance(7.4), 'about 7 m');
      expect(formatDistance(20), '> 15 m');
    });
  });

  group('heat', () {
    test('is 0 when cold and 1 when hot', () {
      expect(heatOf(-100), 0);
      expect(heatOf(-95), 0);
      expect(heatOf(-45), 1);
      expect(heatOf(-30), 1);
    });

    test('rises with the signal', () {
      var last = -1.0;
      for (var r = -95; r <= -45; r += 5) {
        final h = heatOf(r.toDouble());
        expect(h, greaterThanOrEqualTo(last));
        last = h;
      }
    });

    test('words follow the heat', () {
      expect(Heat.of(0), Heat.freezing);
      expect(Heat.of(0.2), Heat.cold);
      expect(Heat.of(0.4), Heat.cool);
      expect(Heat.of(0.6), Heat.warm);
      expect(Heat.of(0.8), Heat.hot);
      expect(Heat.of(1), Heat.burning);
    });
  });

  group('beepInterval', () {
    test('is silent when there is almost no signal', () {
      expect(beepInterval(0), isNull);
      expect(beepInterval(0.04), isNull);
    });

    test('is slow when cold and fast when hot', () {
      expect(beepInterval(0.05)!.inMilliseconds, greaterThan(1400));
      expect(beepInterval(1)!.inMilliseconds, 120);
    });

    test('never gets slower as heat rises', () {
      var last = 1 << 30;
      for (var h = 0.05; h <= 1.0; h += 0.05) {
        final ms = beepInterval(h)!.inMilliseconds;
        expect(ms, lessThanOrEqualTo(last));
        last = ms;
      }
    });
  });

  group('TrendTracker', () {
    final t0 = DateTime(2026, 1, 1, 12);

    test('is steady with too little data', () {
      final t = TrendTracker()..add(t0, -80);
      expect(t.trend, Trend.steady);
      t.add(t0.add(const Duration(milliseconds: 500)), -60);
      expect(t.trend, Trend.steady);
    });

    test('detects closer and farther', () {
      final closer = TrendTracker()
        ..add(t0, -80)
        ..add(t0.add(const Duration(seconds: 2)), -72);
      expect(closer.trend, Trend.closer);

      final farther = TrendTracker()
        ..add(t0, -60)
        ..add(t0.add(const Duration(seconds: 2)), -68);
      expect(farther.trend, Trend.farther);
    });

    test('small changes are steady', () {
      final t = TrendTracker()
        ..add(t0, -70)
        ..add(t0.add(const Duration(seconds: 2)), -71);
      expect(t.trend, Trend.steady);
    });

    test('old samples fall out of the window', () {
      final t = TrendTracker()
        ..add(t0, -90)
        ..add(t0.add(const Duration(seconds: 6)), -60)
        ..add(t0.add(const Duration(seconds: 8)), -60);
      expect(t.trend, Trend.steady);
    });
  });

  test('signal lost after 8 seconds', () {
    final now = DateTime(2026, 1, 1, 12);
    expect(isSignalLost(null, now), isTrue);
    expect(isSignalLost(now.subtract(const Duration(seconds: 5)), now), isFalse);
    expect(isSignalLost(now.subtract(const Duration(seconds: 9)), now), isTrue);
  });
}
