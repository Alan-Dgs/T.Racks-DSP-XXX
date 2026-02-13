// Settings Overlay

import 'package:flutter/material.dart';

import '../services/socket_service.dart';

class SettingsOverlay {

  static void showSettingsOverlay(BuildContext context, SocketService socketService) {
    final controller = TextEditingController(
      text: socketService.refreshIntervalMs.toString(),
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Settings'),
        content: TextField(
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