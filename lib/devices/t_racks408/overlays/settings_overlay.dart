// Settings Overlay

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/rta_settings_provider.dart';
import '../services/socket_service.dart';

class SettingsOverlay {

  static bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static void showSettingsOverlay(BuildContext context, SocketService socketService) {
    final controller = TextEditingController(
      text: socketService.refreshIntervalMs.toString(),
    );
    final rtaSettings = context.read<RtaSettingsProvider>();
    if (!_isMobile) {
      rtaSettings.enumerateDevices();
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Settings'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Refresh interval (5–300 ms)',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
                onSubmitted: (value) {
                  final ms = int.tryParse(value);
                  if (ms != null && ms >= 5 && ms <= 300) {
                    socketService.setRefreshInterval(ms);
                    Navigator.of(context).pop();
                  }
                },
              ),
              if (!_isMobile) ...[
                const SizedBox(height: 16),
                ListenableBuilder(
                  listenable: rtaSettings,
                  builder: (context, _) {
                    return DropdownButtonFormField<int>(
                      initialValue: rtaSettings.selectedDevice?.id,
                      decoration: const InputDecoration(
                        labelText: 'Mic input',
                        border: OutlineInputBorder(),
                      ),
                      isExpanded: true,
                      hint: const Text('No devices found'),
                      items: rtaSettings.devices.map((device) {
                        return DropdownMenuItem<int>(
                          value: device.id,
                          child: Text(
                            device.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (id) {
                        if (id != null) {
                          rtaSettings.selectDevice(id);
                        }
                      },
                    );
                  },
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              socketService.setRefreshInterval(300);
              Navigator.of(context).pop();
            },
            child: const Text('Reset'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final ms = int.tryParse(controller.text);
              if (ms != null && ms >= 5 && ms <= 100) {
                socketService.setRefreshInterval(ms);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }
}
