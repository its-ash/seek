import 'package:flutter/material.dart';

import '../seek/models.dart';

/// The icon for a device type.
IconData iconForKind(DeviceKind kind) => switch (kind) {
      DeviceKind.earbuds => Icons.earbuds_rounded,
      DeviceKind.headphones => Icons.headphones_rounded,
      DeviceKind.speaker => Icons.speaker_rounded,
      DeviceKind.watch => Icons.watch_rounded,
      DeviceKind.band => Icons.monitor_heart_rounded,
      DeviceKind.tag => Icons.sell_rounded,
      DeviceKind.phone => Icons.smartphone_rounded,
      DeviceKind.computer => Icons.laptop_rounded,
      DeviceKind.other => Icons.bluetooth_rounded,
    };

/// "3 s ago" style text for the list.
String seenText(SeekDevice d, DateTime now) {
  final s = d.ageSeconds(now);
  if (s == null) return 'Not heard yet';
  if (s < 2) return 'Seen just now';
  if (s < 60) return 'Last seen $s s ago';
  return 'Last seen ${s ~/ 60} min ago';
}
