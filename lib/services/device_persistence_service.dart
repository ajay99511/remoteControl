import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/device.dart';

/// Wraps flutter_secure_storage for device persistence, TOFU cert pinning,
/// and Samsung pairing token storage.
class DevicePersistenceService {
  static const _lastDeviceKey = 'last_device_v1';
  static const _knownDevicesKey = 'known_devices_v1';
  static const _tofuPrefix = 'tofu_cert_';
  static const _samsungTokenPrefix = 'samsung_token_';
  static const _lgClientKeyPrefix = 'lg_client_key_';
  static const _vizioTokenPrefix = 'vizio_token_';

  /// Keychain accessibility is set explicitly rather than left to the
  /// plugin's default.
  ///
  /// Everything in this store is a *device-local* secret: a pairing token, an
  /// LG client key, a TOFU certificate pin. The default accessibility is
  /// included in encrypted backups, so all three would restore onto a
  /// different handset - and a certificate pin that migrates is a pin
  /// vouching for a TV the new device has never met. The `_this_device`
  /// variant excludes them from backup while still allowing reads after a
  /// reboot, which auto-reconnect needs.
  ///
  /// Android needs no equivalent: flutter_secure_storage 10 encrypts with its
  /// own ciphers by default (the old encryptedSharedPreferences flag is
  /// deprecated and ignored).
  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
  static const _macOsOptions = MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  final FlutterSecureStorage _storage;

  DevicePersistenceService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: _iosOptions,
            mOptions: _macOsOptions,
          );

  // ── Device persistence ──────────────────────────────────────────────────

  Future<void> saveDevice(Device device) async {
    await _storage.write(
      key: _lastDeviceKey,
      value: jsonEncode(device.toJson()),
    );
  }

  Future<Device?> loadDevice() async {
    try {
      final raw = await _storage.read(key: _lastDeviceKey);
      if (raw == null) return null;
      return Device.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearDevice() async {
    await _storage.delete(key: _lastDeviceKey);
  }

  // ── Remembered devices ───────────────────────────────────────────────────

  /// How many devices to keep. A household has a handful of televisions, and
  /// an unbounded list is a store that only ever grows - every guest network,
  /// every hotel TV, kept forever in the keychain.
  static const _maxKnownDevices = 8;

  /// Records a device the user has actually connected to, most recent first.
  ///
  /// Keyed on [Device.credentialKey] rather than the address, so a television
  /// that moved between DHCP leases updates its entry instead of appearing
  /// twice - once at each address it has ever held.
  Future<void> rememberDevice(Device device) async {
    final known = await loadKnownDevices();
    final next = [
      device,
      ...known.where((d) => d.credentialKey != device.credentialKey),
    ];
    if (next.length > _maxKnownDevices) {
      next.removeRange(_maxKnownDevices, next.length);
    }
    await _writeKnownDevices(next);
  }

  /// Every device the user has connected to before, most recent first.
  ///
  /// Returns what it can parse. A single unreadable entry - written by an
  /// older build, or truncated - must not cost the user the rest of the list.
  Future<List<Device>> loadKnownDevices() async {
    try {
      final raw = await _storage.read(key: _knownDevicesKey);
      if (raw == null || raw.isEmpty) return const [];
      final entries = jsonDecode(raw) as List<dynamic>;
      final devices = <Device>[];
      for (final entry in entries) {
        try {
          devices.add(Device.fromJson(entry as Map<String, dynamic>));
        } catch (_) {
          continue;
        }
      }
      return devices;
    } catch (_) {
      return const [];
    }
  }

  Future<void> forgetDevice(Device device) async {
    final known = await loadKnownDevices();
    await _writeKnownDevices(
      known.where((d) => d.credentialKey != device.credentialKey).toList(),
    );
  }

  Future<void> _writeKnownDevices(List<Device> devices) => _storage.write(
    key: _knownDevicesKey,
    value: jsonEncode([for (final d in devices) d.toJson()]),
  );

  // ── TOFU certificate pinning ─────────────────────────────────────────────

  Future<void> saveCertFingerprint(String host, String sha256Hex) async {
    await _storage.write(key: '$_tofuPrefix$host', value: sha256Hex);
  }

  Future<String?> loadCertFingerprint(String host) async {
    return _storage.read(key: '$_tofuPrefix$host');
  }

  Future<void> clearCertFingerprint(String host) async {
    await _storage.delete(key: '$_tofuPrefix$host');
  }

  // ── Samsung pairing token ────────────────────────────────────────────────

  Future<void> saveSamsungToken(String host, String token) async {
    await _storage.write(key: '$_samsungTokenPrefix$host', value: token);
  }

  Future<String?> loadSamsungToken(String host) async {
    return _storage.read(key: '$_samsungTokenPrefix$host');
  }

  // ── LG client key ────────────────────────────────────────────────────────

  Future<void> saveLgClientKey(String host, String clientKey) async {
    await _storage.write(key: '$_lgClientKeyPrefix$host', value: clientKey);
  }

  Future<String?> loadLgClientKey(String host) async {
    return _storage.read(key: '$_lgClientKeyPrefix$host');
  }

  // ── Vizio auth token ─────────────────────────────────────────────────────

  Future<void> saveVizioToken(String host, String token) async {
    await _storage.write(key: '$_vizioTokenPrefix$host', value: token);
  }

  Future<String?> loadVizioToken(String host) async {
    return _storage.read(key: '$_vizioTokenPrefix$host');
  }
}

/// Riverpod provider for DevicePersistenceService.
final devicePersistenceProvider = Provider<DevicePersistenceService>(
  (_) => DevicePersistenceService(),
);
