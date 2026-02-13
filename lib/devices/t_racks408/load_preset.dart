// Channel Config Dump & Preset Loading
//
// Shared logic for the 29-command channel config dump sequence (cmd 0x27 → 0x24
// responses) used by both initialization and preset loading.
//
// Preset loading sequence (from PCAP analysis):
//   1. Send load preset command (cmd 0x20, preset index)
//   2. Send 29 config dump commands (cmd 0x27, sub-indices 0x00-0x1C)
//   3. Send 2 status queries (cmd 0x12)
//   4. Parse 0x24 response chunks to extract channel gains and preset name

import 'package:flutter/foundation.dart';

import 'protocol.dart';
import 'services/protocol_service.dart';

/// Parses channel configuration from 0x24 response chunks.
///
/// Used by both DSPInitializer (on connect) and preset loading (on user action).
class ChannelConfigParser {
  static const int configChunkCount = 29; // sub-indices 0x00-0x1C

  // Chunk buffer
  final Map<int, List<int>> _configChunks = {};

  // Parsed state
  final Map<String, double> _channelGains = {};
  final Map<String, int> _matrixRouting = {};
  final Map<String, List<double>> _geqBands = {};
  String _currentPreset = 'Unknown';

  Map<String, double> get channelGains => Map.unmodifiable(_channelGains);
  Map<String, int> get matrixRouting => Map.unmodifiable(_matrixRouting);
  Map<String, List<double>> get geqBands => Map.unmodifiable(_geqBands);
  // ignore: unnecessary_getters_setters
  String get currentPreset => _currentPreset;
  // ignore: unnecessary_getters_setters
  set currentPreset(String name) => _currentPreset = name;

  void reset() {
    _configChunks.clear();
    _channelGains.clear();
    _matrixRouting.clear();
    _geqBands.clear();
    _currentPreset = 'Unknown';
  }

  /// Process a 0x24 config chunk from protocol data.
  /// Call this for every incoming message; non-0x24 messages are ignored.
  /// Returns true when all chunks have been received and config was parsed.
  bool processConfigChunk(List<int> data) {
    if (data.length < 6 || data[0] != 0x10 || data[1] != 0x02) return false;

    try {
      // Find footer (10 03)
      int footerIndex = -1;
      for (int i = 0; i < data.length - 1; i++) {
        if (data[i] == 0x10 && data[i + 1] == 0x03) {
          footerIndex = i;
          break;
        }
      }
      if (footerIndex == -1) return false;

      final isResponse = data[2] == 0x01;
      if (!isResponse || data.length <= 7) return false;

      final cmdByte = data[5];
      final dataByte = data[6];

      if (cmdByte != 0x24) return false;

      // Buffer this chunk (data after sub-index byte, up to footer)
      final chunkData = data.sublist(7, footerIndex);
      _configChunks[dataByte] = chunkData;

      // First chunk (sub-index 0x00) contains the current preset name
      if (dataByte == 0x00 && chunkData.length >= 16) {
        // Bytes 0-1: flags (ffff or ff00), bytes 2-16: preset name (14 chars)
        final nameBytes = chunkData.sublist(2, 16);
        _currentPreset = String.fromCharCodes(nameBytes).trim();
      }

      // Once all chunks received, parse the full config
      if (_configChunks.length >= configChunkCount) {
        _parseChannelConfig();
        return true;
      }
    } catch (e) {
      debugPrint('Config chunk decode error: $e');
    }

    return false;
  }

  /// Reassemble and parse the full channel configuration from buffered 0x24 chunks
  void _parseChannelConfig() {
    // Reassemble continuous byte stream from all chunks in order
    final stream = <int>[];
    for (int i = 0; i <= 0x1C; i++) {
      final chunk = _configChunks[i];
      if (chunk == null) return; // Missing chunk, abort
      stream.addAll(chunk);
    }

    // Channel names to search for and their labels
    final channelPatterns = <String, List<int>>{
      'In A': [0x49, 0x6e, 0x41],  // "InA"
      'In B': [0x49, 0x6e, 0x42],  // "InB"
      'In C': [0x49, 0x6e, 0x43],  // "InC"
      'In D': [0x49, 0x6e, 0x44],  // "InD"
      'Out 1': [0x4f, 0x75, 0x74, 0x31], // "Out1"
      'Out 2': [0x4f, 0x75, 0x74, 0x32], // "Out2"
      'Out 3': [0x4f, 0x75, 0x74, 0x33], // "Out3"
      'Out 4': [0x4f, 0x75, 0x74, 0x34], // "Out4"
      'Out 5': [0x4f, 0x75, 0x74, 0x35], // "Out5"
      'Out 6': [0x4f, 0x75, 0x74, 0x36], // "Out6"
      'Out 7': [0x4f, 0x75, 0x74, 0x37], // "Out7"
      'Out 8': [0x4f, 0x75, 0x74, 0x38], // "Out8"
    };

    // Find the byte offset of each channel name in the stream
    final channelOffsets = <String, int>{};
    for (final entry in channelPatterns.entries) {
      final pattern = entry.value;
      for (int i = 0; i <= stream.length - pattern.length; i++) {
        bool match = true;
        for (int j = 0; j < pattern.length; j++) {
          if (stream[i + j] != pattern[j]) {
            match = false;
            break;
          }
        }
        if (match) {
          channelOffsets[entry.key] = i;
          break;
        }
      }
    }

    // Extract gains: each channel's gain is the LE16 at 8 bytes before the
    // NEXT channel's name position. The channel order in the stream is:
    // InA, InB, InC, InD, Out1, Out2, ..., Out8
    final channelOrder = [
      'In A', 'In B', 'In C', 'In D',
      'Out 1', 'Out 2', 'Out 3', 'Out 4',
      'Out 5', 'Out 6', 'Out 7', 'Out 8',
    ];

    for (int i = 0; i < channelOrder.length; i++) {
      final channel = channelOrder[i];
      if (!channelOffsets.containsKey(channel)) continue;

      int gainOffset;
      if (i + 1 < channelOrder.length) {
        // Gain is 8 bytes before the next channel's name
        final nextChannel = channelOrder[i + 1];
        if (!channelOffsets.containsKey(nextChannel)) continue;
        gainOffset = channelOffsets[nextChannel]! - 8;
      } else {
        // Last channel (Out 8): gain is at the start of the final chunk (0x1C)
        // which is the first 2 bytes of that chunk's data
        int offset = 0;
        for (int c = 0; c < 0x1C; c++) {
          offset += _configChunks[c]?.length ?? 0;
        }
        gainOffset = offset;
      }

      if (gainOffset >= 0 && gainOffset + 1 < stream.length) {
        final rawValue = stream[gainOffset] | (stream[gainOffset + 1] << 8);
        final dB = (rawValue - 280) / 10.0;
        _channelGains[channel] = dB;
        debugPrint('Config: $channel gain = ${dB.toStringAsFixed(1)} dB (raw: $rawValue)');
      }
    }

    // Extract matrix routing bitmasks for each output channel.
    // Pattern: "OutN" (4 bytes) + 4 null bytes + bitmask byte
    // Bitmask: 0x01=In A, 0x02=In B, 0x04=In C, 0x08=In D
    for (final output in ['Out 1', 'Out 2', 'Out 3', 'Out 4',
                           'Out 5', 'Out 6', 'Out 7', 'Out 8']) {
      final offset = channelOffsets[output];
      if (offset == null) continue;
      final bitmaskOffset = offset + 8; // 4 name + 4 nulls
      if (bitmaskOffset < stream.length) {
        _matrixRouting[output] = stream[bitmaskOffset];
        debugPrint('Config: $output matrix = 0x${stream[bitmaskOffset].toRadixString(16).padLeft(2, '0')}');
      }
    }

    // Extract GEQ bands for input channels.
    // Each input record has 31 x u16 LE values at offset +16 from the channel name.
    // Value encoding: same as GEQ set-band command (0-240, dB = (value - 120) / 10.0)
    final proto = ProtocolService();
    for (final input in ['In A', 'In B', 'In C', 'In D']) {
      final offset = channelOffsets[input];
      if (offset == null) continue;

      final geqStart = offset + 16; // GEQ data starts 16 bytes after channel name
      final geqEnd = geqStart + 31 * 2; // 31 bands x 2 bytes each
      if (geqEnd > stream.length) continue;

      final bands = <double>[];
      for (int b = 0; b < 31; b++) {
        final pos = geqStart + b * 2;
        final rawValue = stream[pos] | (stream[pos + 1] << 8);
        bands.add(proto.geqValueToDb(rawValue));
      }
      _geqBands[input] = bands;
      debugPrint('Config: $input GEQ loaded (${bands.where((v) => v != 0.0).length} non-zero bands)');
    }
  }

  /// Build a load preset command for the given preset index (0-based).
  ///
  /// Protocol: `10 02 00 01 02 20 [index] 10 03 [checksum]`
  static List<int> buildLoadPresetCommand(int presetIndex) {
    // Protocol uses 1-based preset indices; our keys are 0-based
    final dataBytes = [0x00, 0x01, 0x02, 0x20, presetIndex + 1];
    int checksum = 1;
    for (final b in dataBytes) {
      checksum ^= b;
    }
    return [0x10, 0x02, ...dataBytes, 0x10, 0x03, checksum];
  }

  /// Build the full command sequence for loading a preset:
  /// 1. Load preset command
  /// 2. Config dump (29 commands)
  /// 3. Status queries (2 commands)
  static List<List<int>> buildLoadPresetSequence(int presetIndex) {
    return [
      buildLoadPresetCommand(presetIndex),
      ...TRacksProto.configDumpCommands,
      ...TRacksProto.statusQueryCommands,
    ];
  }

  /// Build the store preset name command (cmd 0x26).
  ///
  /// Protocol: `10 02 00 01 0f 26 [14-char name] 10 03 [checksum]`
  /// Name is padded with spaces to exactly 14 characters.
  static List<int> buildStorePresetNameCommand(String name) {
    final padded = name.length >= 14
        ? name.substring(0, 14)
        : name.padRight(14);
    final nameBytes = padded.codeUnits;
    final dataBytes = [0x00, 0x01, 0x0f, 0x26, ...nameBytes];
    int checksum = 1;
    for (final b in dataBytes) {
      checksum ^= b;
    }
    return [0x10, 0x02, ...dataBytes, 0x10, 0x03, checksum];
  }

  /// Build the store preset slot command (cmd 0x21).
  ///
  /// Protocol: `10 02 00 01 02 21 [slot] 10 03 [checksum]`
  /// Slot is 1-based (U01 = 1, U20 = 20).
  static List<int> buildStorePresetSlotCommand(int presetIndex) {
    final dataBytes = [0x00, 0x01, 0x02, 0x21, presetIndex + 1];
    int checksum = 1;
    for (final b in dataBytes) {
      checksum ^= b;
    }
    return [0x10, 0x02, ...dataBytes, 0x10, 0x03, checksum];
  }

  /// Build the full command sequence for storing/saving a preset:
  /// 1. Store preset name command (cmd 0x26)
  /// 2. Store to slot command (cmd 0x21)
  /// 3. Status query (cmd 0x12)
  static List<List<int>> buildStorePresetSequence(int presetIndex, String name) {
    return [
      buildStorePresetNameCommand(name),
      buildStorePresetSlotCommand(presetIndex),
      ...TRacksProto.statusQueryCommands,
    ];
  }
}