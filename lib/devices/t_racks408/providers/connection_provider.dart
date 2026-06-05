// Connection State Provider
//
// Manages connection state, initialization sequence, and keepalive.

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/socket_service.dart';
import '../services/protocol_service.dart';
import '../device_profile.dart';
import '../../../initialize.dart';
import '../load_preset.dart';
import 'device_provider.dart';
import '../protocol.dart';

/// A single debug log entry. Packet entries store both raw hex and decoded
/// representations so the Decode checkbox can toggle between them at display time.
class DebugEntry {
  final String text; // Display text for non-packet messages
  final String? rawHex; // Raw hex (e.g. "Rx: 10 02 ... → ...")
  final String? decoded; // Decoded (e.g. "Rx: SET GAIN In A -3.2 dB")
  final double timestamp;

  /// Plain status/progress message (not a packet).
  DebugEntry.status(this.text, this.timestamp) : rawHex = null, decoded = null;

  /// Rx or Tx packet with both representations.
  DebugEntry.packet({
    required this.rawHex,
    required this.decoded,
    required this.timestamp,
  }) : text = '';

  /// The string to display, given the current decode toggle.
  String display(bool decodeOn) {
    if (rawHex != null) return decodeOn ? decoded! : rawHex!;
    return text;
  }
}

class ConnectionProvider extends ChangeNotifier {
  static const profile = DeviceProfiles.dsp408;

  final SocketService _socketService;
  final ProtocolService _protocolService;
  DeviceProvider? _deviceProvider;
  final DSPInitializer _initializer = DSPInitializer();

  /// Set the device provider reference (called from provider setup)
  set deviceProvider(DeviceProvider provider) {
    _deviceProvider = provider;
  }

  // Preset loading
  List<List<int>>? _presetLoadQueue;
  int _presetLoadIndex = 0;
  bool _presetLoadWaiting = false;
  ChannelConfigParser? _presetConfigParser;

  // Connection state
  String _connectionStatus = 'Disconnected';
  bool _isLoading = false;

  // Debug messages
  final List<DebugEntry> _debugEntries = [];
  Stopwatch? _connectionStopwatch;

  // Debug log filters
  bool _showRx = false;
  bool _showTx = false;
  bool _showDecoded = false;
  bool get showRx => _showRx;
  bool get showTx => _showTx;
  bool get showDecoded => _showDecoded;

  // Data subscription
  StreamSubscription<List<int>>? _dataSubscription;

  // Getters
  String get connectionStatus => _connectionStatus;
  bool get isConnected => _socketService.isConnected && !_isLoading;
  bool get isSocketConnected => _socketService.isConnected;
  bool get isLoading => _isLoading;
  List<DebugEntry> get debugEntries => List.unmodifiable(_debugEntries);
  int get packetsSent => _socketService.packetsSent;
  int get packetsReceived => _socketService.packetsReceived;
  double get initProgress {
    // Preset loading progress takes priority when active
    if (_presetLoadQueue != null) {
      return _presetLoadQueue!.isNotEmpty
          ? _presetLoadIndex / _presetLoadQueue!.length
          : 0.0;
    }
    // Otherwise show initialization progress
    return _initializer.totalCommands > 0
        ? _initializer.currentIndex / _initializer.totalCommands
        : 0.0;
  }

  ConnectionProvider(this._socketService, this._protocolService) {
    // Listen to socket changes
    _socketService.addListener(_onSocketStateChanged);

    // Listen to socket data for initialization sequence
    _dataSubscription = _socketService.dataStream.listen(_handleSocketData);
  }

  /// Handle socket state changes — only notify if status actually changed
  void _onSocketStateChanged() {
    final newStatus = _socketService.isConnected
        ? 'Connected to ${_socketService.host}:${_socketService.port}'
        : 'Disconnected';
    if (newStatus != _connectionStatus) {
      _connectionStatus = newStatus;
      notifyListeners();
    }
  }

  /// Handle incoming socket data
  void _handleSocketData(List<int> data) {
    // Log Rx packet with both representations
    if (_showRx) {
      final hexData = _protocolService.formatAsHex(data);
      final asciiData = _protocolService.formatAsAscii(data);
      _addPacketEntry(
        rawHex: 'Rx: $hexData → $asciiData',
        decoded: 'Rx: ${_describeRxPacket(data)}',
      );
    }

    // Handle preset loading sequence
    if (_presetLoadWaiting && _presetLoadQueue != null) {
      _presetLoadWaiting = false;
      _presetConfigParser?.processConfigChunk(data);
      _presetLoadIndex++;
      _addMessage(
        'Preset load response ($_presetLoadIndex/${_presetLoadQueue!.length})',
      );
      notifyListeners();

      Future.delayed(const Duration(milliseconds: 50), () {
        _sendNextPresetLoadCommand();
      });
    }
    // Handle initialization sequence
    else if (_initializer.isWaitingForResponse) {
      // Pass data to initializer for protocol processing (presets, config chunks)
      _initializer.processProtocolMessage(data);
      _initializer.processStartupResponse();
      _addMessage(
        'Response received - sending next command (${_initializer.currentIndex}/${_initializer.totalCommands})',
      );
      notifyListeners();

      // Send next command after delay
      Future.delayed(const Duration(milliseconds: 50), () {
        _sendNextInitCommand();
      });
    }
    // During keepalive: don't notify just for debug messages
  }

  /// Connect to device
  Future<void> connect(String ip, int port) async {
    try {
      _isLoading = true;
      _connectionStatus = 'Connecting...';
      _debugEntries.clear();
      _connectionStopwatch = Stopwatch()..start();
      notifyListeners();

      // Reset initializer
      _initializer.reset();

      // Connect socket
      await _socketService.connect(ip, port);

      // Start initialization sequence
      _addMessage('Connected - sending handshake...');
      notifyListeners();

      // Send handshake
      final handshake = TRacksProto.handshakeCommand;
      _socketService.send(handshake);
      _initializer.markCommandSent();

      _logTx(handshake);
      notifyListeners();
    } catch (e) {
      _connectionStatus = 'Failed to connect: $e';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Disconnect from device
  Future<void> disconnect() async {
    _socketService.stopQueue();
    await _socketService.disconnect();
    _initializer.reset();
    _connectionStopwatch?.stop();
    _isLoading = false;
    notifyListeners();
  }

  /// Send next initialization command
  void _sendNextInitCommand() {
    _initializer.sendNextCommand(
      isSocketAvailable: () => _socketService.isConnected,
      sendToSocket: (command) {
        try {
          _socketService.send(command);
          _logTx(command);
          notifyListeners();
        } catch (e) {
          _addMessage('DEBUG: Send error: $e');
          notifyListeners();
        }
      },
      logDebug: (message) {
        _addMessage(message);
        notifyListeners();
      },
      onComplete: () {
        // Apply parsed state to device provider
        _applyParsedConfig(
          channelGains: _initializer.channelGains,
          matrixRouting: _initializer.matrixRouting,
          geqBands: _initializer.geqBands,
          peqBands: _initializer.peqBands,
          hiPass: _initializer.hiPass,
          loPass: _initializer.loPass,
          gates: _initializer.gates,
          compressors: _initializer.compressors,
          limiters: _initializer.limiters,
          delays: _initializer.delays,
          currentPreset: _initializer.currentPreset,
        );

        _isLoading = false;
        notifyListeners();
        // Start the command queue with keepalive
        final keepalive = _protocolService.buildKeepaliveCommand();
        _socketService.startQueue(keepalive);
      },
    );
  }

  /// Load a preset by index (0-based)
  ///
  /// Stops keepalive, sends the load preset command sequence
  /// (load cmd + config dump + status queries), then restarts keepalive.
  void loadPreset(int presetIndex) {
    if (!_socketService.isConnected || _isLoading) return;

    _isLoading = true;
    _addMessage(
      'Loading preset U${(presetIndex + 1).toString().padLeft(2, '0')}...',
    );
    notifyListeners();

    // Stop keepalive queue
    _socketService.stopQueue();

    // Build command sequence and reset state
    _presetLoadQueue = ChannelConfigParser.buildLoadPresetSequence(presetIndex);
    _presetLoadIndex = 0;
    _presetLoadWaiting = false;
    _presetConfigParser = ChannelConfigParser();

    // Send first command
    _sendNextPresetLoadCommand();
  }

  /// Save (store) the current settings to a preset slot (0-based index).
  ///
  /// Stops keepalive, sends the store preset name + slot commands,
  /// then restarts keepalive.
  void savePreset(int presetIndex, String presetName) {
    if (!_socketService.isConnected || _isLoading) return;

    _isLoading = true;
    _addMessage(
      'Saving to preset U${(presetIndex + 1).toString().padLeft(2, '0')} "$presetName"...',
    );
    notifyListeners();

    // Stop keepalive queue
    _socketService.stopQueue();

    // Build store command sequence and reset state
    _presetLoadQueue = ChannelConfigParser.buildStorePresetSequence(
      presetIndex,
      presetName,
    );
    _presetLoadIndex = 0;
    _presetLoadWaiting = false;
    _presetConfigParser = null; // No config parsing needed for save

    // Send first command
    _sendNextPresetLoadCommand();
  }

  /// Send the next command in the preset loading sequence
  void _sendNextPresetLoadCommand() {
    if (_presetLoadQueue == null) return;

    if (!_socketService.isConnected) {
      _addMessage('DEBUG: Preset load aborted - disconnected');
      _finishPresetLoad();
      return;
    }

    if (_presetLoadIndex >= _presetLoadQueue!.length) {
      // All commands sent — apply parsed config (if loading, not saving)
      if (_presetConfigParser != null) {
        _addMessage('Preset load complete');
      } else {
        _addMessage('Preset saved');
      }
      if (_deviceProvider != null && _presetConfigParser != null) {
        _applyParsedConfig(
          channelGains: _presetConfigParser!.channelGains,
          matrixRouting: _presetConfigParser!.matrixRouting,
          geqBands: _presetConfigParser!.geqBands,
          peqBands: _presetConfigParser!.peqBands,
          hiPass: _presetConfigParser!.hiPass,
          loPass: _presetConfigParser!.loPass,
          gates: _presetConfigParser!.gates,
          compressors: _presetConfigParser!.compressors,
          limiters: _presetConfigParser!.limiters,
          delays: _presetConfigParser!.delays,
          currentPreset: _presetConfigParser!.currentPreset,
        );
      }
      _finishPresetLoad();
      return;
    }

    // Send the next command
    final command = _presetLoadQueue![_presetLoadIndex];
    try {
      _socketService.send(command);
      _presetLoadWaiting = true;
      _logTx(command);
      notifyListeners();
    } catch (e) {
      _addMessage('DEBUG: Preset load send error: $e');
      _finishPresetLoad();
    }
  }

  void _applyParsedConfig({
    required Map<String, double> channelGains,
    required Map<String, int> matrixRouting,
    required Map<String, List<double>> geqBands,
    required Map<String, List<PeqBand>> peqBands,
    required Map<String, FilterState> hiPass,
    required Map<String, FilterState> loPass,
    required Map<String, GateState> gates,
    required Map<String, CompressorState> compressors,
    required Map<String, LimiterState> limiters,
    required Map<String, DelayState> delays,
    required String currentPreset,
  }) {
    final deviceProvider = _deviceProvider;
    if (deviceProvider == null) return;

    if (channelGains.isNotEmpty) {
      deviceProvider.applyChannelConfig(channelGains);
      _addMessage('Applied channel config: ${channelGains.length} channels');
    }
    if (matrixRouting.isNotEmpty) {
      deviceProvider.applyMatrixRouting(matrixRouting);
      _addMessage('Applied matrix routing: ${matrixRouting.length} outputs');
    }
    if (geqBands.isNotEmpty) {
      deviceProvider.applyGeqBands(geqBands);
      _addMessage('Applied GEQ: ${geqBands.length} channels');
    }
    if (peqBands.isNotEmpty) {
      deviceProvider.applyPeqBands(peqBands);
      _addMessage('Applied PEQ: ${peqBands.length} channels');
    }
    if (hiPass.isNotEmpty) {
      deviceProvider.applyHiPass(hiPass);
      _addMessage('Applied HPF: ${hiPass.length} channels');
    }
    if (loPass.isNotEmpty) {
      deviceProvider.applyLoPass(loPass);
      _addMessage('Applied LPF: ${loPass.length} channels');
    }
    if (gates.isNotEmpty) {
      deviceProvider.applyGates(gates);
      _addMessage('Applied Gate: ${gates.length} inputs');
    }
    if (compressors.isNotEmpty) {
      deviceProvider.applyCompressors(compressors);
      _addMessage('Applied Compressor: ${compressors.length} outputs');
    }
    if (limiters.isNotEmpty) {
      deviceProvider.applyLimiters(limiters);
      _addMessage('Applied Limiter: ${limiters.length} outputs');
    }
    if (delays.isNotEmpty) {
      deviceProvider.applyDelays(delays);
      _addMessage('Applied Delay: ${delays.length} channels');
    }
    if (currentPreset != 'Unknown') {
      deviceProvider.setCurrentPreset(currentPreset);
      _addMessage('Active preset: $currentPreset');
    }
    deviceProvider.markSynced();
  }

  /// Clean up after preset loading and restart keepalive
  void _finishPresetLoad() {
    _presetLoadQueue = null;
    _presetLoadIndex = 0;
    _presetLoadWaiting = false;
    _presetConfigParser = null;
    _isLoading = false;
    notifyListeners();

    // Restart keepalive
    final keepalive = _protocolService.buildKeepaliveCommand();
    _socketService.startQueue(keepalive);
  }

  double get _elapsed =>
      (_connectionStopwatch?.elapsed.inMicroseconds ?? 0) / 1e6;

  /// Add a plain status/progress message
  void _addMessage(String message) {
    _debugEntries.add(DebugEntry.status(message, _elapsed));
  }

  /// Add a packet entry with both raw hex and decoded representations
  void _addPacketEntry({required String rawHex, required String decoded}) {
    _debugEntries.add(
      DebugEntry.packet(rawHex: rawHex, decoded: decoded, timestamp: _elapsed),
    );
  }

  /// Add debug message (public)
  void addDebugMessage(String message) {
    _addMessage(message);
    notifyListeners();
  }

  /// Export all debug entries as plain text, independent of UI filters.
  String exportDebugLogText({bool includeTimestamps = true}) {
    return _debugEntries
        .map((entry) {
          final prefix = includeTimestamps
              ? '[${entry.timestamp.toStringAsFixed(4)}] '
              : '';
          if (entry.rawHex == null) {
            return '$prefix${entry.text}';
          }
          return [
            '$prefix${entry.rawHex}',
            if (entry.decoded != null) '$prefix${entry.decoded}',
          ].join('\n');
        })
        .join('\n');
  }

  /// Toggle Rx packet log
  void toggleShowRx() {
    _showRx = !_showRx;
    notifyListeners();
  }

  /// Toggle Tx packet log
  void toggleShowTx() {
    _showTx = !_showTx;
    notifyListeners();
  }

  /// Toggle decoded packet descriptions
  void toggleShowDecoded() {
    _showDecoded = !_showDecoded;
    notifyListeners();
  }

  /// Log a transmitted command with both representations
  void _logTx(List<int> data) {
    if (_showTx) {
      final hexData = _protocolService.formatAsHex(data);
      final asciiData = _protocolService.formatAsAscii(data);
      _addPacketEntry(
        rawHex: 'Tx: $hexData → $asciiData',
        decoded: 'Tx: ${_describePacket(data)}',
      );
    }
  }

  // 31-band ISO 1/3-octave center frequencies for GEQ decode
  static const _geqFreqs = [
    '20',
    '25',
    '31.5',
    '40',
    '50',
    '63',
    '80',
    '100',
    '125',
    '160',
    '200',
    '250',
    '315',
    '400',
    '500',
    '630',
    '800',
    '1K',
    '1.25K',
    '1.6K',
    '2K',
    '2.5K',
    '3.15K',
    '4K',
    '5K',
    '6.3K',
    '8K',
    '10K',
    '12.5K',
    '16K',
    '20K',
  ];

  static final _channelNames = profile.channelLabelsByIndex;

  /// Decode an Rx packet using the parsed ProtocolMessage for richer output
  String _describeRxPacket(List<int> data) {
    final message = _protocolService.decode(data);
    if (message is PresetMessage) {
      final label = 'U${(message.index + 1).toString().padLeft(2, '0')}';
      return 'PRESET $label: "${message.name}"';
    }
    if (message is ChannelConfigMessage) {
      return 'CONFIG chunk 0x${message.subIndex.toRadixString(16).padLeft(2, '0')} (${message.chunkData.length} bytes)';
    }
    if (message is DeviceInfoMessage) {
      return 'DEVICE: ${message.deviceName}';
    }
    if (message is KeepaliveMessage) {
      // Show peak levels across all 12 channels
      final labels = profile.allChannels;
      final parts = <String>[];
      for (
        int i = 0;
        i < message.meterLevels.length && i < labels.length;
        i++
      ) {
        final v = message.meterLevels[i];
        if (v > 0.0001) parts.add('${labels[i]}:${v.toStringAsFixed(3)}');
      }
      return 'METERS ${parts.isEmpty ? "(silence)" : parts.join(" ")}';
    }
    if (message is PresetCountMessage) {
      return 'PRESET COUNT: ${message.count}';
    }
    // Fallback to generic decode
    return _describePacket(data);
  }

  /// Decode a raw Tx protocol packet into a human-readable description
  String _describePacket(List<int> data) {
    if (data.length < 6 || data[0] != 0x10 || data[1] != 0x02) {
      return 'UNKNOWN (${data.length} bytes)';
    }

    final cmdByte = data[5];

    switch (cmdByte) {
      case 0x10: // Handshake
        return 'HANDSHAKE → DSP408';
      case 0x40:
        return 'KEEPALIVE → request meter levels';
      case 0x12:
        return 'STATUS QUERY → get active preset';
      case 0x13:
        return 'GET DEVICE INFO → request device name';
      case 0x2c:
        return 'GET PRESET COUNT → request total presets';
      case 0x29:
        if (data.length > 6) {
          final idx = data[6];
          return 'GET PRESET U${(idx + 1).toString().padLeft(2, '0')} → request name';
        }
        return 'GET PRESET';
      case 0x27:
        if (data.length > 6) {
          final sub = data[6];
          return 'GET CONFIG CHUNK 0x${sub.toRadixString(16).padLeft(2, '0')} → request channel data';
        }
        return 'GET CONFIG';
      case 0x34: // Gain
        if (data.length > 8) {
          final ch =
              _channelNames[data[6]] ?? 'ch 0x${data[6].toRadixString(16)}';
          final value = data[7] | (data[8] << 8);
          final dB = _protocolService.gainValueToDb(value);
          return 'SET GAIN $ch → ${dB >= 0 ? "+${dB.toStringAsFixed(1)}" : dB.toStringAsFixed(1)} dB';
        }
        return 'SET GAIN';
      case 0x35: // Mute
        if (data.length > 7) {
          final ch =
              _channelNames[data[6]] ?? 'ch 0x${data[6].toRadixString(16)}';
          final muted = data[7] == 0x01;
          return 'SET MUTE $ch → ${muted ? "MUTED" : "UNMUTED"}';
        }
        return 'SET MUTE';
      case 0x48: // GEQ band
        if (data.length > 8) {
          final ch =
              _channelNames[data[6]] ?? 'ch 0x${data[6].toRadixString(16)}';
          final band = data[7];
          final dB = _protocolService.geqValueToDb(data[8]);
          final freq = (band >= 0 && band < _geqFreqs.length)
              ? _geqFreqs[band]
              : '#$band';
          return 'SET GEQ $ch ${freq}Hz → ${dB >= 0 ? "+${dB.toStringAsFixed(1)}" : dB.toStringAsFixed(1)} dB';
        }
        return 'SET GEQ';
      case 0x33: // PEQ band
        if (data.length > 12) {
          final ch =
              _channelNames[data[6]] ?? 'ch 0x${data[6].toRadixString(16)}';
          final band = data[7];
          final gain = data[8];
          final dB = _protocolService.geqValueToDb(gain); // same encoding
          final type = data[11] < ProtocolService.peqTypeNames.length
              ? ProtocolService.peqTypeNames[data[11]]
              : '${data[11]}';
          final bypass = data[12] == 1 ? ' [BYPASS]' : '';
          return 'SET PEQ $ch band ${band + 1} → ${dB >= 0 ? "+${dB.toStringAsFixed(1)}" : dB.toStringAsFixed(1)} dB $type$bypass';
        }
        return 'SET PEQ';
      case 0x32: // Hi Pass
        if (data.length > 8) {
          final ch =
              _channelNames[data[6]] ?? 'ch 0x${data[6].toRadixString(16)}';
          final enabled = data[8] == 1 ? 'ON' : 'OFF';
          return 'SET HPF $ch → $enabled';
        }
        return 'SET HPF';
      case 0x31: // Lo Pass
        if (data.length > 8) {
          final ch =
              _channelNames[data[6]] ?? 'ch 0x${data[6].toRadixString(16)}';
          final slope = data[8] < ProtocolService.crossoverSlopeNames.length
              ? ProtocolService.crossoverSlopeNames[data[8]]
              : '${data[8]}';
          return 'SET LPF $ch → $slope';
        }
        return 'SET LPF';
      case 0x3a: // Matrix routing
        if (data.length > 7) {
          final out =
              _channelNames[data[6]] ?? 'ch 0x${data[6].toRadixString(16)}';
          final mask = data[7];
          final inputs = <String>[];
          for (final entry in profile.matrixInputBits.entries) {
            if (mask & entry.value != 0) inputs.add(entry.key);
          }
          return 'SET MATRIX $out ← ${inputs.isEmpty ? "none" : inputs.join(" + ")}';
        }
        return 'SET MATRIX';
      case 0x24: // Config chunk response
        if (data.length > 6) {
          return 'CONFIG CHUNK 0x${data[6].toRadixString(16).padLeft(2, '0')} (${data.length} bytes)';
        }
        return 'CONFIG CHUNK';
      default:
        return 'CMD 0x${cmdByte.toRadixString(16).padLeft(2, '0')} (${data.length} bytes)';
    }
  }

  /// Clear debug messages
  void clearMessages() {
    _debugEntries.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _socketService.stopQueue();
    _dataSubscription?.cancel();
    _socketService.removeListener(_onSocketStateChanged);
    super.dispose();
  }
}
