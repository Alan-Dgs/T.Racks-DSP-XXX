import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../providers/device_provider.dart';

class GainTab extends StatelessWidget {
  final DeviceProvider deviceProvider;

  const GainTab({super.key, required this.deviceProvider});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Input channels
          Expanded(
            child: Column(
              children: [
                const Text('Inputs',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ['In A', 'In B', 'In C', 'In D']
                        .map((ch) => _buildVerticalFader(context, ch))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Output channels
          Expanded(
            flex: 2,
            child: Column(
              children: [
                const Text('Outputs',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      'Out 1', 'Out 2', 'Out 3', 'Out 4',
                      'Out 5', 'Out 6', 'Out 7', 'Out 8'
                    ]
                        .map((ch) => _buildVerticalFader(context, ch))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalFader(BuildContext context, String channel) {
    final isInput = channel.startsWith('In ');
    final gain = isInput
        ? deviceProvider.getInputGain(channel)
        : deviceProvider.getOutputGain(channel);
    final isMuted = isInput
        ? deviceProvider.getInputMute(channel)
        : deviceProvider.getOutputMute(channel);
    final isInverted = isInput
        ? deviceProvider.getInputPhase(channel)
        : deviceProvider.getOutputPhase(channel);

    final meterLevel = deviceProvider.getMeterLevel(channel);

    return Expanded(
      child: Column(
        children: [
          // Vertical slider overlaid on meter bar
          Expanded(
            child: Stack(
              children: [
                // Meter bar behind the slider
                Positioned.fill(
                  child: Center(
                    child: SizedBox(
                      width: 12,
                      child: MeterBar(level: meterLevel),
                    ),
                  ),
                ),
                // Slider on top
                Positioned.fill(
                  child: Listener(
                    onPointerSignal: (signal) {
                      if (signal is PointerScrollEvent) {
                        final stepSize = gain < -20.0 ? 0.5 : 0.1;
                        final delta =
                            signal.scrollDelta.dy > 0 ? -stepSize : stepSize;
                        final newValue = (gain + delta).clamp(-60.0, 12.0);
                        deviceProvider.setGain(channel, newValue);
                      }
                    },
                    child: GestureDetector(
                      onDoubleTap: () {
                        deviceProvider.setGain(channel, 0.0);
                      },
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            activeTrackColor: Colors.white.withAlpha(120),
                            inactiveTrackColor: Colors.white.withAlpha(40),
                            thumbColor: Colors.white,
                            overlayColor: Colors.white.withAlpha(30),
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                          ),
                          child: Slider(
                            value: gain,
                            min: -60,
                            max: 12,
                            divisions: 720,
                            label: '${gain.toStringAsFixed(1)} dB',
                            onChanged: (val) {
                              deviceProvider.setGain(channel, val);
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Channel label (clickable to rename)
          GestureDetector(
            onTap: () => _showRenameDialog(context, channel),
            child: Text(deviceProvider.getAlias(channel),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          const SizedBox(height: 4),
          // Clickable dB display
          GestureDetector(
            onTap: () => _showDbInputDialog(context, channel, gain),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF75715E)),
                borderRadius: BorderRadius.circular(4),
                color: const Color(0xFF3E3D32),
              ),
              child: Text('${gain.toStringAsFixed(1)} dB',
                  style:
                      const TextStyle(fontSize: 10, color: Color(0xFFF8F8F2))),
            ),
          ),
          const SizedBox(height: 4),
          // Mute button
          SizedBox(
            width: 72,
            height: 28,
            child: ElevatedButton(
              onPressed: () => deviceProvider.toggleMute(channel),
              style: ElevatedButton.styleFrom(
                backgroundColor: isMuted
                    ? const Color(0xFFF92672)
                    : const Color(0xFFA6E22E),
                foregroundColor: const Color(0xFF272822),
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              ),
              child: const Text('Mute', style: TextStyle(fontSize: 10)),
            ),
          ),
          const SizedBox(height: 3),
          // Invert button
          SizedBox(
            width: 72,
            height: 28,
            child: ElevatedButton(
              onPressed: () => deviceProvider.togglePhase(channel),
              style: ElevatedButton.styleFrom(
                backgroundColor: isInverted
                    ? const Color(0xFFFD971F)
                    : const Color(0xFF75715E),
                foregroundColor: isInverted
                    ? const Color(0xFF272822)
                    : const Color(0xFFF8F8F2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              ),
              child: Text(isInverted ? 'Inverse' : 'Normal',
                  style: const TextStyle(fontSize: 10)),
            ),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, String channel) {
    final currentAlias = deviceProvider.getAlias(channel);
    final controller = TextEditingController(text: currentAlias);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rename $channel'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Alias',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              deviceProvider.setAlias(channel, value.trim());
            }
            Navigator.of(context).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              deviceProvider.resetAlias(channel);
              Navigator.of(context).pop();
            },
            child: const Text('Reset'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                deviceProvider.setAlias(channel, value);
              }
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDbInputDialog(
      BuildContext context, String channel, double currentDb) {
    final controller =
        TextEditingController(text: currentDb.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$channel Gain'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true, signed: true),
          decoration: const InputDecoration(
            labelText: 'dB (-60.0 to 12.0)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) {
            final db = double.tryParse(value);
            if (db != null && db >= -60.0 && db <= 12.0) {
              deviceProvider.setGain(channel, db);
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final db = double.tryParse(controller.text);
              if (db != null && db >= -60.0 && db <= 12.0) {
                deviceProvider.setGain(channel, db);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }
}

/// Vertical meter bar: green at bottom, yellow in middle, red at top.
/// [level] is a linear float from the device (0.0 = silence).
///
/// The DSP408 meter values have three distinct ranges:
///   - Muted/off:    ~0.00009 (-81 dB) — device noise floor when channel is off
///   - Noise floor:  ~0.4-0.5 (-6 to -8 dB) — analog noise with channel on, no audio
///   - Active signal: ~0.5-2.0+ (-6 dB to +6 dB) — actual audio
///
/// We treat levels below the noise floor threshold as silence and map
/// the useful signal range (noise floor to clipping) across the meter.
class MeterBar extends StatelessWidget {
  final double level;

  // Noise floor threshold: levels at or below this are treated as silence.
  // ~0.55 linear corresponds to ~-5.2 dB, just above the highest observed
  // noise floor value (~0.53 / -5.5 dB on Out 8).
  static const double _noiseFloor = 0.55;
  // Maximum expected level (clipping)
  static const double _maxLevel = 2.0;

  const MeterBar({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    // Levels at or below noise floor → empty meter
    // Above noise floor → map linearly from 0 to 1
    double fill;
    if (level <= _noiseFloor) {
      fill = 0.0;
    } else {
      fill = ((level - _noiseFloor) / (_maxLevel - _noiseFloor)).clamp(0.0, 1.0);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;

        return ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            children: [
              // Background
              Container(
                width: double.infinity,
                height: totalHeight,
                color: const Color(0xFF1E1F1C),
              ),
              // Full-height gradient, clipped from the bottom by fill level
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: totalHeight,
                child: ClipRect(
                  clipper: _BottomRevealClipper(fill),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Color(0xFFA6E22E),
                          Color(0xFFA6E22E),
                          Color(0xFFE6DB74),
                          Color(0xFFF92672),
                        ],
                        stops: [0.0, 0.5, 0.75, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Clips a widget to reveal only the bottom [fraction] of its height.
class _BottomRevealClipper extends CustomClipper<Rect> {
  final double fraction;

  _BottomRevealClipper(this.fraction);

  @override
  Rect getClip(Size size) {
    final top = size.height * (1.0 - fraction);
    return Rect.fromLTRB(0, top, size.width, size.height);
  }

  @override
  bool shouldReclip(_BottomRevealClipper oldClipper) =>
      oldClipper.fraction != fraction;
}
