# Seek

Find lost earbuds, watches and Bluetooth tags with a hot and cold meter.

**[Website](https://seek.itsash.in)** · **[Download APK](https://github.com/its-ash/seek/releases/latest/download/seek.apk)** · Get it in **[Ash Store](https://store.itsash.in)**

## Features

- **Device list**: paired devices first with their names and type icons, then nearby devices found by a
  Bluetooth LE scan and classic discovery. Each shows its last signal (dBm) and "last seen N s ago".
  Nameless noise can be hidden.
- **Hot / cold finder**: a big meter from the smoothed signal strength (Kalman filter), a closer or
  farther arrow, and a rough distance clearly marked "approx.".
- **Beep and vibration** that speed up as you get closer. Each can be switched off.
- **Signal lost** state when the device has not been heard for 8 seconds.
- **Play sound** (user triggered, paired audio devices): a loud tone on the connected Bluetooth audio so
  you can hear a lost earbud. Stops by itself after 20 seconds.
- **Tips**: earbuds often only advertise when they are out of the case, so open the lid.
- **Private**: no account, no location tracking, no analytics. The only network call is the update check
  in Settings. Scans stop when you leave the screen or the app.

## Install

- **Ash Store**: install [Ash Store](https://store.itsash.in) once, then install and update Seek from it.
- **APK**: download the [latest APK](https://github.com/its-ash/seek/releases/latest/download/seek.apk) on your phone and open it. Allow your browser to install unknown apps if Android asks.

Requires Android 8.0 (API 26) or later. Allow the Nearby devices permission (Android 12+). On Android 11
and older Android asks for Location, which it needs for any Bluetooth scan; Seek does not use or store it.

## Develop

Needs Flutter ≥ 3.44 and the shared theme package at `../theme`.

```bash
make run      # run on a connected device
make test     # flutter analyze + flutter test
make build    # release APK
make deploy   # bump version, build, tag, push, GitHub release (see store.mk)
```

## Release

`make deploy` follows the Ash Store kit (`store.mk`, `store.json`): it bumps the
version in `pubspec.yaml`, builds, commits, tags `vX.Y.Z`, pushes, and publishes
a GitHub release with `seek.apk`. Ash Store and the website pick up the new
version from that release.

## Project layout

```
lib/
├── main.dart
├── seek/
│   ├── proximity.dart          # Kalman filter, distance, heat, beep rate, trend (pure)
│   ├── models.dart             # SeekDevice, ScanEvent, DeviceKind
│   ├── seek_platform.dart      # MethodChannel + EventChannel to MainActivity.kt
│   ├── device_store.dart       # paired + nearby list
│   └── finder_controller.dart  # one device: meter, beep, vibration, tone
└── screens/
    ├── home_screen.dart        # device list
    ├── finder_screen.dart      # hot / cold meter
    ├── settings_screen.dart
    └── kind_icon.dart
android/app/src/main/kotlin/com/itsash/seek/
├── MainActivity.kt             # channels, permissions
├── Scanner.kt                  # BLE scan + classic discovery
├── Tone.kt                     # beep and loud tone
└── DeviceType.kt               # class of device -> type name
test/                           # proximity, stores, fake platform
```

See `CLAUDE.md` for details.

## License

No license file is included yet.

Built by [itsash.in](https://itsash.in).
