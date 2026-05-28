# Universal Remote Hardening — Bugfix Design

## Overview

The `devicecontroller` Flutter app has 28 audited defects spanning security, platform coverage,
state persistence, network lifecycle, permissions, protocol correctness, architecture, UX,
accessibility, key coverage, performance, logging, type safety, metadata, and testing.

The fix strategy is **additive-first**: new files are created for new controllers and services;
existing files are surgically modified to remove defects without breaking the preserved behaviors
documented in `bugfix.md` §3. Every change is traceable to a numbered requirement (§2) and a
correctness property defined in this document.

---

## Glossary

- **Bug_Condition (C)**: A predicate over an input or system state that identifies a defective
  execution path (e.g., `badCertificateCallback` always returning `true`).
- **Property (P)**: The desired post-fix behavior for inputs where C holds.
- **Preservation**: Behaviors that must remain byte-for-byte identical after the fix; defined in
  `bugfix.md` §3.
- **TOFU**: Trust-On-First-Use — accept any certificate on first contact, pin the SHA-256
  fingerprint, reject mismatches on subsequent contacts.
- **SSAP**: Samsung Smart Application Protocol — the JSON-over-WebSocket dialect used by webOS
  (LG) on port 3000.
- **ECP**: External Control Protocol — Roku's HTTP REST API on port 8060.
- **SmartCast**: Vizio's REST API on port 7345.
- **DeviceType**: Typed enum replacing raw `Device.type` strings.
- **AppId**: Typed enum replacing raw app-name strings in `launchApp`.
- **UnsupportedDeviceException**: Typed exception thrown when no controller exists for a device.
- **DevicePersistenceService**: Wrapper around `flutter_secure_storage` for device, TOFU cert,
  and Samsung token storage.
- **ConnectivityService**: Wrapper around `connectivity_plus` + `WidgetsBindingObserver`.
- **AppLogger**: Singleton `logger` package instance replacing all `debugPrint` calls.
- **ConnectionNotifier._controller**: Private field on the notifier holding the live
  `DeviceController`; NOT part of the serializable `DeviceConnectionState`.

---

## Bug Details

### Bug Condition

The 28 defects share a common structural pattern: the codebase was scaffolded for a single
device type (Roku) and never hardened for production. The composite bug condition is:

```
FUNCTION isBugCondition(system)
  INPUT: system — the current devicecontroller codebase
  OUTPUT: boolean

  RETURN system.samsungTlsCallback = ALWAYS_TRUE                   // C1
      OR system.websocketStreamUnlistened = true                    // C2
      OR system.sendTextUnbounded = true                            // C3
      OR system.lgControllerMissing = true                          // C4
      OR system.vizioControllerMissing = true                       // C5
      OR system.fireTvControllerMissing = true                      // C6
      OR system.googleTvControllerMissing = true                    // C7
      OR system.unknownTypeSilentFallback = true                    // C8
      OR system.irControllerMissing = true                          // C9
      OR system.deviceNotPersisted = true                           // C10
      OR system.secureStorageUnused = true                          // C11
      OR system.connectivityListenerMissing = true                  // C12
      OR system.appResumeReconnectMissing = true                    // C13
      OR system.websocketHeartbeatMissing = true                    // C14
      OR system.exponentialBackoffMissing = true                    // C15
      OR system.nearbyWifiPermissionMissing = true                  // C16
      OR system.iosLocalNetworkPermissionMissing = true             // C17
      OR system.rokuHttpTimeoutMissing = true                       // C18
      OR system.ssdpSingleProbe = true                              // C19
      OR system.controllerInRiverpodState = true                    // C20
      OR system.manualConnectHardcodesRoku = true                   // C21
      OR system.ipValidationMissing = true                          // C22
      OR system.appIdRawString = true                               // C23
      OR system.touchpadVelocityOnly = true                         // C24
      OR system.powerLocalStateBool = true                          // C25
      OR system.muteRockerMisrouted = true                          // C26
      OR system.scannerDirectlyCoupledToConnection = true           // C27
      OR system.noAccessibilitySemantics = true                     // C28
      OR system.remoteKeyEnumIncomplete = true                      // C29
      OR system.backdropFilterSigmaExcessive = true                 // C30
      OR system.debugPrintUnstructured = true                       // C31
      OR system.deviceTypeRawString = true                          // C32
      OR system.appMetadataTemplate = true                          // C33
      OR system.testSuiteTemplate = true                            // C34
END FUNCTION
```

### Concrete Examples

| # | Trigger | Current (Defective) | Expected (Fixed) |
|---|---------|---------------------|------------------|
| C1 | WSS connect to Samsung | `badCertificateCallback` returns `true` unconditionally | TOFU: pin SHA-256 on first connect, reject mismatch |
| C8 | Connect to LG TV | Falls back to `RokuController` silently | Throws `UnsupportedDeviceException` (until `LgController` added) |
| C18 | Roku `sendKey` on unreachable device | Hangs indefinitely | Throws `TimeoutException` after 3 s |
| C20 | Read `DeviceConnectionState` | Contains live `DeviceController` object | Contains only `status`, `device`, `errorMessage` |
| C26 | Tap top of MUTE rocker | Sends `RemoteKey.volumeUp` | Replaced by standalone mute button sending `RemoteKey.mute` |
| C29 | User needs channel up | `RemoteKey` has no `channelUp` | `RemoteKey.channelUp` exists and maps correctly |

---

## Expected Behavior

### Preservation Requirements

The following behaviors are **unchanged** by this fix (see `bugfix.md` §3):

**Unchanged Behaviors:**
- Roku ECP: HTTP POST to `/keypress/{key}` and `/launch/{appId}` on port 8060
- Samsung WebSocket: WSS-first (8002) → WS fallback (8001), `ms.remote.control` JSON payload
- mDNS auto-scan on scanner screen open, scanning animation, deduplication by `ip+port`
- SSDP `SERVER`/`LOCATION` header parsing for Roku and Samsung
- `disconnected → connecting → connected/error` state machine; no direct `disconnected → connected`
- `MockController` for devices with `id` starting with `mock-`
- Haptic feedback on all remote button taps
- VOL rocker: top = `volumeUp`, bottom = `volumeDown`
- Three remote tab modes: Navigation, Touchpad, Numpad
- App shortcuts: Netflix, YouTube, Prime Video, Disney+
- Keyboard overlay `sendText` + dismiss

**Scope of Non-Affected Inputs:**
All inputs that do NOT involve the 34 bug conditions above are completely unaffected. This
includes all existing Roku and Samsung command paths, all existing UI interactions, and all
existing provider state transitions.

---

## Hypothesized Root Cause

The defects cluster into five root causes:

1. **Prototype-grade security shortcuts**: `badCertificateCallback = always true` and unlistened
   WebSocket streams are typical "get it working" shortcuts that were never hardened.

2. **Single-device-type scaffolding**: The codebase was built for Roku only. Samsung was added
   partially. LG, Vizio, Fire TV, Google TV, and IR were never started. The `_buildController`
   switch has a `default` that silently falls back to Roku.

3. **Missing infrastructure layer**: `flutter_secure_storage` is declared but never wired.
   `connectivity_plus` is absent. `logger` is absent. These are standard production dependencies
   that were deferred.

4. **Riverpod state design error**: `DeviceController` (a mutable, non-serializable object) was
   placed directly in `DeviceConnectionState`. This violates Riverpod's immutable-state contract
   and makes the controller inaccessible for heartbeat/reconnect logic.

5. **UI shortcuts**: Local `isPowerOn` boolean, velocity-only touchpad, MUTE rocker misrouting,
   and missing `Semantics` wrappers are all first-pass UI implementations that were never
   revisited.

---

## Correctness Properties

Property 1: Bug Condition — Samsung TOFU Certificate Pinning

_For any_ WSS connection to a Samsung TV where `isBugCondition_C1` holds (i.e., the current
code accepts all certificates unconditionally), the fixed `SamsungController.connect()` SHALL
extract the server certificate's SHA-256 fingerprint, store it in `DevicePersistenceService`
keyed by host on first contact, and reject with a user-visible error if the fingerprint differs
on subsequent contacts.

**Validates: Requirements 2.1, 2.11**

Property 2: Preservation — Existing Samsung WebSocket Command Path

_For any_ Samsung connection where `isBugCondition_C1` does NOT hold (i.e., the certificate
is already pinned and matches), the fixed `SamsungController` SHALL produce exactly the same
`ms.remote.control` and `ms.channel.emit` JSON payloads as the original code, preserving all
key-press and app-launch behavior.

**Validates: Requirements 3.4, 3.5, 3.6**

Property 3: Bug Condition — Roku HTTP Timeout Enforcement

_For any_ Roku HTTP operation (`connect`, `sendKey`, `sendText`, `launchApp`) where the device
is unreachable and `isBugCondition_C18` holds (no timeout applied), the fixed `RokuController`
SHALL throw a `TimeoutException` within 3 seconds.

**Validates: Requirements 2.18**

Property 4: Preservation — Roku ECP Command Correctness

_For any_ Roku HTTP operation where the device IS reachable and `isBugCondition_C18` does NOT
hold, the fixed `RokuController` SHALL produce exactly the same HTTP POST requests to
`/keypress/{key}` and `/launch/{appId}` as the original code.

**Validates: Requirements 3.1, 3.2, 3.3**

Property 5: Bug Condition — Connection State Machine Legality

_For any_ `(fromState, event)` pair where `isBugCondition_C20` holds (controller stored in
state), the fixed `ConnectionNotifier` SHALL hold `DeviceController` as a private field
`_controller` and SHALL NOT include it in `DeviceConnectionState`; the state machine SHALL
permit only the transitions `disconnected→connecting`, `connecting→connected`,
`connecting→error`, `connected→disconnected`, `error→disconnected`.

**Validates: Requirements 2.20, 3.11, 3.12**

Property 6: Preservation — State Machine Transition Correctness

_For any_ `(fromState, event)` pair where `isBugCondition_C20` does NOT hold, the fixed
`ConnectionNotifier` SHALL produce the same observable state transitions as the original
notifier, preserving `disconnected→connecting→connected` on success and
`disconnected→connecting→error` on failure.

**Validates: Requirements 3.11, 3.12**

Property 7: Bug Condition — Device Persistence Round-Trip

_For any_ `Device` object where `isBugCondition_C10` holds (device not persisted), the fixed
system SHALL serialize the device to JSON via `toJson()`, write it to `DevicePersistenceService`,
and restore an equal `Device` via `fromJson()` on the next app launch.

**Validates: Requirements 2.10, 2.11**

Property 8: Bug Condition — Duplicate Device Filtering

_For any_ two discovered devices `d1` and `d2` where `d1.ip == d2.ip && d1.port == d2.port`,
the fixed `ScannerNotifier` SHALL add only one entry to the device list regardless of discovery
order or source (mDNS vs SSDP).

**Validates: Requirements 3.8, 3.9**

Property 9: Bug Condition — Unsupported Device Explicit Error

_For any_ device whose `DeviceType` is not `roku`, `samsung`, `lg`, `vizio`, `fireTv`,
`googleTv`, or `ir`, the fixed `ConnectionNotifier._buildController()` SHALL throw
`UnsupportedDeviceException` with a descriptive message; the silent Roku fallback SHALL NOT
execute.

**Validates: Requirements 2.8**

Property 10: Bug Condition — sendText Length Guard

_For any_ call to `SamsungController.sendText(text)` where `text.length > 500`, the fixed
method SHALL truncate `text` to 500 characters before base64-encoding and transmitting.

**Validates: Requirements 2.3**

---

## Fix Implementation

### Directory Structure — New and Modified Files

```
lib/
├── models/
│   ├── device.dart                    MODIFIED  — add DeviceType enum, update Device.type field
│   ├── remote_key.dart                MODIFIED  — add 19 new keys
│   └── app_id.dart                    NEW       — AppId enum for typed app identifiers
├── controllers/
│   ├── device_controller.dart         MODIFIED  — update launchApp signature to AppId
│   ├── samsung_controller.dart        MODIFIED  — TOFU, stream listen, token store, heartbeat,
│   │                                              backoff, sendText truncation
│   ├── roku_controller.dart           MODIFIED  — .timeout(3s) on all HTTP calls, new RemoteKeys
│   ├── lg_controller.dart             NEW       — webOS SSAP WebSocket, pairing PIN, heartbeat
│   ├── vizio_controller.dart          NEW       — SmartCast REST API port 7345
│   ├── fire_tv_controller.dart        NEW       — stub, UnsupportedDeviceException on connect
│   ├── google_tv_controller.dart      NEW       — stub, UnsupportedDeviceException on connect
│   ├── ir_controller.dart             NEW       — Android IR blaster, IR code database
│   └── mock_controller.dart           MODIFIED  — replace debugPrint with AppLogger
├── providers/
│   ├── connection_provider.dart       MODIFIED  — _controller private field, connectivity,
│   │                                              WidgetsBindingObserver, backoff, DeviceType switch
│   └── scanner_provider.dart          MODIFIED  — 3x SSDP, 8s window, AppLogger, DeviceType
├── services/
│   ├── device_persistence_service.dart NEW      — flutter_secure_storage wrapper
│   └── connectivity_service.dart       NEW      — connectivity_plus + WidgetsBindingObserver
├── core/
│   └── app_logger.dart                NEW       — singleton logger instance
├── exceptions/
│   └── unsupported_device_exception.dart NEW    — typed exception
├── screens/
│   ├── remote.dart                    MODIFIED  — power fire-and-forget, touchpad delta,
│   │                                              mute button, Semantics, BackdropFilter sigma
│   └── device_scanner.dart            MODIFIED  — manual connect dialog with DeviceType dropdown
│                                                   + port auto-fill + IP validation
└── widgets/
    └── remote_buttons.dart            MODIFIED  — Semantics + tooltip on all interactive widgets

android/app/src/main/AndroidManifest.xml  MODIFIED — NEARBY_WIFI_DEVICES permission
ios/Runner/Info.plist                     MODIFIED — NSLocalNetworkUsageDescription, NSBonjourServices
pubspec.yaml                              MODIFIED — add connectivity_plus, logger, mockito,
                                                     build_runner; update description/name

test/
├── controllers/
│   ├── roku_controller_test.dart      NEW       — mock http.Client, timeout, key dispatch
│   └── samsung_controller_test.dart   NEW       — mock WebSocket, TOFU, sendText truncation
├── providers/
│   ├── connection_notifier_test.dart  NEW       — state machine transitions
│   └── scanner_notifier_test.dart     NEW       — duplicate filtering
└── widget_test.dart                   MODIFIED  — replace counter template with smoke test
```

---

### Class Signatures

#### `lib/models/device.dart`

```dart
/// Typed enum replacing raw Device.type strings.
enum DeviceType {
  roku,
  samsung,
  lg,
  vizio,
  fireTv,
  googleTv,
  ir,
  unknown;

  /// Parse from legacy JSON string values.
  static DeviceType fromString(String s) { ... }
  String toJson() => name;
}

class Device {
  final String id;
  final String name;
  final DeviceType type;   // CHANGED: was String
  final String model;
  final int signal;
  final String? ip;
  final int? port;

  const Device({ ... });
  Map<String, dynamic> toJson();
  factory Device.fromJson(Map<String, dynamic> json);
  Device copyWith({ ... });

  @override bool operator ==(Object other);
  @override int get hashCode;
}
```

#### `lib/models/remote_key.dart`

```dart
enum RemoteKey {
  // Existing 14 keys (unchanged)
  up, down, left, right, select, back, home,
  playPause, volumeUp, volumeDown, mute, power,
  rewind, fastForward,

  // 19 new keys (Requirement 2.29)
  channelUp, channelDown, info, menu, search,
  inputSource, subtitles, sleep, replay, star,
  instantReplay, exit, ok, record, guide,
  aspectRatio, pip, audioTrack, settings,
}
```

#### `lib/models/app_id.dart`

```dart
/// Typed enum for app launch identifiers (Requirement 2.23).
enum AppId {
  netflix,
  youtube,
  primeVideo,
  disneyPlus,
  hulu,
  spotify,
  appleTv;

  /// Human-readable display name used in UI.
  String get displayName { ... }
}
```

#### `lib/exceptions/unsupported_device_exception.dart`

```dart
/// Thrown when no DeviceController exists for a given DeviceType (Requirement 2.8).
class UnsupportedDeviceException implements Exception {
  final DeviceType deviceType;
  final String message;

  const UnsupportedDeviceException(this.deviceType)
      : message = 'No controller available for device type: ${deviceType.name}';

  @override String toString() => 'UnsupportedDeviceException: $message';
}
```

#### `lib/core/app_logger.dart`

```dart
import 'package:logger/logger.dart';

/// Singleton structured logger replacing all debugPrint calls (Requirement 2.31).
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  final Logger _logger = Logger(
    printer: PrettyPrinter(methodCount: 0, printTime: true),
    level: kReleaseMode ? Level.warning : Level.verbose,
  );

  void v(String message, [Object? error, StackTrace? stackTrace]);
  void d(String message, [Object? error, StackTrace? stackTrace]);
  void i(String message, [Object? error, StackTrace? stackTrace]);
  void w(String message, [Object? error, StackTrace? stackTrace]);
  void e(String message, [Object? error, StackTrace? stackTrace]);
}

/// Convenience top-level accessor.
AppLogger get log => AppLogger.instance;
```

---

#### `lib/services/device_persistence_service.dart`

```dart
/// Wraps flutter_secure_storage for device, TOFU cert, and Samsung token storage
/// (Requirements 2.1, 2.2, 2.10, 2.11).
class DevicePersistenceService {
  static const _lastDeviceKey = 'last_device';
  static const _tofuPrefix    = 'tofu_cert_';
  static const _tokenPrefix   = 'samsung_token_';

  final FlutterSecureStorage _storage;

  DevicePersistenceService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  // Device persistence
  Future<void> saveDevice(Device device) async;
  Future<Device?> loadDevice() async;
  Future<void> clearDevice() async;

  // TOFU certificate pinning
  Future<void> saveCertFingerprint(String host, String sha256Hex) async;
  Future<String?> loadCertFingerprint(String host) async;

  // Samsung pairing token
  Future<void> saveSamsungToken(String host, String token) async;
  Future<String?> loadSamsungToken(String host) async;
}

/// Riverpod provider.
final devicePersistenceProvider = Provider<DevicePersistenceService>(
  (_) => DevicePersistenceService(),
);
```

#### `lib/services/connectivity_service.dart`

```dart
/// Wraps connectivity_plus stream and WidgetsBindingObserver for network
/// lifecycle events (Requirements 2.12, 2.13).
class ConnectivityService with WidgetsBindingObserver {
  final _connectivityController =
      StreamController<ConnectivityResult>.broadcast();

  Stream<ConnectivityResult> get onConnectivityChanged =>
      _connectivityController.stream;

  ConnectivityService() {
    WidgetsBinding.instance.addObserver(this);
    Connectivity().onConnectivityChanged.listen(_connectivityController.add);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _connectivityController.add(ConnectivityResult.wifi); // trigger reconnect check
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivityController.close();
  }
}

final connectivityServiceProvider = Provider<ConnectivityService>(
  (ref) {
    final svc = ConnectivityService();
    ref.onDispose(svc.dispose);
    return svc;
  },
);
```

#### `lib/controllers/device_controller.dart` (modified)

```dart
abstract class DeviceController {
  Future<void> connect();
  Future<void> disconnect();
  Future<void> sendKey(RemoteKey key);
  Future<void> sendText(String text);
  Future<void> launchApp(AppId appId);   // CHANGED: String → AppId
  bool get isConnected;
}
```

#### `lib/controllers/samsung_controller.dart` (modified)

```dart
class SamsungController implements DeviceController {
  final String host;
  final int port;
  final DevicePersistenceService _persistence;

  WebSocketChannel? _channel;
  bool _connected = false;
  Timer? _heartbeatTimer;
  Timer? _pongTimeoutTimer;
  int _retryCount = 0;
  static const _maxRetries = 4;

  SamsungController({
    required this.host,
    this.port = 8001,
    required DevicePersistenceService persistence,
  }) : _persistence = persistence;

  // TOFU: extracts SHA-256 hex from X509Certificate DER bytes
  static String _certFingerprint(X509Certificate cert) { ... }

  @override
  Future<void> connect() async {
    // 1. Load stored token for re-auth
    // 2. Attempt WSS 8002 with TOFU validation
    //    a. On first connect: store fingerprint
    //    b. On subsequent: compare fingerprint, reject if mismatch
    // 3. Fall back to WS 8001
    // 4. Listen to stream for pairing token; persist via _persistence
    // 5. Start heartbeat timer (30s ping, 5s pong timeout)
    // 6. Exponential backoff on failure (1s, 2s, 4s, 8s, max 4 retries)
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _channel?.sink.add('ping');
      _pongTimeoutTimer = Timer(const Duration(seconds: 5), _onPongTimeout);
    });
  }

  void _onPongTimeout() { /* mark disconnected, trigger reconnect */ }

  @override Future<void> disconnect() async { ... }
  @override Future<void> sendKey(RemoteKey key) async { ... }

  @override
  Future<void> sendText(String text) async {
    // Truncate to 500 chars (Requirement 2.3)
    final safe = text.length > 500 ? text.substring(0, 500) : text;
    // ... encode and send
  }

  @override Future<void> launchApp(AppId appId) async { ... }
  @override bool get isConnected => _connected;

  static const Map<RemoteKey, String> _keyMap = { /* all 33 keys */ };
  static const Map<AppId, String> _appIds = { /* typed AppId → Tizen app ID */ };
}
```

#### `lib/controllers/roku_controller.dart` (modified)

```dart
class RokuController implements DeviceController {
  // All HTTP calls gain .timeout(const Duration(seconds: 3))
  // launchApp signature changes to AppId
  // New RemoteKey values mapped to ECP key strings
  // debugPrint → log.d / log.e

  static const Map<RemoteKey, String> _keyMap = {
    // existing 14 + new 19 keys mapped to ECP strings
    RemoteKey.channelUp:   'ChannelUp',
    RemoteKey.channelDown: 'ChannelDown',
    RemoteKey.info:        'Info',
    RemoteKey.menu:        'InstantReplay', // Roku equivalent
    RemoteKey.search:      'Search',
    RemoteKey.inputSource: 'InputTuner',
    RemoteKey.subtitles:   'Subtitle',
    RemoteKey.sleep:       'Sleep',
    RemoteKey.replay:      'InstantReplay',
    RemoteKey.star:        'Star',
    RemoteKey.exit:        'Home',
    RemoteKey.ok:          'Select',
    RemoteKey.guide:       'Guide',
    RemoteKey.settings:    'Settings',
    // pip, audioTrack, aspectRatio, record → no ECP equivalent, silently ignored
    ...
  };

  static const Map<AppId, String> _appIds = {
    AppId.netflix:    '12',
    AppId.youtube:    '837',
    AppId.primeVideo: '13',
    AppId.disneyPlus: '291097',
    AppId.hulu:       '2285',
    AppId.spotify:    '22297',
  };
}
```

---

#### `lib/controllers/lg_controller.dart` (new)

```dart
/// LG webOS TV controller via SSAP WebSocket on port 3000 (Requirement 2.4).
class LgController implements DeviceController {
  final String host;
  final int port;
  final DevicePersistenceService _persistence;

  WebSocketChannel? _channel;
  bool _connected = false;
  Timer? _heartbeatTimer;
  Timer? _pongTimeoutTimer;
  String? _clientKey;  // persisted pairing key

  LgController({
    required this.host,
    this.port = 3000,
    required DevicePersistenceService persistence,
  }) : _persistence = persistence;

  @override
  Future<void> connect() async {
    // 1. Load stored client key from persistence
    // 2. Connect WS to ws://$host:$port
    // 3. Send SSAP register payload with clientKey if available
    // 4. Listen for pairing prompt response; if PIN required, surface to UI
    // 5. On successful registration, persist new clientKey
    // 6. Start heartbeat (30s ping, 5s pong timeout)
    // 7. Exponential backoff on failure
  }

  @override Future<void> sendKey(RemoteKey key) async {
    // SSAP: {"type":"request","uri":"ssap://com.webos.service.ime/sendEnterKey"} etc.
  }

  @override Future<void> sendText(String text) async { ... }
  @override Future<void> launchApp(AppId appId) async { ... }
  @override Future<void> disconnect() async { ... }
  @override bool get isConnected => _connected;

  static const Map<RemoteKey, String> _ssapUris = {
    RemoteKey.up:          'ssap://com.webos.service.ime/sendEnterKey',
    RemoteKey.volumeUp:    'ssap://audio/volumeUp',
    RemoteKey.volumeDown:  'ssap://audio/volumeDown',
    RemoteKey.mute:        'ssap://audio/setMute',
    RemoteKey.home:        'ssap://system.launcher/open',
    // ... full mapping
  };

  static const Map<AppId, String> _appIds = {
    AppId.netflix:    'netflix',
    AppId.youtube:    'youtube.leanback.v4',
    AppId.primeVideo: 'amazon',
    AppId.disneyPlus: 'disneyplus',
    // ...
  };
}
```

#### `lib/controllers/vizio_controller.dart` (new)

```dart
/// Vizio SmartCast REST API controller on port 7345 (Requirement 2.5).
class VizioController implements DeviceController {
  final String host;
  final int port;
  final http.Client _client;

  bool _connected = false;
  String? _authToken;

  VizioController({
    required this.host,
    this.port = 7345,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Uri _smartCastUri(String path) =>
      Uri.parse('https://$host:$port/$path');

  @override
  Future<void> connect() async {
    // 1. POST /pairing/start to initiate pairing
    // 2. User enters PIN shown on TV
    // 3. POST /pairing/pair with PIN to receive auth token
    // 4. Store auth token in DevicePersistenceService
    // 5. All subsequent requests include X-Auth-Token header
  }

  @override Future<void> sendKey(RemoteKey key) async {
    // PUT /key_command/ with {"KEYLIST": [{"CODESET": cs, "CODE": code, "ACTION": "KEYPRESS"}]}
  }

  @override Future<void> sendText(String text) async { /* not supported, no-op */ }
  @override Future<void> launchApp(AppId appId) async {
    // PUT /app/launch with app name
  }
  @override Future<void> disconnect() async { _connected = false; }
  @override bool get isConnected => _connected;

  static const Map<RemoteKey, Map<String, int>> _keyMap = {
    RemoteKey.up:        {'codeset': 3, 'code': 8},
    RemoteKey.down:      {'codeset': 3, 'code': 0},
    RemoteKey.left:      {'codeset': 3, 'code': 1},
    RemoteKey.right:     {'codeset': 3, 'code': 7},
    RemoteKey.select:    {'codeset': 3, 'code': 2},
    RemoteKey.back:      {'codeset': 4, 'code': 0},
    RemoteKey.volumeUp:  {'codeset': 5, 'code': 1},
    RemoteKey.volumeDown:{'codeset': 5, 'code': 0},
    RemoteKey.mute:      {'codeset': 5, 'code': 3},
    RemoteKey.power:     {'codeset': 11, 'code': 0},
    // ... full mapping
  };
}
```

#### `lib/controllers/fire_tv_controller.dart` (new)

```dart
/// Amazon Fire TV stub — returns UnsupportedDeviceException (Requirement 2.6).
class FireTvController implements DeviceController {
  @override
  Future<void> connect() async =>
      throw UnsupportedDeviceException(DeviceType.fireTv);

  @override Future<void> disconnect() async {}
  @override Future<void> sendKey(RemoteKey key) async =>
      throw UnsupportedDeviceException(DeviceType.fireTv);
  @override Future<void> sendText(String text) async =>
      throw UnsupportedDeviceException(DeviceType.fireTv);
  @override Future<void> launchApp(AppId appId) async =>
      throw UnsupportedDeviceException(DeviceType.fireTv);
  @override bool get isConnected => false;
}
```

#### `lib/controllers/google_tv_controller.dart` (new)

```dart
/// Google TV / Android TV stub — returns UnsupportedDeviceException (Requirement 2.7).
class GoogleTvController implements DeviceController {
  @override
  Future<void> connect() async =>
      throw UnsupportedDeviceException(DeviceType.googleTv);
  // ... same pattern as FireTvController
}
```

#### `lib/controllers/ir_controller.dart` (new)

```dart
/// Android IR blaster controller (Requirement 2.9).
/// Uses the `flutter_ir` or platform channel to transmit IR codes.
class IrController implements DeviceController {
  final String brand;  // 'samsung' | 'lg' | 'vizio' | 'sony' | 'tcl'
  bool _connected = false;

  IrController({required this.brand});

  @override
  Future<void> connect() async {
    // Check ConsumerIrManager.hasIrEmitter() via platform channel
    // Throw UnsupportedDeviceException if no IR hardware
    _connected = true;
  }

  @override Future<void> sendKey(RemoteKey key) async {
    final code = _irDatabase[brand]?[key];
    if (code == null) return;
    // Transmit via platform channel: frequency + pattern
  }

  @override Future<void> sendText(String text) async { /* not applicable */ }
  @override Future<void> launchApp(AppId appId) async { /* not applicable */ }
  @override Future<void> disconnect() async { _connected = false; }
  @override bool get isConnected => _connected;

  /// IR code database: brand → RemoteKey → {frequency, pattern}
  /// Covers Samsung, LG, Vizio, Sony, TCL USA models.
  static const Map<String, Map<RemoteKey, IrCode>> _irDatabase = {
    'samsung': {
      RemoteKey.power:      IrCode(frequency: 38000, pattern: [170, 170, 13, ...]),
      RemoteKey.volumeUp:   IrCode(frequency: 38000, pattern: [170, 170, 13, ...]),
      // ... full Samsung NEC codes
    },
    'lg': { /* LG NEC codes */ },
    'vizio': { /* Vizio NEC codes */ },
    'sony': { /* Sony SIRC codes */ },
    'tcl': { /* TCL NEC codes */ },
  };
}

class IrCode {
  final int frequency;
  final List<int> pattern;
  const IrCode({required this.frequency, required this.pattern});
}
```

---

#### `lib/providers/connection_provider.dart` (modified)

```dart
/// Serializable state — DeviceController is NOT stored here (Requirement 2.20).
class DeviceConnectionState {
  final ConnectionStatus status;
  final Device? device;
  final String? errorMessage;   // controller field REMOVED

  const DeviceConnectionState({ ... });
  DeviceConnectionState copyWith({ ... });
}

class ConnectionNotifier extends Notifier<DeviceConnectionState>
    with WidgetsBindingObserver {

  DeviceController? _controller;   // private field, not in state
  int _retryCount = 0;
  static const _maxRetries = 4;
  static const _retryDelays = [1, 2, 4, 8]; // seconds

  late final DevicePersistenceService _persistence;
  late final ConnectivityService _connectivity;
  StreamSubscription? _connectivitySub;

  @override
  DeviceConnectionState build() {
    _persistence = ref.read(devicePersistenceProvider);
    _connectivity = ref.read(connectivityServiceProvider);
    _connectivitySub = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    ref.onDispose(() {
      _connectivitySub?.cancel();
      _controller?.disconnect();
    });
    _tryAutoReconnect();
    return const DeviceConnectionState();
  }

  Future<void> _tryAutoReconnect() async {
    final saved = await _persistence.loadDevice();
    if (saved != null) await connect(saved);
  }

  void _onConnectivityChanged(ConnectivityResult result) {
    if (result == ConnectivityResult.none) {
      state = state.copyWith(
        status: ConnectionStatus.error,
        errorMessage: 'Wi-Fi connection lost',
      );
    } else if (state.status == ConnectionStatus.error && state.device != null) {
      connect(state.device!);  // attempt reconnect
    }
  }

  Future<void> connect(Device device) async {
    state = DeviceConnectionState(status: ConnectionStatus.connecting, device: device);
    _retryCount = 0;
    await _connectWithBackoff(device);
  }

  Future<void> _connectWithBackoff(Device device) async {
    try {
      _controller = _buildController(device);
      await _controller!.connect();
      await _persistence.saveDevice(device);
      state = DeviceConnectionState(status: ConnectionStatus.connected, device: device);
      _retryCount = 0;
    } catch (e) {
      if (_retryCount < _maxRetries) {
        final delay = _retryDelays[_retryCount];
        _retryCount++;
        await Future.delayed(Duration(seconds: delay));
        await _connectWithBackoff(device);
      } else {
        state = DeviceConnectionState(
          status: ConnectionStatus.error,
          device: device,
          errorMessage: e.toString(),
        );
      }
    }
  }

  Future<void> disconnect() async {
    await _controller?.disconnect();
    _controller = null;
    await _persistence.clearDevice();
    state = const DeviceConnectionState();
  }

  Future<void> sendKey(RemoteKey key) async { ... }
  Future<void> sendText(String text) async { ... }
  Future<void> launchApp(AppId appId) async { ... }

  DeviceController _buildController(Device device) {
    if (device.id.startsWith('mock-')) return MockController(deviceName: device.name);
    final persistence = ref.read(devicePersistenceProvider);
    return switch (device.type) {
      DeviceType.roku     => RokuController(host: device.ip!, port: device.port ?? 8060),
      DeviceType.samsung  => SamsungController(host: device.ip!, port: device.port ?? 8001,
                                               persistence: persistence),
      DeviceType.lg       => LgController(host: device.ip!, port: device.port ?? 3000,
                                          persistence: persistence),
      DeviceType.vizio    => VizioController(host: device.ip!, port: device.port ?? 7345),
      DeviceType.fireTv   => FireTvController(),
      DeviceType.googleTv => GoogleTvController(),
      DeviceType.ir       => IrController(brand: device.model.toLowerCase()),
      DeviceType.unknown  => throw UnsupportedDeviceException(device.type),
    };
  }
}
```

#### `lib/providers/scanner_provider.dart` (modified — SSDP hardening)

```dart
// _startSsdpDiscovery() changes:
//   - Send M-SEARCH 3 times with 500ms intervals (Requirement 2.19)
//   - Keep socket alive for 8 seconds (was 5)
//   - Replace debugPrint with log.d / log.e

Future<void> _startSsdpDiscovery() async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  socket.broadcastEnabled = true;
  final data = utf8.encode(_searchMessage);
  final multicast = InternetAddress('239.255.255.250');

  // Send 3 probes with 500ms intervals
  for (int i = 0; i < 3; i++) {
    socket.send(data, multicast, 1900);
    if (i < 2) await Future.delayed(const Duration(milliseconds: 500));
  }

  socket.listen((event) { /* parse responses */ });

  // 8-second listen window
  Future.delayed(const Duration(seconds: 8), socket.close);
}
```

---

#### `lib/screens/device_scanner.dart` — Manual Connect Dialog (modified)

```dart
void _handleManualConnect() {
  showDialog(
    context: context,
    builder: (context) {
      final ipController = TextEditingController();
      DeviceType selectedType = DeviceType.roku;
      int selectedPort = 8060;
      String? ipError;

      // Default ports per device type
      const defaultPorts = {
        DeviceType.roku:    8060,
        DeviceType.samsung: 8001,
        DeviceType.lg:      3000,
        DeviceType.vizio:   7345,
      };

      // IPv4 + IPv6 validation regex (Requirement 2.22)
      final ipRegex = RegExp(
        r'^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$'   // IPv4
        r'|^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$',    // IPv6 simplified
      );

      return StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          // ...
          content: Column(children: [
            // Device type dropdown (Requirement 2.21)
            DropdownButton<DeviceType>(
              value: selectedType,
              items: [DeviceType.roku, DeviceType.samsung, DeviceType.lg, DeviceType.vizio]
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                  .toList(),
              onChanged: (t) => setState(() {
                selectedType = t!;
                selectedPort = defaultPorts[t]!;
              }),
            ),
            // IP field with inline validation error
            TextField(
              controller: ipController,
              onChanged: (v) => setState(() {
                ipError = ipRegex.hasMatch(v) ? null : 'Invalid IP address';
              }),
              decoration: InputDecoration(errorText: ipError, ...),
            ),
            // Port field (auto-filled, editable)
            TextField(
              controller: TextEditingController(text: '$selectedPort'),
              keyboardType: TextInputType.number,
            ),
          ]),
          actions: [
            ElevatedButton(
              onPressed: ipError == null && ipController.text.isNotEmpty
                  ? () {
                      Navigator.pop(context);
                      final device = Device(
                        id: 'manual-${DateTime.now().millisecondsSinceEpoch}',
                        name: 'Manual Connection',
                        type: selectedType,
                        model: 'Custom IP',
                        signal: 100,
                        ip: ipController.text,
                        port: selectedPort,
                      );
                      ref.read(connectionProvider.notifier).connect(device);
                    }
                  : null,
              child: const Text('Connect'),
            ),
          ],
        );
      });
    },
  );
}
```

#### `lib/screens/remote.dart` — UX Fixes (modified)

```dart
// Power button: fire-and-forget, no local state (Requirement 2.25)
void _sendPower() {
  _sendKey(RemoteKey.power);
  // No setState — no local isPowerOn toggle
}

// Touchpad: delta accumulation with 30px threshold (Requirement 2.24)
Offset _touchpadDelta = Offset.zero;
RemoteKey? _pendingDirection;

GestureDetector(
  onPanUpdate: (details) {
    _touchpadDelta += details.delta;
    final dx = _touchpadDelta.dx.abs();
    final dy = _touchpadDelta.dy.abs();
    if (dx > 30 || dy > 30) {
      final key = dx > dy
          ? (_touchpadDelta.dx > 0 ? RemoteKey.right : RemoteKey.left)
          : (_touchpadDelta.dy > 0 ? RemoteKey.down  : RemoteKey.up);
      setState(() => _pendingDirection = key);
    }
  },
  onPanEnd: (_) {
    if (_pendingDirection != null) _sendKey(_pendingDirection!);
    setState(() { _touchpadDelta = Offset.zero; _pendingDirection = null; });
  },
  onTap: () => _sendKey(RemoteKey.select),
)

// BackdropFilter sigma reduced to 15 (Requirement 2.30)
BackdropFilter(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), ...)

// MUTE rocker replaced with standalone button (Requirement 2.26)
RemoteButton(
  icon: LucideIcons.volumeX,
  label: 'MUTE',
  onTap: () => _sendKey(RemoteKey.mute),
  tooltip: 'Mute',
)

// Semantics on D-pad OK button (Requirement 2.28)
Semantics(
  label: 'OK — confirm selection',
  button: true,
  child: InkWell(onTap: () => _sendKey(RemoteKey.select), ...),
)
```

#### `lib/widgets/remote_buttons.dart` — Accessibility (modified)

```dart
// RemoteButton: wrap with Semantics + add tooltip to IconButton
class RemoteButton extends StatelessWidget {
  final String? tooltip;   // NEW parameter
  // ...

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label ?? tooltip ?? 'Remote button',
      button: true,
      child: Tooltip(
        message: tooltip ?? label ?? '',
        child: Column(children: [
          Material(
            child: InkWell(
              onTap: () { HapticFeedback.lightImpact(); onTap(); },
              // ...
            ),
          ),
          // label text unchanged
        ]),
      ),
    );
  }
}

// RockerButton: Semantics on each half
Semantics(
  label: 'Volume up',
  button: true,
  child: InkWell(onTap: onUp, ...),
)
Semantics(
  label: 'Volume down',
  button: true,
  child: InkWell(onTap: onDown, ...),
)

// AppButton: Semantics wrapper
Semantics(
  label: 'Launch $name',
  button: true,
  child: Material(...),
)
```

---

### Platform Configuration Changes

#### `android/app/src/main/AndroidManifest.xml`

```xml
<!-- Add before existing permissions (Requirement 2.16) -->
<uses-permission
    android:name="android.permission.NEARBY_WIFI_DEVICES"
    android:usesPermissionFlags="neverForLocation" />
```

#### `ios/Runner/Info.plist`

```xml
<!-- Add inside <dict> (Requirement 2.17) -->
<key>NSLocalNetworkUsageDescription</key>
<string>Universal Remote needs local network access to discover and control your smart TV.</string>
<key>NSBonjourServices</key>
<array>
    <string>_roku._tcp</string>
    <string>_samsungtv._tcp</string>
    <string>_smart-tv._tcp</string>
    <string>_samsungbridge._tcp</string>
    <string>_googlecast._tcp</string>
    <string>_airplay._tcp</string>
    <string>_http._tcp</string>
</array>
<!-- Update display name (Requirement 2.33) -->
<key>CFBundleDisplayName</key>
<string>Universal Remote</string>
<key>CFBundleName</key>
<string>universalremote</string>
```

#### `pubspec.yaml`

```yaml
name: devicecontroller
description: "A universal remote control app for Roku, Samsung, LG, and Vizio smart TVs."

dependencies:
  # existing — keep
  flutter_secure_storage: ^10.0.0
  web_socket_channel: ^3.0.3
  http: ^1.2.0
  # new
  connectivity_plus: ^6.1.0
  logger: ^2.4.0

dev_dependencies:
  mockito: ^5.4.4
  build_runner: ^2.4.13
```

---

## Data Flow Diagrams

### Connection Lifecycle (Happy Path)

```
User taps device
      │
      ▼
ConnectionNotifier.connect(device)
      │  state → connecting
      ▼
_buildController(device)  ──── DeviceType switch ────►  RokuController
      │                                                   SamsungController
      │                                                   LgController
      │                                                   VizioController
      │                                                   FireTvController (throws)
      │                                                   GoogleTvController (throws)
      │                                                   IrController
      │                                                   UnsupportedDeviceException
      ▼
controller.connect()
      │  (with exponential backoff: 1s, 2s, 4s, 8s × 4)
      ▼
DevicePersistenceService.saveDevice(device)
      │
      ▼
state → connected
      │
      ▼
HeartbeatTimer (Samsung/LG only)
  30s ──► ping ──► 5s pong timeout ──► reconnect if no pong
```

### Samsung TOFU Flow

```
connect() called
      │
      ▼
Load stored fingerprint from DevicePersistenceService
      │
      ├── No stored fingerprint (first connect)
      │         │
      │         ▼
      │   Accept cert, extract SHA-256, store fingerprint
      │         │
      │         ▼
      │   Listen stream for pairing token → persist token
      │
      └── Stored fingerprint exists
                │
                ▼
          Compare presented cert SHA-256 vs stored
                │
                ├── Match → proceed
                └── Mismatch → throw TofuMismatchException (user-visible error)
```

### Connectivity Lifecycle

```
ConnectivityService
      │
      ├── connectivity_plus stream ──► onConnectivityChanged
      │                                      │
      │                                      ├── result = none
      │                                      │     └── state → error("Wi-Fi lost")
      │                                      │
      │                                      └── result = wifi/mobile (was error)
      │                                            └── ConnectionNotifier.connect(lastDevice)
      │
      └── WidgetsBindingObserver
                │
                └── AppLifecycleState.resumed
                      └── emit wifi event → trigger reconnect check
```

### Manual Connect Dialog Flow

```
User taps "Manual IP"
      │
      ▼
AlertDialog opens
      │
      ├── DeviceType dropdown (Roku/Samsung/LG/Vizio)
      │         └── onChange → auto-fill port (8060/8001/3000/7345)
      │
      ├── IP TextField
      │         └── onChange → validate IPv4/IPv6 regex → show inline error
      │
      └── Connect button (disabled if ipError != null)
                │
                ▼
          Device(type: selectedType, ip: input, port: selectedPort)
                │
                ▼
          ConnectionNotifier.connect(device)
```

---

## Testing Strategy

### Validation Approach

The testing strategy follows the bug condition methodology: first run exploratory tests on
**unfixed** code to surface counterexamples and confirm root causes, then implement fixes and
run fix-checking and preservation-checking tests.

---

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate each bug BEFORE implementing the fix.
Confirm or refute the root cause analysis.

**Test Plan**: Write tests that exercise the defective code paths and assert the expected
(correct) behavior. These tests WILL FAIL on unfixed code — that is the intended outcome.
The failure messages confirm the root cause.

**Test Cases**:

1. **TOFU not enforced** (C1): Connect `SamsungController` to a mock WebSocket server that
   presents a self-signed cert; assert that `badCertificateCallback` is NOT always-true.
   Will fail on unfixed code — callback always returns `true`.

2. **Roku timeout absent** (C18): Call `RokuController.connect()` with a mock `http.Client`
   that never responds; assert the call completes within 5 seconds.
   Will fail on unfixed code — hangs indefinitely.

3. **Controller in state** (C20): Inspect `DeviceConnectionState` after a successful connect;
   assert it has no `controller` field.
   Will fail on unfixed code — `controller` field exists.

4. **sendText unbounded** (C3): Call `SamsungController.sendText('x' * 600)`; capture the
   WebSocket message and assert the encoded string represents ≤ 500 characters.
   Will fail on unfixed code — full 600-char string is transmitted.

5. **Unknown type silent fallback** (C8): Call `_buildController` with `DeviceType.unknown`;
   assert `UnsupportedDeviceException` is thrown.
   Will fail on unfixed code — `RokuController` is returned silently.

6. **Duplicate device filtering** (C8/scanner): Add two devices with identical `ip+port`;
   assert `ScannerState.devices.length == 1`.
   Will pass on unfixed code (deduplication already exists) — confirms preservation.

**Expected Counterexamples**:
- `SamsungController.connect()` accepts any certificate without pinning
- `RokuController.connect()` never times out on unreachable host
- `DeviceConnectionState` contains a live `DeviceController` object
- `sendText` transmits strings longer than 500 characters

---

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed code produces
the expected behavior.

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition(input) DO
  result := fixedFunction(input)
  ASSERT expectedBehavior(result)
END FOR
```

**Key assertions per property:**

| Property | Input | Assertion |
|----------|-------|-----------|
| P1 (TOFU) | First WSS connect | `fingerprintStored == true` |
| P1 (TOFU) | Second WSS connect, different cert | `ConnectionRejected` thrown |
| P3 (Roku timeout) | Unreachable host | `TimeoutException` within 3 s |
| P5 (state machine) | Any connect call | `DeviceConnectionState` has no `controller` field |
| P7 (persistence) | Successful connect | `DevicePersistenceService.loadDevice()` returns same device |
| P9 (unsupported) | `DeviceType.unknown` | `UnsupportedDeviceException` thrown |
| P10 (truncation) | `sendText('x' * 600)` | Transmitted payload ≤ 500 chars |

---

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed code
produces the same result as the original code.

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT originalFunction(input) = fixedFunction(input)
END FOR
```

**Testing Approach**: Property-based testing is used for preservation because:
- It generates many random inputs automatically across the full input domain
- It catches edge cases that manual unit tests miss
- It provides strong guarantees that behavior is unchanged for all non-buggy inputs

**Test Cases**:

1. **Roku ECP preservation**: For any `RemoteKey` value, the fixed `RokuController.sendKey`
   SHALL POST to the same `/keypress/{key}` path as the original. Verified with mock
   `http.Client` capturing requests.

2. **Samsung key payload preservation**: For any `RemoteKey` value, the fixed
   `SamsungController.sendKey` SHALL produce the same `ms.remote.control` JSON as the
   original. Verified with mock WebSocket sink.

3. **State machine transition preservation**: For any `(fromState, event)` pair, the fixed
   `ConnectionNotifier` SHALL produce the same `ConnectionStatus` transitions as the original.
   Verified with `ProviderContainer` in tests.

4. **Device JSON round-trip**: For any `Device` object, `Device.fromJson(device.toJson())`
   SHALL equal the original device. Verified with property-based test over random devices.

5. **Duplicate filtering preservation**: For any two devices with the same `ip+port`, the
   scanner SHALL contain exactly one entry. Verified with unit test.

---

### Unit Tests

#### `test/controllers/roku_controller_test.dart`

```dart
// Uses mockito-generated MockClient from http package

group('RokuController', () {
  late MockClient mockClient;
  late RokuController controller;

  setUp(() {
    mockClient = MockClient();
    controller = RokuController(host: '192.168.1.100', client: mockClient);
  });

  test('connect() succeeds when device-info returns 200', () async { ... });
  test('connect() throws TimeoutException after 3s on unreachable host', () async { ... });
  test('sendKey(up) POSTs to /keypress/Up', () async { ... });
  test('sendKey(channelUp) POSTs to /keypress/ChannelUp', () async { ... });
  test('sendText sends one Lit_ keypress per character', () async { ... });
  test('launchApp(AppId.netflix) POSTs to /launch/12', () async { ... });
  test('launchApp with unknown AppId surfaces error', () async { ... });
  test('sendKey is no-op when not connected', () async { ... });
  test('all HTTP calls apply 3-second timeout', () async { ... });
});
```

#### `test/controllers/samsung_controller_test.dart`

```dart
// Uses mockito-generated MockWebSocketChannel

group('SamsungController', () {
  late MockDevicePersistenceService mockPersistence;
  late MockWebSocketSink mockSink;

  test('connect() stores fingerprint on first WSS connection', () async { ... });
  test('connect() rejects mismatched fingerprint on second connection', () async { ... });
  test('connect() persists pairing token from stream', () async { ... });
  test('sendKey(mute) sends KEY_MUTE in ms.remote.control payload', () async { ... });
  test('sendText truncates to 500 chars', () async {
    final text = 'x' * 600;
    await controller.sendText(text);
    final captured = mockSink.capturedMessages.last;
    final decoded = base64Decode(jsonDecode(captured)['params']['Cmd']);
    expect(utf8.decode(decoded).length, equals(500));
  });
  test('heartbeat sends ping every 30s', () async { ... });
  test('pong timeout triggers reconnect after 5s', () async { ... });
  test('exponential backoff retries up to 4 times', () async { ... });
});
```

#### `test/providers/connection_notifier_test.dart`

```dart
group('ConnectionNotifier', () {
  test('state machine: disconnected → connecting → connected on success', () async { ... });
  test('state machine: disconnected → connecting → error on failure', () async { ... });
  test('no direct disconnected → connected transition', () async { ... });
  test('DeviceConnectionState does not contain DeviceController', () {
    final state = DeviceConnectionState(status: ConnectionStatus.connected, device: mockDevice);
    expect(state, isNot(contains(isA<DeviceController>())));
  });
  test('unknown DeviceType throws UnsupportedDeviceException', () async { ... });
  test('auto-reconnect on app resume', () async { ... });
  test('connectivity loss sets error state', () async { ... });
  test('exponential backoff: 4 retries before permanent error', () async { ... });
});
```

#### `test/providers/scanner_notifier_test.dart`

```dart
group('ScannerNotifier', () {
  test('duplicate device by ip+port is filtered', () async {
    final notifier = ScannerNotifier();
    notifier.addDevice(Device(ip: '192.168.1.1', port: 8060, ...));
    notifier.addDevice(Device(ip: '192.168.1.1', port: 8060, ...));
    expect(notifier.state.devices.length, equals(1));
  });
  test('devices with same ip but different port are both added', () async { ... });
  test('SSDP sends 3 M-SEARCH packets', () async { ... });
  test('SSDP listen window is 8 seconds', () async { ... });
});
```

---

### Property-Based Tests

```dart
// Using dart_test with custom generators

// Property: Device JSON round-trip (Property 7)
test('Device.fromJson(device.toJson()) == device for any device', () {
  for (final device in generateRandomDevices(count: 1000)) {
    expect(Device.fromJson(device.toJson()), equals(device));
  }
});

// Property: State machine no illegal transitions (Property 5)
test('No direct disconnected → connected transition', () {
  for (final event in generateRandomEvents(count: 500)) {
    final next = transition(ConnectionStatus.disconnected, event);
    expect(next, isNot(equals(ConnectionStatus.connected)));
  }
});

// Property: Roku key dispatch — exactly one HTTP call per sendKey (Property 4)
test('sendKey produces exactly one POST request', () async {
  for (final key in RemoteKey.values) {
    final callCount = await countHttpCalls(() => controller.sendKey(key));
    expect(callCount, equals(1));
  }
});

// Property: Duplicate filtering (Property 8)
test('Adding N duplicates results in 1 device', () {
  for (final n in [2, 5, 10, 100]) {
    final notifier = ScannerNotifier();
    for (int i = 0; i < n; i++) {
      notifier.addDevice(Device(ip: '10.0.0.1', port: 8060, ...));
    }
    expect(notifier.state.devices.length, equals(1));
  }
});
```

---

### Integration Tests

- **Full Roku flow**: Discover → connect → sendKey → launchApp → disconnect, with mock HTTP server
- **Samsung TOFU flow**: First connect (pin cert) → disconnect → second connect (same cert, pass)
  → third connect (different cert, reject)
- **Connectivity drop and reconnect**: Simulate Wi-Fi loss → verify error state → simulate
  Wi-Fi restore → verify auto-reconnect attempt
- **Manual connect dialog**: Open dialog → select Samsung → verify port auto-fills to 8001 →
  enter invalid IP → verify error shown → enter valid IP → connect
- **Touchpad delta accumulation**: Simulate slow pan < 30px → verify no key sent → continue
  pan past 30px → verify correct directional key sent
- **Accessibility**: Run `SemanticsController` over remote screen → verify all interactive
  widgets have non-empty semantic labels

---
