class Device {
  final String id;
  final String name;
  final String type; // 'wifi' or 'bluetooth'
  final String model;
  final int signal;
  final String? ip;
  final int? port;

  Device({
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
    'type': type,
    'model': model,
    'signal': signal,
    'ip': ip,
    'port': port,
  };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
    id: json['id'],
    name: json['name'],
    type: json['type'],
    model: json['model'],
    signal: json['signal'],
    ip: json['ip'],
    port: json['port'],
  );
}
