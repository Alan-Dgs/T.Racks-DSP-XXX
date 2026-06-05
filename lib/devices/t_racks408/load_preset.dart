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
import 'providers/device_provider.dart';
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
  final Map<String, List<PeqBand>> _peqBands = {};
  final Map<String, FilterState> _hiPass = {};
  final Map<String, FilterState> _loPass = {};
  final Map<String, GateState> _gates = {};
  final Map<String, CompressorState> _compressors = {};
  final Map<String, LimiterState> _limiters = {};
  final Map<String, DelayState> _delays = {};
  String _currentPreset = 'Unknown';

  Map<String, double> get channelGains => Map.unmodifiable(_channelGains);
  Map<String, int> get matrixRouting => Map.unmodifiable(_matrixRouting);
  Map<String, List<double>> get geqBands => Map.unmodifiable(_geqBands);
  Map<String, List<PeqBand>> get peqBands => Map.unmodifiable(_peqBands);
  Map<String, FilterState> get hiPass => Map.unmodifiable(_hiPass);
  Map<String, FilterState> get loPass => Map.unmodifiable(_loPass);
  Map<String, GateState> get gates => Map.unmodifiable(_gates);
  Map<String, CompressorState> get compressors =>
      Map.unmodifiable(_compressors);
  Map<String, LimiterState> get limiters => Map.unmodifiable(_limiters);
  Map<String, DelayState> get delays => Map.unmodifiable(_delays);
  // ignore: unnecessary_getters_setters
  String get currentPreset => _currentPreset;
  // ignore: unnecessary_getters_setters
  set currentPreset(String name) => _currentPreset = name;

  void reset() {
    _configChunks.clear();
    _channelGains.clear();
    _matrixRouting.clear();
    _geqBands.clear();
    _peqBands.clear();
    _hiPass.clear();
    _loPass.clear();
    _gates.clear();
    _compressors.clear();
    _limiters.clear();
    _delays.clear();
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
      'In A': [0x49, 0x6e, 0x41], // "InA"
      'In B': [0x49, 0x6e, 0x42], // "InB"
      'In C': [0x49, 0x6e, 0x43], // "InC"
      'In D': [0x49, 0x6e, 0x44], // "InD"
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
      'In A',
      'In B',
      'In C',
      'In D',
      'Out 1',
      'Out 2',
      'Out 3',
      'Out 4',
      'Out 5',
      'Out 6',
      'Out 7',
      'Out 8',
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
        debugPrint(
          'Config: $channel gain = ${dB.toStringAsFixed(1)} dB (raw: $rawValue)',
        );
      }
    }

    // Extract matrix routing bitmasks for each output channel.
    // Pattern: "OutN" (4 bytes) + 4 null bytes + bitmask byte
    // Bitmask: 0x01=In A, 0x02=In B, 0x04=In C, 0x08=In D
    for (final output in [
      'Out 1',
      'Out 2',
      'Out 3',
      'Out 4',
      'Out 5',
      'Out 6',
      'Out 7',
      'Out 8',
    ]) {
      final offset = channelOffsets[output];
      if (offset == null) continue;
      final bitmaskOffset = offset + 8; // 4 name + 4 nulls
      if (bitmaskOffset < stream.length) {
        _matrixRouting[output] = stream[bitmaskOffset];
        debugPrint(
          'Config: $output matrix = 0x${stream[bitmaskOffset].toRadixString(16).padLeft(2, '0')}',
        );
      }
    }

    // Extract GEQ bands for input channels.
    // Each input record has 31 x u16 LE values at offset +16 from the channel name.
    // Value encoding: same as GEQ set-band command (0-240, dB = (value - 120) / 10.0)
    final proto = ProtocolService();
    for (final input in ['In A', 'In B', 'In C', 'In D']) {
      final offset = channelOffsets[input];
      if (offset == null) continue;

      final geqStart =
          offset + 16; // GEQ data starts 16 bytes after channel name
      final geqEnd = geqStart + 31 * 2; // 31 bands x 2 bytes each
      if (geqEnd > stream.length) continue;

      final bands = <double>[];
      for (int b = 0; b < 31; b++) {
        final pos = geqStart + b * 2;
        final rawValue = stream[pos] | (stream[pos + 1] << 8);
        bands.add(proto.geqValueToDb(rawValue));
      }
      _geqBands[input] = bands;
      debugPrint(
        'Config: $input GEQ loaded (${bands.where((v) => v != 0.0).length} non-zero bands)',
      );
    }

    // Extract PEQ bands for input channels.
    // Each input has 8 PEQ bands × 6 bytes at channelOffset + 78 (after 16-byte header + 62-byte GEQ).
    // Band format: [gain_lo] [gain_hi] [freq_lo] [freq_hi] [Q] [type]
    for (final input in ['In A', 'In B', 'In C', 'In D']) {
      final offset = channelOffsets[input];
      if (offset == null) continue;

      final peqStart = offset + 78; // 16 header + 62 GEQ
      final peqEnd = peqStart + 8 * 6;
      if (peqEnd > stream.length) continue;

      final bands = <PeqBand>[];
      for (int b = 0; b < 8; b++) {
        final pos = peqStart + b * 6;
        bands.add(_parsePeqBand(stream, pos));
      }
      _peqBands[input] = bands;
      debugPrint(
        'Config: $input PEQ loaded (${bands.where((b) => b.gainDb != 0.0).length} non-zero bands)',
      );

      // Input filter data: 6 bytes after PEQ bands
      // [HPF freq LE16] [LPF freq LE16] [00] [00]
      final filterStart = peqEnd;
      if (filterStart + 4 <= stream.length) {
        final hpfFreq = stream[filterStart] | (stream[filterStart + 1] << 8);
        final lpfFreq =
            stream[filterStart + 2] | (stream[filterStart + 3] << 8);
        _hiPass[input] = FilterState(freqRaw: hpfFreq, enabled: hpfFreq > 0);
        _loPass[input] = FilterState(freqRaw: lpfFreq);
        debugPrint('Config: $input HPF=$hpfFreq LPF=$lpfFreq');
      }

      final gateStart = offset + 8;
      if (gateStart + 8 <= stream.length) {
        final attackRaw = _readLe16(stream, gateStart);
        final releaseRaw = _readLe16(stream, gateStart + 2);
        final holdRaw = _readLe16(stream, gateStart + 4);
        final thresholdRaw = _readLe16(stream, gateStart + 6);
        _gates[input] = GateState(
          thresholdDb: _thresholdRawToDb(thresholdRaw, -90.0, 0.0),
          attackMs: _msMinusOneRawToMs(attackRaw, 1, 999),
          holdMs: _msMinusOneRawToMs(holdRaw, 10, 999),
          releaseMs: _msMinusOneRawToMs(releaseRaw, 10, 3000),
        );
      }

      final delayStart = offset + 136;
      if (delayStart + 2 <= stream.length) {
        _delays[input] = DelayState(
          ms: proto.delayRawToMs(_readLe16(stream, delayStart)),
        );
      }
    }

    // Extract PEQ bands for output channels.
    // Each output has 9 PEQ bands x 6 bytes at channelOffset + 24.
    // The first 24 bytes contain output header/routing/gain fields.
    for (final output in [
      'Out 1',
      'Out 2',
      'Out 3',
      'Out 4',
      'Out 5',
      'Out 6',
      'Out 7',
      'Out 8',
    ]) {
      final offset = channelOffsets[output];
      if (offset == null) continue;

      final peqStart = offset + 24;
      final peqEnd = peqStart + 9 * 6;
      if (peqEnd > stream.length) continue;

      final bands = <PeqBand>[];
      for (int b = 0; b < 9; b++) {
        final pos = peqStart + b * 6;
        bands.add(_parsePeqBand(stream, pos));
      }
      _peqBands[output] = bands;
      debugPrint(
        'Config: $output PEQ loaded (${bands.where((b) => b.gainDb != 0.0).length} non-zero bands)',
      );

      // Output HPF/LPF fields are not yet mapped safely from the config dump.
      // Commands are implemented, but applying guessed offsets here would make
      // the UI lie after connection/preset load.

      final compressorStart = offset + 78;
      if (compressorStart + 10 <= stream.length) {
        _compressors[output] = CompressorState(
          ratioRaw: _readLe16(stream, compressorStart).clamp(0, 15),
          attackMs: _msMinusOneRawToMs(
            _readLe16(stream, compressorStart + 2),
            1,
            999,
          ),
          releaseMs: _msMinusOneRawToMs(
            _readLe16(stream, compressorStart + 4),
            10,
            3000,
          ),
          kneeDb: _readLe16(stream, compressorStart + 6).clamp(0, 12),
          thresholdDb: _thresholdRawToDb(
            _readLe16(stream, compressorStart + 8),
            -90.0,
            20.0,
          ),
        );
      }

      final limiterStart = offset + 88;
      if (limiterStart + 8 <= stream.length) {
        _limiters[output] = LimiterState(
          attackMs: _msMinusOneRawToMs(_readLe16(stream, limiterStart), 1, 999),
          releaseMs: _msMinusOneRawToMs(
            _readLe16(stream, limiterStart + 2),
            10,
            3000,
          ),
          thresholdDb: _thresholdRawToDb(
            _readLe16(stream, limiterStart + 6),
            -90.0,
            20.0,
          ),
        );
      }

      final delayStart = offset + 100;
      if (delayStart + 2 <= stream.length) {
        _delays[output] = DelayState(
          ms: proto.delayRawToMs(_readLe16(stream, delayStart)),
        );
      }
    }
  }

  static int _readLe16(List<int> stream, int pos) =>
      stream[pos] | (stream[pos + 1] << 8);

  static double _thresholdRawToDb(int raw, double minDb, double maxDb) =>
      (raw / 2.0 - 90.0).clamp(minDb, maxDb);

  static int _msMinusOneRawToMs(int raw, int minMs, int maxMs) =>
      (raw + 1).clamp(minMs, maxMs);

  /// Parse a single PEQ band from 6 bytes in the stream.
  static PeqBand _parsePeqBand(List<int> stream, int pos) {
    final gainRaw = stream[pos] | (stream[pos + 1] << 8);
    final freqRaw = stream[pos + 2] | (stream[pos + 3] << 8);
    final qRaw = stream[pos + 4];
    final type = stream[pos + 5];
    final gainDb = (gainRaw - 120) / 10.0;
    return PeqBand(
      freqRaw: freqRaw,
      qRaw: qRaw,
      gainDb: gainDb.clamp(-12.0, 12.0),
      type: type.clamp(0, 8),
    );
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
  static List<List<int>> buildStorePresetSequence(
    int presetIndex,
    String name,
  ) {
    return [
      buildStorePresetNameCommand(name),
      buildStorePresetSlotCommand(presetIndex),
      ...TRacksProto.statusQueryCommands,
    ];
  }
}
