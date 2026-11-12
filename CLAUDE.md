# Seek (package: seek / com.itsash.seek)

Finds lost Bluetooth things (earbuds, watch, band, speaker, BLE tags) with a hot/cold meter. Kotlin scans
and plays sounds; Flutter is the UI (device list, finder, settings).

## Code layout

- `android/app/src/main/kotlin/com/itsash/seek/`
  - `Scanner.kt`: BLE `SCAN_MODE_LOW_LATENCY` scan plus classic discovery, restarted each time it ends.
    Runs only between `start()` and `stop()`.
  - `Tone.kt`: `beep` (ToneGenerator on the notification stream, so it stays on the phone speaker) and
    `playLoud` (AudioTrack warble on the media stream, which Android routes to a connected A2DP device;
    auto-stops after 20 s).
  - `DeviceType.kt`: class-of-device to `earbuds|headphones|speaker|watch|band|audio|phone|computer|other`.
  - `MainActivity.kt`: channels, runtime permissions, vibration, keep-screen-on. Stops scan and tone in `onStop`.
- `lib/seek/`: `proximity.dart` (pure: Kalman `RssiFilter`, log-distance estimate, `heatOf`, `Heat`,
  `beepInterval`, `TrendTracker`, `isSignalLost`), `models.dart`, `seek_platform.dart` (interface + channel
  impl, fakeable), `device_store.dart` (list), `finder_controller.dart` (one device).
- `lib/screens/`: `home_screen` (list; scan only while visible and app in foreground), `finder_screen`
  (scan only while open), `settings_screen` (ends with `UiAppearanceSection`, `UiUpdateSection(storeId: 'seek')`,
  `UiDeveloperSection()`).

## Channel contract

MethodChannel `com.itsash.seek/control`:
- `status()` -> `{supported, enabled, permitted}`
- `requestPermissions()` -> bool (Android 12+: BLUETOOTH_SCAN + BLUETOOTH_CONNECT; older: ACCESS_FINE_LOCATION)
- `openBluetoothSettings()`
- `bonded()` -> `[{address, name?, type, bonded: true}]`
- `beep({ms})`, `vibrate({ms})`, `playTone()`, `stopTone()`, `keepAwake({on})`

EventChannel `com.itsash.seek/scan` (args `{classic: bool}`): the scan starts on listen and stops on cancel.
Events `{address, name?, rssi, kind: "le"|"classic", type, bonded}`. Errors: `PERMISSION`, `BLUETOOTH_OFF`,
`SCAN_FAILED`.

## Signal model

- RSSI -> Kalman filter -> heat `0..1` (-95 dBm = 0, -45 dBm = 1) -> word, gauge color, beep interval
  (1.6 s cold to 0.12 s hot).
- Distance: `10^((-59 - rssi) / (10 * 2.4))`, clamped 0.1 to 50 m, always shown as "approx.".
- Trend: smoothed RSSI now vs up to 4 s ago, 2.5 dB threshold.
- Signal lost after 8 s without a reading. A device found again after that resets the filter.
- A paired device often advertises over BLE under another address than its classic address; the finder and
  list match it by name as a fallback.

## Commands

- `make run`, `make build`, `make test` (analyze + Dart tests), `make clean`.
- Icon: `assets/icon/*.svg` -> `rsvg-convert -w 1024 -h 1024` to `*-1024.png`, then
  `dart run flutter_launcher_icons`.

## Conventions

- minSdk 26. UI only from `../theme` (read `../theme/COMPONENTS.md`).
- BLUETOOTH_SCAN is declared `neverForLocation`; no location is used or stored.
- Only network use: `UiUpdateSection` in Settings. No analytics.

## Release (Ash Store)

- `store.json` (id `seek`, repo its-ash/seek), `store.mk`, `index.html` + `CNAME` (`seek.itsash.in`).
  See `../ash-store/store-kit/STORE.md`.
- `make deploy` = bump version -> build -> commit, tag `vX.Y.Z`, push -> GitHub release with `seek.apk` ->
  topics, homepage, Pages. Never create releases, tags or asset names by hand.
- Do not edit `store.mk` here. Edit `../ash-store/store-kit/store.mk`, then run `make store-sync` at the
  workspace root.
