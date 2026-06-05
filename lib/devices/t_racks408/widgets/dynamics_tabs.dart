import 'package:flutter/material.dart';

import '../providers/device_provider.dart';
import '../services/protocol_service.dart';

class GateTab extends StatelessWidget {
  final DeviceProvider deviceProvider;

  const GateTab({super.key, required this.deviceProvider});

  @override
  Widget build(BuildContext context) {
    return _ChannelGrid(
      channels: deviceProvider.inputChannels,
      itemHeight: 292,
      builder: (channel) {
        final state = deviceProvider.getGate(channel);
        return _ChannelPanel(
          title: deviceProvider.getAlias(channel),
          subtitle: 'Input gate',
          children: [
            _DbSlider(
              label: 'Threshold',
              value: state.thresholdDb,
              min: -90,
              max: 0,
              divisions: 180,
              onChanged: (value) =>
                  deviceProvider.setGate(channel, thresholdDb: value),
            ),
            _MsSlider(
              label: 'Attack',
              value: state.attackMs,
              min: 1,
              max: 999,
              onChanged: (value) =>
                  deviceProvider.setGate(channel, attackMs: value),
            ),
            _MsSlider(
              label: 'Hold',
              value: state.holdMs,
              min: 10,
              max: 999,
              onChanged: (value) =>
                  deviceProvider.setGate(channel, holdMs: value),
            ),
            _MsSlider(
              label: 'Release',
              value: state.releaseMs,
              min: 10,
              max: 3000,
              onChanged: (value) =>
                  deviceProvider.setGate(channel, releaseMs: value),
            ),
          ],
        );
      },
    );
  }
}

class CompressorTab extends StatelessWidget {
  final DeviceProvider deviceProvider;

  const CompressorTab({super.key, required this.deviceProvider});

  @override
  Widget build(BuildContext context) {
    return _ChannelGrid(
      channels: deviceProvider.outputChannels,
      itemHeight: 344,
      builder: (channel) {
        final state = deviceProvider.getCompressor(channel);
        return _ChannelPanel(
          title: deviceProvider.getAlias(channel),
          subtitle: 'Output compressor',
          children: [
            _DbSlider(
              label: 'Threshold',
              value: state.thresholdDb,
              min: -90,
              max: 20,
              divisions: 220,
              onChanged: (value) =>
                  deviceProvider.setCompressor(channel, thresholdDb: value),
            ),
            _RatioDropdown(
              value: state.ratioRaw,
              onChanged: (value) =>
                  deviceProvider.setCompressor(channel, ratioRaw: value),
            ),
            _IntSlider(
              label: 'Knee',
              value: state.kneeDb,
              min: 0,
              max: 12,
              suffix: 'dB',
              onChanged: (value) =>
                  deviceProvider.setCompressor(channel, kneeDb: value),
            ),
            _MsSlider(
              label: 'Attack',
              value: state.attackMs,
              min: 1,
              max: 999,
              onChanged: (value) =>
                  deviceProvider.setCompressor(channel, attackMs: value),
            ),
            _MsSlider(
              label: 'Release',
              value: state.releaseMs,
              min: 10,
              max: 3000,
              onChanged: (value) =>
                  deviceProvider.setCompressor(channel, releaseMs: value),
            ),
          ],
        );
      },
    );
  }
}

class LimiterTab extends StatelessWidget {
  final DeviceProvider deviceProvider;

  const LimiterTab({super.key, required this.deviceProvider});

  @override
  Widget build(BuildContext context) {
    return _ChannelGrid(
      channels: deviceProvider.outputChannels,
      itemHeight: 244,
      builder: (channel) {
        final state = deviceProvider.getLimiter(channel);
        return _ChannelPanel(
          title: deviceProvider.getAlias(channel),
          subtitle: 'Output limiter',
          children: [
            _DbSlider(
              label: 'Threshold',
              value: state.thresholdDb,
              min: -90,
              max: 20,
              divisions: 220,
              onChanged: (value) =>
                  deviceProvider.setLimiter(channel, thresholdDb: value),
            ),
            _MsSlider(
              label: 'Attack',
              value: state.attackMs,
              min: 1,
              max: 999,
              onChanged: (value) =>
                  deviceProvider.setLimiter(channel, attackMs: value),
            ),
            _MsSlider(
              label: 'Release',
              value: state.releaseMs,
              min: 10,
              max: 3000,
              onChanged: (value) =>
                  deviceProvider.setLimiter(channel, releaseMs: value),
            ),
          ],
        );
      },
    );
  }
}

class DelayTab extends StatelessWidget {
  final DeviceProvider deviceProvider;

  const DelayTab({super.key, required this.deviceProvider});

  static const _units = ['ms', 'm', 'ft'];

  @override
  Widget build(BuildContext context) {
    final selected = deviceProvider.delayUnit;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: SegmentedButton<int>(
            segments: List.generate(
              _units.length,
              (index) =>
                  ButtonSegment<int>(value: index, label: Text(_units[index])),
            ),
            selected: {selected},
            onSelectionChanged: (value) =>
                deviceProvider.setDelayUnit(value.first),
          ),
        ),
        Expanded(
          child: _ChannelGrid(
            channels: deviceProvider.allChannels,
            itemHeight: 172,
            builder: (channel) {
              final state = deviceProvider.getDelay(channel);
              return _ChannelPanel(
                title: deviceProvider.getAlias(channel),
                subtitle: _units[selected],
                children: [
                  _DelaySlider(
                    ms: state.ms,
                    unit: selected,
                    onChanged: (value) =>
                        deviceProvider.setDelay(channel, value),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChannelGrid extends StatelessWidget {
  final List<String> channels;
  final double itemHeight;
  final Widget Function(String channel) builder;

  const _ChannelGrid({
    required this.channels,
    required this.itemHeight,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 330,
        mainAxisExtent: itemHeight,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: channels.length,
      itemBuilder: (context, index) => builder(channels[index]),
    );
  }
}

class _ChannelPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _ChannelPanel({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFA6E22E),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF75715E),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DbSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _DbSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _LabeledControl(
      label: label,
      value: '${_signed(value)} dB',
      child: Slider(
        min: min,
        max: max,
        divisions: divisions,
        value: value.clamp(min, max),
        onChanged: (v) => onChanged((v * 2).round() / 2.0),
      ),
    );
  }

  String _signed(double value) {
    final sign = value >= 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(1)}';
  }
}

class _MsSlider extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _MsSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _IntSlider(
      label: label,
      value: value,
      min: min,
      max: max,
      suffix: 'ms',
      onChanged: onChanged,
    );
  }
}

class _IntSlider extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final String suffix;
  final ValueChanged<int> onChanged;

  const _IntSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _LabeledControl(
      label: label,
      value: '$value $suffix',
      child: Slider(
        min: min.toDouble(),
        max: max.toDouble(),
        divisions: max - min,
        value: value.clamp(min, max).toDouble(),
        onChanged: (v) => onChanged(v.round()),
      ),
    );
  }
}

class _DelaySlider extends StatelessWidget {
  final double ms;
  final int unit;
  final ValueChanged<double> onChanged;

  const _DelaySlider({
    required this.ms,
    required this.unit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _LabeledControl(
      label: 'Delay',
      value: _format(ms, unit),
      child: Slider(
        min: 0,
        max: 680,
        divisions: 6800,
        value: ms.clamp(0.0, 680.0),
        onChanged: (value) => onChanged((value * 10).round() / 10.0),
      ),
    );
  }

  String _format(double ms, int unit) {
    if (unit == 1) {
      return '${(ms * 233.580 / 680.0).toStringAsFixed(3)} m';
    }
    if (unit == 2) {
      return '${(ms * 766.329 / 680.0).toStringAsFixed(3)} ft';
    }
    return '${ms.toStringAsFixed(3)} ms';
  }
}

class _RatioDropdown extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _RatioDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final entries = ProtocolService.compressorRatioNames
        .map(
          (name) =>
              MapEntry(name, ProtocolService.compressorRatioRawByName[name]!),
        )
        .toList();
    final selected = entries.any((entry) => entry.value == value)
        ? value
        : entries.first.value;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const SizedBox(
            width: 86,
            child: Text('Ratio', style: TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: DropdownButton<int>(
              value: selected,
              isExpanded: true,
              items: entries
                  .map(
                    (entry) => DropdownMenuItem<int>(
                      value: entry.value,
                      child: Text(entry.key),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) onChanged(value);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledControl extends StatelessWidget {
  final String label;
  final String value;
  final Widget child;

  const _LabeledControl({
    required this.label,
    required this.value,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 86,
                child: Text(label, style: const TextStyle(fontSize: 12)),
              ),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFD971F),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
