// DSP408 Protocol Service
//
// Handles encoding and decoding of DSP408 protocol messages.
// Includes command building, checksum calculation, and message parsing.

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
      levels.add(linear);
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
