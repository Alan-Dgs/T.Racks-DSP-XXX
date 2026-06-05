import 'package:flutter_test/flutter_test.dart';
import 'package:dsp/devices/t_racks408/providers/device_provider.dart';
import 'package:dsp/devices/t_racks408/services/protocol_service.dart';
import 'package:dsp/devices/t_racks408/services/socket_service.dart';

void main() {
  test('offline snapshot preserves implemented DSP408 state', () {
    final source = DeviceProvider(SocketService(), ProtocolService());
    final target = DeviceProvider(SocketService(), ProtocolService());

    source.setGain('In A', -3.2);
    source.toggleMute('Out 1');
    source.togglePhase('In A');
    source.toggleMatrixInput('Out 1', 'In A');
    source.setMatrixGain('Out 1', 'In A', -6.0);
    source.setGeqBand('In A', 0, 2.5);
    source.setGeqBypass('In A', true);
    source.setPeqBand(
      'Out 1',
      8,
      freqRaw: 321,
      qRaw: 44,
      gainDb: -4.5,
      type: 2,
      bypass: true,
    );
    source.setHiPass('Out 1', freqRaw: 120, slope: 6, enabled: true);
    source.setLoPass('Out 1', freqRaw: 900, slope: 12, enabled: true);
    source.setGate(
      'In A',
      thresholdDb: -40,
      attackMs: 10,
      holdMs: 250,
      releaseMs: 750,
    );
    source.setCompressor(
      'Out 1',
      thresholdDb: -20,
      ratioRaw: 5,
      kneeDb: 6,
      attackMs: 25,
      releaseMs: 800,
    );
    source.setLimiter('Out 1', thresholdDb: -10, attackMs: 20, releaseMs: 500);
    source.setDelay('Out 1', 19.896);
    source.setDelayUnit(1);
    source.setTestTone(source: 3, frequencyIndex: 17);

    final snapshot = source.exportOfflineSnapshot();
    target.applyOfflineSnapshot(snapshot);

    expect(target.hasLocalChanges, isTrue);
    expect(target.getInputGain('In A'), -3.2);
    expect(target.getOutputMute('Out 1'), isTrue);
    expect(target.getInputPhase('In A'), isTrue);
    expect(target.getMatrixEnabled('Out 1', 'In A'), isTrue);
    expect(target.getMatrixGain('Out 1', 'In A'), -6.0);
    expect(target.getGeqBand('In A', 0), 2.5);
    expect(target.getGeqBypass('In A'), isTrue);

    final peq = target.getPeqBand('Out 1', 8);
    expect(peq.freqRaw, 321);
    expect(peq.qRaw, 44);
    expect(peq.gainDb, -4.5);
    expect(peq.type, 2);
    expect(peq.bypass, isTrue);

    expect(target.getHiPass('Out 1').enabled, isTrue);
    expect(target.getLoPass('Out 1').freqRaw, 900);
    expect(target.getGate('In A').holdMs, 250);
    expect(target.getCompressor('Out 1').ratioRaw, 5);
    expect(target.getLimiter('Out 1').thresholdDb, -10);
    expect(target.getDelay('Out 1').ms, 19.896);
    expect(target.delayUnit, 1);
    expect(target.testTone.source, 3);
    expect(target.testTone.frequencyIndex, 17);

    source.dispose();
    target.dispose();
  });
}
