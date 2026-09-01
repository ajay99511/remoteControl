# Universal Remote (`devicecontroller`)

A Flutter app that turns a phone into a remote control for smart TVs on the
same Wi-Fi network. Discovers devices over mDNS/NSD and SSDP, then speaks each
vendor's own control protocol.

## Device support

| Vendor | Transport | Status |
|---|---|---|
| **Roku** | ECP over HTTP, port 8060 | Working — keys, text entry, app launch |
| **Samsung** (Tizen) | WebSocket, `wss://` 8002 with TOFU pinning, `ws://` 8001 legacy | Working — keys, text entry, app launch |
| **LG** (webOS) | SSAP over WebSocket, port 3000, plus the pointer input socket | Working — volume, channel, playback, app launch, and the D-pad. webOS carries the arrows on a second socket requested at registration; OK goes the same way, since `sendEnterKey` is an IME operation that does nothing without a focused text field. A TV that will not grant the socket keeps OK on the IME path and reports the arrows as unsupported. Unverified against real hardware. |
| **Vizio** (SmartCast) | REST over TLS, port 7345, TOFU pinning | Partial — key commands work. Text entry and app launch report unsupported: SmartCast exposes no text endpoint on this API, and app launch needs per-app payloads this controller does not carry. Pairing (PIN entry) is not implemented, so a TV that has never been paired returns 401 and reports that it needs pairing. |
| **Fire TV** | — | Not implemented. Reports unsupported. |
| **Google TV / Android TV** | — | Not implemented. Reports unsupported. Note that discovery maps every `_googlecast._tcp` responder here, so ordinary Chromecasts appear and cannot be controlled. |
| **IR blaster** | Android `ConsumerIrManager` | Not implemented. There is no platform channel; `connect()` refuses rather than presenting a remote that transmits nothing. |

Discovered devices are named from their own UPnP / ECP description, so the
list shows what the owner called the TV rather than a generic vendor label.
Identity comes from the SSDP `USN` or the description's `UDN`, so a DHCP lease
renewal does not orphan the pairing token or the certificate pin.

## Remembering devices

Devices you have connected to are kept in a bounded most-recently-used list
(8) in secure storage, keyed on that stable identity rather than the address.
They appear on the discovery screen immediately, before any probe has been
answered, marked **Saved** until this scan hears from them.

If a remembered device has moved — a DHCP lease renewal is the ordinary case —
a connect attempt re-resolves it once over SSDP before spending its retry
budget, and accepts only a response whose stable id matches. Without that, a
television that was powered on and two addresses away produced fifteen seconds
of backoff and "could not connect".

## Architecture

```
lib/
  controllers/     one adapter per vendor behind DeviceController
  providers/       Riverpod notifiers: connection state, discovery
  services/        secure storage, connectivity
  screens/         discovery and remote UI
  models/          Device, RemoteKey, AppId, CommandResult
  exceptions/      typed, non-retryable failure kinds
```

Two ideas carry most of the design:

- **`DeviceController`** is the seam between the app and each vendor's wire
  protocol. Commands return a `CommandResult` rather than `void`, so an
  unsupported key, a dead session and a delivered command are distinguishable
  by the caller — the UI reports each differently instead of confirming all
  three with a haptic.
- **`Stream<ControllerHealth> health`** lets a transport report session loss
  the app did not ask for. Without it, a heartbeat timeout tore the session
  down inside the controller and the UI kept showing "CONNECTED".

There is deliberately no Domain/Repository/UseCase layer. With no server, no
business rules beyond key mapping and one key-value blob of persistence, those
layers would have nothing in them.

## Running

```bash
flutter pub get
flutter run
```

Regenerate mocks after changing a class that tests mock:

```bash
dart run build_runner build
```

## Verification

The same three commands CI runs:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-warnings --fatal-infos
flutter test --coverage
```

`analysis_options.yaml` promotes several lints to errors — `dead_code`,
`unawaited_futures`, `cancel_subscriptions` — because each one would have
caught a defect that shipped. See `AUDIT_AND_STANDARDS_ANALYSIS.md`.

## Known release blockers

1. **`applicationId` is still `com.example.devicecontroller`**
   (`android/app/build.gradle.kts`). Google Play rejects `com.example.*`. This
   needs a real organisation identifier before any release, and it is not a
   choice this codebase should guess.
2. **No crash reporting.** `installErrorHandlers()` routes uncaught errors to
   the logger and marks the seam where a reporter attaches, but nothing
   collects them off-device.
3. **No force-upgrade path.** There is no version gate or remote config, so a
   bad build cannot be superseded remotely.
4. **Vizio pairing (PIN entry) is not implemented.** An unpaired TV is
   correctly reported as needing pairing, but there is no flow to complete it.

## Permissions

- Android: `NEARBY_WIFI_DEVICES`, `INTERNET`, `ACCESS_NETWORK_STATE`,
  `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`
- iOS: `NSLocalNetworkUsageDescription` plus `NSBonjourServices` for all seven
  discovered service types

Discovery degrades to SSDP only if the nearby-devices permission is denied.
