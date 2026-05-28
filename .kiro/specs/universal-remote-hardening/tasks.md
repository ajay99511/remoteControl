# Implementation Plan: Universal Remote Hardening

## Overview

25 tasks across 5 waves that fix all 28 audited defects in the `devicecontroller` Flutter app.
Wave 1 (foundation) runs fully in parallel. Each subsequent wave depends on the prior wave's
outputs. All tasks within a wave are independent of each other and can run in parallel.

## Tasks

### Wave 1 — Foundation (all parallel)

- [ ] 1. Add new dependencies to pubspec.yaml
  - [ ] 1.1 Add `connectivity_plus: ^6.1.0` to dependencies
  - [ ] 1.2 Add `logger: ^2.4.0` to dependencies
  - [ ] 1.3 Add `mockito: ^5.4.4` to dev_dependencies
  - [ ] 1.4 Add `build_runner: ^2.4.13` to dev_dependencies
  - [ ] 1.5 Update description to `"A universal remote control app for Roku, Samsung, LG, and Vizio smart TVs."`
  - _Requirements: 2.31, 2.34_

- [ ] 2. Fix Android manifest permissions
  - [ ] 2.1 Add `<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" android:usesPermissionFlags="neverForLocation"/>` to `android/app/src/main/AndroidManifest.xml`
  - _Requirements: 2.16_

- [ ] 3. Fix iOS Info.plist permissions and metadata
  - [ ] 3.1 Add `NSLocalNetworkUsageDescription` with value `"Universal Remote needs local network access to discover and control your smart TV."`
  - [ ] 3.2 Add `NSBonjourServices` array with all 7 service types
  - [ ] 3.3 Update `CFBundleDisplayName` to `"Universal Remote"`
  - [ ] 3.4 Update `CFBundleName` to `"universalremote"`
  - _Requirements: 2.17, 2.33_

- [ ] 4. Create core infrastructure — AppLogger and UnsupportedDeviceException
  - [ ] 4.1 Create `lib/core/app_logger.dart` — singleton `Logger` instance with `PrettyPrinter`, release-mode level filtering
  - [ ] 4.2 Create `lib/exceptions/unsupported_device_exception.dart` — typed exception with `DeviceType` field
  - _Requirements: 2.8, 2.31_

- [ ] 5. Update models — DeviceType enum, Device class, RemoteKey enum, AppId enum
  - [ ] 5.1 Modify `lib/models/device.dart`: add `DeviceType` enum (roku, samsung, lg, vizio, fireTv, googleTv, ir, unknown) with `fromString()` and `toJson()`
  - [ ] 5.2 Update `Device.type` field from `String` to `DeviceType`
  - [ ] 5.3 Add `==` operator and `hashCode` to `Device`
  - [ ] 5.4 Add `copyWith()` to `Device`
  - [ ] 5.5 Modify `lib/models/remote_key.dart`: add 19 new keys (channelUp, channelDown, info, menu, search, inputSource, subtitles, sleep, replay, star, instantReplay, exit, ok, record, guide, aspectRatio, pip, audioTrack, settings)
  - [ ] 5.6 Create `lib/models/app_id.dart`: `AppId` enum with netflix, youtube, primeVideo, disneyPlus, hulu, spotify, appleTv and `displayName` getter
  - _Requirements: 2.23, 2.29, 2.32_

- [ ] 6. Create DevicePersistenceService
  - [ ] 6.1 Create `lib/services/device_persistence_service.dart`
  - [ ] 6.2 Implement `saveDevice`, `loadDevice`, `clearDevice` using `flutter_secure_storage`
  - [ ] 6.3 Implement `saveCertFingerprint`, `loadCertFingerprint` with `tofu_cert_` prefix
  - [ ] 6.4 Implement `saveSamsungToken`, `loadSamsungToken` with `samsung_token_` prefix
  - [ ] 6.5 Add Riverpod `devicePersistenceProvider`
  - _Requirements: 2.1, 2.2, 2.10, 2.11_

- [ ] 7. Create ConnectivityService
  - [ ] 7.1 Create `lib/services/connectivity_service.dart`
  - [ ] 7.2 Implement `ConnectivityService` with `WidgetsBindingObserver` mixin
  - [ ] 7.3 Subscribe to `connectivity_plus` stream
  - [ ] 7.4 Emit on `AppLifecycleState.resumed`
  - [ ] 7.5 Add Riverpod `connectivityServiceProvider` with `ref.onDispose`
  - _Requirements: 2.12, 2.13_

### Wave 2 — Controllers (depends on Wave 1)

- [ ] 8. Update DeviceController interface
  - [ ] 8.1 Modify `lib/controllers/device_controller.dart`: change `launchApp(String appName)` to `launchApp(AppId appId)`
  - _Requirements: 2.23_
  - _Depends on: Task 5_

- [ ] 9. Update RokuController
  - [ ] 9.1 Add `.timeout(const Duration(seconds: 3))` to ALL http calls (connect, sendKey, sendText, launchApp)
  - [ ] 9.2 Change `launchApp` signature to `AppId`
  - [ ] 9.3 Update `_appIds` map to use `AppId` keys
  - [ ] 9.4 Add all 19 new `RemoteKey` values to `_keyMap` (ChannelUp, ChannelDown, Info, Search, Subtitle, Sleep, InstantReplay, Star, Guide, Settings, Select for ok, Home for exit; pip/audioTrack/aspectRatio/record → no-op)
  - [ ] 9.5 Replace all `debugPrint` with `log.d` / `log.e`
  - _Requirements: 2.18, 2.23, 2.29, 2.31_
  - _Depends on: Tasks 4, 5, 8_

- [ ] 10. Update SamsungController — TOFU, token, heartbeat, truncation
  - [ ] 10.1 Add `DevicePersistenceService _persistence` constructor parameter
  - [ ] 10.2 Implement TOFU: extract SHA-256 fingerprint from `X509Certificate` DER bytes using `crypto` package; on first connect store via `_persistence.saveCertFingerprint`; on subsequent connects compare and throw `TofuMismatchException` if different
  - [ ] 10.3 Listen to WebSocket stream; parse pairing token from JSON; persist via `_persistence.saveSamsungToken`
  - [ ] 10.4 Add `_startHeartbeat()`: 30s periodic timer sending `'ping'`; 5s pong timeout calling `_onPongTimeout()`
  - [ ] 10.5 Add `_onPongTimeout()`: set `_connected = false`, cancel timers
  - [ ] 10.6 Add `sendText` 500-char truncation
  - [ ] 10.7 Change `launchApp` signature to `AppId`; update `_appIds` to `Map<AppId, String>`
  - [ ] 10.8 Add all 19 new `RemoteKey` values to `_keyMap`
  - [ ] 10.9 Replace all `debugPrint` with `log.d` / `log.e`
  - _Requirements: 2.1, 2.2, 2.3, 2.14, 2.23, 2.29, 2.31_
  - _Depends on: Tasks 4, 5, 6, 8_

- [ ] 11. Create LgController
  - [ ] 11.1 Create `lib/controllers/lg_controller.dart`
  - [ ] 11.2 WebSocket on `ws://$host:3000`
  - [ ] 11.3 SSAP register payload with stored `clientKey` if available
  - [ ] 11.4 Listen for pairing prompt; surface PIN requirement via exception
  - [ ] 11.5 Persist `clientKey` via `DevicePersistenceService`
  - [ ] 11.6 Heartbeat: 30s ping, 5s pong timeout
  - [ ] 11.7 Full `_ssapUris` map for all 33 `RemoteKey` values
  - [ ] 11.8 `_appIds` map for all `AppId` values
  - [ ] 11.9 `launchApp(AppId)` signature
  - [ ] 11.10 Replace all `debugPrint` with `log.d` / `log.e`
  - _Requirements: 2.4, 2.14, 2.23, 2.29, 2.31_
  - _Depends on: Tasks 4, 5, 6, 8_

- [ ] 12. Create VizioController
  - [ ] 12.1 Create `lib/controllers/vizio_controller.dart`
  - [ ] 12.2 SmartCast REST API on `https://$host:7345`
  - [ ] 12.3 `connect()`: POST `/pairing/start`, surface PIN requirement, POST `/pairing/pair`, store auth token
  - [ ] 12.4 `sendKey(RemoteKey)`: PUT `/key_command/` with KEYLIST payload; full `_keyMap` for all applicable keys
  - [ ] 12.5 `launchApp(AppId)`: PUT `/app/launch`
  - [ ] 12.6 All HTTP calls with `.timeout(Duration(seconds: 3))`
  - [ ] 12.7 Replace all `debugPrint` with `log.d` / `log.e`
  - _Requirements: 2.5, 2.23, 2.29, 2.31_
  - _Depends on: Tasks 4, 5, 8_

- [ ] 13. Create FireTvController and GoogleTvController stubs
  - [ ] 13.1 Create `lib/controllers/fire_tv_controller.dart`: all methods throw `UnsupportedDeviceException(DeviceType.fireTv)`
  - [ ] 13.2 Create `lib/controllers/google_tv_controller.dart`: all methods throw `UnsupportedDeviceException(DeviceType.googleTv)`
  - _Requirements: 2.6, 2.7_
  - _Depends on: Tasks 4, 5, 8_

- [ ] 14. Create IrController
  - [ ] 14.1 Create `lib/controllers/ir_controller.dart`
  - [ ] 14.2 `connect()`: check IR hardware availability via platform channel; throw `UnsupportedDeviceException(DeviceType.ir)` if no IR emitter
  - [ ] 14.3 `sendKey(RemoteKey)`: look up `_irDatabase[brand]?[key]`; transmit via platform channel
  - [ ] 14.4 IR code database for samsung, lg, vizio, sony, tcl — NEC codes for power, volumeUp, volumeDown, mute, channelUp, channelDown, home, back, up, down, left, right, select
  - [ ] 14.5 `launchApp` and `sendText` are no-ops
  - [ ] 14.6 Replace all `debugPrint` with `log.d` / `log.e`
  - _Requirements: 2.9, 2.31_
  - _Depends on: Tasks 4, 5, 8_

- [ ] 15. Update MockController
  - [ ] 15.1 Change `launchApp` signature to `AppId`
  - [ ] 15.2 Replace `debugPrint` with `log.d`
  - _Requirements: 2.23, 2.31_
  - _Depends on: Tasks 5, 8_

### Wave 3 — Providers (depends on Wave 2)

- [ ] 16. Refactor ConnectionNotifier — remove controller from state, add lifecycle
  - [ ] 16.1 Remove `DeviceController? controller` from `DeviceConnectionState`; add `DeviceController? _controller` private field to `ConnectionNotifier`
  - [ ] 16.2 Fix `errorMessage` copyWith bug (ensure `copyWith` can clear errorMessage to null)
  - [ ] 16.3 Inject `DevicePersistenceService` and `ConnectivityService` via `ref.read` in `build()`
  - [ ] 16.4 Subscribe to `ConnectivityService.onConnectivityChanged` in `build()`; cancel in `ref.onDispose`
  - [ ] 16.5 Implement `_tryAutoReconnect()` called from `build()`: load saved device, attempt connect
  - [ ] 16.6 Implement `_onConnectivityChanged()`: set error on `none`; trigger reconnect on restore
  - [ ] 16.7 Implement `_connectWithBackoff()`: exponential backoff 1s/2s/4s/8s, max 4 retries
  - [ ] 16.8 Update `_buildController()` to use `DeviceType` switch with all 7 types + `unknown` throwing `UnsupportedDeviceException`
  - [ ] 16.9 Update `sendKey`, `sendText`, `launchApp` to use `_controller` private field
  - [ ] 16.10 Update `launchApp` signature to `AppId`
  - [ ] 16.11 Replace all `debugPrint` with `log.d` / `log.e`
  - _Requirements: 2.8, 2.10, 2.12, 2.13, 2.15, 2.20, 2.23, 2.31_
  - _Depends on: Tasks 6, 7, 9, 10, 11, 12, 13, 14, 15_

- [ ] 17. Update ScannerNotifier — SSDP hardening, DeviceType, logging
  - [ ] 17.1 Update `_startSsdpDiscovery()`: send M-SEARCH 3 times with 500ms intervals; extend listen window to 8 seconds
  - [ ] 17.2 Update `_handleServiceFound()` and `_handleSsdpResponse()` to use `DeviceType` enum instead of raw strings
  - [ ] 17.3 Replace all `debugPrint` with `log.d` / `log.e`
  - _Requirements: 2.19, 2.31, 2.32_
  - _Depends on: Tasks 4, 5_

### Wave 4 — UI (depends on Wave 3)

- [ ] 18. Update device_scanner.dart — manual connect dialog, decoupling
  - [ ] 18.1 Replace `_handleManualConnect()` dialog: add `DeviceType` dropdown (roku/samsung/lg/vizio)
  - [ ] 18.2 Auto-fill port on type change (8060/8001/3000/7345)
  - [ ] 18.3 Add IPv4/IPv6 regex validation with inline error
  - [ ] 18.4 Disable Connect button when `ipError != null`
  - [ ] 18.5 Update `_deviceIcon()` and `_deviceColor()` to use `DeviceType` enum
  - [ ] 18.6 Verify device selection goes through `connectionProvider.notifier.connect()` with no direct coupling
  - _Requirements: 2.21, 2.22, 2.27, 2.32_
  - _Depends on: Tasks 5, 16_

- [ ] 19. Update remote.dart — power, touchpad, mute, BackdropFilter, Semantics
  - [ ] 19.1 Remove `isPowerOn` local state; make power button fire-and-forget (no `setState`)
  - [ ] 19.2 Replace touchpad `onPanEnd` velocity detection with `onPanUpdate` delta accumulation (`_touchpadDelta`); fire key when `|dx| > 30 || |dy| > 30`
  - [ ] 19.3 Add visual directional indicator (`_pendingDirection`); reset on `onPanEnd`
  - [ ] 19.4 Replace MUTE `RockerButton` with standalone `RemoteButton(icon: LucideIcons.volumeX, label: 'MUTE', onTap: () => _sendKey(RemoteKey.mute))`
  - [ ] 19.5 Reduce `BackdropFilter` sigma from 80 to 15 (both occurrences)
  - [ ] 19.6 Add `Semantics` wrappers with descriptive labels to D-pad OK button, Back, Home, Play buttons
  - [ ] 19.7 Add `tooltip` to all `IconButton` instances in `_buildHeader()`
  - [ ] 19.8 Update `launchApp` calls to use `AppId` enum (AppId.netflix, AppId.youtube, AppId.primeVideo, AppId.disneyPlus)
  - _Requirements: 2.23, 2.24, 2.25, 2.26, 2.28, 2.30_
  - _Depends on: Tasks 5, 16_

- [ ] 20. Update remote_buttons.dart — Semantics and tooltip
  - [ ] 20.1 Add `tooltip` parameter to `RemoteButton`
  - [ ] 20.2 Wrap `RemoteButton` content in `Semantics(label: label ?? tooltip ?? 'Remote button', button: true, child: Tooltip(...))`
  - [ ] 20.3 Add `Semantics(label: 'Volume up', button: true)` around VOL rocker top half
  - [ ] 20.4 Add `Semantics(label: 'Volume down', button: true)` around VOL rocker bottom half
  - [ ] 20.5 Add `Semantics(label: 'Launch \$name', button: true)` around `AppButton`
  - _Requirements: 2.28_
  - _Depends on: Task 5_

### Wave 5 — Tests (depends on Waves 1–4)

- [ ] 21. Write RokuController unit tests
  - [ ] 21.1 Create `test/controllers/roku_controller_test.dart`
  - [ ] 21.2 Use `mockito` `MockClient` (generated via `build_runner`)
  - [ ] 21.3 Test: `connect()` succeeds when device-info returns 200
  - [ ] 21.4 Test: `connect()` throws `TimeoutException` after 3s on unreachable host (use `Future.delayed` mock)
  - [ ] 21.5 Test: `sendKey(RemoteKey.up)` POSTs to `/keypress/Up`
  - [ ] 21.6 Test: `sendKey(RemoteKey.channelUp)` POSTs to `/keypress/ChannelUp`
  - [ ] 21.7 Test: `sendText('ab')` sends two `Lit_` keypresses
  - [ ] 21.8 Test: `launchApp(AppId.netflix)` POSTs to `/launch/12`
  - [ ] 21.9 Test: `sendKey` is no-op when not connected
  - [ ] 21.10 Test: all HTTP calls complete within 3 seconds or throw
  - _Requirements: 2.34_
  - _Depends on: Tasks 1, 9_

- [ ] 22. Write SamsungController unit tests
  - [ ] 22.1 Create `test/controllers/samsung_controller_test.dart`
  - [ ] 22.2 Mock `DevicePersistenceService` and WebSocket sink
  - [ ] 22.3 Test: `connect()` stores fingerprint on first WSS connection
  - [ ] 22.4 Test: `connect()` rejects mismatched fingerprint on second connection
  - [ ] 22.5 Test: `connect()` persists pairing token from stream
  - [ ] 22.6 Test: `sendKey(RemoteKey.mute)` sends `KEY_MUTE` in `ms.remote.control` payload
  - [ ] 22.7 Test: `sendText('x' * 600)` transmits ≤ 500 characters
  - [ ] 22.8 Test: heartbeat sends ping every 30s
  - [ ] 22.9 Test: pong timeout triggers `_connected = false` after 5s
  - _Requirements: 2.34_
  - _Depends on: Tasks 1, 6, 10_

- [ ] 23. Write ConnectionNotifier unit tests
  - [ ] 23.1 Create `test/providers/connection_notifier_test.dart`
  - [ ] 23.2 Use `ProviderContainer` with overrides for `devicePersistenceProvider` and `connectivityServiceProvider`
  - [ ] 23.3 Test: state machine `disconnected → connecting → connected` on success
  - [ ] 23.4 Test: state machine `disconnected → connecting → error` on failure
  - [ ] 23.5 Test: no direct `disconnected → connected` transition
  - [ ] 23.6 Test: `DeviceConnectionState` does not contain `DeviceController` field
  - [ ] 23.7 Test: unknown `DeviceType` throws `UnsupportedDeviceException`
  - [ ] 23.8 Test: auto-reconnect on app resume
  - [ ] 23.9 Test: connectivity loss sets error state
  - [ ] 23.10 Test: exponential backoff — 4 retries before permanent error
  - _Requirements: 2.34_
  - _Depends on: Tasks 1, 6, 7, 16_

- [ ] 24. Write ScannerNotifier unit tests
  - [ ] 24.1 Create `test/providers/scanner_notifier_test.dart`
  - [ ] 24.2 Test: duplicate device by `ip+port` is filtered (only 1 entry)
  - [ ] 24.3 Test: devices with same IP but different port are both added
  - [ ] 24.4 Test: SSDP sends 3 M-SEARCH packets (verify via mock socket)
  - [ ] 24.5 Test: SSDP listen window is 8 seconds
  - [ ] 24.6 Test: device JSON round-trip — `Device.fromJson(device.toJson()) == device`
  - _Requirements: 2.34_
  - _Depends on: Tasks 1, 5, 17_

- [ ] 25. Replace widget_test.dart smoke test
  - [ ] 25.1 Modify `test/widget_test.dart`: remove counter template test
  - [ ] 25.2 Add smoke test: `MyApp` renders without throwing
  - [ ] 25.3 Add smoke test: `DeviceScannerScreen` is present in widget tree
  - _Requirements: 2.34_
  - _Depends on: Tasks 18, 19, 20_

## Task Dependency Graph

```json
{
  "waves": [
    {
      "wave": 1,
      "tasks": [1, 2, 3, 4, 5, 6, 7],
      "description": "Foundation — all parallel, no dependencies"
    },
    {
      "wave": 2,
      "tasks": [8, 9, 10, 11, 12, 13, 14, 15],
      "description": "Controllers — all parallel, depend on Wave 1"
    },
    {
      "wave": 3,
      "tasks": [16, 17],
      "description": "Providers — parallel, depend on Wave 2"
    },
    {
      "wave": 4,
      "tasks": [18, 19, 20],
      "description": "UI — parallel, depend on Wave 3"
    },
    {
      "wave": 5,
      "tasks": [21, 22, 23, 24, 25],
      "description": "Tests — parallel, depend on Waves 1–4"
    }
  ],
  "dependencies": {
    "8":  [5],
    "9":  [4, 5, 8],
    "10": [4, 5, 6, 8],
    "11": [4, 5, 6, 8],
    "12": [4, 5, 8],
    "13": [4, 5, 8],
    "14": [4, 5, 8],
    "15": [5, 8],
    "16": [6, 7, 9, 10, 11, 12, 13, 14, 15],
    "17": [4, 5],
    "18": [5, 16],
    "19": [5, 16],
    "20": [5],
    "21": [1, 9],
    "22": [1, 6, 10],
    "23": [1, 6, 7, 16],
    "24": [1, 5, 17],
    "25": [18, 19, 20]
  }
}
```

## Notes

- All Wave 1 tasks are independent and can execute in parallel.
- Task 17 (ScannerNotifier) only depends on Tasks 4 and 5 from Wave 1, so it can start as soon as those complete — it does not need to wait for all of Wave 2.
- Task 20 (remote_buttons.dart) only depends on Task 5, so it can start as soon as Wave 1 completes.
- The `crypto` package used in Task 10 for SHA-256 fingerprinting is already a transitive dependency of `flutter_secure_storage`; no additional pubspec entry is needed.
- Tasks 13 (Fire TV / Google TV stubs) are intentionally minimal — they exist to satisfy the `DeviceType` switch in Task 16 and to provide a clear user-facing error rather than a silent Roku fallback.
- IR code values in Task 14 are NEC protocol hex codes; the platform channel implementation requires a native Android plugin (e.g., `flutter_ir`) to be added to pubspec.yaml as part of that task.
