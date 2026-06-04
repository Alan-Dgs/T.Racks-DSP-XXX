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
