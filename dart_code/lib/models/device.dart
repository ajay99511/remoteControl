class Device {
  final String id;
  final String name;
  final String type; // 'wifi' or 'bluetooth'
  final String model;
  final int signal;

  Device({
    required this.id,
    required this.name,
    required this.type,
    required this.model,
    required this.signal,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'model': model,
        'signal': signal,
      };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'],
        name: json['name'],
        type: json['type'],
        model: json['model'],
        signal: json['signal'],
      );
}
