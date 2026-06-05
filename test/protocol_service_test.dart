import 'package:flutter_test/flutter_test.dart';

import 'package:dsp/devices/t_racks408/device_profile.dart';
import 'package:dsp/devices/t_racks408/services/protocol_service.dart';

void main() {
  group('DeviceProfiles.dsp408', () {
    test('describes the 4x8 channel layout', () {
      const profile = DeviceProfiles.dsp408;

      expect(profile.inputChannels, ['In A', 'In B', 'In C', 'In D']);
      expect(profile.outputChannels.length, 8);
      expect(profile.channelIndex('In A'), 0x00);
      expect(profile.channelIndex('Out 8'), 0x0B);
      expect(profile.allChannels.length, 12);
    });
  });

  group('ProtocolService command builders', () {
    final proto = ProtocolService();

    test('builds gain commands with calculated checksum', () {
      expect(proto.buildGainCommand('In A', 0.0), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x04,
        0x34,
        0x00,
        0x18,
        0x01,
        0x10,
        0x03,
        0x29,
      ]);

      expect(proto.buildGainCommand('Out 8', -60.0), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x04,
        0x34,
        0x0B,
        0x00,
        0x00,
        0x10,
        0x03,
        0x3B,
      ]);
    });

    test('builds mute commands from the channel profile', () {
      expect(proto.buildMuteCommand('In A', true), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x03,
        0x35,
        0x00,
        0x01,
        0x10,
        0x03,
        0x37,
      ]);

      expect(proto.buildMuteCommand('Out 8', false), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x03,
        0x35,
        0x0B,
        0x00,
        0x10,
        0x03,
        0x3D,
      ]);
    });

    test('builds matrix routing commands', () {
      final mask =
          ProtocolService.matrixInputBits['In A']! |
          ProtocolService.matrixInputBits['In C']!;

      expect(proto.buildMatrixRoutingCommand('Out 1', mask), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x03,
        0x3A,
        0x04,
        0x05,
        0x10,
        0x03,
        0x38,
      ]);
    });

    test('builds matrix attenuation commands from capture', () {
      expect(proto.buildMatrixGainCommand('Out 1', 'In A', -6.0), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x05,
        0x41,
        0x04,
        0x00,
        0xDC,
        0x00,
        0x10,
        0x03,
        0x9C,
      ]);
    });

    test('builds phase commands from capture', () {
      expect(proto.buildPhaseCommand('In A', true), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x03,
        0x36,
        0x00,
        0x01,
        0x10,
        0x03,
        0x34,
      ]);

      expect(proto.buildPhaseCommand('Out 1', false), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x03,
        0x36,
        0x04,
        0x00,
        0x10,
        0x03,
        0x31,
      ]);
    });

    test('builds GEQ commands for input channels only', () {
      expect(proto.buildGeqBandCommand('In B', 0, 0.0), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x05,
        0x48,
        0x01,
        0x00,
        0x78,
        0x00,
        0x10,
        0x03,
        0x34,
      ]);

      expect(
        () => proto.buildGeqBandCommand('Out 1', 0, 0.0),
        throwsArgumentError,
      );
    });

    test('builds GEQ bypass command from capture', () {
      expect(proto.buildGeqBypassCommand('In A', true), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x03,
        0x49,
        0x00,
        0x01,
        0x10,
        0x03,
        0x4B,
      ]);
    });

    test('builds HPF/LPF slope commands from capture', () {
      expect(proto.buildHiPassCommand('In A', 0x78, 0x09), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x05,
        0x32,
        0x00,
        0x78,
        0x00,
        0x09,
        0x10,
        0x03,
        0x46,
      ]);

      expect(proto.buildLoPassCommand('In A', 0x012C, 0x14), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x05,
        0x31,
        0x00,
        0x2C,
        0x01,
        0x14,
        0x10,
        0x03,
        0x0D,
      ]);
    });

    test('builds channel name commands from capture', () {
      expect(proto.buildChannelNameCommand('In A', '12345678'), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x0A,
        0x3D,
        0x00,
        0x31,
        0x32,
        0x33,
        0x34,
        0x35,
        0x36,
        0x37,
        0x38,
        0x10,
        0x03,
        0x3F,
      ]);

      expect(proto.buildChannelNameCommand('Out 1', 'Out1'), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x0A,
        0x3D,
        0x04,
        0x4F,
        0x75,
        0x74,
        0x31,
        0x00,
        0x00,
        0x00,
        0x00,
        0x10,
        0x03,
        0x4C,
      ]);
    });

    test('builds gate commands from capture', () {
      expect(
        proto.buildGateCommand(
          'In A',
          thresholdDb: -40.0,
          attackMs: 10,
          holdMs: 250,
          releaseMs: 750,
        ),
        [
          0x10,
          0x02,
          0x00,
          0x01,
          0x0A,
          0x3E,
          0x00,
          0x09,
          0x00,
          0xED,
          0x02,
          0xF9,
          0x00,
          0x64,
          0x00,
          0x10,
          0x03,
          0x4F,
        ],
      );
    });

    test('builds compressor commands from capture', () {
      expect(
        proto.buildCompressorCommand(
          'Out 1',
          thresholdDb: -20.0,
          ratioRaw: 9,
          kneeDb: 6,
          attackMs: 25,
          releaseMs: 800,
        ),
        [
          0x10,
          0x02,
          0x00,
          0x01,
          0x0C,
          0x30,
          0x04,
          0x09,
          0x00,
          0x18,
          0x00,
          0x1F,
          0x03,
          0x06,
          0x00,
          0x8C,
          0x00,
          0x10,
          0x03,
          0xBF,
        ],
      );
    });

    test('uses the complete compressor ratio list from the official UI', () {
      expect(ProtocolService.compressorRatioNames, [
        '1:1.0',
        '1:1.1',
        '1:1.2',
        '1:1.3',
        '1:1.4',
        '1:1.5',
        '1:1.6',
        '1:1.7',
        '1:2.0',
        '1:2.5',
        '1:3.0',
        '1:3.5',
        '1:4.0',
        '1:5.0',
        '1:6.0',
        '1:8.0',
        '1:10',
        '1:20',
        'Limit',
      ]);
      expect(ProtocolService.compressorRatioRawByName['Limit'], 18);
    });

    test('builds limiter commands from capture', () {
      expect(
        proto.buildLimiterCommand(
          'Out 1',
          thresholdDb: -10.0,
          attackMs: 20,
          releaseMs: 500,
        ),
        [
          0x10,
          0x02,
          0x00,
          0x01,
          0x0A,
          0x3F,
          0x04,
          0x13,
          0x00,
          0xF3,
          0x01,
          0x00,
          0x00,
          0xA0,
          0x00,
          0x10,
          0x03,
          0x70,
        ],
      );
    });

    test('builds delay and delay unit commands from capture', () {
      expect(proto.buildDelayCommand('In A', 1.0), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x04,
        0x38,
        0x00,
        0x60,
        0x00,
        0x10,
        0x03,
        0x5C,
      ]);

      expect(proto.buildDelayCommand('Out 1', 10.0), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x04,
        0x38,
        0x04,
        0xC0,
        0x03,
        0x10,
        0x03,
        0xFB,
      ]);

      expect(proto.buildDelayUnitCommand(1), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x02,
        0x15,
        0x01,
        0x10,
        0x03,
        0x16,
      ]);
    });

    test('builds test tone commands from capture', () {
      expect(proto.buildTestToneCommand(0x01), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x03,
        0x39,
        0x01,
        0x00,
        0x10,
        0x03,
        0x3B,
      ]);

      expect(proto.buildTestToneCommand(0x03, frequencyIndex: 0x11), [
        0x10,
        0x02,
        0x00,
        0x01,
        0x03,
        0x39,
        0x03,
        0x11,
        0x10,
        0x03,
        0x28,
      ]);
    });
  });

  group('ProtocolService meter parsing', () {
    test('returns silence for short keepalive packets', () {
      expect(
        ProtocolService.parseMeterLevels([0x10, 0x02, 0x01, 0x00, 0x01, 0x40]),
        List.filled(DeviceProfiles.dsp408.allChannels.length, 0.0),
      );
    });
  });
}
