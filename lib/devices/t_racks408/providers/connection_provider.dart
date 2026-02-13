// Connection State Provider
//
// Manages connection state, initialization sequence, and keepalive.

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/socket_service.dart';
import '../services/protocol_service.dart';
import '../../../initialize.dart';
import '../load_preset.dart';
import 'device_provider.dart';
import '../protocol.dart';

class ConnectionProvider extends ChangeNotifier {
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
  final List<String> _receivedMessages = [];
  final List<double> _messageTimestamps = [];
  Stopwatch? _connectionStopwatch;

  // Data subscription
  StreamSubscription<List<int>>? _dataSubscription;

  // Getters
  String get connectionStatus => _connectionStatus;
  bool get isConnected => _socketService.isConnected && !_isLoading;
  bool get isSocketConnected => _socketService.isConnected;
  bool get isLoading => _isLoading;
  List<String> get receivedMessages => List.unmodifiable(_receivedMessages);
  List<double> get messageTimestamps => List.unmodifiable(_messageTimestamps);
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
    // Log received data
    final hexData = _protocolService.formatAsHex(data);
    final asciiData = _protocolService.formatAsAscii(data);
    _addMessage('Rx: $hexData → $asciiData');

    // Decode protocol message for logging
    final message = _protocolService.decode(data);
    if (message is PresetMessage) {
      final label = 'U${(message.index + 1).toString().padLeft(2, '0')}';
      _addMessage('Rx: PRESET $label: ${message.name}');
    } else if (message is ChannelConfigMessage) {
      _addMessage('Rx: CONFIG chunk 0x${message.subIndex.toRadixString(16).padLeft(2, '0')}');
    } else if (message is DeviceInfoMessage) {
      _addMessage('Rx: DEVICE: ${message.deviceName}');
    }

    // Handle preset loading sequence
    if (_presetLoadWaiting && _presetLoadQueue != null) {
      _presetLoadWaiting = false;
      _presetConfigParser?.processConfigChunk(data);
      _presetLoadIndex++;
      _addMessage(
          'Preset load response ($_presetLoadIndex/${_presetLoadQueue!.length})');
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
          'Response received - sending next command (${_initializer.currentIndex}/${_initializer.totalCommands})');
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
      _receivedMessages.clear();
      _messageTimestamps.clear();
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

      final hexData = _protocolService.formatAsHex(handshake);
      final asciiData = _protocolService.formatAsAscii(handshake);
      _addMessage('Tx: $hexData → $asciiData');
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
          final hexData = _protocolService.formatAsHex(command);
          final asciiData = _protocolService.formatAsAscii(command);
          _addMessage('Tx: $hexData → $asciiData');
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
        if (_deviceProvider != null) {
          final gains = _initializer.channelGains;
          if (gains.isNotEmpty) {
            _deviceProvider!.applyChannelConfig(gains);
            _addMessage('Applied channel config: ${gains.length} channels');
          }
          final routing = _initializer.matrixRouting;
          if (routing.isNotEmpty) {
            _deviceProvider!.applyMatrixRouting(routing);
            _addMessage('Applied matrix routing: ${routing.length} outputs');
          }
          final geq = _initializer.geqBands;
          if (geq.isNotEmpty) {
            _deviceProvider!.applyGeqBands(geq);
            _addMessage('Applied GEQ: ${geq.length} channels');
          }
          final preset = _initializer.currentPreset;
          if (preset != 'Unknown') {
            _deviceProvider!.setCurrentPreset(preset);
            _addMessage('Active preset: $preset');
          }
        }

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
    _addMessage('Loading preset U${(presetIndex + 1).toString().padLeft(2, '0')}...');
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
    _addMessage('Saving to preset U${(presetIndex + 1).toString().padLeft(2, '0')} "$presetName"...');
    notifyListeners();

    // Stop keepalive queue
    _socketService.stopQueue();

    // Build store command sequence and reset state
    _presetLoadQueue = ChannelConfigParser.buildStorePresetSequence(presetIndex, presetName);
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
        final gains = _presetConfigParser!.channelGains;
        if (gains.isNotEmpty) {
          _deviceProvider!.applyChannelConfig(gains);
          _addMessage('Applied channel config: ${gains.length} channels');
        }
        final routing = _presetConfigParser!.matrixRouting;
        if (routing.isNotEmpty) {
          _deviceProvider!.applyMatrixRouting(routing);
          _addMessage('Applied matrix routing: ${routing.length} outputs');
        }
        final geq = _presetConfigParser!.geqBands;
        if (geq.isNotEmpty) {
          _deviceProvider!.applyGeqBands(geq);
          _addMessage('Applied GEQ: ${geq.length} channels');
        }
        final preset = _presetConfigParser!.currentPreset;
        if (preset != 'Unknown') {
          _deviceProvider!.setCurrentPreset(preset);
          _addMessage('Active preset: $preset');
        }
      }
      _finishPresetLoad();
      return;
    }

    // Send the next command
    final command = _presetLoadQueue![_presetLoadIndex];
    try {
      _socketService.send(command);
      _presetLoadWaiting = true;
      final hexData = _protocolService.formatAsHex(command);
      final asciiData = _protocolService.formatAsAscii(command);
      _addMessage('Tx: $hexData → $asciiData');
      notifyListeners();
    } catch (e) {
      _addMessage('DEBUG: Preset load send error: $e');
      _finishPresetLoad();
    }
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

  /// Add a timestamped debug message
  void _addMessage(String message) {
    _receivedMessages.add(message);
    final elapsed = _connectionStopwatch?.elapsed.inMicroseconds ?? 0;
    _messageTimestamps.add(elapsed / 1e6);
  }

  /// Add debug message (public)
  void addDebugMessage(String message) {
    _addMessage(message);
    notifyListeners();
  }

  /// Clear debug messages
  void clearMessages() {
    _receivedMessages.clear();
    _messageTimestamps.clear();
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
