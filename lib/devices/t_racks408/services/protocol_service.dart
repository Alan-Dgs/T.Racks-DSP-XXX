// DSP408 Protocol Service
//
// Handles encoding and decoding of DSP408 protocol messages.
// Includes command building, checksum calculation, and message parsing.

import 'dart:math' as math;

/// Types of protocol messages
enum MessageType {
  handshake,
  deviceInfo,
  preset,
  currentPreset,
  channelConfig,
  presetCount,
  gain,
  mute,
  keepalive,
  unknown,
}

/// Base class for protocol messages
abstract class ProtocolMessage {
  final MessageType type;
  final List<int> rawData;

  ProtocolMessage(this.type, this.rawData);
}

/// Preset information message
class PresetMessage extends ProtocolMessage {
  final int index;
  final String name;

  PresetMessage(this.index, this.name, List<int> rawData)
      : super(MessageType.preset, rawData);
}

/// Current preset message
class CurrentPresetMessage extends ProtocolMessage {
  final String name;

  CurrentPresetMessage(this.name, List<int> rawData)
      : super(MessageType.currentPreset, rawData);
}

/// Channel config chunk message (cmd 0x24)
class ChannelConfigMessage extends ProtocolMessage {
  final int subIndex;
  final List<int> chunkData;

  ChannelConfigMessage(this.subIndex, this.chunkData, List<int> rawData)
      : super(MessageType.channelConfig, rawData);
}

/// Device info message
class DeviceInfoMessage extends ProtocolMessage {
  final String deviceName;

  DeviceInfoMessage(this.deviceName, List<int> rawData)
      : super(MessageType.deviceInfo, rawData);
}

/// Preset count message
class PresetCountMessage extends ProtocolMessage {
  final int count;

  PresetCountMessage(this.count, List<int> rawData)
      : super(MessageType.presetCount, rawData);
}

/// Keepalive/meter message (cmd 0x40 response with 12 channel levels)
class KeepaliveMessage extends ProtocolMessage {
  /// Meter levels for all 12 channels as linear float values
  /// Order: In A, In B, In C, In D, Out 1-8
  final List<double> meterLevels;

  KeepaliveMessage(this.meterLevels, List<int> rawData)
      : super(MessageType.keepalive, rawData);
}

/// Unknown message
class UnknownMessage extends ProtocolMessage {
  UnknownMessage(List<int> rawData) : super(MessageType.unknown, rawData);
}

class ProtocolService {
  /// Decode IEEE 754 half-precision (float16) from 2 bytes in little-endian
  static double decodeFloat16(int low, int high) {
    final value = low | (high << 8);
    final sign = (value >> 15) & 1;
    final exponent = (value >> 10) & 0x1F;
    final mantissa = value & 0x3FF;

    double result;
    if (exponent == 0) {
      // Subnormal
      result = (mantissa / 1024.0) * (1.0 / 16384.0); // 2^-14
    } else if (exponent == 31) {
      // Inf/NaN
      result = mantissa == 0 ? double.infinity : double.nan;
    } else {
      result = (1.0 + mantissa / 1024.0) * _pow2(exponent - 15);
    }
    return sign == 1 ? -result : result;
  }

  static double _pow2(int exp) {
    if (exp >= 0) {
      return (1 << exp).toDouble();
    } else {
      return 1.0 / (1 << -exp).toDouble();
    }
  }

  /// Parse 12 channel meter levels from keepalive response data
  /// Each channel is 3 bytes: [float16_low, float16_high, peak_byte]
  static List<double> parseMeterLevels(List<int> data) {
    final levels = <double>[];
    // Data starts at byte 6 (after 10 02 01 00 27 40)
    // 12 channels * 3 bytes = 36 bytes of meter data
    if (data.length < 42) return List.filled(12, 0.0); // too short

    for (int ch = 0; ch < 12; ch++) {
      final offset = 6 + ch * 3;
      final linear = decodeFloat16(data[offset], data[offset + 1]);
      // DSP returns 0xFF 0xFF (NaN) for channels during PEQ recalculation
      levels.add(linear.isFinite ? linear : 0.0);
    }
    return levels;
  }

  /// Calculate checksum for DSP408 protocol
  int calculateChecksum(List<int> dataBytes) {
    int checksum = 1;
    for (int byte in dataBytes) {
      checksum ^= byte;
    }
    return checksum;
  }

  /// Convert dB value to DSP protocol value
  int gainDbToValue(double dB) {
    if (dB < -20.0) {
      // Coarse range: 0.5dB resolution (2 units per dB)
      return ((dB + 60) * 2).round();
    } else {
      // Fine range: 0.1dB resolution (10 units per dB)
      return (80 + (dB + 20) * 10).round();
    }
  }

  /// Convert DSP protocol value back to dB
  double gainValueToDb(int value) {
    return (value - 280) / 10.0;
  }

  /// Quantize gain value to appropriate step
  double quantizeGain(double dB) {
    if (dB < -20.0) {
      // Coarse range: round to nearest 0.5dB
      return (dB * 2).round() / 2;
    } else {
      // Fine range: round to nearest 0.1dB
      return (dB * 10).round() / 10;
    }
  }

  /// Build gain command
  List<int> buildGainCommand(String channelLabel, double dB) {
    final quantizedDb = quantizeGain(dB);
    final value = gainDbToValue(quantizedDb);
    final valueLow = value & 0xFF;
    final valueHigh = (value >> 8) & 0xFF;

    // Map label to channel index
    final channelMap = {
      'In A': 0x00, 'In B': 0x01, 'In C': 0x02, 'In D': 0x03,
      'Out 1': 0x04, 'Out 2': 0x05, 'Out 3': 0x06, 'Out 4': 0x07,
      'Out 5': 0x08, 'Out 6': 0x09, 'Out 7': 0x0A, 'Out 8': 0x0B,
    };

    final channel = channelMap[channelLabel];
    if (channel == null) {
      throw ArgumentError('Invalid channel label: $channelLabel');
    }

    // Build command: 10 02 00 01 04 34 [channel] [value_low] [value_high] 10 03 [checksum]
    final dataBytes = [0x00, 0x01, 0x04, 0x34, channel, valueLow, valueHigh];
    final checksum = calculateChecksum(dataBytes);

    return [0x10, 0x02, ...dataBytes, 0x10, 0x03, checksum];
  }

  /// Build mute command
  List<int> buildMuteCommand(String channelLabel, bool mute) {
    final muteCommands = {
      // Input channels
      'In A': mute
          ? [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x00, 0x01, 0x10, 0x03, 0x37]
          : [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x00, 0x00, 0x10, 0x03, 0x36],
      'In B': mute
          ? [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x01, 0x01, 0x10, 0x03, 0x36]
          : [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x01, 0x00, 0x10, 0x03, 0x37],
      'In C': mute
          ? [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x02, 0x01, 0x10, 0x03, 0x35]
          : [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x02, 0x00, 0x10, 0x03, 0x34],
      'In D': mute
          ? [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x03, 0x01, 0x10, 0x03, 0x34]
          : [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x03, 0x00, 0x10, 0x03, 0x35],
      // Output channels
      'Out 1': mute
          ? [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x04, 0x01, 0x10, 0x03, 0x33]
          : [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x04, 0x00, 0x10, 0x03, 0x32],
      'Out 2': mute
          ? [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x05, 0x01, 0x10, 0x03, 0x32]
          : [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x05, 0x00, 0x10, 0x03, 0x33],
      'Out 3': mute
          ? [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x06, 0x01, 0x10, 0x03, 0x31]
          : [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x06, 0x00, 0x10, 0x03, 0x30],
      'Out 4': mute
          ? [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x07, 0x01, 0x10, 0x03, 0x30]
          : [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x07, 0x00, 0x10, 0x03, 0x31],
      'Out 5': mute
          ? [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x08, 0x01, 0x10, 0x03, 0x3F]
          : [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x08, 0x00, 0x10, 0x03, 0x3E],
      'Out 6': mute
          ? [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x09, 0x01, 0x10, 0x03, 0x3E]
          : [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x09, 0x00, 0x10, 0x03, 0x3F],
      'Out 7': mute
          ? [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x0A, 0x01, 0x10, 0x03, 0x3D]
          : [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x0A, 0x00, 0x10, 0x03, 0x3C],
      'Out 8': mute
          ? [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x0B, 0x01, 0x10, 0x03, 0x3C]
          : [0x10, 0x02, 0x00, 0x01, 0x03, 0x35, 0x0B, 0x00, 0x10, 0x03, 0x3D],
    };

    final command = muteCommands[channelLabel];
    if (command == null) {
      throw ArgumentError('Invalid channel label: $channelLabel');
    }

    return command;
  }

  /// Convert GEQ dB value (-12.0 to +12.0) to protocol byte (0x00-0xF0)
  /// Linear: byte = (dB * 10) + 120, resolution 0.1 dB
  int geqDbToValue(double dB) => (dB * 10 + 120).round().clamp(0, 240);

  /// Convert GEQ protocol byte back to dB
  double geqValueToDb(int value) => (value - 120) / 10.0;

  /// Quantize GEQ dB to 0.1 dB resolution
  double quantizeGeqDb(double dB) => (dB * 10).round() / 10.0;

  /// Build GEQ band command (cmd 0x05 0x48)
  ///
  /// Protocol: `10 02 00 01 05 48 [channel] [band] [value] 00 10 03 [checksum]`
  /// Channel: 0x00=In A, 0x01=In B, 0x02=In C, 0x03=In D
  /// Band: 0x00-0x1E (0-30, 20Hz-20kHz)
  /// Value: 0x00-0xF0 (0-240, -12.0 to +12.0 dB)
  List<int> buildGeqBandCommand(String channel, int bandIndex, double dB) {
    const channelMap = {
      'In A': 0x00, 'In B': 0x01, 'In C': 0x02, 'In D': 0x03,
    };
    final ch = channelMap[channel];
    if (ch == null) throw ArgumentError('Invalid GEQ channel: $channel');
    if (bandIndex < 0 || bandIndex > 30) {
      throw ArgumentError('Invalid band index: $bandIndex');
    }

    final value = geqDbToValue(quantizeGeqDb(dB));
    final dataBytes = [0x00, 0x01, 0x05, 0x48, ch, bandIndex, value, 0x00];
    final checksum = calculateChecksum(dataBytes);
    return [0x10, 0x02, ...dataBytes, 0x10, 0x03, checksum];
  }

  /// Build matrix routing command (cmd 0x3a)
  ///
  /// Protocol: `10 02 00 01 03 3a [output_byte] [input_bitmask] 10 03 [checksum]`
  /// Output byte: 0x04 = Out 1, ..., 0x0b = Out 8
  /// Input bitmask: 0x01 = In A, 0x02 = In B, 0x04 = In C, 0x08 = In D
  List<int> buildMatrixRoutingCommand(String output, int inputBitmask) {
    const outputMap = {
      'Out 1': 0x04, 'Out 2': 0x05, 'Out 3': 0x06, 'Out 4': 0x07,
      'Out 5': 0x08, 'Out 6': 0x09, 'Out 7': 0x0A, 'Out 8': 0x0B,
    };
    final outputByte = outputMap[output];
    if (outputByte == null) {
      throw ArgumentError('Invalid output label: $output');
    }
    final dataBytes = [0x00, 0x01, 0x03, 0x3a, outputByte, inputBitmask];
    final checksum = calculateChecksum(dataBytes);
    return [0x10, 0x02, ...dataBytes, 0x10, 0x03, checksum];
  }

  /// Input bitmask constants for matrix routing
  static const matrixInputBits = {
    'In A': 0x01,
    'In B': 0x02,
    'In C': 0x04,
    'In D': 0x08,
  };

  // ─── PEQ ───

  /// PEQ frequency encoding: log scale from 19.70 Hz to 20160 Hz over 1000 steps.
  /// freq_hz = 19.70 * (20160/19.70)^(raw/1000)
  static const double _peqMinFreq = 19.70;
  static const double _peqMaxFreq = 20160.0;
  static const double _peqFreqRatio = _peqMaxFreq / _peqMinFreq;
  static const int _peqFreqSteps = 1000;

  /// Convert PEQ raw frequency value to Hz
  double peqFreqToHz(int raw) {
    if (raw <= 0) return _peqMinFreq;
    if (raw >= _peqFreqSteps) return _peqMaxFreq;
    return _peqMinFreq * math.pow(_peqFreqRatio, raw / _peqFreqSteps);
  }

  /// Convert Hz to PEQ raw frequency value
  int peqHzToFreq(double hz) {
    if (hz <= _peqMinFreq) return 0;
    if (hz >= _peqMaxFreq) return _peqFreqSteps;
    return (math.log(hz / _peqMinFreq) / math.log(_peqFreqRatio) * _peqFreqSteps).round().clamp(0, _peqFreqSteps);
  }

  /// PEQ Q encoding: log scale from 0.40 to 128.00 over 255 steps.
  double peqRawToQ(int raw) {
    if (raw <= 0) return 0.40;
    if (raw >= 255) return 128.0;
    return 0.40 * math.pow(320.0, raw / 255.0); // 320 = 128.0/0.40
  }

  int peqQToRaw(double q) {
    if (q <= 0.40) return 0;
    if (q >= 128.0) return 255;
    return (math.log(q / 0.40) / math.log(320.0) * 255.0).round().clamp(0, 255);
  }

  /// PEQ gain: same encoding as GEQ (0-240, dB = (value-120)/10.0)
  double peqGainToDb(int value) => (value - 120) / 10.0;
  int peqDbToGain(double dB) => (dB * 10 + 120).round().clamp(0, 240);

  /// PEQ filter types
  static const peqTypeNames = [
    'Peak', 'Low Shelf', 'High Shelf',
    'LP -6dB', 'LP -12dB', 'HP -6dB', 'HP -12dB',
    'All Pass 1', 'All Pass 2',
  ];

  /// Hi/Lo Pass crossover slope types
  static const crossoverSlopeNames = [
    'BW -6', 'BW -12', 'BW -18', 'BW -24', 'BW -30', 'BW -36', 'BW -42', 'BW -48',
    'LR -12', 'LR -24', 'LR -36', 'LR -48',
    'BS -6', 'BS -12', 'BS -18', 'BS -24', 'BS -30', 'BS -36', 'BS -42', 'BS -48',
  ];

  /// Build PEQ band command (cmd 0x33)
  ///
  /// Protocol: `10 02 00 01 0a 33 [ch] [band] [gain] [00] [freq_lo] [freq_hi] [Q] [type] [bypass] 10 03 [chk]`
  List<int> buildPeqBandCommand(String channel, int band, {
    required double gainDb,
    required int freqRaw,
    required int qRaw,
    required int type,
    required bool bypass,
  }) {
    const channelMap = {
      'In A': 0x00, 'In B': 0x01, 'In C': 0x02, 'In D': 0x03,
      'Out 1': 0x04, 'Out 2': 0x05, 'Out 3': 0x06, 'Out 4': 0x07,
      'Out 5': 0x08, 'Out 6': 0x09, 'Out 7': 0x0A, 'Out 8': 0x0B,
    };
    final ch = channelMap[channel];
    if (ch == null) throw ArgumentError('Invalid PEQ channel: $channel');

    final gain = peqDbToGain(gainDb);
    final freqLo = freqRaw & 0xFF;
    final freqHi = (freqRaw >> 8) & 0xFF;

    final dataBytes = [0x00, 0x01, 0x0a, 0x33, ch, band, gain, 0x00, freqLo, freqHi, qRaw & 0xFF, type, bypass ? 1 : 0];
    final checksum = calculateChecksum(dataBytes);
    return [0x10, 0x02, ...dataBytes, 0x10, 0x03, checksum];
  }

  /// Build Hi Pass filter command (cmd 0x32)
  ///
  /// Protocol: `10 02 00 01 05 32 [ch] [freq_lo] [freq_hi] [enable] 10 03 [chk]`
  List<int> buildHiPassCommand(String channel, int freqRaw, bool enable) {
    const channelMap = {
      'In A': 0x00, 'In B': 0x01, 'In C': 0x02, 'In D': 0x03,
      'Out 1': 0x04, 'Out 2': 0x05, 'Out 3': 0x06, 'Out 4': 0x07,
      'Out 5': 0x08, 'Out 6': 0x09, 'Out 7': 0x0A, 'Out 8': 0x0B,
    };
    final ch = channelMap[channel];
    if (ch == null) throw ArgumentError('Invalid channel: $channel');

    final freqLo = freqRaw & 0xFF;
    final freqHi = (freqRaw >> 8) & 0xFF;

    final dataBytes = [0x00, 0x01, 0x05, 0x32, ch, freqLo, freqHi, enable ? 1 : 0];
    final checksum = calculateChecksum(dataBytes);
    return [0x10, 0x02, ...dataBytes, 0x10, 0x03, checksum];
  }

  /// Build Lo Pass filter command (cmd 0x31)
  ///
  /// Protocol: `10 02 00 01 05 31 [ch] [freq_lo] [freq_hi] [slope] 10 03 [chk]`
  List<int> buildLoPassCommand(String channel, int freqRaw, int slope) {
    const channelMap = {
      'In A': 0x00, 'In B': 0x01, 'In C': 0x02, 'In D': 0x03,
      'Out 1': 0x04, 'Out 2': 0x05, 'Out 3': 0x06, 'Out 4': 0x07,
      'Out 5': 0x08, 'Out 6': 0x09, 'Out 7': 0x0A, 'Out 8': 0x0B,
    };
    final ch = channelMap[channel];
    if (ch == null) throw ArgumentError('Invalid channel: $channel');

    final freqLo = freqRaw & 0xFF;
    final freqHi = (freqRaw >> 8) & 0xFF;

    final dataBytes = [0x00, 0x01, 0x05, 0x31, ch, freqLo, freqHi, slope];
    final checksum = calculateChecksum(dataBytes);
    return [0x10, 0x02, ...dataBytes, 0x10, 0x03, checksum];
  }

  /// Build keepalive command
  List<int> buildKeepaliveCommand() {
    return [0x10, 0x02, 0x00, 0x01, 0x01, 0x40, 0x10, 0x03, 0x41];
  }

  /// Check if data is a keepalive response
  bool isKeepaliveResponse(List<int> data) {
    if (data.length < 6) return false;
    return data[0] == 0x10 &&
        data[1] == 0x02 &&
        data[2] == 0x01 && // Response marker
        data[5] == 0x40; // Keepalive command byte
  }

  /// Decode protocol message
  ProtocolMessage? decode(List<int> data) {
    if (data.length < 6 || data[0] != 0x10 || data[1] != 0x02) {
      return null;
    }

    try {
      // Find footer (10 03)
      int footerIndex = -1;
      for (int i = 0; i < data.length - 1; i++) {
        if (data[i] == 0x10 && data[i + 1] == 0x03) {
          footerIndex = i;
          break;
        }
      }

      if (footerIndex == -1) return null;

      // Extract command and data payload
      final isResponse = data[2] == 0x01;
      if (!isResponse || data.length <= 7) return null;

      final cmdByte = data[5];
      final dataByte = data.length > 6 ? data[6] : null;

      // Keepalive / meter response
      if (cmdByte == 0x40) {
        final levels = parseMeterLevels(data);
        return KeepaliveMessage(levels, data);
      }

      // Device info
      if (cmdByte == 0x13 && data.length > 10) {
        final nameBytes = data.sublist(7, footerIndex);
        final deviceName = String.fromCharCodes(nameBytes).trim();
        return DeviceInfoMessage(deviceName, data);
      }

      // Preset data
      if (cmdByte == 0x29 && dataByte != null) {
        final presetNum = dataByte;
        final nameBytes = data.sublist(7, footerIndex);
        final presetName = String.fromCharCodes(nameBytes).trim();
        return PresetMessage(presetNum, presetName, data);
      }

      // Preset count
      if (cmdByte == 0x2c && data.length > 7) {
        final count = data[7];
        return PresetCountMessage(count, data);
      }

      // Channel config chunk (cmd 0x24)
      if (cmdByte == 0x24 && dataByte != null) {
        final chunkData = data.sublist(7, footerIndex);
        return ChannelConfigMessage(dataByte, chunkData, data);
      }

      return UnknownMessage(data);
    } catch (e) {
      return null;
    }
  }

  /// Format data as hex string for display
  String formatAsHex(List<int> data) {
    return data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  /// Format data as ASCII string for display
  String formatAsAscii(List<int> data) {
    return data
        .map((b) => (b >= 0x20 && b <= 0x7E) ? String.fromCharCode(b) : '.')
        .join('');
  }
}
