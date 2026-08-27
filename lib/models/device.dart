import 'package:flutter/foundation.dart';

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

  /// Parse from legacy JSON string values (case-insensitive).
  static DeviceType fromString(String s) {
    switch (s.toLowerCase()) {
      case 'roku':
        return DeviceType.roku;
      case 'samsung':
        return DeviceType.samsung;
      case 'lg':
        return DeviceType.lg;
      case 'vizio':
        return DeviceType.vizio;
      case 'firetv':
      case 'fire_tv':
      case 'fire tv':
        return DeviceType.fireTv;
      case 'googletv':
      case 'google_tv':
      case 'google tv':
      case 'androidtv':
      case 'android tv':
        return DeviceType.googleTv;
      case 'ir':
        return DeviceType.ir;
      default:
        return DeviceType.unknown;
    }
  }

  String toJson() => name;
}

/// Default control port per device type.
///
/// Single source of truth: these five numbers were previously duplicated
/// across the connection factory, the manual-connect dialog and both
/// discovery matchers, free to drift apart.
const Map<DeviceType, int> kDefaultPorts = {
  DeviceType.roku: 8060,
  DeviceType.samsung: 8001,
  DeviceType.lg: 3000,
  DeviceType.vizio: 7345,
};

@immutable
class Device {
  final String id;
  final String name;
  final DeviceType type;
  final String model;
  final String? ip;
  final int? port;

  const Device({
    required this.id,
    required this.name,
    required this.type,
    required this.model,
    this.ip,
    this.port,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.toJson(),
    'model': model,
    'ip': ip,
    'port': port,
  };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
    id: json['id'] as String,
    name: json['name'] as String,
    type: DeviceType.fromString(json['type'] as String? ?? 'unknown'),
    model: json['model'] as String,
    ip: json['ip'] as String?,
    port: json['port'] as int?,
  );

  Device copyWith({
    String? id,
    String? name,
    DeviceType? type,
    String? model,
    String? ip,
    int? port,
  }) => Device(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    model: model ?? this.model,
    ip: ip ?? this.ip,
    port: port ?? this.port,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Device &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          type == other.type &&
          model == other.model &&
          ip == other.ip &&
          port == other.port;

  @override
  int get hashCode => Object.hash(id, name, type, model, ip, port);

  @override
  String toString() =>
      'Device(id: $id, name: $name, type: ${type.name}, ip: $ip, port: $port)';
}
