// Socket Service for TCP Communication
//
// Handles all TCP socket operations including connection, disconnection,
// sending commands, receiving data, and a command queue with keepalive.

import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';

class SocketService extends ChangeNotifier {
  Socket? _socket;
  bool _isConnected = false;

  // Stream controller for incoming data
  final _dataController = StreamController<List<int>>.broadcast();

  // Connection info
  String _host = '';
  int _port = 0;

  // Packet counters
  int _packetsSent = 0;
  int _packetsReceived = 0;

  // Command queue
  final List<List<int>> _commandQueue = [];
  bool _awaitingResponse = false;
  Timer? _queueTimer;
  Timer? _responseTimeout;
  List<int>? _keepaliveCommand;

  // Refresh interval (keepalive polling rate)
  int _refreshIntervalMs = 300;

  // Getters
  bool get isConnected => _isConnected;
  String get host => _host;
  int get port => _port;
  int get packetsSent => _packetsSent;
  int get packetsReceived => _packetsReceived;
  int get refreshIntervalMs => _refreshIntervalMs;
  Stream<List<int>> get dataStream => _dataController.stream;

  /// Update the refresh interval (keepalive polling rate) in milliseconds.
  void setRefreshInterval(int ms) {
    _refreshIntervalMs = ms.clamp(5, 300);
    if (_keepaliveCommand != null) {
      _resetKeepaliveTimer();
    }
    notifyListeners();
  }

  /// Connect to TCP server
  Future<void> connect(String host, int port) async {
    try {
      // Close existing connection if any
      await disconnect();

      _socket = await Socket.connect(host, port);
      _host = host;
      _port = port;
      _isConnected = true;
      _packetsSent = 0;
      _packetsReceived = 0;

      // Listen for incoming data
      _socket!.listen(
        (data) {
          if (data.isNotEmpty) {
            _packetsReceived++;
            _awaitingResponse = false;
            _responseTimeout?.cancel();
            _responseTimeout = null;
            _dataController.add(data);
            // Immediately send next queued command if any
            _trySendNext();
          }
        },
        onError: (error) {
          debugPrint('Socket error: $error');
          disconnect();
        },
        onDone: () {
          debugPrint('Socket connection closed');
          disconnect();
        },
      );

      notifyListeners();
    } catch (e) {
      _isConnected = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Disconnect from server
  Future<void> disconnect() async {
    stopQueue();
    if (_socket != null) {
      await _socket!.close();
      _socket = null;
    }
    _isConnected = false;
    _host = '';
    _port = 0;
    notifyListeners();
  }

  /// Send command to server (direct send, bypasses queue)
  void send(List<int> command) {
    if (_socket == null || !_isConnected) {
      throw StateError('Socket is not connected');
    }

    _socket!.add(command);
    _packetsSent++;
  }

  /// Enqueue a single command and send immediately if possible
  void enqueue(List<int> command) {
    _commandQueue.add(command);
    _trySendNext();
  }

  /// Enqueue multiple commands and send immediately if possible
  void enqueueAll(List<List<int>> commands) {
    _commandQueue.addAll(commands);
    _trySendNext();
  }

  /// Clear all pending commands from the queue
  void clearQueue() {
    _commandQueue.clear();
  }

  /// Start the command queue with keepalive
  void startQueue(List<int> keepaliveCommand) {
    _keepaliveCommand = keepaliveCommand;
    _commandQueue.clear();
    _awaitingResponse = false;
    _resetKeepaliveTimer();
  }

  /// Stop the command queue
  void stopQueue() {
    _queueTimer?.cancel();
    _queueTimer = null;
    _responseTimeout?.cancel();
    _responseTimeout = null;
    _commandQueue.clear();
    _awaitingResponse = false;
    _keepaliveCommand = null;
  }

  /// Reset the keepalive timer (called after sending a command or receiving data)
  void _resetKeepaliveTimer() {
    _queueTimer?.cancel();
    if (_keepaliveCommand == null) return;
    _queueTimer = Timer.periodic(Duration(milliseconds: _refreshIntervalMs), (_) {
      _sendKeepalive();
    });
  }

  /// Send keepalive if queue is empty and not awaiting response
  void _sendKeepalive() {
    if (!_isConnected || _socket == null) return;
    if (_awaitingResponse) return;
    if (_commandQueue.isNotEmpty) return;
    if (_keepaliveCommand == null) return;

    try {
      _socket!.add(_keepaliveCommand!);
      _packetsSent++;
    } catch (e) {
      debugPrint('Keepalive send failed: $e');
      stopQueue();
    }
  }

  /// Try to send the next queued command immediately
  void _trySendNext() {
    if (!_isConnected || _socket == null) return;
    if (_awaitingResponse) return;
    if (_commandQueue.isEmpty) return;

    try {
      final command = _commandQueue.removeAt(0);
      _socket!.add(command);
      _packetsSent++;
      _awaitingResponse = true;
      _resetKeepaliveTimer();
      // Safety timeout — if no response within 500ms, unstick the queue
      _responseTimeout?.cancel();
      _responseTimeout = Timer(const Duration(milliseconds: 500), () {
        _responseTimeout = null;
        if (_awaitingResponse) {
          debugPrint('Response timeout — resetting awaitingResponse');
          _awaitingResponse = false;
          _trySendNext();
        }
      });
    } catch (e) {
      debugPrint('Queue send failed: $e');
      stopQueue();
    }
  }

  @override
  void dispose() {
    stopQueue();
    disconnect();
    _dataController.close();
    super.dispose();
  }
}
