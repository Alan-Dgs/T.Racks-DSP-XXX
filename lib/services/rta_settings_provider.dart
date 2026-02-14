// Shared RTA input device settings provider.
// Used by the Settings overlay, RTA tab, and GEQ tab.

import 'package:flutter/foundation.dart';
import 'package:flutter_recorder/flutter_recorder.dart';
// ignore: implementation_imports
import 'package:flutter_recorder/src/enums.dart' show CaptureDevice;

class RtaSettingsProvider extends ChangeNotifier {
  List<CaptureDevice> _devices = [];
  CaptureDevice? _selectedDevice;

  List<CaptureDevice> get devices => _devices;
  CaptureDevice? get selectedDevice => _selectedDevice;

  /// Returns the device ID to pass to RtaService.startCapture().
  /// Falls back to 0 (default device) on mobile or when no device is selected.
  int get deviceId => _selectedDevice?.id ?? 0;

  bool get isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  void enumerateDevices() {
    try {
      final devices = Recorder.instance.listCaptureDevices();
      _devices = devices;
      // Keep current selection if still valid, otherwise pick default
      if (_selectedDevice != null &&
          devices.any((d) => d.id == _selectedDevice!.id)) {
        return;
      }
      _selectedDevice = devices.where((d) => d.isDefault).firstOrNull ??
          (devices.isNotEmpty ? devices.first : null);
      notifyListeners();
    } catch (e) {
      debugPrint('RtaSettingsProvider: Failed to enumerate devices: $e');
    }
  }

  void selectDevice(int id) {
    final device = _devices.where((d) => d.id == id).firstOrNull;
    if (device != null && device.id != _selectedDevice?.id) {
      _selectedDevice = device;
      notifyListeners();
    }
  }
}
