import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seek/seek/device_store.dart';
import 'package:seek/seek/finder_controller.dart';
import 'package:seek/seek/models.dart';

import 'fake_platform.dart';

void main() {
  group('DeviceKind', () {
    test('native type wins, name fills the gaps', () {
      expect(DeviceKind.parse('watch', 'whatever'), DeviceKind.watch);
      expect(DeviceKind.parse('other', 'Redmi Buds 4'), DeviceKind.earbuds);
      expect(DeviceKind.parse('audio', 'Mystery'), DeviceKind.headphones);
      expect(DeviceKind.parse(null, 'Mi Smart Band 8'), DeviceKind.band);
      expect(DeviceKind.parse(null, 'Tile'), DeviceKind.tag);
      expect(DeviceKind.parse(null, ''), DeviceKind.other);
    });
  });

  group('DeviceStore', () {
    const bonded = SeekDevice(address: 'AA', name: 'My Buds', kind: DeviceKind.earbuds, bonded: true);

    test('lists paired devices, then nearby sorted by signal', () async {
      final p = FakePlatform(pairedDevices: [bonded]);
      final s = DeviceStore(p);
      await s.start();
      p.emit(event('B1', -80, name: 'Far'));
      p.emit(event('B2', -50, name: 'Near'));
      p.emit(event('AA', -60));
      await Future<void>.delayed(Duration.zero);

      expect(s.paired.single.rssi, -60);
      expect(s.nearby.map((d) => d.name), ['Near', 'Far']);
      s.dispose();
    });

    test('hides unnamed devices when asked', () async {
      final p = FakePlatform();
      final s = DeviceStore(p);
      await s.start();
      p.emit(event('B1', -60));
      p.emit(event('B2', -70, name: 'Named'));
      await Future<void>.delayed(Duration.zero);

      expect(s.nearby.map((d) => d.address), ['B2']);
      expect(s.hiddenCount, 1);
      s.hideUnnamed = false;
      expect(s.nearby.length, 2);
      s.dispose();
    });

    test('matches a paired device that advertises under another address by name', () async {
      final p = FakePlatform(pairedDevices: [bonded]);
      final s = DeviceStore(p);
      await s.start();
      p.emit(event('LE-ADDR', -55, name: 'my buds'));
      await Future<void>.delayed(Duration.zero);

      expect(s.paired.single.rssi, -55);
      expect(s.nearby, isEmpty);
      s.dispose();
    });

    test('scan stops when stop() is called', () async {
      final p = FakePlatform();
      final s = DeviceStore(p);
      await s.start();
      expect(p.scanListens, 1);
      s.stop();
      expect(p.scanCancels, 1);
      expect(s.scanning, isFalse);
      s.dispose();
    });

    test('does not scan without permission', () async {
      final p = FakePlatform(btStatus: const BtStatus(supported: true, enabled: true, permitted: false));
      final s = DeviceStore(p);
      await s.start();
      expect(p.scanListens, 0);
      await s.requestPermission();
      expect(p.scanListens, 1);
      s.dispose();
    });

    test('drops nearby devices after 90 s', () {
      fakeAsync((async) {
        var clock = DateTime(2026, 1, 1, 12);
        final p = FakePlatform();
        final s = DeviceStore(p, now: () => clock);
        s.start();
        async.flushMicrotasks();
        p.emit(event('B1', -60, name: 'Gone soon'));
        async.flushMicrotasks();
        expect(s.nearby.length, 1);
        clock = clock.add(const Duration(seconds: 100));
        async.elapse(const Duration(seconds: 1));
        expect(s.nearby, isEmpty);
        s.dispose();
      });
    });
  });

  group('FinderController', () {
    const device = SeekDevice(address: 'AA', name: 'My Buds', kind: DeviceKind.earbuds, bonded: true);

    test('starts searching, then tracks, then reports signal lost', () {
      fakeAsync((async) {
        var clock = DateTime(2026, 1, 1, 12);
        final p = FakePlatform();
        final f = FinderController(p, device, now: () => clock);
        f.start();
        async.flushMicrotasks();
        expect(f.state, FinderState.searching);
        expect(p.awake, isTrue);

        p.emit(event('AA', -60));
        async.flushMicrotasks();
        expect(f.state, FinderState.tracking);
        expect(f.heat, greaterThan(0.5));

        clock = clock.add(const Duration(seconds: 10));
        expect(f.state, FinderState.lost);
        expect(f.heat, 0);
        f.dispose();
        expect(p.awake, isFalse);
        expect(p.scanCancels, 1);
      });
    });

    test('ignores other devices but matches a paired one by name', () {
      fakeAsync((async) {
        final p = FakePlatform();
        final f = FinderController(p, device);
        f.start();
        async.flushMicrotasks();
        p.emit(event('ZZ', -40, name: 'Other'));
        async.flushMicrotasks();
        expect(f.state, FinderState.searching);
        p.emit(event('LE', -50, name: 'My Buds'));
        async.flushMicrotasks();
        expect(f.state, FinderState.tracking);
        f.dispose();
      });
    });

    test('beeps faster when closer', () {
      int beepsFor(int rssi) {
        late int count;
        fakeAsync((async) {
          var clock = DateTime(2026, 1, 1, 12);
          final p = FakePlatform();
          final f = FinderController(p, device, now: () => clock);
          f.start();
          async.flushMicrotasks();
          // Keep the signal fresh for 5 s.
          for (var i = 0; i < 50; i++) {
            p.emit(event('AA', rssi));
            async.elapse(const Duration(milliseconds: 100));
            clock = clock.add(const Duration(milliseconds: 100));
          }
          count = p.beeps;
          f.dispose();
        });
        return count;
      }

      expect(beepsFor(-50), greaterThan(beepsFor(-85)));
      expect(beepsFor(-85), greaterThan(0));
    });

    test('beep and vibration can be switched off', () {
      fakeAsync((async) {
        var clock = DateTime(2026, 1, 1, 12);
        final p = FakePlatform();
        void step() {
          p.emit(event('AA', -50));
          async.elapse(const Duration(milliseconds: 100));
          clock = clock.add(const Duration(milliseconds: 100));
        }

        final f = FinderController(p, device, now: () => clock)
          ..beepOn = false
          ..vibrateOn = false;
        f.start();
        async.flushMicrotasks();
        for (var i = 0; i < 30; i++) {
          step();
        }
        expect(p.beeps, 0);
        expect(p.vibrations, 0);
        f.vibrateOn = true;
        for (var i = 0; i < 10; i++) {
          step();
        }
        expect(p.vibrations, greaterThan(0));
        f.dispose();
      });
    });

    test('play sound toggles the tone and stops on dispose', () {
      fakeAsync((async) {
        final p = FakePlatform();
        final f = FinderController(p, device);
        f.start();
        async.flushMicrotasks();
        f.toggleTone();
        async.flushMicrotasks();
        expect(f.tonePlaying, isTrue);
        expect(p.tonesStarted, 1);
        f.toggleTone();
        async.flushMicrotasks();
        expect(f.tonePlaying, isFalse);
        final stopsBefore = p.tonesStopped;
        f.dispose();
        expect(p.tonesStopped, stopsBefore + 1);
      });
    });
  });
}
