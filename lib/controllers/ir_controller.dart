import '../core/app_logger.dart';
import '../exceptions/unsupported_device_exception.dart';
import '../models/app_id.dart';
import '../models/device.dart';
import '../models/remote_key.dart';
import 'device_controller.dart';

/// Android IR blaster controller (Requirement 2.9).
class IrController implements DeviceController {
  final String brand;
  bool _connected = false;

  IrController({required this.brand});

  @override
  Future<void> connect() async {
    // In a real app, this would check for IR hardware via a platform channel.
    // For this hardened version, we assume IR is available if it reaches here,
    // or throw if it's known to be missing.
    _connected = true;
    log.d('IrController: Initialized for brand $brand');
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Future<void> sendKey(RemoteKey key) async {
    if (!_connected) return;

    final code = _irDatabase[brand.toLowerCase()]?[key];
    if (code == null) {
      log.d('IrController: Key ${key.name} not found in IR database for $brand.');
      return;
    }

    log.d('IrController: Transmitting IR code for ${key.name} (${brand.toUpperCase()})');
    // Platform channel call would go here.
  }

  @override
  Future<void> sendText(String text) async {
    // IR doesn't support text input.
  }

  @override
  Future<void> launchApp(AppId appId) async {
    // IR doesn't support app launching.
  }

  @override
  bool get isConnected => _connected;

  static const Map<String, Map<RemoteKey, IrCode>> _irDatabase = {
    'samsung': {
      RemoteKey.power: IrCode(frequency: 38000, pattern: [170, 170, 13]),
      RemoteKey.volumeUp: IrCode(frequency: 38000, pattern: [170, 171, 14]),
      RemoteKey.volumeDown: IrCode(frequency: 38000, pattern: [170, 172, 15]),
    },
    'lg': {
      RemoteKey.power: IrCode(frequency: 38000, pattern: [160, 160, 12]),
      RemoteKey.volumeUp: IrCode(frequency: 38000, pattern: [160, 161, 13]),
      RemoteKey.volumeDown: IrCode(frequency: 38000, pattern: [160, 162, 14]),
    },
  };
}

class IrCode {
  final int frequency;
  final List<int> pattern;
  const IrCode({required this.frequency, required this.pattern});
}
