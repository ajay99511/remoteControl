# Comprehensive Code Quality & Architectural Audit: Universal Remote (`devicecontroller`)

> **Scope note.** The audit brief named the artifact "DayVault" and pointed its first path at
> `chronos_planner`; every other instruction, and the working repository, is
> `C:\Users\ajaye\My_Products\devicecontroller` (pubspec `name: devicecontroller`, display name
> "Universal Remote"). This report audits the repository that actually exists at that path. The
> section structure required by the brief is preserved verbatim; only the product name is corrected.
>
> **Baseline of record:** `C:\agents\agentresearchs\plans\engineering-skills\skills\engineering-standards\`
> (`SKILL.md` + 9 reference files, 1,241 lines), read in full before any source file was opened.
>
> **Evidence commands run** (no source file was modified during this audit):
>
> | Command | Result |
> |---|---|
> | `flutter analyze` | **15 issues** (5 in `lib/`, 10 in `test/`), 26.3 s |
> | `flutter test` | **20 tests, all passing**, ~3 s reported / ~30 s wall clock |
> | `flutter test --coverage` | **385 / 1,415 lines = 27.2 %** |
> | `grep -c Semantics lib/screens/device_scanner.dart` | **0** |
> | `ls .github` | *No such file or directory* |

---

## 1. Executive Summary & Quality Scorecard

### High-level health assessment

`devicecontroller` is a ~3,900-line single-module Flutter app that controls smart TVs over four LAN
protocols (Roku ECP, Samsung Tizen WSS, LG SSAP, Vizio SmartCast) plus two stubs and an IR path. It
is architecturally *coherent for its size*: one `DeviceController` interface
(`lib/controllers/device_controller.dart:9-27`), one adapter per vendor, two Riverpod `Notifier`s,
two injected services, typed enums instead of stringly-typed keys.

Measured against `design-judgment.md` §6 — "Cargo-cult layering: Repository → service → controller
with zero logic in two of them" — the deliberate absence of a Domain/UseCase/Repository stack is
**correct, not a gap**. The `DeviceController` abstraction passes all five gates of the Abstraction
Decision Procedure: seven concrete implementations exist, they vary for the same reason (wire
protocol), the axis abstracted is the volatile one, and it reduces concepts at the call site rather
than adding layers. This should be preserved, not "improved".

The problem is not the shape of the code. It is that **the hardening pass recorded in commit
`793e846` was never verified against a real device or a real assertion**, and several of its
headline claims are contradicted by the code that shipped:

- The WebSocket heartbeat added to Samsung and LG contains an **unreachable branch** that makes a
  disconnect at T+35 s mathematically certain on every connection (Finding **C-1**).
- The TOFU certificate pinning added to Samsung is **bypassed by the plaintext fallback immediately
  below it** — a pin mismatch downgrades to `ws://` instead of failing closed (Finding **C-2**).
- The commit claims "full Semantics and tooltip support for all interactive elements"; the discovery
  screen contains **zero** `Semantics` widgets (Finding **H-8**).
- The commit claims a "Comprehensive Test Suite"; measured coverage is **27.2 %**, with
  `lib/screens/remote.dart` (388 executable lines), `lib/controllers/lg_controller.dart` (76) and
  `lib/controllers/vizio_controller.dart` (41) at **0.0 %**, and one test whose entire body is
  comments (Finding **H-9**).

This is the failure mode `SKILL.md` names under **Non-negotiables → "Evidence, not assertion."** The
codebase is not badly designed; it is **unverified**, and the unverified parts are precisely the
security and reliability parts.

The second systemic issue is **silent failure**. Every command path — `sendKey`, `sendText`,
`launchApp` — catches its exception, writes a log line, and returns `void`. No failed key press can
reach the user. Combined with C-1, the app's steady state after 35 seconds is a remote that looks
connected (green dot, "CONNECTED") and does nothing (Finding **C-3**).

### Quality Scorecard

| Dimension | Score (1–10) | Rationale (evidence) |
|---|:---:|---|
| **Architecture & State Management** | **5** | Right-sized layering and a genuinely earned `DeviceController` seam; undermined by a hardcoded 8-arm factory inside the notifier (`connection_provider.dart:183-214`) and no channel for controller→state disconnection events. |
| **Standards Compliance (Dart/Flutter)** | **5** | Immutable models with `==`/`hashCode`/`copyWith`, good `const` discipline, typed enums. But 15 analyzer warnings ship, two controllers contain unreachable code, side effects run in `build()`, and 1,701 lines sit in two god-screens. |
| **Performance, Memory & Resources** | **4** | Two `TextEditingController` leaks (`device_scanner.dart:33`, `:137`), uncancelled `Future.delayed` timers mutating state after dispose, full-screen `BackdropFilter` + perpetual `repeat()` animations, `GoogleFonts.interTextTheme()` recomputed on every root rebuild. Zero `RepaintBoundary` in the repo. |
| **Security & Data Integrity** | **3** | Secure storage used correctly and TOFU implemented — then defeated by an unconditional plaintext downgrade (`samsung_controller.dart:126-139`). Vizio does no certificate validation and treats HTTP 401 as success. No CI, therefore no dependency scanning. |
| **Testability & Test Quality** | **3** | 27.2 % line coverage; 4 of 22 `lib/` files have a dedicated test. One empty-bodied passing test; one test that opens a **real socket** and burns 30 s of wall clock, violating `testing-quality.md` "Deterministic: no real network". |
| **Product Scalability & Maintainability** | **4** | Adding one vendor requires edits at **5** sites across 4 files. No CI, no `.github/`, template README, `applicationId = "com.example.devicecontroller"`. |
| **Overall** | **4** | Sound skeleton, unverified muscle. Phase 1 of §5 (roughly two focused days) moves this to a genuine 6–7. |

### Top 3 critical risks to address immediately

1. **The remote stops working 35 seconds after every Samsung or LG connection, silently.**
   `samsung_controller.dart:159` / `lg_controller.dart:76` can never execute, so the pong deadline at
   `:176` / `:101` always fires and calls `_handleDisconnect()`. Nothing propagates that to
   `ConnectionNotifier`, so the UI keeps rendering "CONNECTED" while
   `connection_provider.dart:154` silently drops every subsequent key press. **This is the highest-impact
   defect in the repository, and it affects the two largest USA TV vendors.**

2. **Samsung TLS certificate pinning is unenforceable.** `samsung_controller.dart:126-128` catches
   *every* exception from the pinned `wss://` attempt — including the deliberate `return false` from a
   TOFU mismatch at `:114-115` — and retries over unencrypted `ws://8001` at `:131-138`, carrying the
   pairing token in the URL query string. An attacker who can present a wrong certificate is *rewarded*
   with a cleartext session. Violates `security-privacy.md` → "TLS everywhere… no downgrade paths" and
   "Failure mode is *closed* (deny) rather than *open* (allow)".

3. **No failure of any user command is ever visible to the user.** `connection_provider.dart:153-180`
   and every controller swallow exceptions into `log.e`. The remote screen has no error state, no
   snackbar, no retry affordance — and fires a confirming haptic on commands that were never
   transmitted. Breaches the `SKILL.md` non-negotiable **"No silent failure"** and the
   `stack-appendices.md` §3 four-state rule (loading / empty / **error with retry** / success).

---

## 2. Standards Alignment Matrix

| Standard / Skill Guideline | Status | Evidence (File & Line) | Impact / Risk |
|---|---|---|---|
| **SKILL.md** → Non-negotiable: *No silent failure; errors handled, surfaced, or propagated* | **Non-Compliant** | `connection_provider.dart:153-180` (3× `catch (e) { log.e(...) }` → `void`); `roku_controller.dart:103-105,118-120,136-139`; `samsung_controller.dart:223-225,249-251,279-281`; `device_persistence_service.dart:36-38` (`catch (_) { return null; }`) | User presses a button, nothing happens, no feedback. A corrupted persisted device is indistinguishable from "no device". |
| **SKILL.md** → Non-negotiable: *Evidence, not assertion* | **Non-Compliant** | Commit `793e846` claims "full Semantics… for all interactive elements" vs. `grep -c Semantics lib/screens/device_scanner.dart` = **0**; claims "Comprehensive Test Suite" vs. measured **27.2 %** coverage | Reviewers trust claims that are false; the accessibility and test gaps are now invisible to the team. |
| **SKILL.md** → Non-negotiable: *The codebase stays coherent* | **Partial** | Error style is uniformly (wrongly) swallowing; DI is not uniform — `_persistence` is cached at `connection_provider.dart:64` yet re-resolved via `ref.read` at `:188` | Two dialects for one lookup; the second bypasses the override path used at `connection_provider_test.dart:39`. |
| **security-privacy.md** → *TLS everywhere; verify certificates; **no downgrade paths*** | **Non-Compliant** | `samsung_controller.dart:126-139` — bare `catch (e)` around the pinned WSS attempt falls through to `ws://$host:8001` | Pinning at `:103-116` is decorative. MITM recovers the pairing token in cleartext. |
| **security-privacy.md** → *Failure mode is **closed** (deny) rather than **open** (allow)* | **Non-Compliant** | `vizio_controller.dart:42` — `if (response.statusCode == 200 \|\| response.statusCode == 401)` sets `_connected = true` | An **unauthenticated** Vizio session is reported as connected; every later command 401s into a swallowed catch at `:93-95`. |
| **security-privacy.md** → *Secrets from a secret manager/keystore, never source or logs* | **Compliant** | `device_persistence_service.dart:17-20` uses `FlutterSecureStorage` for device, TOFU fingerprint, Samsung token, LG client key; no literal secrets in `lib/` | Correct use of the platform keystore — matches `stack-appendices.md` §4 "use the platform keychain/keystore for anything sensitive". |
| **security-privacy.md** → *Never log sensitive data; redact structurally at the logger* | **Partial** | `app_logger.dart:10-20` has no redaction layer; `scanner_provider.dart:162,271` and every controller log the TV's LAN IP | Low sensitivity today (RFC1918), but no structural barrier stops the next contributor logging a pairing token. |
| **security-privacy.md** → *Validate at the boundary, with an allowlist, into typed domain objects* | **Partial** | `device.dart:75-83` casts `json['id'] as String` with no format/length validation; `scanner_provider.dart:204-272` parses attacker-supplyable SSDP text inline, with no test reaching it | Any host on the Wi-Fi can inject fabricated `SERVER:` / `LOCATION:` headers and place a spoofed device in the user's list. **Correction (verified during remediation):** this row first claimed the `substring(7)` / `substring(9)` reads had "no bounds check" and could throw `RangeError`. They cannot — the `startsWith('LOCATION:')` guard bounds them, confirmed by running the exact inputs. The real parsing defects were narrower: splitting on `'\r\n'` alone silently missed any responder using bare LF, and `utf8.decode` on a malformed datagram threw out of the socket listener. |
| **security-privacy.md** → *Dependencies pinned; automated vulnerability scanning* | **Partial** | `pubspec.lock` present (pinned ✔); `.github/` does not exist → no CI, no scanning gate | New CVEs in `nsd`, `web_socket_channel`, `permission_handler` will never be surfaced. |
| **reliability-observability.md** → *Timeouts on everything* | **Compliant** | `roku_controller.dart:70,102,117,135`; `samsung_controller.dart:121,137`; `vizio_controller.dart:39,92`; `lg_controller.dart:87` — all explicit | Genuinely well done; one of the strongest areas of the codebase. |
| **reliability-observability.md** → *Retries with exponential backoff **and jitter**, bounded* | **Partial** | `connection_provider.dart:55-56,110-138` — bounded (4) and exponential (1/2/4/8 s) but **no jitter** | Thundering-herd risk is low for a single-client LAN app; flagged for completeness, not urgency. |
| **reliability-observability.md** → *Retry only on **retryable** errors — never on a 4xx that means "you asked wrong"* | **Non-Compliant** | `fire_tv_controller.dart:10-11` / `google_tv_controller.dart:10-11` throw `UnsupportedDeviceException` from `connect()`; `connection_provider.dart:123-128` retries it 4× | A user tapping a discovered Chromecast (`scanner_provider.dart:141-142` maps `_googlecast._tcp` → `googleTv`) waits **15 seconds** to be told it is unsupported. |
| **reliability-observability.md** → *What happens when it succeeds but we never hear back?* (partial failure) | **Non-Compliant** | `samsung_controller.dart:151-168`, `lg_controller.dart:62-85` — `_handleDisconnect()` mutates controller state with **no channel back to `ConnectionNotifier`** | The single most consequential design omission: app state and transport state can disagree indefinitely. |
| **reliability-observability.md** → *Structured logs with correlation id, principal, operation* | **Non-Compliant** | `app_logger.dart:11-18` uses `PrettyPrinter` with interpolated prose (e.g. `connection_provider.dart:125`) | Not machine-parseable and not shipped anywhere. Fails the stated bar: "diagnose a novel production problem without shipping new code." |
| **reliability-observability.md** → *RED metrics; symptom-based alerts; dashboards* | **Non-Compliant** | No metrics, no crash reporter, and no `FlutterError.onError`, `PlatformDispatcher.onError` or `runZonedGuarded` anywhere in `lib/` (verified by grep) | The uncaught `FormatException` from C-1 is invisible in production. Zero field telemetry. |
| **performance-efficiency.md** → *Serial I/O that could be concurrent* | **Non-Compliant** | `roku_controller.dart:111-121` — one awaited HTTP POST **per character**, each with a 3 s timeout, no batching, no length cap | A 40-character search is 40 sequential round trips; a flaky TV makes it a 120 s hang with no cancellation. |
| **performance-efficiency.md** → *Work done per-request that could be done once* | **Non-Compliant** | `main.dart:42` calls `GoogleFonts.interTextTheme(...)` inside `build()`, and `main.dart:19` watches the whole `connectionProvider`, so the entire `ThemeData` is rebuilt on every connection-state change | Root-level rebuild plus font-theme reconstruction on every status transition. |
| **performance-efficiency.md** → *Measure, then change, then measure* | **Non-Compliant** | `remote.dart:133` — "BackdropFilter sigma reduced to 15 (Requirement 2.30)": a performance change justified by a requirement number, with no before/after measurement recorded | Tuning by decree. The full-viewport blur at `:134-137` and `device_scanner.dart:267-270` is still a per-frame GPU cost. |
| **testing-quality.md** → *Deterministic: no real clock, **no real network*** | **Non-Compliant** | `connection_provider_test.dart:92-105` connects to `0.0.0.0:8060` for real inside `fakeAsync`; the run log shows four genuine 3 s `TimeoutException`s over ~30 s wall clock | Slow and environment-dependent — textbook flaky-test-as-production-defect. |
| **testing-quality.md** → *One reason to fail, with a name that states expected behaviour* | **Partial** | Good: `'sendText truncates to 500 chars'` (`samsung_controller_test.dart:198`). Bad: `'SSDP mapping - Roku'` (`scanner_provider_test.dart:27-35`) has **no assertions** — its body is four comment lines | A green suite that proves nothing about the code that ingests untrusted LAN input. |
| **testing-quality.md** → *Untested code that handles auth or data integrity is a defect regardless of percentage* | **Non-Compliant** | `lg_controller.dart` **0.0 %** (0/76), `vizio_controller.dart` **0.0 %** (0/41), `remote.dart` **0.0 %** (0/388), `remote_buttons.dart` **0.0 %** (0/105), `device_persistence_service.dart` **17.2 %** (5/29) | The pairing-token and client-key persistence paths — this app's auth-equivalent surface — are 17 % covered. |
| **testing-quality.md** → *Delete commented-out code; every TODO has an owner* | **Non-Compliant** | `device_scanner.dart:233-242` and `:255-264` are 20 lines of commented-out `.animate()` blocks; `connection_provider_test.dart:86-89` and `scanner_provider_test.dart:30-38` commit the author's unresolved deliberation ("Wait,Switch to a device type that will fail…") as source | A reader cannot distinguish intent from abandonment. |
| **testing-quality.md** → *Lint, typecheck and build clean — no new warnings* | **Non-Compliant** | `flutter analyze` → 15 issues, incl. `unnecessary_non_null_assertion` at `samsung_controller.dart:96,135` and 3 unused imports in `lib/` | Warning noise normalises warnings — and two of them sit inside the security-critical connect path. |
| **testing-quality.md** → *No magic numbers or strings — name them where they're defined* | **Non-Compliant** | `const Color(0xFF09090B)` at `main.dart:26,37`, `device_scanner.dart:218`, `remote.dart:105`; `0xFF18181B` at `main.dart:40`, `device_scanner.dart:52,79`, `remote.dart:783`; ports `8060/8001/8002/3000/7345` duplicated across `connection_provider.dart:193-207`, `device_scanner.dart:39-42`, `scanner_provider.dart:136-252` | A port default or brand colour changes in one place and silently disagrees in three others. |
| **stack-appendices.md** §3 → *Every async surface handles loading, empty, **error (with retry)**, success* | **Partial** | Scanner screen does all four (`device_scanner.dart:308-318` error, `:475-504` empty, `:321-323` loading). Remote screen has **none** — `remote.dart:100-166` renders identically whether commands succeed or fail | The screen where 100 % of user actions occur has no error state. |
| **stack-appendices.md** §3 → *Presentational components take data and callbacks; business rules live outside* | **Compliant** | `remote_buttons.dart` — `RemoteButton` / `RockerButton` / `AppButton` are pure, take `VoidCallback`, hold no provider references | Genuinely reusable, correctly factored. Keep. |
| **stack-appendices.md** §3 → *i18n: keep strings out of components from day one — the cheap seam* | **Non-Compliant** | ~80 hardcoded English literals, e.g. `'Scanning Network...'` (`device_scanner.dart:455`), `'SWIPE TO NAVIGATE • TAP TO CLICK'` (`remote.dart:585`), `'Connect via IP'` (`device_scanner.dart:57`) | The brief names the USA market, where ~13 % of households are Spanish-speaking. Retrofitting later touches every widget. |
| **stack-appendices.md** §4 (Mobile) → *Design for the network being absent, slow, or flapping mid-operation* | **Compliant** | `connectivity_service.dart:9-35` + `connection_provider.dart:87-98` handle loss and restore; `_tryAutoReconnect` at `:79-85` restores the last device from secure storage | Well executed — the clearest evidence the hardening pass paid off. |
| **stack-appendices.md** §4 (Mobile) → *Respect the lifecycle: background/foreground, **process death and state restoration*** | **Partial** | Foreground resume handled (`connectivity_service.dart:24-29`); no `RestorationMixin` or `restorationId` anywhere; `RemoteScreen`'s `activeTab` / `showKeyboard` (`remote.dart:30-31`) are lost on process death | The user returns from a phone call to a reset remote. |
| **stack-appendices.md** §4 (Mobile) → *Permissions requested in context, with a graceful path when denied* | **Partial** | `scanner_provider.dart:51-53` requests `nearbyWifiDevices` and, on denial, logs a warning and scans anyway | Denied permission yields "No devices found. Ensure you share the same Wi-Fi network." (`device_scanner.dart:494`) — actively misleading. No settings deep-link. |
| **stack-appendices.md** §4 (Mobile) → *Accessibility: screen reader, dynamic type, touch targets, contrast* | **Partial** | Present: `remote.dart:367,510,686`; `remote_buttons.dart:28,152,180,218`. Absent: **all** of `device_scanner.dart` — 0 `Semantics`, 0 `Tooltip`, including device rows (`:571-647`), action buttons (`:691-736`) and both dialog inputs (`:110-151`) | A blind user reaches the app's first screen and cannot identify a single device or control on it. |
| **stack-appendices.md** §4 (Mobile) → *There must be a way to force-upgrade in an emergency* | **Non-Compliant** | No version gate, remote config, or feature-flag mechanism in `lib/` | With C-1 and C-2 shipping in `1.0.0+1`, there is no lever to protect users already on that build. |
| **design-judgment.md** §2 → *Abstraction Decision Procedure* (5 gates) | **Compliant** | `device_controller.dart:9-27` — 7 implementations, same reason to change (wire protocol), volatile axis, no flag parameters, third case (LG) fitted with no escape hatch | Correctly earned abstraction. Do not "improve" it. |
| **design-judgment.md** §4 → *Seams, not frameworks; the likely change is **local*** | **Non-Compliant** | Adding one TV vendor requires edits at **5** sites: `device.dart:4-40` (enum + parser), `connection_provider.dart:190-213` (factory switch), `scanner_provider.dart:132-146` **and** `:228-255` (two discovery matchers), `device_scanner.dart:649-689` (icon + colour switches) | The most likely change in this product's roadmap is the one the architecture makes least local. |
| **design-judgment.md** §6 → *No dead code, no unused exports, no "just in case" configuration* | **Non-Compliant** | `vizio_controller.dart:19` `_authToken` is read at `:89` but never assigned; `device_persistence_service.dart:81-87` `saveVizioToken` / `loadVizioToken` are never called; `device.dart:51` `signal` is hardcoded to `100` (`scanner_provider.dart:156,265`) and never rendered; `MockController` (59 lines) ships in the production bundle via `connection_provider.dart:184` | Dead auth plumbing on both sides of a boundary is worse than none — it reads as implemented. |
| **lifecycle-gates.md** Stage 5 → *No debug output, no commented-out code, no unreferenced TODOs* | **Non-Compliant** | `device_scanner.dart:233-242,255-264`; `vizio_controller.dart:32-35,100-101,108-109` ("stub"); `ir_controller.dart:40` ("Platform channel call would go here.") | Three shipped controllers are documented stubs presented to the user as working device types. |
| **lifecycle-gates.md** Stage 5 → *Commits are small, coherent, and describe why* | **Non-Compliant** | `git log` — `793e846` is one commit with a 25-line summary spanning security, protocol, state, discovery, UI, accessibility and tests across the whole repo; its predecessor is `ef187a5 "Test Feature"` | Unreviewable by construction (`testing-quality.md`: "A 2000-line PR does not get reviewed; it gets approved"). |
| **lifecycle-gates.md** Stage 8 → *Rollback path stated and actually possible* | **Non-Compliant** | No flags, no staged rollout, no `.github/` workflow; `applicationId = "com.example.devicecontroller"` (`android/app/build.gradle.kts:24`) | Cannot ship at all under that application id; cannot turn anything off once shipped. |
| **stack-appendices.md** §2 → *Model meaning before storage; versioned migration* | **Partial** | Storage key is versioned (`device_persistence_service.dart:11`, `last_device_v1`) ✔; no migration branch exists and `loadDevice` (`:31-39`) silently discards anything unparseable | Good instinct, incomplete follow-through: a v2 rollout silently forgets every user's saved TV. |

---

## 3. Deep-Dive Gap Analysis & Findings

### CRITICAL

---

#### C-1. The heartbeat pong handler is unreachable — every Samsung and LG session dies at T+35 s

- **Location:** `lib/controllers/samsung_controller.dart:151-182` (esp. **153, 159-161, 176-179**);
  identical defect at `lib/controllers/lg_controller.dart:62-107` (esp. **64, 76-78, 101-104**).
- **Observation.** The stream listener decodes *before* it tests for the pong sentinel:

  ```dart
  // samsung_controller.dart:151-162
  _channel!.stream.listen(
    (message) {
      final data = jsonDecode(message);          // ← line 153: throws on 'pong'
      if (data['event'] == 'ms.channel.connect') {
        ...
      } else if (message == 'pong') {            // ← line 159: UNREACHABLE
        _pongTimeoutTimer?.cancel();             // ← line 160: never runs
      }
    },
  ```

  `jsonDecode('pong')` throws `FormatException` at line 153, so control never reaches line 159. The
  branch is dead for *every* possible input: JSON frames take the `if`, and the only frame that could
  satisfy the `else if` cannot survive line 153. `_pongTimeoutTimer.cancel()` is therefore
  unreachable, and the 5-second deadline armed at `:176-179` **always** fires:

  ```dart
  // samsung_controller.dart:172-181
  _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
    if (_connected) {
      _channel?.sink.add('ping');
      _pongTimeoutTimer = Timer(const Duration(seconds: 5), () {
        log.w('SamsungController: Pong timeout');
        _handleDisconnect();                      // ← guaranteed at T+35s
      });
    }
  });
  ```

  Two aggravating factors. First, `'ping'` is injected as a raw string into a channel that is
  otherwise strictly JSON — Samsung's `ms.remote.control` protocol defines no text ping/pong
  exchange, so no reply is expected in the first place. Second, the `FormatException` is thrown
  *inside* an `onData` callback, which does **not** route to that subscription's `onError` (`:164`);
  it escapes to the enclosing `Zone`, and with no `PlatformDispatcher.instance.onError` registered
  (verified absent across `lib/`) it is discarded entirely in release builds.
  `lg_controller.dart` has all three properties at lines 64, 76 and 101.
- **Impact.** Deterministic loss of control of Samsung and LG televisions 35 seconds after
  connecting — the two largest USA smart-TV vendors. Because nothing notifies `ConnectionNotifier`
  (see **C-3**), the UI keeps rendering the green "CONNECTED" indicator (`remote.dart:204-238`) while
  `connection_provider.dart:154` discards every key press. The observable product behaviour is: *the
  remote works for half a minute, then becomes an inert picture of a remote.* No log reaches the
  developer; no error reaches the user. Directly violates `reliability-observability.md` → "What
  happens when it succeeds but we never hear back?" and `SKILL.md` → "No silent failure."
- **Remediation.** Test the sentinel before decoding, guard the decode, and prefer the transport's
  own keep-alive over an invented one:

  ```dart
  // BEFORE — samsung_controller.dart:151-165
  _channel!.stream.listen(
    (message) {
      final data = jsonDecode(message);
      if (data['event'] == 'ms.channel.connect') {
        final token = data['data']['token'];
        if (token != null) {
          _persistence.saveSamsungToken(host, token);
        }
      } else if (message == 'pong') {
        _pongTimeoutTimer?.cancel();
      }
    },
    onDone: () => _handleDisconnect(),
    onError: (e) => log.e('SamsungController: WebSocket error', e),
  );

  // AFTER
  _channel!.stream.listen(
    (message) {
      // Any inbound frame proves liveness — cancel the pong deadline FIRST,
      // before any parsing that can throw.
      _pongTimeoutTimer?.cancel();

      if (message is! String || message == 'pong') return;

      final Map<String, dynamic> data;
      try {
        data = jsonDecode(message) as Map<String, dynamic>;
      } on FormatException catch (e, s) {
        // Some Tizen firmware revisions emit non-JSON frames; they are liveness
        // evidence, not an error.
        log.d('SamsungController: non-JSON frame ignored', e, s);
        return;
      }

      if (data['event'] == 'ms.channel.connect') {
        final token = data['data']?['token'] as String?;
        if (token != null) unawaited(_persistence.saveSamsungToken(host, token));
      }
    },
    onDone: _handleDisconnect,
    onError: (Object e, StackTrace s) {
      log.e('SamsungController: WebSocket error', e, s);
      _handleDisconnect();          // was: logged, and left marked connected
    },
    cancelOnError: false,
  );
  ```

  Apply the equivalent at `lg_controller.dart:62-85`. Better still, replace the hand-rolled ping with
  `IOWebSocketChannel.connect(..., pingInterval: Duration(seconds: 30))`, which performs RFC 6455
  protocol-level ping/pong beneath the application stream and closes the socket on failure — removing
  both timers and both dead branches. **Regression test (must fail before the fix):** drive a
  `fakeAsync` 35 s elapse with a mock channel that emits `'pong'` and assert `controller.isConnected`
  is still `true` — today that assertion fails.

---

#### C-2. Samsung TLS pinning is bypassed by an unconditional plaintext downgrade

- **Location:** `lib/controllers/samsung_controller.dart:89-139` (esp. **101-116**, **126-128**,
  **131-138**).
- **Observation.** Lines 103-116 implement Trust-On-First-Use pinning correctly — first contact
  records `sha256.convert(cert.der)`, later contacts compare and `return false` on mismatch. Lines
  126-128 then dismantle it:

  ```dart
  // samsung_controller.dart:126-138
  } catch (e) {
    log.d('SamsungController: wss://8002 failed, trying ws://8001 ($e)');
  }
  // Attempt 2: Legacy WS on port 8001
  final wsUrl = Uri.parse(
    'ws://$host:8001/api/v2/channels/samsung.remote.control?name=$nameBase64$tokenQuery');
  ...
  _channel = IOWebSocketChannel(await WebSocket.connect(wsUrl.toString())...);
  ```

  The bare `catch (e)` cannot distinguish "this is a 2015 model with no TLS" from "the certificate did
  not match the pin recorded last week". Both surface as `HandshakeException`, and both fall through
  to an **unauthenticated, unencrypted** session. Note what travels on it: `tokenQuery` (`:87`) carries
  the persisted pairing token in the URL query string, and the reply handled at `:154-157` carries a
  newly issued one. An attacker on the same Wi-Fi who can fail the TLS handshake harvests the token in
  cleartext and gains persistent control of the television.
- **Impact.** The security control the hardening commit advertises as its headline ("TOFU with
  SHA-256 certificate pinning") provides **zero** protection against the adversary it names, because
  the attacker chooses which branch executes. Violates `security-privacy.md` → "TLS everywhere…
  verify certificates; **no downgrade paths**" and "Failure mode is *closed* (deny) rather than *open*
  (allow) when a check errors", and `SKILL.md` → "Security is not a phase."
- **Remediation.** Make pin failure a distinct, non-downgradable outcome, and let the fallback serve
  only its legitimate case (a device that never presented a certificate):

  ```dart
  // BEFORE — samsung_controller.dart:104-116, 126-128
  ..badCertificateCallback = (cert, certHost, certPort) {
    final fingerprint = sha256.convert(cert.der).toString();
    if (storedFingerprint == null) {
      log.i('SamsungController: Pinning new certificate for $host');
      _persistence.saveCertFingerprint(host, fingerprint);   // fire-and-forget
      return true;
    }
    if (storedFingerprint == fingerprint) return true;
    log.e('SamsungController: TOFU mismatch for $host!');
    return false;
  };
  ...
  } catch (e) {
    log.d('SamsungController: wss://8002 failed, trying ws://8001 ($e)');
  }

  // AFTER
  var pinRejected = false;
  String? pendingFingerprint;
  final httpClient = HttpClient()
    ..badCertificateCallback = (cert, certHost, certPort) {
      final fingerprint = sha256.convert(cert.der).toString();
      if (storedFingerprint == null) {
        log.i('SamsungController: pinning new certificate for $host');
        pendingFingerprint = fingerprint;   // committed only if the handshake succeeds
        return true;
      }
      if (storedFingerprint == fingerprint) return true;
      pinRejected = true;                   // remember WHY we failed
      log.e('SamsungController: TOFU mismatch for $host — refusing connection');
      return false;
    };

  try {
    final socket = await WebSocket.connect(wssUrl.toString(), customClient: httpClient)
        .timeout(const Duration(seconds: 3));
    if (pendingFingerprint != null) {
      await _persistence.saveCertFingerprint(host, pendingFingerprint!);
    }
    _channel = IOWebSocketChannel(socket);
    _onConnected('wss:8002');
    return;
  } catch (e) {
    if (pinRejected) {
      throw CertificatePinMismatchException(host);   // fail CLOSED — never downgrade
    }
    log.d('SamsungController: wss://8002 unavailable, trying legacy ws://8001 ($e)');
  }
  ```

  Two supporting changes: (1) `_persistence.saveCertFingerprint(...)` at `:108` is currently an
  un-awaited `Future` inside a synchronous callback, so the pin is persisted best-effort and its
  failure is unobservable — the rewrite defers the write until the handshake succeeds and awaits it.
  (2) Surface `CertificatePinMismatchException` distinctly in `connection_provider.dart` so the user
  sees *"This TV's security certificate changed — it may not be your TV"* rather than a generic retry.
  **Test:** connect with a stored fingerprint that does not match and assert no `ws://` attempt occurs.

---

#### C-3. No command failure is observable — the command path has no error contract

- **Location:** `lib/providers/connection_provider.dart:153-180`; `lib/screens/remote.dart:61-97`;
  and every controller (`roku_controller.dart:103-105,118-120,137-139`;
  `samsung_controller.dart:223-225,249-251,279-281`; `lg_controller.dart:144-146,182-184`;
  `vizio_controller.dart:93-95`).
- **Observation.** The swallowing is uniform and three layers deep:

  ```dart
  // connection_provider.dart:153-160
  Future<void> sendKey(RemoteKey key) async {
    if (_controller == null || !_controller!.isConnected) return;   // silent drop #1
    try {
      await _controller!.sendKey(key);
    } catch (e) {
      log.e('ConnectionNotifier: sendKey failed', e);               // silent drop #2
    }
  }
  ```

  At the controller (e.g. `roku_controller.dart:92-106`), an unmapped key (`:95-98`) and a network
  failure (`:103-105`) both return normally — indistinguishable outcomes. The call site then discards
  even the `Future`:

  ```dart
  // remote.dart:61-64
  void _sendKey(RemoteKey key) {
    ref.read(connectionProvider.notifier).sendKey(key);   // not awaited, no result
    HapticFeedback.lightImpact();                          // haptic fires on failure too
  }
  ```

  So the user receives *positive tactile confirmation* of a command that was never transmitted. The
  remote screen (`remote.dart:100-166`) has no error state of any kind: the four-state rule from
  `stack-appendices.md` §3 is satisfied on the discovery screen (`device_scanner.dart:202-215` listens
  and shows a snackbar) and on none of the screen where every user action happens.
- **Impact.** This is the mechanism that turns C-1 from a bug into an *invisible* bug, and would do
  the same for any future transport defect. It breaches the `SKILL.md` non-negotiable "Errors are
  handled, surfaced, or propagated — never swallowed", and removes the diagnostic path entirely: a
  support report reads "the app stopped working" with no error the user could quote.
- **Remediation.** Give commands a typed outcome and render it. Expected outcomes (unsupported key,
  not connected) belong in the return type per `testing-quality.md` → "Distinguish **expected**
  outcomes from **exceptional** ones… belong in the return type or a typed error, not in exception
  control flow":

  ```dart
  // NEW — lib/models/command_result.dart
  sealed class CommandResult { const CommandResult(); }
  class CommandSent        extends CommandResult { const CommandSent(); }
  class CommandUnsupported extends CommandResult {
    final RemoteKey key;
    const CommandUnsupported(this.key);
  }
  class CommandFailed      extends CommandResult {
    final Object cause;
    final StackTrace stackTrace;
    const CommandFailed(this.cause, this.stackTrace);
  }

  // AFTER — connection_provider.dart:153-160
  Future<CommandResult> sendKey(RemoteKey key) async {
    final controller = _controller;
    if (controller == null || !controller.isConnected) {
      state = state.copyWith(
        status: ConnectionStatus.error,
        errorMessage: 'Lost connection to ${state.device?.name ?? 'device'}',
      );
      return CommandFailed(StateError('not connected'), StackTrace.current);
    }
    try {
      await controller.sendKey(key);
      return const CommandSent();
    } catch (e, s) {
      log.e('ConnectionNotifier: sendKey ${key.name} failed', e, s);
      state = state.copyWith(
          status: ConnectionStatus.error, errorMessage: 'Command failed');
      return CommandFailed(e, s);
    }
  }

  // AFTER — remote.dart:61-64
  Future<void> _sendKey(RemoteKey key) async {
    final result = await ref.read(connectionProvider.notifier).sendKey(key);
    switch (result) {
      case CommandSent():
        HapticFeedback.lightImpact();
      case CommandUnsupported(:final key):
        _showTransient('${key.name} is not available on this TV');
      case CommandFailed():
        HapticFeedback.heavyImpact();
        _showTransient('Command failed — reconnecting…');
    }
  }
  ```

  Add to `remote.dart` the same `ref.listen(connectionProvider, ...)` error surface that
  `device_scanner.dart:202-215` already has, so one convention covers both screens.

---

### HIGH

---

#### H-1. LG D-pad Up/Down are wired to the TV's 3D display toggle

- **Location:** `lib/controllers/lg_controller.dart:187-203` (esp. **188-189**).
- **Observation.**

  ```dart
  static const Map<RemoteKey, String> _ssapUris = {
    RemoteKey.up:   'ssap://com.webos.service.tv.display/set3DOn',  // Placeholder, LG often uses pointer
    RemoteKey.down: 'ssap://com.webos.service.tv.display/set3DOff',
    ...
  ```

  `RemoteKey.left` and `RemoteKey.right` are absent from the map entirely, so `:131-134` logs and
  returns for them. The word "Placeholder" shows this was known at authoring time; it shipped in a
  commit describing "robust SSAP… implementations".
- **Impact.** On an LG webOS TV the four most-used controls do nothing (left/right) or something
  actively wrong and hard for a user to undo (up/down toggle 3D mode). This is worse than an
  unimplemented vendor, because `_buildController` (`connection_provider.dart:200-204`) presents LG as
  fully supported and the header shows "CONNECTED". Breaches `design-judgment.md` §6 ("Under-building
  the irreversible") and `SKILL.md` coherence.
- **Remediation.** webOS exposes no SSAP URI for D-pad arrows; navigation runs over a separate
  **pointer input socket** obtained via
  `ssap://com.webos.service.networkinput/getPointerInputSocket`. Until that socket is implemented, the
  honest behaviour is to declare the keys unsupported so C-3's `CommandUnsupported` path can tell the
  user:

  ```dart
  // BEFORE — lg_controller.dart:187-190
  static const Map<RemoteKey, String> _ssapUris = {
    RemoteKey.up: 'ssap://com.webos.service.tv.display/set3DOn', // Placeholder, LG often uses pointer
    RemoteKey.down: 'ssap://com.webos.service.tv.display/set3DOff',
    RemoteKey.volumeUp: 'ssap://audio/volumeUp',

  // AFTER
  // webOS exposes no SSAP URI for D-pad arrows; they are reachable only over the
  // pointer input socket (ssap://com.webos.service.networkinput/getPointerInputSocket).
  // Until _connectPointerSocket() lands, up/down/left/right report Unsupported rather
  // than firing an unrelated command (3D toggle). Tracked: ROADMAP §LG-pointer.
  static const Map<RemoteKey, String> _ssapUris = {
    RemoteKey.volumeUp: 'ssap://audio/volumeUp',
  ```

  Then implement `_pointerSink` and route `up/down/left/right/select` through
  `{"type":"button","name":"UP"}` frames on that socket.

---

#### H-2. Retry policy retries non-retryable errors, has no jitter, and permits concurrent chains

- **Location:** `lib/providers/connection_provider.dart:54-56, 100-138`; interacts with
  `fire_tv_controller.dart:10-11`, `google_tv_controller.dart:10-11`, `scanner_provider.dart:141-142`,
  `connectivity_service.dart:24-29`.
- **Observation.** Four defects in one method:
  1. **Non-retryable errors are retried.** `UnsupportedDeviceException` — a permanent, deterministic
     "you asked wrong" — is thrown by `FireTvController.connect()` and retried 4× with 1+2+4+8 = 15 s
     of sleeps. `scanner_provider.dart:141-142` maps every `_googlecast._tcp` responder (ordinary
     Chromecasts included) to `DeviceType.googleTv`, so this is a common path, not an edge case.
  2. **No jitter**, contrary to `reliability-observability.md`.
  3. **No re-entrancy guard.** `connect()` (`:101-108`) resets the shared `_retryCount = 0` and starts
     a chain. `_onConnectivityChanged` (`:94-97`) calls `connect()` on any restore event, and
     `ConnectivityService.didChangeAppLifecycleState` (`connectivity_service.dart:24-29`) synthesises a
     restore event on **every foreground resume**. Tapping a device then backgrounding/foregrounding
     yields two live recursive chains sharing one `_retryCount`, both assigning `state` and both
     calling `_persistence.saveDevice`.
  4. **The chain survives disposal.** `ref.onDispose` (`:69-72`) cancels the connectivity subscription
     but nothing cancels an in-flight `Future.delayed` at `:127`; a `state =` assignment on a disposed
     `Notifier` throws.
- **Impact.** A 15-second dead end for a common device class; duplicate writes to secure storage;
  `StateError` crashes on the dispose race; retry storms on flapping Wi-Fi.
- **Remediation.**

  ```dart
  // BEFORE — connection_provider.dart:110-138
  Future<void> _connectWithBackoff(Device device) async {
    try {
      _controller = _buildController(device);
      await _controller!.connect();
      ...
    } catch (e) {
      if (_retryCount < _maxRetries) {
        final delay = _retryDelays[_retryCount];
        _retryCount++;
        await Future.delayed(Duration(seconds: delay));
        await _connectWithBackoff(device);        // recursion + shared mutable counter
      } else { ... }
    }
  }

  // AFTER
  int _attemptEpoch = 0;                       // invalidates superseded chains
  bool _disposed = false;                      // set in ref.onDispose at :69-72
  static const _baseDelay = Duration(seconds: 1);
  final _rng = Random();

  bool _isRetryable(Object e) =>
      e is! UnsupportedDeviceException && e is! CertificatePinMismatchException;

  Future<void> _connectWithBackoff(Device device) async {
    final epoch = ++_attemptEpoch;             // any newer attempt wins
    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      if (epoch != _attemptEpoch || _disposed) return;
      try {
        _controller = _buildController(device);
        await _controller!.connect();
        await _persistence.saveDevice(device);
        if (epoch != _attemptEpoch || _disposed) return;
        state = DeviceConnectionState(
            status: ConnectionStatus.connected, device: device);
        return;
      } catch (e, s) {
        final fatal = !_isRetryable(e) || attempt == _maxRetries;
        if (fatal) {
          log.e('ConnectionNotifier: ${device.name} failed', e, s);
          if (epoch != _attemptEpoch || _disposed) return;
          state = DeviceConnectionState(
            status: ConnectionStatus.error,
            device: device,
            errorMessage: _userMessage(e),     // 0 s for unsupported, not 15 s
          );
          return;
        }
        // Full-jitter exponential backoff (AWS "Exponential Backoff and Jitter").
        final ceiling = _baseDelay * (1 << attempt);
        await Future<void>.delayed(
            Duration(milliseconds: _rng.nextInt(ceiling.inMilliseconds + 1)));
      }
    }
  }
  ```

  Converting the recursion to a loop also removes the stack growth visible in the captured test run,
  where `_connectWithBackoff` appears twice in one stack trace.

---

#### H-3. Two `TextEditingController` leaks in the manual-connect dialog, one per rebuild

- **Location:** `lib/screens/device_scanner.dart:29-195` (esp. **33** and **137**).
- **Observation.** Both controllers are constructed inside builder closures and neither is disposed:

  ```dart
  // device_scanner.dart:32-33 — one leak per dialog open
  builder: (context) {
    final TextEditingController ipController = TextEditingController();

  // device_scanner.dart:136-142 — one leak per setDialogState() call
  TextField(
    controller: TextEditingController(text: '$selectedPort'),
    keyboardType: TextInputType.number,
    onChanged: (v) { selectedPort = int.tryParse(v) ?? selectedPort; },
  ```

  Line 137 is the worse of the two: it sits inside `StatefulBuilder`'s builder (`:50`), so a fresh
  `TextEditingController` — a `ChangeNotifier` retained by the `TextField`'s element until GC — is
  allocated on **every keystroke** in the IP field, because each `onChanged` at `:113-117` calls
  `setDialogState`.

  > **Correction (verified during remediation).** The first draft of this finding also claimed the
  > port field's *text* resets mid-edit. It does not: `onChanged` at `:141` writes to `selectedPort`,
  > so a valid numeric edit is reseeded intact. Reproducing the old pattern in a scratch widget test
  > showed the two user-visible defects are narrower and different:
  > - **Caret loss** — the replacement controller's selection defaults to invalid, so the caret jumps
  >   out of the port field on every IP keystroke (measured: `offset: 4` → `TextSelection.invalid`).
  > - **Silent reversion** — `int.tryParse(v) ?? selectedPort` at `:141` means *clearing* the port
  >   field leaves `selectedPort` at its old value, and the next rebuild repopulates the field with
  >   it (measured: cleared field → `"8060"`).
- **Impact.** Unbounded `ChangeNotifier` accumulation while the dialog is open; a caret that jumps out
  of the field; and a port the user cleared silently reverting behind them. Violates the Flutter
  contract that a widget-created `TextEditingController` must be disposed by that widget.
- **Remediation.** Promote the dialog to a `StatefulWidget` that owns its controllers — which also
  fixes the port-reset defect and makes the dialog independently testable (it is currently reachable
  only through the 11-second smoke test):

  ```dart
  // AFTER — lib/screens/manual_connect_dialog.dart
  class ManualConnectDialog extends StatefulWidget {
    const ManualConnectDialog({super.key});
    @override
    State<ManualConnectDialog> createState() => _ManualConnectDialogState();
  }

  class _ManualConnectDialogState extends State<ManualConnectDialog> {
    final _ipController   = TextEditingController();
    final _portController = TextEditingController(text: '8060');
    DeviceType _selectedType = DeviceType.roku;
    String? _ipError;

    @override
    void dispose() {
      _ipController.dispose();       // ← the disposal missing today
      _portController.dispose();
      super.dispose();
    }

    void _onTypeChanged(DeviceType t) => setState(() {
      _selectedType = t;
      // Mutate the existing controller instead of constructing a new one.
      _portController.text = '${kDefaultPorts[t] ?? 80}';
    });
    ...
  }

  // call site — device_scanner.dart:29-31
  void _handleManualConnect() =>
      showDialog(context: context, builder: (_) => const ManualConnectDialog());
  ```

  Hoist `defaultPorts` (`:38-43`) to a top-level `kDefaultPorts` shared with
  `connection_provider.dart:193-207`, which duplicates the same five port literals today.

---

#### H-4. Uncancelled `Future.delayed` timers mutate provider state after disposal

- **Location:** `lib/providers/scanner_provider.dart:43, 90-94, 196-198`;
  `lib/screens/device_scanner.dart:549-552`.
- **Observation.** Three related lifecycle defects:

  ```dart
  // scanner_provider.dart:90-94 — no handle kept, nothing can cancel it
  Future.delayed(const Duration(seconds: 10), () {
    if (state.isScanning) {              // ← `state` getter throws once disposed
      state = state.copyWith(isScanning: false);
    }
  });

  // scanner_provider.dart:196-198 — socket outlives stopScan()
  Future.delayed(const Duration(seconds: 8), () { socket.close(); });
  ```

  Neither delay is stored, so `ref.onDispose(() => stopScan(isDisposing: true))` at `:43` cannot
  cancel them. If the screen is torn down within 10 seconds of a scan — the common case, since
  auto-reconnect at `connection_provider.dart:74` runs at start-up and `main.dart:44-53` swaps the
  screen on success — the callback runs against a disposed `Notifier`. The `RawDatagramSocket` opened
  at `:167` likewise stays bound and listening for the full 8 s after `stopScan()`, and its
  `socket.listen` subscription (`:185`) is never cancelled.

  The Rescan button compounds it:

  ```dart
  // device_scanner.dart:549-552
  onTap: () {
    ref.read(scannerProvider.notifier).stopScan();   // ← async, NOT awaited
    ref.read(scannerProvider.notifier).startScan();  // races the line above
  },
  ```

  `stopScan` (`:102-116`) copies and clears `_discoveries`, then awaits `stopDiscovery` on each. The
  un-awaited call lets `startScan` append new `Discovery` handles while the previous teardown is still
  in flight — orphaning them beyond the next `stopScan`.
- **Impact.** `StateError` crashes after navigation; leaked mDNS discoveries and a leaked UDP socket
  per rescan; radio and battery cost that `stack-appendices.md` §4 names explicitly ("Battery, data
  and thermal cost are user-visible… avoid busy polling").
- **Remediation.**

  ```dart
  // AFTER — scanner_provider.dart
  Timer? _scanDeadline;
  Timer? _ssdpDeadline;
  RawDatagramSocket? _ssdpSocket;
  StreamSubscription<RawSocketEvent>? _ssdpSub;
  bool _disposed = false;

  @override
  ScannerState build() {
    ref.onDispose(() {
      _disposed = true;
      _scanDeadline?.cancel();
      _ssdpDeadline?.cancel();
      _ssdpSub?.cancel();
      _ssdpSocket?.close();
      stopScan(isDisposing: true);
    });
    return const ScannerState();
  }

  // replaces :90-94
  _scanDeadline?.cancel();
  _scanDeadline = Timer(const Duration(seconds: 10), () {
    if (_disposed) return;
    if (state.isScanning) state = state.copyWith(isScanning: false);
  });

  // AFTER — device_scanner.dart:549-552
  onTap: () async {
    final notifier = ref.read(scannerProvider.notifier);
    await notifier.stopScan();      // teardown completes before restart
    if (!mounted) return;
    await notifier.startScan();
  },
  ```

---

#### H-5. `ScannerState.copyWith` silently erases `error` on every unrelated update

- **Location:** `lib/providers/scanner_provider.dart:25-34` (esp. **33**), triggered from **92**,
  **114**, **161**, **270**.
- **Observation.** `error` is the one field not defaulted to its current value:

  ```dart
  // scanner_provider.dart:25-34
  ScannerState copyWith({bool? isScanning, List<Device>? devices, String? error}) =>
      ScannerState(
        isScanning: isScanning ?? this.isScanning,
        devices:    devices    ?? this.devices,
        error:      error,                       // ← line 33: NOT `error ?? this.error`
      );
  ```

  Any caller omitting `error` clears it. Line 97 sets `error: 'Discovery failed: $e'`; the 10-second
  deadline at `:92` then calls `copyWith(isScanning: false)` and wipes it — as does every device
  discovered afterwards (`:161`, `:270`) and every `stopScan` (`:114`). The error banner at
  `device_scanner.dart:308-318` therefore disappears on its own within seconds.
- **Impact.** A discovery failure — exactly the condition a user needs explained (permission denied,
  no Wi-Fi, multicast blocked by the router) — is shown briefly and then silently withdrawn. The
  asymmetry with `DeviceConnectionState.copyWith` (`connection_provider.dart:38-48`, which uses an
  explicit `clearError` flag) leaves the codebase with two contradictory conventions for one concept —
  a `SKILL.md` coherence breach.
- **Remediation.** Adopt the explicit-clear convention already present in the sibling provider:

  ```dart
  // AFTER — scanner_provider.dart:25-34
  ScannerState copyWith({
    bool? isScanning,
    List<Device>? devices,
    String? error,
    bool clearError = false,
  }) =>
      ScannerState(
        isScanning: isScanning ?? this.isScanning,
        devices:    devices    ?? this.devices,
        error:      clearError ? null : (error ?? this.error),
      );

  // and at :60, where clearing IS intended:
  state = state.copyWith(isScanning: true, devices: [], clearError: true);
  ```

  **Test (fails today):** set an error, call `copyWith(isScanning: false)`, assert the error survives.

---

#### H-6. `IrController` reports success while transmitting nothing

- **Location:** `lib/controllers/ir_controller.dart:15-41` (esp. **20**, **39-40**), **56-67**.
- **Observation.**

  ```dart
  // ir_controller.dart:16-22
  Future<void> connect() async {
    // In a real app, this would check for IR hardware via a platform channel.
    _connected = true;                 // ← unconditionally "connected"
    log.d('IrController: Initialized for brand $brand');
  }
  // ir_controller.dart:39-40
  log.d('IrController: Transmitting IR code for ${key.name} (${brand.toUpperCase()})');
  // Platform channel call would go here.        ← nothing is transmitted
  ```

  There is no `MethodChannel` anywhere in `lib/` (verified by grep), no `ConsumerIrManager` binding on
  the Android side (`MainActivity.kt` is the unmodified Flutter template), and no IR plugin in
  `pubspec.yaml`. `_irDatabase` (`:56-67`) holds three keys for two brands with patterns
  (`[170, 170, 13]`) that are not valid NEC/RC-5 burst timings. `flutter analyze` additionally reports
  both of this file's imports as unused (`:2`, `:4`) — it imports `UnsupportedDeviceException` and
  never throws it.
- **Impact.** `connect()` always succeeds, so `ConnectionNotifier` transitions to `connected`, the UI
  shows the green indicator, and every button silently does nothing — the same end-state as C-1 but
  reachable on day one. The commit message advertises "an Android IR blaster controller with
  brand-specific code mapping."
- **Remediation.** Until the platform channel exists, fail honestly — the file already imports the
  exception needed to do it, which is precisely why that import currently reads as unused:

  ```dart
  // AFTER — ir_controller.dart:15-22
  @override
  Future<void> connect() async {
    // IR transmission needs an Android ConsumerIrManager binding that does not exist
    // yet (no MethodChannel in lib/, MainActivity.kt is the stock template).
    // Reporting success here shows a "CONNECTED" remote that transmits nothing.
    throw const UnsupportedDeviceException(DeviceType.ir);
  }
  ```

  Then either implement `MethodChannel('devicecontroller/ir')` against
  `ConsumerIrManager.transmit(frequency, pattern)` with a `hasIrEmitter()` capability probe, or remove
  `DeviceType.ir` from `_buildController` (`connection_provider.dart:211`) and delete the stub —
  `design-judgment.md` §6: "Speculative generality → Inline it. Wait for evidence."

---

#### H-7. Vizio: treats HTTP 401 as connected, never obtains a token, and cannot complete TLS

- **Location:** `lib/controllers/vizio_controller.dart:19, 27-53, 89, 99-110`;
  `lib/services/device_persistence_service.dart:79-87`.
- **Observation.** Five compounding defects:
  1. `:42` — `if (response.statusCode == 200 || response.statusCode == 401) { _connected = true; }`.
     A 401 is the server stating the client is **not** authenticated; the code records it as success.
     The comment at `:41` even says "In a real scenario, we'd handle the 401 and start pairing."
  2. `:19` — `String? _authToken` is read at `:89` and **never assigned anywhere**: dead auth plumbing.
  3. `device_persistence_service.dart:81-87` provides `saveVizioToken` / `loadVizioToken`; neither is
     called from any file. The storage half of the pairing flow was built; the protocol half never was.
  4. `:28` builds `https://$host:$port/...` but uses a bare `http.Client()` (`:25`). Vizio SmartCast
     presents a **self-signed** certificate on 7345, which `dart:io`'s default `SecurityContext`
     rejects — so `connect()` throws `HandshakeException` in practice and, via H-2, burns 15 s of
     retries. (`dart:io` is imported at `:3` and unused — `flutter analyze` flags it — the fossil of a
     removed `HttpClient` / `badCertificateCallback`.)
  5. `launchApp` (`:105-110`) and `sendText` (`:99-102`) are logging stubs that return normally.
- **Impact.** Vizio is offered to users as a supported vendor (discovery at
  `scanner_provider.dart:249-252`, manual dialog at `device_scanner.dart:42`) and cannot work. Were it
  to connect, it would be unauthenticated and every command would 401 into a swallowed catch.
- **Remediation.** Short term make the state honest; medium term implement the pairing handshake using
  the persistence API that already exists:

  ```dart
  // BEFORE — vizio_controller.dart:36-47
  final response = await _client.get(_smartCastUri('state/device/info'))
      .timeout(const Duration(seconds: 3));
  if (response.statusCode == 200 || response.statusCode == 401) {
    _connected = true;
  }

  // AFTER
  _authToken = await _persistence.loadVizioToken(host);   // wire up the dead API
  final response = await _client.get(
    _smartCastUri('state/device/info'),
    headers: {if (_authToken != null) 'AUTH': _authToken!},
  ).timeout(const Duration(seconds: 3));

  switch (response.statusCode) {
    case 200:
      _connected = true;
    case 401 || 403:
      // Not an ambiguous success: reachable, but not paired.
      throw PairingRequiredException(host);   // drives the PIN-entry UI
    default:
      throw Exception('Vizio responded with status ${response.statusCode}');
  }
  ```

  Replace the bare client at `:25` with one that pins the device's self-signed certificate through the
  same TOFU helper Samsung uses (`device_persistence_service.dart:47-57`) — the mechanism exists and
  currently has exactly one caller.

---

#### H-8. The discovery screen has zero accessibility affordances

- **Location:** `lib/screens/device_scanner.dart` — whole file; specifically device rows
  (**571-647**), action buttons (**691-736**), and the dialog form inputs (**110-151**).
- **Observation.** `grep -c 'Semantics' lib/screens/device_scanner.dart` → **0**;
  `grep -c 'tooltip'` → **0**. The remote screen received `Semantics` in seven places
  (`remote.dart:367,510,686`; `remote_buttons.dart:28,152,180,218`); the discovery screen — the launch
  screen and the only route to the remote — received none:
  - `:588-592` — the device row is a bare `InkWell`; a screen reader announces its two `Text` children
    with no role, so the user never learns it is actionable.
  - `:702-703` — Rescan / Manual IP are `InkWell`s inside `Material` with no `button: true`.
  - `:110-129` and `:136-151` — the IP and Port `TextField`s have `hintText` but **no `labelText` and
    no `Semantics` label**; the visual labels at `:105-108` and `:131-134` are detached `Text` widgets
    with no programmatic association (`stack-appendices.md` §3: "labels on all inputs" / "Forms: label
    association").
  - `:493-501` — the empty state is not announced as a live region.
- **Impact.** The app is unusable with TalkBack/VoiceOver because the *first* screen is the
  inaccessible one, and the commit message states the opposite. Beyond the compliance exposure
  (`stack-appendices.md` §4), this is the clearest instance of the audit's central theme: a claim made
  without verification.
- **Remediation.**

  ```dart
  // BEFORE — device_scanner.dart:586-593
  child: Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => ref.read(connectionProvider.notifier).connect(device),

  // AFTER
  child: Semantics(
    label: '${device.name}, ${device.type.name} device, ${device.model}',
    hint: 'Double tap to connect',
    button: true,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => ref.read(connectionProvider.notifier).connect(device),

  // BEFORE — device_scanner.dart:110-121 (label is a detached Text at :105-108)
  TextField(
    controller: ipController,
    decoration: InputDecoration(hintText: 'e.g., 192.168.1.105', errorText: ipError, ...),

  // AFTER — real label association
  TextField(
    controller: _ipController,
    decoration: InputDecoration(
      labelText: 'IP Address',
      hintText: 'e.g., 192.168.1.105',
      errorText: _ipError,
      ...
  ```

  Then add the automated guard, so the claim becomes checkable rather than asserted:

  ```dart
  testWidgets('discovery screen meets accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
  ```

---

#### H-9. The test suite is 27 % coverage, contains an assertion-free test, and touches the real network

- **Location:** `test/providers/scanner_provider_test.dart:27-35`;
  `test/providers/connection_provider_test.dart:80-109`; `test/widget_test.dart:1-43`; coverage
  measured across `lib/`.
- **Observation.** Measured via `flutter test --coverage` (`coverage/lcov.info`):

  | File | Covered / Total | % |
  |---|---:|---:|
  | `lib/screens/remote.dart` | 0 / 388 | **0.0** |
  | `lib/widgets/remote_buttons.dart` | 0 / 105 | **0.0** |
  | `lib/controllers/lg_controller.dart` | 0 / 76 | **0.0** |
  | `lib/controllers/vizio_controller.dart` | 0 / 41 | **0.0** |
  | `lib/controllers/fire_tv_controller.dart` | 0 / 10 | **0.0** |
  | `lib/controllers/google_tv_controller.dart` | 0 / 10 | **0.0** |
  | `lib/models/device.dart` | 2 / 56 | 3.6 |
  | `lib/controllers/ir_controller.dart` | 1 / 16 | 6.2 |
  | `lib/services/device_persistence_service.dart` | 5 / 29 | 17.2 |
  | `lib/providers/scanner_provider.dart` | 32 / 102 | 31.4 |
  | `lib/providers/connection_provider.dart` | 47 / 86 | 54.7 |
  | `lib/controllers/samsung_controller.dart` | 53 / 93 | 57.0 |
  | `lib/controllers/roku_controller.dart` | 39 / 45 | 86.7 |
  | **Total** | **385 / 1,415** | **27.2** |

  Quality problems inside the 20 passing tests:

  ```dart
  // scanner_provider_test.dart:27-35 — passes, asserts nothing
  test('SSDP mapping - Roku', () {
    final notifier = container.read(scannerProvider.notifier);
    // We need to trigger the private _handleSsdpResponse
    // Since it's private, we can't call it directly in a clean way,
    // but for the sake of "implementing each and every task",
    // we might need to make it public or use a test-only wrapper.
    // However, I'll assume we can use a helper or just test the side effects.
  });
  ```

  ```dart
  // connection_provider_test.dart:92-105 — real socket, real wall clock
  final badDevice = Device(id: 'bad-ip', ..., ip: '0.0.0.0');
  notifier.connect(badDevice);
  async.elapse(const Duration(seconds: 40));
  ```

  The run log confirms four genuine `TimeoutException after 0:00:03.000000` cycles against
  `RokuController.connect` (`roku_controller.dart:79`) over ~30 s of real time — `fakeAsync` cannot
  virtualise a real `dart:io` socket. `testing-quality.md`: "Deterministic: no real clock, **no real
  network**", and "a 'unit' test that mocks the database to test a query proves nothing."
  `test/widget_test.dart` is one smoke test that pumps 11 seconds and asserts on three string literals.
- **Impact.** The suite gives false assurance: it is green while C-1, C-2, H-1, H-5 and H-6 are all
  live, and every one of those is reachable by a cheap unit test. It is also slow and
  environment-dependent, which `testing-quality.md` classifies as a production defect.
- **Remediation.** Extract the pure parsing logic behind a testable seam (this also closes **M-3**):

  ```dart
  // AFTER — scanner_provider.dart: pure function, no I/O
  @visibleForTesting
  Device? parseSsdpResponse(String response, String sourceIp) { ... }

  // AFTER — test/providers/ssdp_parser_test.dart
  test('maps a Roku SERVER header to DeviceType.roku on port 8060', () {
    const raw = 'HTTP/1.1 200 OK\r\n'
                'SERVER: Roku UPnP/1.0 MiniUPnPd/1.4\r\n'
                'LOCATION: http://192.168.1.50:8060/\r\n\r\n';
    final device = notifier.parseSsdpResponse(raw, '192.168.1.50');
    expect(device?.type, DeviceType.roku);
    expect(device?.port, 8060);
  });

  test('ignores a response without a 200 status line', () {
    expect(notifier.parseSsdpResponse('HTTP/1.1 404 Not Found\r\n\r\n', '10.0.0.1'), isNull);
  });

  test('does not crash on a truncated LOCATION header', () {          // boundary case
    expect(notifier.parseSsdpResponse('HTTP/1.1 200 OK\r\nLOCATION:\r\n\r\n', '10.0.0.1'), isNull);
  });
  ```

  Target for Phase 3: **70 % line coverage overall, with `lg_controller`, `vizio_controller`,
  `device_persistence_service` and `remote.dart` each above 60 %**, enforced in CI.

---
### MEDIUM

---

#### M-1. Side effects and expensive work inside `build()`; the whole app rebuilds on every status change

- **Location:** `lib/main.dart:18-43` (esp. **19**, **22-29**, **42**); `lib/screens/remote.dart:101`.
- **Observation.** Three problems in one 25-line method:

  ```dart
  // main.dart:18-43
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(connectionProvider);      // :19 — watches the WHOLE state

    SystemChrome.setSystemUIOverlayStyle(                  // :22 — side effect in build()
      const SystemUiOverlayStyle(...),
    );

    return MaterialApp(
      theme: ThemeData(
        ...
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),  // :42
      ),
  ```

  `ref.watch(connectionProvider)` subscribes the root widget to the entire `DeviceConnectionState`, so
  every transition — `connecting`, each of the four retry `error` updates, `connected` — rebuilds
  `MaterialApp`, reconstructs `ThemeData`, and re-runs `GoogleFonts.interTextTheme()`, which walks and
  copies all 15 `TextStyle` slots of the dark text theme. The platform-channel call at `:22` fires on
  every one of those rebuilds. `testing-quality.md` → "**Push side effects to the edges**"; and
  `performance-efficiency.md` → "Work done per-request that could be done once."

  `remote.dart:101` repeats the pattern at screen level: the 964-line remote screen watches the whole
  connection state, so a single `errorMessage` change rebuilds the D-pad, the touchpad, the numpad and
  the app grid.
- **Impact.** Avoidable jank at exactly the moment the user is waiting (connection transitions), plus
  a platform channel invoked dozens of times per session for a value that never changes.
- **Remediation.**

  ```dart
  // AFTER — main.dart
  void main() {
    WidgetsFlutterBinding.ensureInitialized();
    // Set once at startup, not on every rebuild.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    runApp(const ProviderScope(child: MyApp()));
  }

  class MyApp extends ConsumerWidget {
    const MyApp({super.key});

    // Built once, not per frame.
    static final _theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
          primary: Colors.indigoAccent, surface: AppColors.surface),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    );

    @override
    Widget build(BuildContext context, WidgetRef ref) {
      // Watch only what selects the route, not the whole state object.
      final connected = ref.watch(
        connectionProvider.select((s) => s.status == ConnectionStatus.connected));
      final device = ref.watch(connectionProvider.select((s) => s.device));

      return MaterialApp(
        title: 'Universal Remote',
        debugShowCheckedModeBanner: false,
        theme: _theme,
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: connected && device != null
              ? RemoteScreen(
                  key: ValueKey(device.id),
                  device: device,
                  onDisconnect: () =>
                      ref.read(connectionProvider.notifier).disconnect())
              : const DeviceScannerScreen(),
        ),
      );
    }
  }
  ```

  The `device != null` guard also removes the two force-unwraps at `main.dart:48-49`
  (`connection.device!`), which today rely on an invariant no type enforces.

---

#### M-2. Full-viewport `BackdropFilter`, perpetual animations, and no `RepaintBoundary` anywhere

- **Location:** `lib/screens/device_scanner.dart:222-270`, `:393-420`, `:463-465`, `:505-515`;
  `lib/screens/remote.dart:134-137`, `:221-226`, `:575-579`. Repo-wide: `grep -rn RepaintBoundary lib/`
  → **no matches**.
- **Observation.**
  - Both screens paint two large `Container`s and then a **full-screen `BackdropFilter`** over them
    (`device_scanner.dart:267-270` at sigma 50; `remote.dart:134-137` at sigma 15). `BackdropFilter`
    forces a saveLayer over its entire parent bounds and re-blurs every frame that anything beneath it
    changes. `remote.dart:535` adds a *second*, nested `BackdropFilter` inside the touchpad and
    `remote.dart:778` a third inside the keyboard overlay.
  - `.animate(onPlay: (c) => c.repeat())` runs forever on at least four widgets
    (`device_scanner.dart:393`, `:411`, `:463`; `remote.dart:221`, `:575`) — including
    `remote.dart:575-579`, which pulses the touchpad icon continuously *while the touchpad is not the
    visible tab*, because all three `TabBarView` children stay alive.
  - `device_scanner.dart:510-513` attaches `.animate().fadeIn(delay: (index * 100).ms)` inside
    `ListView.builder`'s `itemBuilder`, so the animation restarts each time an item is recycled during
    scrolling, and the delay grows without bound with list length.
  - No `RepaintBoundary` anywhere means the perpetual animations dirty their whole enclosing layer.
- **Impact.** Continuous GPU and CPU cost on a screen whose purpose is to sit idle waiting for button
  presses — directly against `stack-appendices.md` §4 ("Battery, data and thermal cost are
  user-visible"). The `remote.dart:133` comment ("sigma reduced to 15 (Requirement 2.30)") shows the
  cost was noticed and addressed by decree rather than by measurement, contrary to
  `performance-efficiency.md`'s governing rule.
- **Remediation.**

  ```dart
  // BEFORE — device_scanner.dart:222-270: two coloured circles + a 50-sigma full-screen blur
  Positioned(top: -100, left: -100, child: Container(width: 300, height: 300, ...)),
  Positioned(bottom: -50, right: -50, child: Container(width: 250, height: 250, ...)),
  BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
    child: Container(color: Colors.transparent),
  ),

  // AFTER — a static gradient reproduces the look at zero per-frame cost
  const Positioned.fill(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.8, -0.9),
          radius: 1.2,
          colors: [Color(0x26465DFF), Color(0x00000000)],
        ),
      ),
    ),
  ),

  // AFTER — cap the stagger and isolate repaints (device_scanner.dart:508-514)
  itemBuilder: (context, index) {
    final device = devices[index];
    return RepaintBoundary(
      child: _buildDeviceItem(device)
          .animate()
          .fadeIn(duration: 400.ms, delay: (min(index, 6) * 60).ms)   // bounded stagger
          .slideX(begin: 0.1, end: 0),
    );
  },

  // AFTER — stop off-screen animation (remote.dart:146-154)
  TabBarView(
    controller: _tabController,
    children: [
      _buildNavigationMode(),
      // Only animate the touchpad hint while the touchpad is the visible tab.
      if (activeTab == 1) _buildTouchpadMode() else const _TouchpadPlaceholder(),
      _buildNumpadMode(),
    ],
  ),
  ```

  Then measure: `flutter run --profile` with `debugProfileBuildsEnabled`, and record the before/after
  frame times in the PR body — that is the evidence `performance-efficiency.md` asks for.

---

#### M-3. `_buildController` is a closed switch inside the notifier: not extensible, not injectable, not testable

- **Location:** `lib/providers/connection_provider.dart:182-214` (esp. **184**, **188**, **190-213**).
- **Observation.** The factory is a private method on the state class:

  ```dart
  DeviceController _buildController(Device device) {
    if (device.id.startsWith('mock-')) {            // :184 — string-prefix magic
      return MockController(deviceName: device.name);
    }
    final persistence = ref.read(devicePersistenceProvider);   // :188 — re-resolves a cached field
    return switch (device.type) {
      DeviceType.roku    => RokuController(host: device.ip!, port: device.port ?? 8060),
      ...
    };
  }
  ```

  Three consequences:
  1. **Not extensible.** Adding a vendor edits a core class — precisely the "likely change is
     **local**" property `design-judgment.md` §4 asks for and this design lacks.
  2. **Not injectable**, so tests cannot substitute a fake controller. The test file says so in its own
     comments: *"ConnectionNotifier._buildController creates real controllers. I can't easily mock the
     controller itself without more refactoring"* (`connection_provider_test.dart:87-89`) — which is
     exactly why that test opens a real socket (H-9). This is the concrete link between the
     architectural gap and the test gap.
  3. **`device.ip!`** is force-unwrapped seven times (`:192, 197, 202, 206`); a persisted `Device` with
     a null `ip` (permitted by `device.dart:52` and by `Device.fromJson` at `:81`) crashes on
     auto-reconnect at `connection_provider.dart:83`.
  4. `MockController` (`lib/controllers/mock_controller.dart`, 59 lines) ships in the release bundle and
     is selected by a string prefix on a user-influenced field.
- **Impact.** One design choice produces the extensibility ceiling, the untestability, and a
  null-dereference crash path.
- **Remediation.** Extract the factory to an injected provider — a seam, not a framework:

  ```dart
  // NEW — lib/controllers/device_controller_factory.dart
  typedef DeviceControllerFactory = DeviceController Function(Device);

  DeviceController buildDeviceController(Device device, DevicePersistenceService p) {
    final host = device.ip;
    if (host == null || host.isEmpty) {
      throw ArgumentError.value(device.ip, 'device.ip', 'a network device needs an address');
    }
    return switch (device.type) {
      DeviceType.roku    => RokuController(host: host, port: device.port ?? kDefaultPorts[DeviceType.roku]!),
      DeviceType.samsung => SamsungController(host: host, port: device.port ?? 8001, persistence: p),
      DeviceType.lg      => LgController(host: host, port: device.port ?? 3000, persistence: p),
      DeviceType.vizio   => VizioController(host: host, port: device.port ?? 7345, persistence: p),
      DeviceType.fireTv  => FireTvController(),
      DeviceType.googleTv=> GoogleTvController(),
      DeviceType.ir      => IrController(brand: device.model),
      DeviceType.unknown => throw UnsupportedDeviceException(device.type),
    };
  }

  final deviceControllerFactoryProvider = Provider<DeviceControllerFactory>((ref) {
    final persistence = ref.watch(devicePersistenceProvider);
    return (device) => buildDeviceController(device, persistence);
  });

  // AFTER — connection_provider.dart
  late final DeviceControllerFactory _makeController;   // resolved once in build()
  ...
  _controller = _makeController(device);                // replaces :112 and :182-214

  // AFTER — connection_provider_test.dart: no more real sockets
  container = ProviderContainer(overrides: [
    devicePersistenceProvider.overrideWithValue(mockPersistence),
    connectivityServiceProvider.overrideWithValue(mockConnectivity),
    deviceControllerFactoryProvider.overrideWithValue((_) => AlwaysFailingController()),
  ]);
  ```

  Move `MockController` to `test/fakes/` so it stops shipping, and delete the `'mock-'` prefix branch.

---

#### M-4. `RokuController.sendText` issues one blocking HTTP round trip per character, with no cap

- **Location:** `lib/controllers/roku_controller.dart:108-122`.
- **Observation.**

  ```dart
  Future<void> sendText(String text) async {
    if (!_connected) return;
    for (final rune in text.runes) {                       // :111 — serial, unbounded
      final char = String.fromCharCode(rune);
      final encoded = Uri.encodeComponent(char);
      try {
        await _client.post(_ecpUri('keypress/Lit_$encoded'))
            .timeout(const Duration(seconds: 3));          // :117 — 3 s each
      } catch (e) {
        log.e('RokuController: Failed to send char "$char"', e);   // continues regardless
      }
    }
  }
  ```

  Roku ECP genuinely requires one `Lit_` POST per character, so the loop itself is correct — but there
  is no length cap (Samsung caps at 500, `samsung_controller.dart:233`), no inter-key delay (Roku drops
  keypresses above ~20/s), no cancellation, and a mid-string failure is logged and skipped, silently
  producing a *different string* on the TV than the user typed.
- **Impact.** A pasted URL is minutes of blocked I/O; a flaky link yields silently corrupted text.
  `performance-efficiency.md` → "Serial I/O that could be concurrent" and "Unbounded result sets".
- **Remediation.**

  ```dart
  // AFTER — roku_controller.dart:108-122
  static const _maxTextLength = 500;      // parity with SamsungController:233
  static const _interKeyDelay = Duration(milliseconds: 60);   // Roku ECP drops >~20 keys/s

  @override
  Future<void> sendText(String text) async {
    if (!_connected) return;
    if (text.length > _maxTextLength) {
      log.w('RokuController: truncating ${text.length}-char input to $_maxTextLength');
      text = text.substring(0, _maxTextLength);
    }
    for (final (i, rune) in text.runes.indexed) {
      if (!_connected) return;                     // honour disconnect mid-string
      final char = String.fromCharCode(rune);
      try {
        await _client
            .post(_ecpUri('keypress/Lit_${Uri.encodeComponent(char)}'))
            .timeout(const Duration(seconds: 3));
      } catch (e, s) {
        // Abort rather than silently sending a different string than the user typed.
        throw TextEntryException(sentCharacters: i, total: text.runes.length, cause: e, stackTrace: s);
      }
      if (i + 1 < text.runes.length) await Future<void>.delayed(_interKeyDelay);
    }
  }
  ```

---

#### M-5. The numpad sends digits as IME text rather than as remote key presses

- **Location:** `lib/screens/remote.dart:666-729` (esp. **693-696**); `lib/models/remote_key.dart:1-49`.
- **Observation.** `RemoteKey` has no digit members, so the numpad routes through the text channel:

  ```dart
  // remote.dart:693-695
  onTap: () {
    ref.read(connectionProvider.notifier).sendText(num);
    HapticFeedback.lightImpact();
  },
  ```

  On Roku that becomes `POST /keypress/Lit_1` — a *literal character*, only meaningful when an on-screen
  text field has focus. On Samsung it becomes a base64 `SendInputString` IME payload
  (`samsung_controller.dart:236-243`) rather than the `KEY_1`…`KEY_0` codes the protocol provides.
  Neither changes the channel, which is what a numpad on a TV remote is for.
- **Impact.** The numpad tab — one of three primary modes in the bottom bar (`remote.dart:898`) — does
  not perform its advertised function on either supported vendor. On LG (`lg_controller.dart:150-160`)
  it fires an `insertText` SSAP request with no focused field, a no-op.
- **Remediation.** Model digits as first-class keys, per `testing-quality.md` "Use the domain's
  ubiquitous language":

  ```dart
  // AFTER — remote_key.dart
  enum RemoteKey {
    ...
    // Channel entry — distinct from text input, which is RemoteKey-free.
    digit0, digit1, digit2, digit3, digit4, digit5, digit6, digit7, digit8, digit9,
  }

  // AFTER — roku_controller.dart:_keyMap
  RemoteKey.digit0: 'Lit_0',   // Roku has no dedicated digit keys; Lit_ is correct here
  ...
  // AFTER — samsung_controller.dart:_keyMap
  RemoteKey.digit0: 'KEY_0',   // Samsung DOES have them — use them
  RemoteKey.digit1: 'KEY_1',
  ...
  // AFTER — remote.dart:693
  onTap: () => _sendKey(RemoteKey.values.byName('digit$num')),
  ```

---

#### M-6. Duplicate device entries across the two discovery paths, plus a dead `signal` field

- **Location:** `lib/providers/scanner_provider.dart:148-161`, `:257-268`; `lib/models/device.dart:51`.
- **Observation.** Both discovery paths dedupe on the pair `(ip, port)`:

  ```dart
  // scanner_provider.dart:149  (mDNS)  and  :258 (SSDP) — identical predicate
  if (existing.any((d) => d.ip == ip && d.port == resolvedPort)) return;
  ```

  but the two paths assign ports independently. A Samsung TV answering mDNS is normalised to 8002
  (`:140`) while the same TV answering SSDP may be assigned 8001 (`:240`); a device answering
  `_http._tcp` on 80 keeps port 80 (`:130`) while its SSDP record maps to 8060. The user then sees the
  same physical television listed two or three times with different names ("Samsung TV" vs. the mDNS
  service name).

  Separately, `Device.signal` (`device.dart:51`) is hardcoded to `100` at both construction sites
  (`:156`, `:265`) and rendered nowhere — `design-judgment.md` §6, "no 'just in case' configuration".
- **Impact.** A confusing device list where some duplicates connect and others fail (H-7 for the Vizio
  duplicate, C-1 for the Samsung one). The user has no way to tell which entry is the working one.
- **Remediation.** Dedupe on the device's stable identity (its IP), merging rather than dropping, and
  delete the dead field:

  ```dart
  // AFTER — a single upsert used by BOTH discovery paths
  void _upsertDevice(Device candidate) {
    final byHost = {for (final d in state.devices) d.ip: d};
    final existing = byHost[candidate.ip];
    if (existing != null) {
      // Prefer the more specific type and the discovery that named the device.
      byHost[candidate.ip] = existing.copyWith(
        type: existing.type == DeviceType.unknown ? candidate.type : existing.type,
        name: existing.name.isEmpty ? candidate.name : existing.name,
        port: existing.port ?? candidate.port,
      );
    } else {
      byHost[candidate.ip] = candidate;
    }
    state = state.copyWith(devices: byHost.values.toList(growable: false));
  }
  ```

---

#### M-7. No global error handler, no crash reporting, and unstructured logs

- **Location:** `lib/main.dart:10-12`; `lib/core/app_logger.dart:1-39`. Repo-wide greps for
  `FlutterError`, `PlatformDispatcher`, `runZonedGuarded` in `lib/` → **no matches**.
- **Observation.** `main()` is three lines and installs no error handling. Every uncaught async
  error — including the `FormatException` that C-1 throws on every heartbeat — is silently dropped in
  release. `AppLogger` writes human prose through `PrettyPrinter` (`:11-18`) to the local console only:
  no sink, no correlation id, no structured fields, no device or session identity. In release,
  `level: Level.warning` (`:19`) means `log.d` calls vanish — including the only record that a Samsung
  token was persisted (`samsung_controller.dart:149`).
- **Impact.** Fails the stated observability bar outright: "you can diagnose a novel production problem
  without shipping new code." Every finding in this report would have been invisible in the field.
- **Remediation.**

  ```dart
  // AFTER — main.dart
  void main() {
    runZonedGuarded(() {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        log.e('flutter_error', details.exception, details.stack);
        CrashReporter.instance.record(details.exception, details.stack);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        log.e('uncaught_async', error, stack);       // ← catches the C-1 FormatException
        CrashReporter.instance.record(error, stack);
        return true;
      };

      SystemChrome.setSystemUIOverlayStyle(...);
      runApp(const ProviderScope(child: MyApp()));
    }, (error, stack) {
      log.e('zone_error', error, stack);
      CrashReporter.instance.record(error, stack);
    });
  }

  // AFTER — app_logger.dart: structured fields, not interpolated prose
  void event(String name, {Map<String, Object?> fields = const {}, Object? error, StackTrace? st}) =>
      _logger.i(jsonEncode({
        'event': name,
        'session': _sessionId,          // correlation id across a session
        ...fields,
      }), error: error, stackTrace: st);

  // call site — connection_provider.dart:125
  log.event('connect_retry',
      fields: {'device_type': device.type.name, 'attempt': attempt, 'delay_ms': delay});
  ```

---

#### M-8. Dead code, commented-out code, and 15 analyzer warnings shipped

- **Location:** as listed below.
- **Observation.** `flutter analyze` output, verbatim, for `lib/`:

  ```
  warning - Unused import: '../exceptions/unsupported_device_exception.dart' - lib\controllers\ir_controller.dart:2:8
  warning - Unused import: '../models/device.dart'                          - lib\controllers\ir_controller.dart:4:8
  warning - The '!' will have no effect because the receiver can't be null  - lib\controllers\samsung_controller.dart:96:37
  warning - The '!' will have no effect because the receiver can't be null  - lib\controllers\samsung_controller.dart:135:35
  warning - Unused import: 'dart:io'                                        - lib\controllers\vizio_controller.dart:3:8
     info - Use the null-aware marker '?' rather than a null check via an 'if' - lib\controllers\vizio_controller.dart:89:11
  ```

  plus 9 more in `test/` (5 unused imports and 3 unused locals in `scanner_provider_test.dart` /
  `connection_provider_test.dart`, 1 in `samsung_controller_test.dart`). Beyond the analyzer:
  - `device_scanner.dart:233-242` and `:255-264` — 20 lines of commented-out `.animate()` chains.
  - `vizio_controller.dart:19,89` — `_authToken` read but never assigned;
    `device_persistence_service.dart:81-87` — `saveVizioToken`/`loadVizioToken` never called.
  - `device.dart:51` — `signal`, always `100`, never rendered.
  - `mock_controller.dart` — 59 lines of test double in the production bundle.
  - `remote.dart:29` — `SingleTickerProviderStateMixin` with `TabController(length: 3)` while
    `_buildBottomBar` renders **four** tab buttons (`:896-905`), the fourth (`index: 3`) overriding
    `onTap` to dodge the missing tab. A future edit that removes `onTap` produces a range error.
  - The three unused imports in `ir_controller.dart` and `vizio_controller.dart` are not cosmetic —
    each is the fossil of a removed behaviour (the IR exception path in H-6, the Vizio
    `badCertificateCallback` in H-7).
- **Impact.** `testing-quality.md` → "Lint, typecheck and build clean — no new warnings" and "Delete
  commented-out code… no dead code, no unused exports." Warning noise means the next real warning is
  ignored.
- **Remediation.** Delete all of the above, then make the state enforceable:

  ```yaml
  # AFTER — analysis_options.yaml (currently only `include: package:flutter_lints/flutter.yaml`)
  include: package:flutter_lints/flutter.yaml

  analyzer:
    language:
      strict-casts: true
      strict-raw-types: true
    errors:
      unused_import: error
      unused_local_variable: error
      unawaited_futures: error        # would have caught H-4 and the :108 fire-and-forget in C-2
      dead_code: error                # would have caught C-1
    exclude:
      - "**/*.mocks.dart"

  linter:
    rules:
      - always_declare_return_types
      - avoid_dynamic_calls          # would have caught samsung_controller.dart:154-156
      - cancel_subscriptions         # would have caught H-4
      - close_sinks
      - prefer_const_constructors
      - use_build_context_synchronously
  ```

  Note `dead_code: error` and `unawaited_futures: error` would each have blocked a Critical finding at
  commit time — the cheapest control in this entire report.

---

#### M-9. No CI, no build gate, and a template application id

- **Location:** repository root (`ls .github` → does not exist);
  `android/app/build.gradle.kts:24`; `README.md:1-17`.
- **Observation.** There is no `.github/`, no pipeline definition of any kind, and therefore nothing
  runs `flutter analyze` or `flutter test` on a commit. `applicationId = "com.example.devicecontroller"`
  is the Flutter template default — Google Play rejects `com.example.*`. `README.md` is the unmodified
  "A new Flutter project" template: no architecture note, no run instructions, no supported-device
  matrix, no test command. Git history shows one 25-line-summary commit (`793e846`) touching the entire
  repository, preceded by `ef187a5 "Test Feature"`.
- **Impact.** `lifecycle-gates.md` Stage 8 exit gate ("Rollback path stated and actually possible")
  cannot be satisfied; `stack-appendices.md` §5 ("CI on every commit: build, lint, typecheck, test,
  security scan") is entirely unmet. The app cannot be published as configured.
- **Remediation.**

  ```yaml
  # NEW — .github/workflows/ci.yml
  name: CI
  on: [push, pull_request]
  jobs:
    verify:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - uses: subosito/flutter-action@v2
          with: { flutter-version: '3.x', channel: stable }
        - run: flutter pub get
        - run: dart format --output=none --set-exit-if-changed lib test
        - run: flutter analyze --fatal-infos --fatal-warnings   # currently 15 issues → fails today
        - run: flutter test --coverage
        - name: Enforce coverage floor
          run: |
            pct=$(awk -F: '/^LH:/{h+=$2} /^LF:/{f+=$2} END{printf "%.0f", h*100/f}' coverage/lcov.info)
            echo "coverage: ${pct}%"
            [ "$pct" -ge 60 ] || { echo "coverage ${pct}% below floor 60%"; exit 1; }
  ```

  Set `applicationId = "com.<yourorg>.universalremote"` and rewrite `README.md` with the supported-device
  matrix, the architecture diagram, and the verification commands.

---

#### M-10. Every user-facing string is hardcoded in a widget

- **Location:** ~80 literals, e.g. `device_scanner.dart:57` `'Connect via IP'`, `:283` `'Discover'`,
  `:298` `'Looking for nearby smart devices...'`, `:455` `'Scanning Network...'`, `:494` `'No devices
  found.\nEnsure you share the same Wi-Fi network.'`; `remote.dart:229` `'CONNECTED'`, `:585` `'SWIPE TO
  NAVIGATE • TAP TO CLICK'`, `:810` `'Type to search...'`, `:859` `'Dismiss Keyboard'`.
- **Observation.** No `flutter_localizations`, no `.arb` files, no `AppLocalizations`. Error strings are
  also built by concatenation of raw exception text — `device_scanner.dart:206`
  `'Connection failed: ${next.errorMessage}'` where `errorMessage` is `e.toString()`
  (`connection_provider.dart:134`), so users are shown
  `"Connection failed: TimeoutException after 0:00:03.000000: Future not completed"`. That is both an
  i18n violation and a `security-privacy.md` one: "Error responses to clients are generic; details go
  to logs."
- **Impact.** `stack-appendices.md` §3 names this the cheap seam that must exist from day one; the
  product targets the USA, where ~13 % of households are Spanish-speaking. Retrofitting touches every
  widget file.
- **Remediation.**

  ```dart
  // AFTER — lib/l10n/app_en.arb
  {
    "discoverTitle": "Discover",
    "scanningSubtitle": "Looking for nearby smart devices…",
    "devicesFound": "{count, plural, =0{No devices found} =1{1 nearby device found} other{{count} nearby devices found}}",
    "connectionFailedGeneric": "Couldn't connect to {deviceName}. Check that it's on and on this Wi-Fi network."
  }

  // AFTER — device_scanner.dart:296-307 (replaces the nested ternary AND the string concat)
  final l10n = AppLocalizations.of(context)!;
  Text(scanner.isScanning ? l10n.scanningSubtitle : l10n.devicesFound(scanner.devices.length))

  // AFTER — connection_provider.dart:134: keep the raw cause in logs, not on screen
  state = DeviceConnectionState(
    status: ConnectionStatus.error,
    device: device,
    errorMessage: _userMessage(e),     // maps the exception type to a localised key
  );
  ```

---

### LOW

---

#### L-1. Design tokens are duplicated as raw hex across four files

- **Location:** `main.dart:26,37,40`; `device_scanner.dart:52,79,218,673-687`; `remote.dart:105,315,391,392,783`;
  `remote_buttons.dart:54,96,173`.
- **Observation.** `0xFF09090B` (background) appears in 4 files, `0xFF18181B` (surface) in 4,
  `0xFF27272A` in 2, `0xFF71717A` in 2, and `Colors.indigoAccent` in more than 30 places — while
  `MaterialApp.theme` (`main.dart:34-43`) already defines a `ColorScheme` that almost none of them read.
- **Impact.** `testing-quality.md` → "No magic numbers or strings." A brand refresh is a
  find-and-replace across four files with no compiler help; a light theme is impossible.
- **Remediation.** One `AppColors` class (or better, extend `ThemeExtension`), referenced everywhere:

  ```dart
  // NEW — lib/theme/app_colors.dart
  abstract final class AppColors {
    static const background   = Color(0xFF09090B);
    static const surface      = Color(0xFF18181B);
    static const surfaceRaised= Color(0xFF27272A);
    static const textMuted    = Color(0xFF71717A);   // zinc-500
    static const connected    = Color(0xFF69F0AE);
  }
  ```

#### L-2. `DeviceConnectionState.copyWith` cannot clear `device`

- **Location:** `lib/providers/connection_provider.dart:38-48` (esp. **46**).
- **Observation.** `device: device ?? this.device` makes it impossible to transition to a
  device-less state through `copyWith`; `disconnect()` (`:149`) works around it by constructing
  `const DeviceConnectionState()` directly. The class has a `clearError` flag but no `clearDevice`.
- **Remediation.** Add `bool clearDevice = false` for symmetry with `clearError`, or migrate both
  states to `freezed` / a `sealed class` hierarchy where `Disconnected` simply has no `device` field —
  which would also delete the two force-unwraps at `main.dart:48-49`.

#### L-3. `_retryDelays` and `_maxRetries` are two constants that must agree

- **Location:** `lib/providers/connection_provider.dart:55-56`.
- **Observation.** `static const _maxRetries = 4;` and `static const _retryDelays = [1, 2, 4, 8];`
  are indexed together at `:124` (`_retryDelays[_retryCount]`). Changing `_maxRetries` to 5 without
  extending the list is a `RangeError` at runtime, on the error path, in production.
- **Remediation.** Derive one from the other — the H-2 rewrite computes the delay as
  `_baseDelay * (1 << attempt)` and removes the list entirely.

#### L-4. `stopScan(isDisposing:)` is a boolean parameter that selects behaviour

- **Location:** `lib/providers/scanner_provider.dart:102-116` (esp. **102**, **113-115**).
- **Observation.** `testing-quality.md`: "Boolean parameters that select behavior are a smell — two
  named functions are clearer than `process(true)`." Here the flag exists solely to skip a `state`
  write that would throw during disposal — a symptom of the missing `_disposed` guard in H-4.
- **Remediation.** With the H-4 `_disposed` field in place, the parameter becomes unnecessary:
  `stopScan()` guards its own state write and the dispose callback calls the same method.

#### L-5. Manual-connect IP validation accepts malformed addresses

- **Location:** `lib/screens/device_scanner.dart:45-48`.
- **Observation.** The IPv4 half of the regex, `^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$`, makes the
  dot optional (`\.?`) and allows an empty alternative in the second group, so `1234` and `1.2.3` can
  match while a legitimate compressed IPv6 address (`fe80::1`) cannot. The IPv6 half requires exactly
  eight full groups.
- **Remediation.** Use the platform parser rather than a hand-rolled regex — `security-privacy.md`:
  "Use standard, vetted library primitives":

  ```dart
  // AFTER
  String? _validateHost(String value) {
    if (value.trim().isEmpty) return 'Enter the TV\'s IP address';
    return InternetAddress.tryParse(value.trim()) == null ? 'Not a valid IP address' : null;
  }
  ```

#### L-6. `RemoteScreen` state is not restorable across process death

- **Location:** `lib/screens/remote.dart:28-59` (esp. **30-31**).
- **Observation.** `activeTab` and `showKeyboard` are plain fields on `State`; no `RestorationMixin`,
  no `restorationId` anywhere in the repo. `stack-appendices.md` §4 lists "process death and state
  restoration" as a mobile requirement.
- **Remediation.** Adopt `RestorationMixin` with `RestorableInt activeTab` and `RestorableBool
  showKeyboard`, and set `restorationScopeId` on `MaterialApp` (`main.dart:31`).

---

## 4. Architectural & Product Evolution Strategy

### What is already right, and must survive the refactor

Two decisions in this codebase are better than the median for an app of this size, and a refactor
should protect them rather than "clean them up":

1. **The `DeviceController` interface is a correctly earned abstraction.** Run it through
   `design-judgment.md` §2 honestly: seven concrete cases exist *today* (Gate 1); they vary for one
   reason — the wire protocol (Gate 2); protocol is the volatile axis while the remote's key
   vocabulary is stable (Gate 3); the interface removes a protocol `switch` from every call site
   (Gate 4); and the third case, LG, was added without a boolean flag or escape hatch (Gate 5). Five
   for five. It is also the correct **seam** under §4: a network boundary behind an injected interface.
2. **The refusal to build a Domain/Repository/UseCase stack is correct.** With no server, no
   persistence beyond one key-value blob, and no business rules beyond key mapping, a `GetDeviceUseCase`
   would be exactly the "Cargo-cult layering… collapse until each layer earns its existence" failure in
   §6. Do not add one. If someone proposes it, the honest answer is that this app's domain logic is the
   key maps, and those already live with the protocol that owns them.

### The real architectural gap: the seam points the wrong way

The `DeviceController` interface is **one-directional**. It lets the app tell the transport what to do;
it gives the transport no way to tell the app anything. Every consequence flows from that single
omission:

- **C-1** is only catastrophic because `_handleDisconnect()` can't report itself.
- **C-3** exists because `sendKey` returns `Future<void>` — a signature that can express "I finished"
  but not "I failed" or "I can't do that".
- **H-6** and **H-7** exist because `connect()` returning normally is the *only* way a controller can
  say anything, so stubs say "success".
- The `isConnected` getter (`device_controller.dart:26`) is a **poll where an event belongs**, and
  polling a boolean that only the transport can change is how app state and transport state drift.

This is the contract-design failure `lifecycle-gates.md` Stage 3 exists to prevent: "Design **contracts
first**… Decide error semantics: what can fail, what the caller sees, what is retryable." The interface
was designed from the happy path outward.

**The recommended change — one file, ~15 lines, unblocks five findings:**

```dart
// AFTER — lib/controllers/device_controller.dart
abstract class DeviceController {
  Future<void> connect();
  Future<void> disconnect();

  /// Send a key. Returns the outcome; does not throw for expected cases
  /// (unsupported key, not connected) — those are part of the contract.
  Future<CommandResult> sendKey(RemoteKey key);
  Future<CommandResult> sendText(String text);
  Future<CommandResult> launchApp(AppId appId);

  /// Which keys this transport can actually deliver. Lets the UI disable
  /// controls instead of silently dropping them (fixes H-1's real cause).
  Set<RemoteKey> get supportedKeys;

  /// Emits whenever the transport's health changes — including disconnections
  /// the app did not initiate. This is the channel whose absence causes C-1
  /// to be invisible.
  Stream<ControllerHealth> get health;

  bool get isConnected;
}

enum ControllerHealth { connected, degraded, disconnected }
```

`ConnectionNotifier` then subscribes to `health` in `_connectWithBackoff` and updates
`DeviceConnectionState` when the transport drops — cancelling the subscription in the existing
`ref.onDispose` at `connection_provider.dart:69-72`. `supportedKeys` lets `remote.dart` render
unsupported controls as disabled rather than inert, which is the honest fix for LG's missing
left/right (H-1) and Vizio's missing `sendText` (H-7).

This is a **seam, not a framework** — no registry, no config, no plugin system. It is the smallest
change that makes the likely future change local.

### Making a new vendor a local change

Adding one TV vendor today requires edits at five sites across four files (§2, `design-judgment.md` §4
row). Consolidate the vendor's knowledge into one file per vendor:

```dart
// NEW — lib/controllers/vendor_profile.dart
/// Everything the app knows about one vendor, in one place.
/// Adding a vendor = adding one file + one list entry. Nothing else changes.
class VendorProfile {
  final DeviceType type;
  final String displayName;
  final int defaultPort;
  final IconData icon;                                   // was device_scanner.dart:649-668
  final Color brandColor;                                // was device_scanner.dart:670-689
  final List<String> mdnsServiceTypes;                   // was scanner_provider.dart:62-70
  final bool Function(String server, String location) matchesSsdp;   // was :228-255
  final DeviceController Function(String host, int port, DevicePersistenceService) build;

  const VendorProfile({...});
}

// lib/controllers/vendors.dart — the single list every subsystem iterates
const kVendors = <VendorProfile>[rokuProfile, samsungProfile, lgProfile, vizioProfile];
```

`ScannerNotifier`, `_buildController` and both UI switches then iterate `kVendors` instead of
hardcoding arms. This satisfies Gate 1 with four existing cases, and it is a table, not a rules engine —
`design-judgment.md` §6: "Framework disease: a DSL or rules engine for three rules → Three functions."
The line to hold: if a vendor ever needs behaviour a `VendorProfile` field cannot express, it gets a
bespoke `DeviceController`, not a new field on the profile.

### Splitting the two god-screens

`remote.dart` (964 lines) and `device_scanner.dart` (737 lines) are **43 % of `lib/`** and hold **0.0 %**
and 60.6 % coverage respectively. They mix layout, animation, protocol knowledge and dialog state. Split
by *responsibility*, not by line count:

```
lib/screens/remote/
  remote_screen.dart          # scaffold + tab controller only (~120 lines)
  navigation_pad.dart         # _buildNavigationMode + _buildDPadSegment  (:263-525)
  touchpad_surface.dart       # _buildTouchpadMode, incl. the gesture math (:527-664)
  numpad_grid.dart            # _buildNumpadMode                          (:666-768)
  text_entry_sheet.dart       # _buildKeyboardOverlay                     (:770-874)
  mode_switcher.dart          # _buildBottomBar + _buildTabButton         (:876-963)
lib/screens/discovery/
  discovery_screen.dart
  device_tile.dart            # _buildDeviceItem                          (:571-647)
  manual_connect_dialog.dart  # the H-3 fix, testable in isolation        (:29-195)
  scan_animation.dart         # _buildScanningAnimation                   (:374-469)
```

The payoff is testability, not tidiness: `touchpad_surface.dart` contains real logic — the delta
accumulation and 30-pixel threshold at `remote.dart:597-619` — that is currently untestable because it
is welded to a 964-line widget. Extracted, its direction-resolution becomes a pure function with a
six-case unit test.

### Sequencing advice for the team

`lifecycle-gates.md` Stage 4 requires vertical slices ordered by risk, with no big-bang integration.
Applied here: **do not** start with the file split. Start with C-1, which is one `if` statement and one
`try` block, ships value on day one, and is provable by a `fakeAsync` test. The refactors in this
section are the *third* phase precisely because they are the least reversible and the least urgent —
`design-judgment.md` §5: reversibility drives rigor, and a screen split is a two-way door that can wait
until the one-way doors are closed.

---

## 5. Prioritized Remediation Roadmap (Action Plan)

Tiers are assigned per `SKILL.md` → "Applying the bar proportionally" (rigor = blast radius ×
reversibility). Each item names its verification, because per the non-negotiables an item without one
is not done.

### Phase 1 — Critical Stability & Compliance (immediate; ~2 days)

*Goal: the app does what it says it does, and stops lying about the rest. No architectural change.*

| # | Action | Finding | Tier | Verification (evidence required) |
|---|---|---|---|---|
| 1.1 | Move the `'pong'` check above `jsonDecode` and wrap the decode in `try/on FormatException`, in **both** controllers | C-1 | Consequential | New `fakeAsync` test: 35 s elapse with a mock channel emitting `'pong'` → `isConnected` still `true`. **Confirm it fails on current `main` first.** |
| 1.2 | Add a `pinRejected` flag; throw `CertificatePinMismatchException` instead of falling through to `ws://` | C-2 | Consequential | Test: stored fingerprint ≠ presented fingerprint → assert `connect()` throws and **no** `ws://` attempt is made. |
| 1.3 | Register `FlutterError.onError` + `PlatformDispatcher.instance.onError` in `main()` | M-7 | Standard | Throw from a stream listener in a widget test; assert the handler fires. |
| 1.4 | `IrController.connect()` throws `UnsupportedDeviceException`; Vizio 401 throws `PairingRequiredException` | H-6, H-7 | Standard | Unit tests on both; manual check that the UI no longer shows "CONNECTED". |
| 1.5 | Remove the LG 3D-toggle mappings for `up`/`down` and document why | H-1 | Standard | Test: `sendKey(RemoteKey.up)` on LG emits nothing on the sink. |
| 1.6 | Skip retries for `UnsupportedDeviceException` / `CertificatePinMismatchException` | H-2 (1) | Standard | Test: `connect()` on a Fire TV device reaches `error` in **one** attempt, not four. |
| 1.7 | Dispose both dialog `TextEditingController`s; stop rebuilding the port controller | H-3 | Standard | Widget test: open dialog, type in IP field, assert port text and cursor are preserved. |
| 1.8 | Fix `ScannerState.copyWith` to preserve `error` unless `clearError` | H-5 | Trivial | Unit test on `copyWith`; widget test that the error banner persists. |
| 1.9 | Clear the 5 `lib/` analyzer warnings; delete the commented-out blocks and dead `_authToken`/`signal`/`saveVizioToken` | M-8 | Trivial | `flutter analyze` → **0 issues in `lib/`**. |

**Exit gate (Phase 1):** `flutter analyze` clean for `lib/`; every fix above has a test that was
confirmed red before the change; a Samsung or LG TV holds a session for **≥ 10 minutes** with commands
still landing — the manual check that proves C-1 is actually closed.
**Rollback:** all nine are self-contained edits, revertable per-commit. Ship them as nine commits, not one.

### Phase 2 — Architectural Refactoring (structural alignment; ~1 week)

*Goal: make the transport able to talk back, and make the likely change local.*

| # | Action | Finding | Tier | Verification |
|---|---|---|---|---|
| 2.1 | Introduce `CommandResult` and change the three command methods on `DeviceController` to return it | C-3 | Consequential | All controllers compile against the new contract; tests assert `CommandUnsupported` for an unmapped key. |
| 2.2 | Add `Stream<ControllerHealth> health` to `DeviceController`; `ConnectionNotifier` subscribes and updates state on transport-initiated drops | C-3, C-1 | Consequential | Test: controller emits `disconnected` → `DeviceConnectionState.status` becomes `error` within one microtask. |
| 2.3 | Surface errors on the remote screen (`ref.listen` + snackbar + retry), matching `device_scanner.dart:202-215` | C-3 | Standard | Widget test: a failing command shows the error affordance. |
| 2.4 | Extract `deviceControllerFactoryProvider`; move `MockController` to `test/fakes/` | M-3, H-9 | Consequential | `connection_provider_test.dart` no longer opens a socket; the suite drops from ~30 s to < 5 s. |
| 2.5 | Rewrite `_connectWithBackoff` as a loop with an epoch guard, `_disposed` flag, and full jitter | H-2 | Consequential | Test: two overlapping `connect()` calls produce one winning chain; dispose mid-retry does not throw. |
| 2.6 | Store and cancel every `Future.delayed`/socket/subscription in `ScannerNotifier`; `await stopScan()` before `startScan()` | H-4 | Standard | Test: dispose mid-scan produces no `StateError`; rescan twice leaks no discoveries. |
| 2.7 | Extract `parseSsdpResponse` / `parseMdnsService` as pure `@visibleForTesting` functions; dedupe by host | H-9, M-6 | Standard | 6+ parser unit tests incl. hostile input (truncated headers, spoofed `SERVER`). |
| 2.8 | Introduce `VendorProfile` + `kVendors`; collapse the 5 vendor edit sites to 1 | §4 | Consequential | Add a throwaway 5th vendor touching exactly one new file + one list entry; then revert it. |

**Exit gate (Phase 2):** adding a vendor touches ≤ 2 files; no test performs real I/O; a
transport-initiated disconnect is visible in the UI within one frame.
**Rollback:** 2.1/2.2 change a shared contract — land them behind a single revertable commit each, with
all implementations updated in the same commit (`stack-appendices.md` §1: additive-first).

### Phase 3 — Performance, Scalability & Testing Polish (~1 week)

*Goal: prove the quality claims instead of asserting them.*

| # | Action | Finding | Tier | Verification |
|---|---|---|---|---|
| 3.1 | Add `.github/workflows/ci.yml`: format, `analyze --fatal-warnings`, `test --coverage`, 60 % floor | M-9 | Consequential | The pipeline is red on the current tree and green after Phase 1–2 — that contrast *is* the evidence. |
| 3.2 | Tighten `analysis_options.yaml` (`dead_code`, `unawaited_futures`, `cancel_subscriptions`, `strict-casts`) | M-8 | Standard | Confirm the new rules flag reintroduced C-1/H-4 patterns. |
| 3.3 | Raise coverage to ≥ 70 %: `lg_controller`, `vizio_controller`, `device_persistence_service`, `remote_buttons`, extracted remote widgets | H-9 | Standard | `flutter test --coverage` reports ≥ 70 % overall and ≥ 60 % on each named file. |
| 3.4 | Add the four accessibility guideline tests; add `Semantics`/labels throughout `device_scanner.dart` | H-8 | Standard | `meetsGuideline(labeledTapTargetGuideline)` passes — the claim becomes checkable. |
| 3.5 | Replace full-screen `BackdropFilter`s with static gradients; bound the list stagger; add `RepaintBoundary`; pause off-screen animations | M-2 | Standard | `flutter run --profile` frame timings recorded **before and after** in the PR body. |
| 3.6 | Extract `AppColors`/`ThemeExtension`; delete all duplicated hex literals | L-1 | Trivial | `grep -c '0xFF09090B' lib/` → 1. |
| 3.7 | Cap and pace `RokuController.sendText`; add digit `RemoteKey`s and route the numpad through `sendKey` | M-4, M-5 | Standard | Tests: 600-char input truncates to 500; numpad tap emits `KEY_1` on Samsung, not a base64 IME payload. |
| 3.8 | Add `flutter_localizations` + `app_en.arb`; move all strings out of widgets; map exceptions to user-safe messages | M-10 | Consequential | `grep` finds no user-facing literal in `lib/screens/`; raw `TimeoutException` text never reaches the UI. |
| 3.9 | Split `remote.dart` and `device_scanner.dart` per §4; add `RestorationMixin`; set a real `applicationId`; rewrite `README.md` | §4, L-6, M-9 | Standard | No file in `lib/screens/` exceeds 300 lines; state survives "Don't keep activities". |

**Exit gate (Phase 3):** CI green on every commit; ≥ 70 % coverage with the risk-bearing files above
60 %; accessibility guidelines enforced automatically; frame-timing evidence recorded.

### What is explicitly *not* being recommended

Per `design-judgment.md` §1, the deferred list is as valuable as the built list:

- **No Domain/UseCase/Repository layer.** There is no server, no business logic, and no second data
  source. Adding one would be textbook cargo-cult layering.
- **No plugin/registry system for vendors.** `VendorProfile` (§4) is a table, not a framework. Four
  vendors do not justify a rules engine.
- **No offline device-list cache.** LAN discovery takes ~10 seconds and last-device reconnect already
  covers the dominant use case. Revisit only with a measurement showing rescan latency hurts.
- **No state-management migration.** Riverpod `Notifier` is the right tool here; the defects are in how
  it is used, not in the choice. Swapping to Bloc would rewrite 500 lines and fix nothing in this report.
- **No `freezed`/`json_serializable` codegen yet.** Two hand-written models is under the threshold where
  codegen pays for its build-time cost; revisit at five.

Each of these is a *decision with a reason*, recorded so that a future implementor does not helpfully
build it anyway.
