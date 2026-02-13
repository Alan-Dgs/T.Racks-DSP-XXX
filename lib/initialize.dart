// DSP408 Initialization Module
//
// Handles the automatic startup sequence when connecting to the DSP408 device.
// This sequence retrieves device information, preset count, all preset names,
// the current active preset, and the full channel configuration state.

import 'package:flutter/foundation.dart';

import 'devices/t_racks408/load_preset.dart';
import 'devices/t_racks408/protocol.dart';

class DSPInitializer extends ChangeNotifier {
  // Command queue for automated preset retrieval
  final List<List<int>> _commandQueue = [];
  int _currentCommandIndex = 0;
  bool _waitingForResponse = false;

  // Preset storage
  final Map<int, String> _presets = {};

  // Channel config parser (shared with preset loading)
  final ChannelConfigParser _configParser = ChannelConfigParser();

  DSPInitializer() {
    _buildCommandQueue();
  }

  /// Build the initialization command queue
  void _buildCommandQueue() {
    _commandQueue.clear();
    _commandQueue.addAll([
      TRacksProto.handshakeCommand,                           // Handshake
      TRacksProto.requestDeviceInfo,                          // Get device info
      TRacksProto.requestAllPresetsCommand,                   // Request all presets
      [0x10, 0x02, 0x00, 0x01, 0x01, 0x22, 0x10, 0x03, 0x23], // Unknown Loading Command - TODO: Figure this out
      [0x10, 0x02, 0x00, 0x01, 0x01, 0x14, 0x10, 0x03, 0x15], // Unknown Loading Command - TODO: Figure this out
      // Load all 20 presets.
      ...TRacksProto.loadAllPresetsCommands,
      // Channel config dump (cmd 0x27, sub-indices 0x00-0x1C → triggers 0x24 responses)
      ...TRacksProto.configDumpCommands,
      // Status queries before keepalive begins
      ...TRacksProto.statusQueryCommands,
    ]);
  }

  // Getters for parsed config (delegated to config parser)
  Map<String, double> get channelGains => _configParser.channelGains;
  Map<String, int> get matrixRouting => _configParser.matrixRouting;
  Map<String, List<double>> get geqBands => _configParser.geqBands;

  /// Reset the initialization state
  void reset() {
    _currentCommandIndex = 0;
    _waitingForResponse = false;
    _presets.clear();
    _configParser.reset();
  }

  /// Get the next command to send
  /// Returns null if no more commands or if waiting for response
  List<int>? getNextCommand() {
    if (_waitingForResponse) return null;
    if (_currentCommandIndex >= _commandQueue.length) return null;

    return _commandQueue[_currentCommandIndex];
  }

  /// Mark that a command was sent and we're waiting for response
  void markCommandSent() {
    _waitingForResponse = true;
  }

  /// Check if initialization is complete
  bool get isComplete => _currentCommandIndex >= _commandQueue.length;

  /// Get current progress
  int get currentIndex => _currentCommandIndex;
  int get totalCommands => _commandQueue.length;

  /// Check if waiting for response
  bool get isWaitingForResponse => _waitingForResponse;

  /// Store a preset
  void storePreset(int index, String name) {
    _presets[index] = name;
    notifyListeners();
  }

  /// Set current preset
  void setCurrentPreset(String name) {
    _configParser.currentPreset = name;
    notifyListeners();
  }

  /// Get all presets
  Map<int, String> get presets => Map.unmodifiable(_presets);

  /// Get current preset
  String get currentPreset => _configParser.currentPreset;

  /// Decode and process protocol messages related to initialization
  void processProtocolMessage(List<int> data) {
    if (data.length < 6 || data[0] != 0x10 || data[1] != 0x02) return;

    try {
      // Find footer (10 03)
      int footerIndex = -1;
      for (int i = 0; i < data.length - 1; i++) {
        if (data[i] == 0x10 && data[i + 1] == 0x03) {
          footerIndex = i;
          break;
        }
      }

      if (footerIndex == -1) return;

      // Extract command and data payload
      final isResponse = data[2] == 0x01;
      if (!isResponse || data.length <= 7) return;

      final cmdByte = data[5];
      final dataByte = data.length > 6 ? data[6] : null;

      // Process preset data (command 0x29)
      if (cmdByte == 0x29 && dataByte != null) {
        final presetNum = dataByte + 1;
        final nameBytes = data.sublist(7, footerIndex);
        final presetName = String.fromCharCodes(nameBytes).trim();
        storePreset(presetNum - 1, presetName);
      }
      // Process channel config chunks (command 0x24) — delegated to shared parser
      else if (cmdByte == 0x24) {
        _configParser.processConfigChunk(data);
      }
    } catch (e) {
      debugPrint('Init message decode error: $e');
    }
  }

  /// Process startup commands received by the DSP.
  void processStartupResponse() {
    // Mark it as received and increment the command index.
    // This is internal sequence control, not a data change that needs UI updates
    _waitingForResponse = false;
    _currentCommandIndex++;
  }

  /// Send the next command in the initialization sequence
  ///
  /// Returns a SendCommandResult indicating what action to take:
  /// - SendCommandResult.notConnected: Socket is not available
  /// - SendCommandResult.complete: All commands have been sent
  /// - SendCommandResult.waiting: Already waiting for a response
  /// - SendCommandResult.sent: Command was sent successfully
  SendCommandResult sendNextCommand({
    required bool Function() isSocketAvailable,
    required void Function(List<int> command) sendToSocket,
    required void Function(String message) logDebug,
    required void Function() onComplete,
  }) {
    // Check socket availability
    if (!isSocketAvailable()) {
      logDebug('DEBUG: Cannot send - socket null or not connected');
      return SendCommandResult.notConnected;
    }

    // Check if initialization is complete
    if (isComplete) {
      logDebug('DEBUG: All commands sent! Total: $currentIndex');
      onComplete();
      return SendCommandResult.complete;
    }

    // Get next command (returns null if waiting for response)
    final command = getNextCommand();
    if (command == null) {
      logDebug('DEBUG: Already waiting for response, skipping send');
      return SendCommandResult.waiting;
    }

    // Log the command being sent
    logDebug('DEBUG: Sending command $currentIndex/$totalCommands');

    // Send the command and mark as sent
    sendToSocket(command);
    markCommandSent();

    return SendCommandResult.sent;
  }
}

/// Result of attempting to send the next command
enum SendCommandResult {
  notConnected,  // Socket is not available
  complete,      // All initialization commands sent
  waiting,       // Already waiting for a response
  sent,          // Command sent successfully
}
