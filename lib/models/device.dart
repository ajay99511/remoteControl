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

@immutable
class Device {
  final String id;
  final String name;
  final DeviceType type;
  final String model;
  final int signal;
  final String? ip;
  final int? port;

  const Device({
    required this.id,
    required this.name,
    required this.type,
    required this.model,
    required this.signal,
    this.ip,
    this.port,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.toJson(),
        'model': model,
        'signal': signal,
        'ip': ip,
        'port': port,
      };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as String,
        name: json['name'] as String,
        type: DeviceType.fromString(json['type'] as String? ?? 'unknown'),
        model: json['model'] as String,
        signal: json['signal'] as int,
        ip: json['ip'] as String?,
        port: json['port'] as int?,
      );

  Device copyWith({
    String? id,
    String? name,
    DeviceType? type,
    String? model,
    int? signal,
    String? ip,
    int? port,
  }) =>
      Device(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        model: model ?? this.model,
        signal: signal ?? this.signal,
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
          signal == other.signal &&
          ip == other.ip &&
          port == other.port;

  @override
  int get hashCode => Object.hash(id, name, type, model, signal, ip, port);

  @override
  String toString() =>
      'Device(id: $id, name: $name, type: ${type.name}, ip: $ip, port: $port)';
}
