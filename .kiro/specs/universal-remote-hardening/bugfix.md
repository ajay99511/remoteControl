# Bugfix Requirements Document

## Introduction

The `devicecontroller` Flutter app is a universal TV remote for the USA market. A comprehensive pre-mortem audit identified 28 concrete defects spanning security vulnerabilities, missing platform support, broken UX patterns, architectural flaws, missing permissions, absent tests, and market-fit gaps. Left unaddressed, these defects make the app insecure (TLS MITM), non-functional for ~62% of the USA smart TV market (LG, Vizio, Fire TV, Google TV, IR-only TVs), unreliable (no reconnect, no heartbeat, no timeouts), inaccessible (zero screen-reader support), and untested (template test file). This document captures the current defective behavior, the required correct behavior, and the existing behavior that must be preserved without regression.

---

## Bug Analysis

### Current Behavior (Defect)

**Security**

1.1 WHEN the app connects to a Samsung TV over WSS (port 8002) THEN the system accepts any TLS certificate unconditionally because `badCertificateCallback` always returns `true`, exposing all WebSocket traffic to man-in-the-middle attacks

1.2 WHEN a Samsung TV's pairing token is received over the WebSocket stream THEN the system discards it silently because the WebSocket stream is never listened to and the token is never stored

1.3 WHEN `sendText` is called on `SamsungController` with a string longer than 500 characters THEN the system encodes and transmits the full string without any length guard, risking protocol errors and potential denial-of-service

**Platform Coverage**

1.4 WHEN a user owns an LG webOS TV THEN the system has no `LgController` implementation and cannot connect to or control the device

1.5 WHEN a user owns a Vizio SmartCast TV THEN the system has no `VizioController` implementation and cannot connect to or control the device

1.6 WHEN a user owns an Amazon Fire TV THEN the system has no `FireTvController` implementation and cannot connect to or control the device

1.7 WHEN a user owns a Google TV or Android TV THEN the system has no `GoogleTvController` implementation and cannot connect to or control the device

1.8 WHEN a device type is not `roku` or `samsung` THEN the system silently falls back to `RokuController` with no error, causing silent failures and misleading the user

1.9 WHEN the device has a hardware IR blaster (Android) THEN the system has no `IrController`, no IR package dependency, and no IR code database, making it impossible to control non-smart TVs or TV hardware volume

**State Persistence**

1.10 WHEN the app is closed and reopened THEN the system does not restore the last connected device because no device is ever written to `flutter_secure_storage`, forcing the user to re-scan every session

1.11 WHEN `flutter_secure_storage` is present in `pubspec.yaml` THEN the system never reads or writes to it anywhere in the codebase, making it dead weight

**Network Lifecycle**

1.12 WHEN the device's Wi-Fi connection drops while the app is open THEN the system does not detect the change because `connectivity_plus` is not a dependency and no network listener exists

1.13 WHEN the app is resumed from the background THEN the system does not attempt to reconnect because no `WidgetsBindingObserver` is implemented

1.14 WHEN a Samsung or LG WebSocket connection goes idle THEN the system sends no heartbeat ping, allowing the TV to silently close the connection without the app knowing

1.15 WHEN a connection attempt fails THEN the system does not retry because no exponential backoff reconnect logic exists

**Permissions**

1.16 WHEN the app runs on Android 13+ and attempts Wi-Fi device discovery THEN the system is missing `NEARBY_WIFI_DEVICES` from `AndroidManifest.xml`, causing discovery to fail silently or be denied by the OS

1.17 WHEN the app runs on iOS and attempts local network communication THEN the system is missing `NSLocalNetworkUsageDescription` and `NSBonjourServices` from `Info.plist`, causing iOS to block local network access without a user-facing explanation

**Protocol Correctness**

1.18 WHEN all Roku HTTP calls (`connect`, `sendKey`, `sendText`, `launchApp`) are made THEN the system applies no timeout to the HTTP requests, allowing them to block indefinitely on an unreachable device

1.19 WHEN SSDP discovery runs THEN the system sends a single UDP M-SEARCH packet and listens for only 5 seconds, missing devices that respond slowly or require multiple probes

**Architecture**

1.20 WHEN `DeviceConnectionState` is constructed THEN the system stores a mutable `DeviceController` object directly inside the Riverpod state class, violating the principle that Riverpod state should contain only serializable, immutable data

1.21 WHEN a user manually enters an IP address THEN the system hardcodes `type: 'roku'` and `port: 8060` with no device-type selector, making it impossible to manually connect to Samsung, LG, or Vizio devices

1.22 WHEN a user manually enters an IP address THEN the system performs no IPv4 or IPv6 format validation, allowing malformed addresses to reach the network layer

1.23 WHEN `launchApp` is called with an app name not in the static map THEN the system silently returns without launching and without surfacing any error to the user; app identifiers are raw strings with no enum safety

**UX / UI**

1.24 WHEN the user swipes on the touchpad THEN the system uses only final velocity to determine direction, producing unreliable gesture recognition for slow or short swipes that have low terminal velocity

1.25 WHEN the power button is tapped THEN the system toggles a local `isPowerOn` boolean that has no relationship to the TV's actual power state, creating a misleading UI indicator

1.26 WHEN the MUTE rocker's top half is pressed THEN the system sends `RemoteKey.volumeUp` instead of a mute command, making the top of the MUTE rocker a duplicate volume-up button

1.27 WHEN the scanner screen selects a device THEN the system calls `connectionProvider.notifier.connect()` directly from the scanner widget, tightly coupling discovery UI to connection logic

**Accessibility**

1.28 WHEN a screen reader (TalkBack / VoiceOver) navigates the remote screen THEN the system provides no `Semantics` labels or `tooltip` values on any interactive widget in `remote_buttons.dart` or `remote.dart`, making the app completely inaccessible

**Key Coverage**

1.29 WHEN a user needs to press channel up/down, info, menu, search, input source, subtitles, sleep, replay, star, instant replay, exit, OK, record, guide, aspect ratio, PiP, audio track, or settings THEN the system cannot send these commands because `RemoteKey` enum contains only 14 values and all 19 standard keys are absent

**Performance**

1.30 WHEN the remote screen renders THEN the system applies `BackdropFilter` with `sigmaX: 80, sigmaY: 80` to the entire screen background, causing excessive GPU load on mid-range and low-end devices

**Logging**

1.31 WHEN any controller or provider encounters an error or notable event THEN the system uses unstructured `debugPrint` calls with no log levels, making it impossible to filter, aggregate, or suppress logs in production

**Type Safety**

1.32 WHEN `Device.type` is compared throughout the codebase THEN the system uses raw string literals (`'roku'`, `'samsung'`, `'wifi'`) with no compile-time safety, making typos and missing cases silent bugs

**Metadata**

1.33 WHEN the app is published to the App Store or Play Store THEN the system displays `"A new Flutter project."` as the pubspec description, `"Devicecontroller"` as the iOS display name, and `"devicecontroller"` as the app name — all template placeholders that are unprofessional and misleading

**Testing**

1.34 WHEN the test suite runs THEN the system executes a Flutter counter template test that imports `MyApp` and asserts counter widget behavior, testing nothing in this application and providing zero regression coverage

---

### Expected Behavior (Correct)

**Security**

2.1 WHEN the app connects to a Samsung TV over WSS for the first time THEN the system SHALL extract the server certificate's SHA-256 fingerprint, store it in `flutter_secure_storage` keyed by host, and accept the connection (Trust-On-First-Use); on subsequent connections to the same host the system SHALL compare the presented fingerprint against the stored one and reject the connection with a user-visible error if they differ

2.2 WHEN a Samsung TV sends a pairing token over the WebSocket stream THEN the system SHALL listen to the stream, parse the token from the JSON response, and persist it in `flutter_secure_storage` so it can be sent on subsequent connection attempts

2.3 WHEN `sendText` is called on `SamsungController` with a string longer than 500 characters THEN the system SHALL truncate the input to 500 characters before encoding and transmitting

**Platform Coverage**

2.4 WHEN a user owns an LG webOS TV THEN the system SHALL provide an `LgController` that connects via WebSocket on port 3000, implements the webOS pairing PIN flow, and maps all `RemoteKey` values to the correct SSAP commands

2.5 WHEN a user owns a Vizio SmartCast TV THEN the system SHALL provide a `VizioController` that communicates with the SmartCast REST API on port 7345 and maps all `RemoteKey` values to the correct SmartCast commands

2.6 WHEN a user owns an Amazon Fire TV THEN the system SHALL provide a `FireTvController` stub that exposes the `DeviceController` interface and returns a clear "not yet supported" error on `connect()`

2.7 WHEN a user owns a Google TV or Android TV THEN the system SHALL provide a `GoogleTvController` stub that exposes the `DeviceController` interface and returns a clear "not yet supported" error on `connect()`

2.8 WHEN a device type is not recognized THEN the system SHALL fail with an explicit `UnsupportedDeviceException` that surfaces a user-visible error message; the silent Roku fallback SHALL be removed

2.9 WHEN the device has a hardware IR blaster (Android) THEN the system SHALL provide an `IrController` that uses a native IR plugin, includes an IR code database for Samsung, LG, Vizio, Sony, and TCL USA brands, and maps all applicable `RemoteKey` values to the correct IR codes

**State Persistence**

2.10 WHEN a device connection is successfully established THEN the system SHALL serialize the `Device` to JSON and write it to `flutter_secure_storage` under a well-known key; on app launch the system SHALL read this key, deserialize the device, and attempt auto-reconnect

2.11 WHEN `flutter_secure_storage` is used THEN the system SHALL use it exclusively for device persistence (finding 2.10), TOFU certificate storage (finding 2.1), and Samsung pairing token storage (finding 2.2); the dependency SHALL NOT remain unused

**Network Lifecycle**

2.12 WHEN the device's Wi-Fi connection drops THEN the system SHALL detect the change via `connectivity_plus`, update the connection state to `error`, and display a user-visible reconnect prompt

2.13 WHEN the app is resumed from the background THEN the system SHALL attempt to reconnect to the last connected device via `WidgetsBindingObserver.didChangeAppLifecycleState`

2.14 WHEN a Samsung or LG WebSocket connection is idle for more than 30 seconds THEN the system SHALL send a WebSocket ping frame; if no pong is received within 5 seconds the system SHALL mark the connection as lost and trigger reconnect

2.15 WHEN a connection attempt fails THEN the system SHALL retry using exponential backoff (1 s, 2 s, 4 s, 8 s) up to a maximum of 4 retries before surfacing a permanent error to the user

**Permissions**

2.16 WHEN the app runs on Android 13+ THEN `AndroidManifest.xml` SHALL declare `<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" android:usesPermissionFlags="neverForLocation"/>` so Wi-Fi device discovery is permitted by the OS

2.17 WHEN the app runs on iOS THEN `Info.plist` SHALL contain `NSLocalNetworkUsageDescription` with a user-facing explanation and an `NSBonjourServices` array listing all mDNS service types used by the app

**Protocol Correctness**

2.18 WHEN any Roku HTTP call (`connect`, `sendKey`, `sendText`, `launchApp`) is made THEN the system SHALL apply a 3-second timeout; if the timeout expires the system SHALL throw a `TimeoutException` that is caught and surfaced to the user

2.19 WHEN SSDP discovery runs THEN the system SHALL send the M-SEARCH packet 3 times with 500 ms intervals and keep the listen window open for 8 seconds to capture slow-responding devices

**Architecture**

2.20 WHEN `DeviceConnectionState` is defined THEN the system SHALL hold only serializable data (status, device, errorMessage); the `DeviceController` instance SHALL be a private field on `ConnectionNotifier`, not part of the state object

2.21 WHEN a user manually enters an IP address THEN the system SHALL present a device-type dropdown (Roku / Samsung / LG / Vizio) and SHALL auto-populate the default port for the selected type (8060 / 8001 / 3000 / 7345)

2.22 WHEN a user submits a manual IP address THEN the system SHALL validate the input against an IPv4 and IPv6 regex before attempting connection and SHALL display an inline validation error for malformed addresses

2.23 WHEN `launchApp` is called THEN the system SHALL use a typed `AppId` enum for app identifiers; if the app is not found the system SHALL surface a user-visible error message rather than silently returning

**UX / UI**

2.24 WHEN the user swipes on the touchpad THEN the system SHALL accumulate delta displacement throughout the gesture and fire a directional key only when the accumulated displacement exceeds a 30 px minimum threshold in the dominant axis; the system SHALL display a visual directional indicator during the swipe

2.25 WHEN the power button is tapped THEN the system SHALL send `RemoteKey.power` as a fire-and-forget command with no local state toggle; the power button SHALL have no active/inactive visual state tied to a local boolean

2.26 WHEN the MUTE button is needed THEN the system SHALL replace the MUTE rocker with a standalone mute toggle button that sends `RemoteKey.mute` on tap

2.27 WHEN the scanner screen selects a device THEN the system SHALL emit the selected device through a callback or coordinator; the connection logic SHALL reside in `ConnectionNotifier`, not be invoked directly from the scanner widget

**Accessibility**

2.28 WHEN a screen reader navigates the remote screen THEN every interactive widget in `remote_buttons.dart` and `remote.dart` SHALL have a `Semantics` wrapper with a descriptive label, and every `IconButton` SHALL have a `tooltip` value

**Key Coverage**

2.29 WHEN a user needs to press any standard TV key THEN the system SHALL support all of the following in the `RemoteKey` enum in addition to the existing 14 keys: `channelUp`, `channelDown`, `info`, `menu`, `search`, `inputSource`, `subtitles`, `sleep`, `replay`, `star`, `instantReplay`, `exit`, `ok`, `record`, `guide`, `aspectRatio`, `pip`, `audioTrack`, `settings`

**Performance**

2.30 WHEN the remote screen renders THEN the system SHALL use a `BackdropFilter` sigma of ≤ 20 or replace the blur with a static gradient overlay to reduce GPU load on mid-range devices

**Logging**

2.31 WHEN any controller or provider logs an event THEN the system SHALL use the `logger` package with structured log levels (verbose, debug, info, warning, error); all `debugPrint` calls SHALL be replaced

**Type Safety**

2.32 WHEN `Device.type` is used THEN the system SHALL use a `DeviceType` enum with values for each supported platform; all raw string comparisons SHALL be replaced with enum comparisons

**Metadata**

2.33 WHEN the app is published THEN `pubspec.yaml` SHALL have a meaningful description and app name, `CFBundleDisplayName` in `Info.plist` SHALL be `"Universal Remote"`, and `CFBundleName` SHALL be `"universalremote"`

**Testing**

2.34 WHEN the test suite runs THEN the system SHALL execute meaningful unit tests covering: `RokuController` key dispatch and timeout behavior (with a mocked `http.Client`), `SamsungController` WebSocket message format and TOFU fingerprint logic (with a mocked WebSocket), `ConnectionNotifier` state machine transitions, and `ScannerNotifier` duplicate-device filtering

---

### Unchanged Behavior (Regression Prevention)

**Roku ECP**

3.1 WHEN a Roku device is discovered via mDNS or SSDP and the user taps it THEN the system SHALL CONTINUE TO connect via HTTP ECP on port 8060 and send key presses as POST requests to `/keypress/{key}`

3.2 WHEN `RokuController.launchApp` is called with a known app name THEN the system SHALL CONTINUE TO POST to `/launch/{appId}` using the existing app-ID map

3.3 WHEN `RokuController.sendText` is called THEN the system SHALL CONTINUE TO send one `Lit_<encoded-char>` keypress per character

**Samsung WebSocket**

3.4 WHEN a Samsung TV is discovered and the user taps it THEN the system SHALL CONTINUE TO attempt WSS on port 8002 first, then fall back to WS on port 8001

3.5 WHEN `SamsungController.sendKey` is called THEN the system SHALL CONTINUE TO send the `ms.remote.control` JSON payload with `Cmd: "Click"` and the mapped key string

3.6 WHEN `SamsungController.launchApp` is called with a known app name THEN the system SHALL CONTINUE TO send the `ms.channel.emit` / `ed.apps.launch` payload

**Device Discovery**

3.7 WHEN the scanner screen opens THEN the system SHALL CONTINUE TO start mDNS discovery automatically and display a scanning animation

3.8 WHEN mDNS discovers a device THEN the system SHALL CONTINUE TO deduplicate by `ip + port` before adding to the device list

3.9 WHEN SSDP discovers a device THEN the system SHALL CONTINUE TO parse the `SERVER` and `LOCATION` headers to identify Roku and Samsung devices

3.10 WHEN the user taps "Rescan" THEN the system SHALL CONTINUE TO stop the current scan and start a fresh one

**Connection State Machine**

3.11 WHEN `ConnectionNotifier.connect` is called THEN the system SHALL CONTINUE TO transition through `disconnected → connecting → connected` on success and `disconnected → connecting → error` on failure; no direct `disconnected → connected` transition is permitted

3.12 WHEN `ConnectionNotifier.disconnect` is called THEN the system SHALL CONTINUE TO call `controller.disconnect()` and reset state to `disconnected`

**Remote UI**

3.13 WHEN the remote screen is open and the connection is active THEN the system SHALL CONTINUE TO display the device name, a green connected indicator, and the three tab modes (Navigation, Touchpad, Numpad)

3.14 WHEN the user taps a D-pad direction, Back, Home, or Play/Pause THEN the system SHALL CONTINUE TO call `sendKey` with the corresponding `RemoteKey` and trigger haptic feedback

3.15 WHEN the user taps a numpad digit THEN the system SHALL CONTINUE TO call `sendText` with that digit

3.16 WHEN the user taps an app shortcut (Netflix, YouTube, Prime Video, Disney+) THEN the system SHALL CONTINUE TO call `launchApp` with the app name

3.17 WHEN the keyboard overlay is open and the user submits text THEN the system SHALL CONTINUE TO call `sendText` with the entered string and dismiss the overlay

**Mock Controller**

3.18 WHEN a device whose ID starts with `mock-` is connected THEN the system SHALL CONTINUE TO use `MockController` with simulated delays and `debugPrint` logging

**Haptic Feedback**

3.19 WHEN any remote button is tapped THEN the system SHALL CONTINUE TO trigger `HapticFeedback.lightImpact()` or `HapticFeedback.mediumImpact()` as appropriate

**Volume Rocker**

3.20 WHEN the VOL rocker's top half is pressed THEN the system SHALL CONTINUE TO send `RemoteKey.volumeUp`; when the bottom half is pressed the system SHALL CONTINUE TO send `RemoteKey.volumeDown`

---

## Bug Condition Pseudocode

### C1 — Samsung TLS MITM

```pascal
FUNCTION isBugCondition_C1(connection)
  INPUT: connection of type SamsungWssConnection
  OUTPUT: boolean
  RETURN connection.badCertificateCallback = ALWAYS_TRUE
END FUNCTION

// Fix Checking
FOR ALL conn WHERE isBugCondition_C1(conn) DO
  result ← connectWithTofu(conn)
  ASSERT result.fingerprintStored = true
  ASSERT result.mismatchRejected = true WHEN fingerprint differs
END FOR

// Preservation Checking
FOR ALL conn WHERE NOT isBugCondition_C1(conn) DO
  ASSERT connectWithTofu(conn) = connect_original(conn)
END FOR
```

### C4 — Zero State Persistence

```pascal
FUNCTION isBugCondition_C4(session)
  INPUT: session of type AppSession
  OUTPUT: boolean
  RETURN session.lastDevice NOT IN secureStorage
END FUNCTION

// Fix Checking
FOR ALL session WHERE isBugCondition_C4(session) DO
  connectAndClose(session)
  result ← readSecureStorage(LAST_DEVICE_KEY)
  ASSERT result = session.device.toJson()
END FOR
```

### Correctness Properties (PBT)

```pascal
// Property 1: Connection state machine — no illegal transitions
FOR ALL (fromState, event) DO
  nextState ← transition(fromState, event)
  ASSERT NOT (fromState = disconnected AND nextState = connected)
END FOR

// Property 2: Key delivery — exactly one network command per sendKey
FOR ALL key WHERE isConnected = true DO
  commandsBefore ← networkCommandCount()
  sendKey(key)
  ASSERT networkCommandCount() = commandsBefore + 1
END FOR

// Property 3: Device persistence round-trip
FOR ALL device OF type Device DO
  json ← device.toJson()
  restored ← Device.fromJson(json)
  ASSERT restored = device
END FOR

// Property 4: Duplicate device filtering
FOR ALL (device1, device2) WHERE device1.ip = device2.ip AND device1.port = device2.port DO
  addDevice(device1)
  addDevice(device2)
  ASSERT deviceList.count(d => d.ip = device1.ip AND d.port = device1.port) = 1
END FOR

// Property 5: Timeout enforcement
FOR ALL operation IN {sendKey, connect} DO
  startTime ← now()
  result ← operation() // on unreachable device
  elapsed ← now() - startTime
  ASSERT elapsed <= 5000ms OR result = TimeoutException
END FOR

// Property 6: TOFU fingerprint rejection
FOR ALL host DO
  storeFingerprint(host, fingerprintA)
  result ← connectWithFingerprint(host, fingerprintB) WHERE fingerprintB ≠ fingerprintA
  ASSERT result = ConnectionRejected
END FOR
```
