class DeviceProfile {
  final String id;
  final String displayName;
  final List<String> inputChannels;
  final List<String> outputChannels;
  final Map<String, int> channelIndexes;
  final Map<String, int> matrixInputBits;
  final int presetCount;
  final int configChunkCount;

  const DeviceProfile({
    required this.id,
    required this.displayName,
    required this.inputChannels,
    required this.outputChannels,
    required this.channelIndexes,
    required this.matrixInputBits,
    required this.presetCount,
    required this.configChunkCount,
  });

  List<String> get allChannels => [...inputChannels, ...outputChannels];

  Map<int, String> get channelLabelsByIndex =>
      channelIndexes.map((label, index) => MapEntry(index, label));

  int? channelIndex(String label) => channelIndexes[label];
}

class DeviceProfiles {
  static const dsp408 = DeviceProfile(
    id: 't_racks_dsp_408',
    displayName: 't.racks DSP 408',
    inputChannels: ['In A', 'In B', 'In C', 'In D'],
    outputChannels: [
      'Out 1',
      'Out 2',
      'Out 3',
      'Out 4',
      'Out 5',
      'Out 6',
      'Out 7',
      'Out 8',
    ],
    channelIndexes: {
      'In A': 0x00,
      'In B': 0x01,
      'In C': 0x02,
      'In D': 0x03,
      'Out 1': 0x04,
      'Out 2': 0x05,
      'Out 3': 0x06,
      'Out 4': 0x07,
      'Out 5': 0x08,
      'Out 6': 0x09,
      'Out 7': 0x0A,
      'Out 8': 0x0B,
    },
    matrixInputBits: {'In A': 0x01, 'In B': 0x02, 'In C': 0x04, 'In D': 0x08},
    presetCount: 20,
    configChunkCount: 29,
  );
}
