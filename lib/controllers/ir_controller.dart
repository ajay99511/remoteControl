import '../exceptions/unsupported_device_exception.dart';
import '../models/app_id.dart';
import '../models/command_result.dart';
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
    // IR transmission needs an Android ConsumerIrManager binding that does not
    // exist yet: there is no MethodChannel in this project and MainActivity.kt
    // is the stock Flutter template. Reporting success here produced a remote
    // that displayed "CONNECTED" and silently transmitted nothing.
    //
    // To implement: MethodChannel('devicecontroller/ir') ->
    // ConsumerIrManager.hasIrEmitter() / .transmit(frequency, pattern).
    throw const UnsupportedDeviceException(DeviceType.ir);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Set<RemoteKey> get supportedKeys =>
      _irDatabase[brand.toLowerCase()]?.keys.toSet() ?? const {};

  @override
  Future<CommandResult> sendKey(RemoteKey key) async {
    // connect() always throws, so this is unreachable in practice. Kept
    // honest rather than pretending: there is no transmitter behind it.
    if (!_connected) return const CommandNotConnected();
    return CommandUnsupported(key.name);
  }

  @override
  Future<CommandResult> sendText(String text) async =>
      const CommandUnsupported('text entry');

  @override
  Future<CommandResult> launchApp(AppId appId) async =>
      CommandUnsupported(appId.displayName);

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
