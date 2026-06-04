import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../providers/device_provider.dart';

class GainTab extends StatefulWidget {
  final DeviceProvider deviceProvider;

  const GainTab({super.key, required this.deviceProvider});

  @override
  State<GainTab> createState() => _GainTabState();
}

class _GainTabState extends State<GainTab> {
  final ScrollController _scrollController = ScrollController();

  DeviceProvider get deviceProvider => widget.deviceProvider;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final narrow = screenWidth < 500;
    final pad = narrow ? 4.0 : 12.0;
    final gap = narrow ? 8.0 : 24.0;
    final headerSize = narrow ? 14.0 : 18.0;
    final inputs = deviceProvider.inputChannels;
    final outputs = deviceProvider.outputChannels;

    if (narrow) {
      // Mobile: 4 faders visible at once, scroll for the rest
      // Faders are 5/6 height with bottom padding for home bar
      final faderWidth = (screenWidth - pad * 2 - gap) / 4;
      return Padding(
        padding: EdgeInsets.only(
          left: pad,
          right: pad,
          top: pad,
          bottom: pad + MediaQuery.of(context).viewPadding.bottom,
        ),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: faderWidth * (inputs.length + outputs.length) + gap,
                  height: double.infinity,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Input channels
                      ...inputs.map(
                        (ch) => SizedBox(
                          width: faderWidth,
                          child: _buildVerticalFader(context, ch, narrow),
                        ),
                      ),
                      SizedBox(width: gap),
                      // Output channels
                      ...outputs.map(
                        (ch) => SizedBox(
                          width: faderWidth,
                          child: _buildVerticalFader(context, ch, narrow),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Custom scroll indicator — sits physically below the faders
            _ScrollIndicator(controller: _scrollController),
          ],
        ),
      );
    }

    // Desktop: all faders in one row
    return Padding(
      padding: EdgeInsets.all(pad),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Input channels
          Expanded(
            child: Column(
              children: [
                Text(
                  'Inputs',
                  style: TextStyle(
                    fontSize: headerSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: inputs
                        .map((ch) => _buildVerticalFader(context, ch, narrow))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: gap),
          // Output channels
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Text(
                  'Outputs',
                  style: TextStyle(
                    fontSize: headerSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: outputs
                        .map((ch) => _buildVerticalFader(context, ch, narrow))
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

  Widget _buildVerticalFader(
    BuildContext context,
    String channel,
    bool narrow,
  ) {
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

    // On mobile, wrap in a Column (no Expanded since parent has fixed width).
    // On desktop, wrap in Expanded to fill available space.
    Widget faderContent = Column(
      children: [
        // Vertical slider overlaid on meter bar — 5/6 height on mobile
        Expanded(
          flex: 1,
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
                      final delta = signal.scrollDelta.dy > 0
                          ? -stepSize
                          : stepSize;
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
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: narrow ? 8 : 6,
                          ),
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
        SizedBox(height: narrow ? 2 : 4),
        // Channel label (clickable to rename)
        GestureDetector(
          onTap: () => _showRenameDialog(context, channel),
          child: Text(
            deviceProvider.getAlias(channel),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: narrow ? 12 : 11,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 4),
        // Clickable dB display
        GestureDetector(
          onTap: () => _showDbInputDialog(context, channel, gain),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: narrow ? 4 : 6,
              vertical: narrow ? 4 : 3,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF75715E)),
              borderRadius: BorderRadius.circular(4),
              color: const Color(0xFF3E3D32),
            ),
            child: Text(
              '${gain.toStringAsFixed(1)} dB',
              style: TextStyle(
                fontSize: narrow ? 11 : 10,
                color: const Color(0xFFF8F8F2),
              ),
            ),
          ),
        ),
        SizedBox(height: narrow ? 6 : 4),
        // Mute button — full width on mobile
        SizedBox(
          width: narrow ? double.infinity : 72,
          height: narrow ? 32 : 28,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: narrow ? 4 : 0),
            child: ElevatedButton(
              onPressed: () => deviceProvider.toggleMute(channel),
              style: ElevatedButton.styleFrom(
                backgroundColor: isMuted
                    ? const Color(0xFFF92672)
                    : const Color(0xFFA6E22E),
                foregroundColor: const Color(0xFF272822),
                padding: EdgeInsets.symmetric(
                  horizontal: narrow ? 2 : 4,
                  vertical: 2,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Mute', style: TextStyle(fontSize: narrow ? 12 : 10)),
            ),
          ),
        ),
        SizedBox(height: narrow ? 4 : 3),
        // Invert button — full width on mobile, same size as Mute
        SizedBox(
          width: narrow ? double.infinity : 72,
          height: narrow ? 32 : 28,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: narrow ? 4 : 0),
            child: ElevatedButton(
              onPressed: () => deviceProvider.togglePhase(channel),
              style: ElevatedButton.styleFrom(
                backgroundColor: isInverted
                    ? const Color(0xFFFD971F)
                    : const Color(0xFF75715E),
                foregroundColor: isInverted
                    ? const Color(0xFF272822)
                    : const Color(0xFFF8F8F2),
                padding: EdgeInsets.symmetric(
                  horizontal: narrow ? 2 : 4,
                  vertical: 2,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                isInverted ? 'Inverse' : 'Normal',
                style: TextStyle(fontSize: narrow ? 12 : 10),
              ),
            ),
          ),
        ),
      ],
    );

    if (narrow) return faderContent;
    return Expanded(child: faderContent);
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
          inputFormatters: [LengthLimitingTextInputFormatter(8)],
          decoration: const InputDecoration(
            labelText: 'Name (8 chars max)',
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
    BuildContext context,
    String channel,
    double currentDb,
  ) {
    final controller = TextEditingController(
      text: currentDb.toStringAsFixed(1),
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$channel Gain'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
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
      fill = ((level - _noiseFloor) / (_maxLevel - _noiseFloor)).clamp(
        0.0,
        1.0,
      );
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

/// Custom scroll position indicator that sits physically below content.
class _ScrollIndicator extends StatelessWidget {
  final ScrollController controller;

  const _ScrollIndicator({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              try {
                if (!controller.hasClients ||
                    controller.positions.length != 1) {
                  return const SizedBox.shrink();
                }
                final position = controller.position;
                if (!position.hasContentDimensions ||
                    position.maxScrollExtent <= 0) {
                  return const SizedBox.shrink();
                }
                final viewFraction =
                    position.viewportDimension /
                    (position.maxScrollExtent + position.viewportDimension);
                final thumbWidth = (constraints.maxWidth * viewFraction).clamp(
                  24.0,
                  constraints.maxWidth,
                );
                final scrollFraction =
                    controller.offset / position.maxScrollExtent;
                final thumbOffset =
                    scrollFraction * (constraints.maxWidth - thumbWidth);

                return Stack(
                  children: [
                    // Track
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3E3D32),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    // Thumb
                    Positioned(
                      left: thumbOffset,
                      child: Container(
                        width: thumbWidth,
                        height: 6,
                        decoration: BoxDecoration(
                          color: const Color(0xFF75715E),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                );
              } catch (_) {
                return const SizedBox.shrink();
              }
            },
          );
        },
      ),
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
