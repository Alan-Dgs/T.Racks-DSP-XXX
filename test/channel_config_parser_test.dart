import 'package:flutter_test/flutter_test.dart';
import 'package:dsp/devices/t_racks408/load_preset.dart';

void main() {
  test(
    'ChannelConfigParser extracts dynamics and delays from config chunks',
    () {
      final parser = ChannelConfigParser();
      final stream = List<int>.filled(1448, 0);

      final offsets = {
        'InA': 16,
        'InB': 156,
        'InC': 296,
        'InD': 436,
        'Out1': 576,
        'Out2': 680,
        'Out3': 784,
        'Out4': 888,
        'Out5': 992,
        'Out6': 1096,
        'Out7': 1200,
        'Out8': 1304,
      };

      for (final entry in offsets.entries) {
        _writeAscii(stream, entry.value, entry.key);
      }

      _writeLe16(stream, offsets['InA']! + 8, 9); // attack 10 ms
      _writeLe16(stream, offsets['InA']! + 10, 749); // release 750 ms
      _writeLe16(stream, offsets['InA']! + 12, 249); // hold 250 ms
      _writeLe16(stream, offsets['InA']! + 14, 100); // -40.0 dB
      _writeLe16(stream, offsets['InA']! + 136, 96); // 1.000 ms

      _writeLe16(stream, offsets['Out1']! + 72, 9); // 1:4.0
      _writeLe16(stream, offsets['Out1']! + 74, 24); // attack 25 ms
      _writeLe16(stream, offsets['Out1']! + 76, 799); // release 800 ms
      _writeLe16(stream, offsets['Out1']! + 78, 6); // knee 6 dB
      _writeLe16(stream, offsets['Out1']! + 80, 140); // -20.0 dB

      _writeLe16(stream, offsets['Out1']! + 82, 19); // attack 20 ms
      _writeLe16(stream, offsets['Out1']! + 84, 499); // release 500 ms
      _writeLe16(stream, offsets['Out1']! + 88, 160); // -10.0 dB
      _writeLe16(stream, offsets['Out1']! + 94, 960); // 10.000 ms

      for (int i = 0; i < ChannelConfigParser.configChunkCount; i++) {
        final start = i * 50;
        final end = i == ChannelConfigParser.configChunkCount - 1
            ? stream.length
            : start + 50;
        parser.processConfigChunk(_frame(i, stream.sublist(start, end)));
      }

      final gate = parser.gates['In A']!;
      expect(gate.thresholdDb, -40.0);
      expect(gate.attackMs, 10);
      expect(gate.holdMs, 250);
      expect(gate.releaseMs, 750);

      final comp = parser.compressors['Out 1']!;
      expect(comp.thresholdDb, -20.0);
      expect(comp.ratioRaw, 9);
      expect(comp.kneeDb, 6);
      expect(comp.attackMs, 25);
      expect(comp.releaseMs, 800);

      final limiter = parser.limiters['Out 1']!;
      expect(limiter.thresholdDb, -10.0);
      expect(limiter.attackMs, 20);
      expect(limiter.releaseMs, 500);

      expect(parser.delays['In A']!.ms, 1.0);
      expect(parser.delays['Out 1']!.ms, 10.0);
    },
  );
}

List<int> _frame(int index, List<int> chunk) => [
  0x10,
  0x02,
  0x01,
  0x00,
  chunk.length + 1,
  0x24,
  index,
  ...chunk,
  0x10,
  0x03,
  0x00,
];

void _writeAscii(List<int> stream, int offset, String value) {
  final bytes = value.codeUnits;
  for (int i = 0; i < bytes.length; i++) {
    stream[offset + i] = bytes[i];
  }
}

void _writeLe16(List<int> stream, int offset, int value) {
  stream[offset] = value & 0xff;
  stream[offset + 1] = (value >> 8) & 0xff;
}
