import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

import '../models/device.dart';

/// Validates a manually entered host.
///
/// Uses the platform parser rather than a hand-rolled regex: the previous
/// pattern made the dot separator optional, so "1234" validated, while a
/// compressed IPv6 address such as "fe80::1" could never match.
/// Returns null when [value] is a usable address, otherwise the reason.
String? validateManualHost(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return "Enter the TV's IP address";
  return InternetAddress.tryParse(trimmed) == null
      ? 'Not a valid IP address'
      : null;
}

/// Collects an IP address and port for a device that discovery did not find,
/// and returns the resulting [Device] via [Navigator.pop].
///
/// Deliberately presentational: it takes no providers and performs no
/// connection, so the caller decides what to do with the result and the
/// dialog can be widget-tested on its own.
class ManualConnectDialog extends StatefulWidget {
  const ManualConnectDialog({super.key});

  /// Device types a user can reach by typing an address.
  static const selectableTypes = <DeviceType>[
    DeviceType.roku,
    DeviceType.samsung,
    DeviceType.lg,
    DeviceType.vizio,
  ];

  @override
  State<ManualConnectDialog> createState() => _ManualConnectDialogState();
}

class _ManualConnectDialogState extends State<ManualConnectDialog> {
  static const _surface = AppColors.surface;

  final _ipController = TextEditingController();
  final _portController = TextEditingController(
    text: '${kDefaultPorts[DeviceType.roku]}',
  );

  DeviceType _selectedType = DeviceType.roku;
  String? _ipError;

  @override
  void dispose() {
    // Both controllers were previously created inside builder closures and
    // never disposed - the port one on every keystroke.
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _onTypeChanged(DeviceType? type) {
    if (type == null) return;
    setState(() {
      _selectedType = type;
      // Mutate the existing controller. Constructing a new one here is what
      // reset the caret and leaked a ChangeNotifier per rebuild.
      _portController.text = '${kDefaultPorts[type] ?? 80}';
    });
  }

  void _submit() {
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() => _ipError = 'Port must be between 1 and 65535');
      return;
    }
    Navigator.pop(
      context,
      Device(
        id: 'manual-${DateTime.now().millisecondsSinceEpoch}',
        name: 'Manual ${_selectedType.name.toUpperCase()}',
        type: _selectedType,
        model: 'Custom IP',
        ip: _ipController.text.trim(),
        port: port,
      ),
    );
  }

  bool get _canSubmit =>
      _ipController.text.trim().isNotEmpty &&
      validateManualHost(_ipController.text) == null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Connect via IP',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: 'Device type',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<DeviceType>(
                    value: _selectedType,
                    dropdownColor: _surface,
                    style: const TextStyle(color: Colors.white),
                    isExpanded: true,
                    onChanged: _onTypeChanged,
                    items: [
                      for (final type in ManualConnectDialog.selectableTypes)
                        DropdownMenuItem(
                          value: type,
                          child: Text(type.name.toUpperCase()),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ipController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: (value) => setState(() {
                _ipError = value.trim().isEmpty
                    ? null
                    : validateManualHost(value);
              }),
              onSubmitted: (_) => _canSubmit ? _submit() : null,
              decoration: _fieldDecoration(
                label: 'IP Address',
                hint: 'e.g. 192.168.1.105',
                error: _ipError,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _portController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _fieldDecoration(label: 'Port'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigoAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _canSubmit ? _submit : null,
          child: const Text(
            'Connect',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
    String? error,
  }) => InputDecoration(
    // A real label, associated with the field, rather than a detached Text
    // widget that a screen reader cannot connect to the input.
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white70),
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.grey),
    errorText: error,
    filled: true,
    fillColor: Colors.black.withValues(alpha: 0.2),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );
}
