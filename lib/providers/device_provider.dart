// Device State Provider
//
// Manages all device state including presets, gains, mutes, and current settings.
// Listens to socket data and processes protocol messages.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/socket_service.dart';
import '../services/protocol_service.dart';

class DeviceProvider extends ChangeNotifier {
  final SocketService _socketService;
  final ProtocolService _protocolService;

  StreamSubscription<List<int>>? _dataSubscription;

  // Device state
  final Map<int, String> _presets = {};
  String _currentPreset = 'Unknown';

  // Channel state (gains and mutes)
  final Map<String, double> _inputGains = {
    'In A': 0,
    'In B': 0,
    'In C': 0,
    'In D': 0
  };

  final Map<String, double> _outputGains = {
    'Out 1': 0,
    'Out 2': 0,
    'Out 3': 0,
    'Out 4': 0,
    'Out 5': 0,
    'Out 6': 0,
    'Out 7': 0,
    'Out 8': 0,
  };

  final Map<String, bool> _inputMutes = {
    'In A': false,
    'In B': false,
    'In C': false,
    'In D': false
  };

  final Map<String, bool> _outputMutes = {
    'Out 1': false,
    'Out 2': false,
    'Out 3': false,
    'Out 4': false,
    'Out 5': false,
    'Out 6': false,
    'Out 7': false,
    'Out 8': false,
  };

  final Map<String, bool> _inputPhase = {
    'In A': false,
    'In B': false,
    'In C': false,
    'In D': false,
  };

  final Map<String, bool> _outputPhase = {
    'Out 1': false,
    'Out 2': false,
    'Out 3': false,
    'Out 4': false,
    'Out 5': false,
    'Out 6': false,
    'Out 7': false,
    'Out 8': false,
  };

  // Matrix routing: gain per input-output crossing point
  // Key format: "Out 1:In A", value: dB gain (default 0.0)
  final Map<String, double> _matrixGains = {};

  // Matrix routing: active input bitmask per output (cmd 0x3a)
  // In A = 0x01, In B = 0x02, In C = 0x04, In D = 0x08
  final Map<String, int> _matrixRouting = {
    'Out 1': 0, 'Out 2': 0, 'Out 3': 0, 'Out 4': 0,
    'Out 5': 0, 'Out 6': 0, 'Out 7': 0, 'Out 8': 0,
  };

  // Channel aliases
  final Map<String, String> _channelAliases = {};

  // Gain throttle (50ms per channel)
  final Map<String, double> _pendingGain = {};
  final Map<String, Timer> _gainTimers = {};

  // Meter levels (linear float values, 0.0 = silence)
  // Channel order matches protocol: In A, In B, In C, In D, Out 1-8
  List<double> _meterLevels = List.filled(12, 0.0);

  // Getters
  Map<int, String> get presets => Map.unmodifiable(_presets);
  String get currentPreset => _currentPreset;

  double getInputGain(String channel) => _inputGains[channel] ?? 0;
  double getOutputGain(String channel) => _outputGains[channel] ?? 0;

  bool getInputMute(String channel) => _inputMutes[channel] ?? false;
  bool getOutputMute(String channel) => _outputMutes[channel] ?? false;

  bool getInputPhase(String channel) => _inputPhase[channel] ?? false;
  bool getOutputPhase(String channel) => _outputPhase[channel] ?? false;

  String getAlias(String channel) => _channelAliases[channel] ?? channel;

  /// Get matrix gain for an input-output crossing point
  double getMatrixGain(String output, String input) =>
      _matrixGains['$output:$input'] ?? 0.0;

  /// Set matrix gain for an input-output crossing point
  void setMatrixGain(String output, String input, double dB) {
    final key = '$output:$input';
    _matrixGains[key] = _protocolService.quantizeGain(dB);
    notifyListeners();
  }

  /// Check if a matrix input is routed to an output
  bool getMatrixEnabled(String output, String input) {
    final bit = ProtocolService.matrixInputBits[input] ?? 0;
    return (_matrixRouting[output] ?? 0) & bit != 0;
  }

  /// Toggle a matrix input for an output and send the routing command
  void toggleMatrixInput(String output, String input) {
    if (!_socketService.isConnected) return;

    final bit = ProtocolService.matrixInputBits[input] ?? 0;
    final current = _matrixRouting[output] ?? 0;
    final newBitmask = current ^ bit;
    _matrixRouting[output] = newBitmask;
    notifyListeners();

    final command = _protocolService.buildMatrixRoutingCommand(output, newBitmask);
    _socketService.enqueue(command);
  }

  /// Get meter level for a channel (linear float, 0 = silence)
  double getMeterLevel(String channel) {
    const channelIndex = {
      'In A': 0, 'In B': 1, 'In C': 2, 'In D': 3,
      'Out 1': 4, 'Out 2': 5, 'Out 3': 6, 'Out 4': 7,
      'Out 5': 8, 'Out 6': 9, 'Out 7': 10, 'Out 8': 11,
    };
    final idx = channelIndex[channel];
    if (idx == null) return 0.0;
    return _meterLevels[idx];
  }

  /// Load channel aliases from local storage
  Future<void> loadAliases() async {
    final prefs = await SharedPreferences.getInstance();
    final allChannels = [
      ..._inputGains.keys,
      ..._outputGains.keys,
    ];
    for (final ch in allChannels) {
      final alias = prefs.getString('channel_alias_$ch');
      if (alias != null) {
        _channelAliases[ch] = alias;
      }
    }
    notifyListeners();
  }

  /// Set a custom alias for a channel
  Future<void> setAlias(String channel, String alias) async {
    _channelAliases[channel] = alias;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('channel_alias_$channel', alias);
  }

  /// Reset a channel alias back to default
  Future<void> resetAlias(String channel) async {
    _channelAliases.remove(channel);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('channel_alias_$channel');
  }

  DeviceProvider(this._socketService, this._protocolService) {
    // Listen to socket data stream
    _dataSubscription = _socketService.dataStream.listen(_handleIncomingData);
  }

  /// Handle incoming data from socket
  void _handleIncomingData(List<int> data) {
    final message = _protocolService.decode(data);

    if (message is PresetMessage) {
      _presets[message.index] = message.name;
      notifyListeners();
    } else if (message is CurrentPresetMessage) {
      _currentPreset = message.name;
      notifyListeners();
    } else if (message is KeepaliveMessage) {
      _meterLevels = message.meterLevels;
      notifyListeners();
    } else if (message is DeviceInfoMessage) {
      // Could store device info if needed
      debugPrint('Device: ${message.deviceName}');
    }
  }

  /// Set the current preset name
  void setCurrentPreset(String name) {
    _currentPreset = name;
    notifyListeners();
  }

  /// Apply parsed matrix routing from config dump
  void applyMatrixRouting(Map<String, int> routing) {
    for (final entry in routing.entries) {
      _matrixRouting[entry.key] = entry.value;
    }
    notifyListeners();
  }

  /// Apply parsed channel configuration from initialization
  void applyChannelConfig(Map<String, double> gains) {
    for (final entry in gains.entries) {
      final channel = entry.key;
      final dB = _protocolService.quantizeGain(entry.value);
      if (_inputGains.containsKey(channel)) {
        _inputGains[channel] = dB;
      } else if (_outputGains.containsKey(channel)) {
        _outputGains[channel] = dB;
      }
    }
    notifyListeners();
  }

  /// Set gain for a channel (throttled to 50ms per channel)
  void setGain(String channel, double dB) {
    if (!_socketService.isConnected) return;

    // Optimistic local state update (always immediate for smooth UI)
    if (_inputGains.containsKey(channel)) {
      _inputGains[channel] = _protocolService.quantizeGain(dB);
    } else if (_outputGains.containsKey(channel)) {
      _outputGains[channel] = _protocolService.quantizeGain(dB);
    }
    notifyListeners();

    // Store the latest value; start a timer if one isn't already running
    _pendingGain[channel] = dB;
    if (!_gainTimers.containsKey(channel)) {
      _gainTimers[channel] = Timer(const Duration(milliseconds: 50), () {
        _gainTimers.remove(channel);
        final pending = _pendingGain.remove(channel);
        if (pending != null) {
          _sendGainCommand(channel, pending);
        }
      });
    }
  }

  /// Send the actual gain command to the device
  void _sendGainCommand(String channel, double dB) {
    // Clear stale gain commands — only the latest value matters
    _socketService.clearQueue();
    final command = _protocolService.buildGainCommand(channel, dB);
    _socketService.enqueueAll([command, command]);
  }

  /// Toggle mute for a channel
  void toggleMute(String channel) {
    if (!_socketService.isConnected) return;

    // Determine current mute state
    bool currentMute;
    if (_inputMutes.containsKey(channel)) {
      currentMute = _inputMutes[channel]!;
    } else if (_outputMutes.containsKey(channel)) {
      currentMute = _outputMutes[channel]!;
    } else {
      return;
    }

    // Build and enqueue mute command
    final newMute = !currentMute;
    final command = _protocolService.buildMuteCommand(channel, newMute);
    _socketService.enqueue(command);

    // Optimistic local state update
    if (_inputMutes.containsKey(channel)) {
      _inputMutes[channel] = newMute;
    } else if (_outputMutes.containsKey(channel)) {
      _outputMutes[channel] = newMute;
    }
    notifyListeners();
  }

  /// Toggle phase invert for a channel
  void togglePhase(String channel) {
    if (_inputPhase.containsKey(channel)) {
      _inputPhase[channel] = !_inputPhase[channel]!;
    } else if (_outputPhase.containsKey(channel)) {
      _outputPhase[channel] = !_outputPhase[channel]!;
    }
    notifyListeners();
  }

  /// Reset device state
  void reset() {
    for (final t in _gainTimers.values) {
      t.cancel();
    }
    _gainTimers.clear();
    _pendingGain.clear();

    _presets.clear();
    _currentPreset = 'Unknown';

    // Reset gains to 0
    _inputGains.updateAll((key, value) => 0);
    _outputGains.updateAll((key, value) => 0);

    // Reset mutes to false
    _inputMutes.updateAll((key, value) => false);
    _outputMutes.updateAll((key, value) => false);

    // Reset phase to normal
    _inputPhase.updateAll((key, value) => false);
    _outputPhase.updateAll((key, value) => false);

    // Reset matrix
    _matrixGains.clear();
    _matrixRouting.updateAll((key, value) => 0);

    notifyListeners();
  }

  @override
  void dispose() {
    for (final t in _gainTimers.values) {
      t.cancel();
    }
    _dataSubscription?.cancel();
    super.dispose();
  }
}
