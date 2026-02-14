// Device State Provider
//
// Manages all device state including presets, gains, mutes, and current settings.
// Listens to socket data and processes protocol messages.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/socket_service.dart';
import '../services/protocol_service.dart';

/// State for a single PEQ band
class PeqBand {
  int freqRaw;   // LE16 raw protocol value
  int qRaw;      // Raw Q byte
  double gainDb;  // -12.0 to +12.0 dB
  int type;      // 0-8 (Peak, Low Shelf, etc.)
  bool bypass;

  PeqBand({
    this.freqRaw = 120,
    this.qRaw = 35,
    this.gainDb = 0.0,
    this.type = 0,
    this.bypass = false,
  });

  PeqBand copy() => PeqBand(
    freqRaw: freqRaw,
    qRaw: qRaw,
    gainDb: gainDb,
    type: type,
    bypass: bypass,
  );
}

/// State for a Hi/Lo Pass filter
class FilterState {
  int freqRaw;   // LE16 raw protocol value
  int slope;     // 0-19 (crossover slope type)
  bool enabled;

  FilterState({
    this.freqRaw = 0,
    this.slope = 0,
    this.enabled = false,
  });
}

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

  // GEQ bands: 31-band graphic EQ per input channel (-12 to +12 dB)
  final Map<String, List<double>> _geqBands = {
    'In A': List.filled(31, 0.0),
    'In B': List.filled(31, 0.0),
    'In C': List.filled(31, 0.0),
    'In D': List.filled(31, 0.0),
  };

  // PEQ bands: parametric EQ per channel
  // Inputs have 8 bands (0-7), Outputs have 9 bands (0-8)
  // Each band: {freq: int(raw), q: int(raw), gain: double(dB), type: int(0-8), bypass: bool}
  final Map<String, List<PeqBand>> _peqBands = {
    for (final ch in ['In A', 'In B', 'In C', 'In D'])
      ch: List.generate(8, (_) => PeqBand()),
    for (final ch in ['Out 1', 'Out 2', 'Out 3', 'Out 4', 'Out 5', 'Out 6', 'Out 7', 'Out 8'])
      ch: List.generate(9, (_) => PeqBand()),
  };

  // Hi Pass filter per channel
  final Map<String, FilterState> _hiPass = {
    for (final ch in ['In A', 'In B', 'In C', 'In D',
                       'Out 1', 'Out 2', 'Out 3', 'Out 4',
                       'Out 5', 'Out 6', 'Out 7', 'Out 8'])
      ch: FilterState(),
  };

  // Lo Pass filter per channel
  final Map<String, FilterState> _loPass = {
    for (final ch in ['In A', 'In B', 'In C', 'In D',
                       'Out 1', 'Out 2', 'Out 3', 'Out 4',
                       'Out 5', 'Out 6', 'Out 7', 'Out 8'])
      ch: FilterState(),
  };

  // Channel aliases
  final Map<String, String> _channelAliases = {};

  // Gain throttle (50ms per channel)
  final Map<String, double> _pendingGain = {};
  final Map<String, Timer> _gainTimers = {};

  // GEQ throttle (50ms per channel+band key)
  final Map<String, double> _pendingGeq = {};
  final Map<String, Timer> _geqTimers = {};

  // PEQ throttle (50ms per channel+band key)
  final Map<String, PeqBand> _pendingPeq = {};
  final Map<String, Timer> _peqTimers = {};

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

  /// Get all GEQ band values for a channel
  List<double> getGeqBands(String channel) =>
      List.of(_geqBands[channel] ?? List.filled(31, 0.0));

  /// Get a single GEQ band value
  double getGeqBand(String channel, int bandIndex) =>
      (_geqBands[channel] ?? List.filled(31, 0.0))[bandIndex];

  /// Set a single GEQ band value (throttled to 50ms per channel+band)
  void setGeqBand(String channel, int bandIndex, double dB) {
    final bands = _geqBands[channel];
    if (bands == null || bandIndex < 0 || bandIndex >= 31) return;

    final quantized = _protocolService.quantizeGeqDb(dB.clamp(-12.0, 12.0));
    bands[bandIndex] = quantized;
    notifyListeners();

    if (!_socketService.isConnected) return;

    final key = '$channel:$bandIndex';
    _pendingGeq[key] = quantized;
    if (!_geqTimers.containsKey(key)) {
      _geqTimers[key] = Timer(const Duration(milliseconds: 50), () {
        _geqTimers.remove(key);
        final pending = _pendingGeq.remove(key);
        if (pending != null) {
          _sendGeqBandCommand(channel, bandIndex, pending);
        }
      });
    }
  }

  /// Send the actual GEQ band command to the device
  void _sendGeqBandCommand(String channel, int bandIndex, double dB) {
    final command =
        _protocolService.buildGeqBandCommand(channel, bandIndex, dB);
    _socketService.enqueue(command);
  }

  /// Set all GEQ bands at once (for presets/draw)
  void setAllGeqBands(String channel, List<double> values) {
    if (values.length != 31) return;
    _geqBands[channel] = values.map((v) => v.clamp(-12.0, 12.0)).toList();
    notifyListeners();
  }

  // ─── PEQ ───

  /// Get the number of PEQ bands for a channel (8 for inputs, 9 for outputs)
  int getPeqBandCount(String channel) => _peqBands[channel]?.length ?? 0;

  /// Get all PEQ bands for a channel
  List<PeqBand> getPeqBands(String channel) =>
      (_peqBands[channel] ?? []).map((b) => b.copy()).toList();

  /// Get a single PEQ band
  PeqBand getPeqBand(String channel, int band) =>
      (_peqBands[channel] ?? [])[band].copy();

  /// Get Hi Pass filter state
  FilterState getHiPass(String channel) => _hiPass[channel] ?? FilterState();

  /// Get Lo Pass filter state
  FilterState getLoPass(String channel) => _loPass[channel] ?? FilterState();

  /// Set a PEQ band parameter and send to device (throttled 50ms per channel+band)
  void setPeqBand(String channel, int band, {
    double? gainDb,
    int? freqRaw,
    int? qRaw,
    int? type,
    bool? bypass,
  }) {
    final bands = _peqBands[channel];
    if (bands == null || band < 0 || band >= bands.length) return;

    final b = bands[band];
    if (gainDb != null) b.gainDb = gainDb.clamp(-12.0, 12.0);
    if (freqRaw != null) b.freqRaw = freqRaw.clamp(0, 1000);
    if (qRaw != null) b.qRaw = qRaw.clamp(0, 255);
    if (type != null) b.type = type.clamp(0, 8);
    if (bypass != null) b.bypass = bypass;
    notifyListeners();

    if (!_socketService.isConnected) return;

    final key = 'peq:$channel:$band';
    _pendingPeq[key] = b.copy();
    if (!_peqTimers.containsKey(key)) {
      _peqTimers[key] = Timer(const Duration(milliseconds: 50), () {
        _peqTimers.remove(key);
        final pending = _pendingPeq.remove(key);
        if (pending != null) {
          final command = _protocolService.buildPeqBandCommand(
            channel, band,
            gainDb: pending.gainDb,
            freqRaw: pending.freqRaw,
            qRaw: pending.qRaw,
            type: pending.type,
            bypass: pending.bypass,
          );
          _socketService.enqueue(command);
        }
      });
    }
  }

  /// Set Hi Pass filter and send to device
  void setHiPass(String channel, {int? freqRaw, bool? enabled, int? slope}) {
    final state = _hiPass[channel];
    if (state == null) return;
    if (freqRaw != null) state.freqRaw = freqRaw.clamp(0, 1000);
    if (enabled != null) state.enabled = enabled;
    if (slope != null) state.slope = slope.clamp(0, 19);
    notifyListeners();

    if (!_socketService.isConnected) return;
    final command = _protocolService.buildHiPassCommand(channel, state.freqRaw, state.enabled);
    _socketService.enqueue(command);
  }

  /// Set Lo Pass filter and send to device
  void setLoPass(String channel, {int? freqRaw, int? slope, bool? enabled}) {
    final state = _loPass[channel];
    if (state == null) return;
    if (freqRaw != null) state.freqRaw = freqRaw.clamp(0, 1000);
    if (slope != null) state.slope = slope.clamp(0, 19);
    if (enabled != null) state.enabled = enabled;
    notifyListeners();

    if (!_socketService.isConnected) return;
    // When disabled, send freq=1000 (max / passthrough) to the device
    final sendFreq = state.enabled ? state.freqRaw : 1000;
    final command = _protocolService.buildLoPassCommand(channel, sendFreq, state.slope);
    _socketService.enqueue(command);
  }

  /// Apply PEQ bands from config dump
  void applyPeqBands(Map<String, List<PeqBand>> bands) {
    for (final entry in bands.entries) {
      final existing = _peqBands[entry.key];
      if (existing != null && entry.value.length == existing.length) {
        for (int i = 0; i < existing.length; i++) {
          existing[i] = entry.value[i];
        }
      }
    }
    notifyListeners();
  }

  /// Apply Hi Pass filter state from config dump
  void applyHiPass(Map<String, FilterState> filters) {
    for (final entry in filters.entries) {
      final existing = _hiPass[entry.key];
      if (existing != null) {
        existing.freqRaw = entry.value.freqRaw;
        existing.slope = entry.value.slope;
        existing.enabled = entry.value.enabled;
      }
    }
    notifyListeners();
  }

  /// Apply Lo Pass filter state from config dump
  void applyLoPass(Map<String, FilterState> filters) {
    for (final entry in filters.entries) {
      final existing = _loPass[entry.key];
      if (existing != null) {
        existing.freqRaw = entry.value.freqRaw;
        existing.slope = entry.value.slope;
        existing.enabled = entry.value.enabled;
      }
    }
    notifyListeners();
  }

  /// Reset all GEQ bands to flat (0 dB) and send commands
  void resetGeqBands(String channel) {
    // Cancel any pending GEQ timers for this channel
    _geqTimers.keys
        .where((k) => k.startsWith('$channel:'))
        .toList()
        .forEach((k) {
      _geqTimers.remove(k)?.cancel();
      _pendingGeq.remove(k);
    });

    _geqBands[channel] = List.filled(31, 0.0);
    notifyListeners();

    if (!_socketService.isConnected) return;

    // Send reset command for all 31 bands
    for (int i = 0; i < 31; i++) {
      final command = _protocolService.buildGeqBandCommand(channel, i, 0.0);
      _socketService.enqueue(command);
    }
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
      // Only rebuild if meter levels changed meaningfully (avoid constant redraws)
      bool changed = false;
      for (int i = 0; i < message.meterLevels.length && i < _meterLevels.length; i++) {
        if ((message.meterLevels[i] - _meterLevels[i]).abs() > 0.005) {
          changed = true;
          break;
        }
      }
      _meterLevels = message.meterLevels;
      if (changed) notifyListeners();
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

  /// Apply parsed GEQ bands from config dump
  void applyGeqBands(Map<String, List<double>> bands) {
    for (final entry in bands.entries) {
      if (_geqBands.containsKey(entry.key) && entry.value.length == 31) {
        _geqBands[entry.key] = List.of(entry.value);
      }
    }
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

    for (final t in _geqTimers.values) {
      t.cancel();
    }
    _geqTimers.clear();
    _pendingGeq.clear();

    for (final t in _peqTimers.values) {
      t.cancel();
    }
    _peqTimers.clear();
    _pendingPeq.clear();

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

    // Reset GEQ
    _geqBands.updateAll((key, value) => List.filled(31, 0.0));

    // Reset PEQ
    for (final entry in _peqBands.entries) {
      final count = entry.key.startsWith('In') ? 8 : 9;
      _peqBands[entry.key] = List.generate(count, (_) => PeqBand());
    }
    for (final ch in _hiPass.keys) {
      _hiPass[ch] = FilterState();
    }
    for (final ch in _loPass.keys) {
      _loPass[ch] = FilterState();
    }

    notifyListeners();
  }

  @override
  void dispose() {
    for (final t in _gainTimers.values) {
      t.cancel();
    }
    for (final t in _geqTimers.values) {
      t.cancel();
    }
    for (final t in _peqTimers.values) {
      t.cancel();
    }
    _dataSubscription?.cancel();
    super.dispose();
  }
}
