import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/device.dart';

/// Wraps flutter_secure_storage for device persistence, TOFU cert pinning,
/// and Samsung pairing token storage.
class DevicePersistenceService {
  static const _lastDeviceKey = 'last_device_v1';
  static const _tofuPrefix = 'tofu_cert_';
  static const _samsungTokenPrefix = 'samsung_token_';
  static const _lgClientKeyPrefix = 'lg_client_key_';
  static const _vizioTokenPrefix = 'vizio_token_';

  final FlutterSecureStorage _storage;

  DevicePersistenceService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

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
