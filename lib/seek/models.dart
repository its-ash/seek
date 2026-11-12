/// What kind of thing a Bluetooth device is. Drives the icon and whether "Play sound" is offered.
enum DeviceKind {
  earbuds('Earbuds'),
  headphones('Headphones'),
  speaker('Speaker'),
  watch('Watch'),
  band('Fitness band'),
  tag('Tag'),
  phone('Phone'),
  computer('Computer'),
  other('Device');

  const DeviceKind(this.label);

  final String label;

  /// Audio gear that can play a tone when it is the connected media output.
  bool get isAudio => this == earbuds || this == headphones || this == speaker;

  /// Picks a kind from the native type (`earbuds`, `audio`, ...) and the name. A specific native
  /// type wins; the name fills in for generic types and for BLE-only devices without a class.
  static DeviceKind parse(String? nativeType, String? name) {
    final native = switch (nativeType) {
      'earbuds' => earbuds,
      'headphones' => headphones,
      'speaker' => speaker,
      'watch' => watch,
      'band' => band,
      'phone' => phone,
      'computer' => computer,
      _ => null,
    };
    if (native != null) return native;
    final byName = fromName(name);
    if (byName != null) return byName;
    return nativeType == 'audio' ? headphones : other;
  }

  static DeviceKind? fromName(String? name) {
    final n = (name ?? '').toLowerCase();
    if (n.isEmpty) return null;
    bool has(List<String> words) => words.any(n.contains);
    if (has(['airpod', 'buds', 'earbud', 'earphone', 'airdope', 'tws', 'pods', 'ear (', 'neckband'])) {
      return earbuds;
    }
    if (has(['headphone', 'headset', 'wh-', 'xm4', 'xm5', 'bose', 'quietcomfort'])) return headphones;
    if (has(['speaker', 'boom', 'soundbar', 'jbl', 'echo', 'charge ', 'flip ', 'srs-'])) return speaker;
    if (has(['watch', 'amazfit', 'garmin', 'fossil'])) return watch;
    if (has(['band', 'fit', 'mi smart', 'whoop', 'oura'])) return band;
    if (has(['tag', 'tile', 'chipolo', 'beacon', 'smarttag', 'airtag', 'tracker'])) return tag;
    return null;
  }
}

/// How the sighting was made.
enum SightingSource { le, classic }

/// A device in the list. [rssi] and [lastSeen] are null until the scan has seen it.
class SeekDevice {
  const SeekDevice({
    required this.address,
    required this.name,
    required this.kind,
    this.bonded = false,
    this.rssi,
    this.lastSeen,
  });

  final String address;

  /// Friendly name, empty when the device does not advertise one.
  final String name;
  final DeviceKind kind;
  final bool bonded;
  final int? rssi;
  final DateTime? lastSeen;

  bool get hasName => name.trim().isNotEmpty;

  /// Name for display; unnamed devices show their address.
  String get title => hasName ? name : address;

  /// Whole seconds since [lastSeen], or null when never seen.
  int? ageSeconds(DateTime now) {
    final t = lastSeen;
    if (t == null) return null;
    final s = now.difference(t).inSeconds;
    return s < 0 ? 0 : s;
  }

  SeekDevice copyWith({String? name, DeviceKind? kind, bool? bonded, int? rssi, DateTime? lastSeen}) {
    return SeekDevice(
      address: address,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      bonded: bonded ?? this.bonded,
      rssi: rssi ?? this.rssi,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  /// From the native bonded list: `{address, name?, type, bonded}`.
  factory SeekDevice.fromBonded(Map<Object?, Object?> m) {
    final name = (m['name'] as String?) ?? '';
    return SeekDevice(
      address: m['address'] as String,
      name: name,
      kind: DeviceKind.parse(m['type'] as String?, name),
      bonded: true,
    );
  }
}

/// One reading from the scan stream: `{address, name?, rssi, kind, type, bonded}`.
class ScanEvent {
  const ScanEvent({
    required this.address,
    required this.name,
    required this.rssi,
    required this.source,
    required this.kind,
    required this.bonded,
  });

  final String address;
  final String name;
  final int rssi;
  final SightingSource source;
  final DeviceKind kind;
  final bool bonded;

  factory ScanEvent.fromMap(Map<Object?, Object?> m) {
    final name = (m['name'] as String?) ?? '';
    return ScanEvent(
      address: m['address'] as String,
      name: name,
      rssi: (m['rssi'] as num).toInt(),
      source: m['kind'] == 'classic' ? SightingSource.classic : SightingSource.le,
      kind: DeviceKind.parse(m['type'] as String?, name),
      bonded: m['bonded'] == true,
    );
  }
}

/// Bluetooth state as the app needs it.
class BtStatus {
  const BtStatus({required this.supported, required this.enabled, required this.permitted});

  final bool supported;
  final bool enabled;
  final bool permitted;

  bool get ready => supported && enabled && permitted;
}
