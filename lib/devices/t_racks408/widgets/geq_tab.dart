// Graphic EQ (GEQ)

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/rta_service.dart';
import '../../../services/rta_settings_provider.dart';
import '../providers/device_provider.dart';

// 31-band ISO 1/3-octave center frequencies
const List<double> _bandFrequencies = [
  20,
  25,
  31.5,
  40,
  50,
  63,
  80,
  100,
  125,
  160,
  200,
  250,
  315,
  400,
  500,
  630,
  800,
  1000,
  1250,
  1600,
  2000,
  2500,
  3150,
  4000,
  5000,
  6300,
  8000,
  10000,
  12500,
  16000,
  20000,
];

String _formatFreq(double freq) {
  if (freq >= 1000) {
    final k = freq / 1000;
    return k == k.truncateToDouble() ? '${k.toInt()}K' : '${k}K';
  }
  return freq == freq.truncateToDouble() ? '${freq.toInt()}' : '$freq';
}

class GeqTab extends StatefulWidget {
  final DeviceProvider deviceProvider;

  const GeqTab({super.key, required this.deviceProvider});

  @override
  State<GeqTab> createState() => _GeqTabState();
}

class _GeqTabState extends State<GeqTab> {
  DeviceProvider get deviceProvider => widget.deviceProvider;
  final ScrollController _scrollController = ScrollController();

  final Set<String> _selectedChannels = {'In A'};
  final bool _drawMode = false;
  int? _activeBandIndex;

  bool _rtaEnabled = false;
  RtaService? _rtaService;
  bool _disposed = false;

  void _toggleRta() async {
    if (_rtaEnabled) {
      _rtaService?.release();
      _rtaService = null;
      setState(() => _rtaEnabled = false);
    } else {
      final rtaSettings = context.read<RtaSettingsProvider>();
      if (!rtaSettings.isMobile) {
        rtaSettings.enumerateDevices();
      }
      final svc = RtaService();
      svc.onUpdate = () {
        if (!_disposed) setState(() {});
      };
      try {
        await svc.requestPermission();
        await svc.startCapture(deviceId: rtaSettings.deviceId);
        if (!mounted) {
          svc.release();
          return;
        }
        _rtaService = svc;
        setState(() => _rtaEnabled = true);
      } catch (e) {
        svc.release();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to start RTA: $e')));
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _rtaService?.release();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final narrow = screenWidth < 500;

    return ListenableBuilder(
      listenable: deviceProvider,
      builder: (context, _) {
        final selectedChannel = _selectedChannels.first;
        final bands = deviceProvider.getGeqBands(selectedChannel);
        final bypass = deviceProvider.getGeqBypass(selectedChannel);
        return Column(
          children: [
            // Graph area
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (narrow) {
                    // Mobile: graph is ~3.5x screen width (one decade per screen)
                    // log(30000/10) / log(10) ≈ 3.48 decades
                    final graphWidth = constraints.maxWidth * 3.5;
                    return Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: graphWidth,
                              height: double.infinity,
                              child: LayoutBuilder(
                                builder: (context, innerConstraints) {
                                  return _GeqGraph(
                                    bands: bands,
                                    drawMode: _drawMode,
                                    activeBandIndex: _activeBandIndex,
                                    rtaMagnitudes: _rtaEnabled
                                        ? _rtaService?.magnitudes
                                        : null,
                                    rtaPeaks: _rtaEnabled
                                        ? _rtaService?.peaks
                                        : null,
                                    width: graphWidth,
                                    height: innerConstraints.maxHeight,
                                    narrow: true,
                                    onBandChanged: (index, dB) {
                                      setState(() => _activeBandIndex = index);
                                      for (final ch in _selectedChannels) {
                                        deviceProvider.setGeqBand(
                                          ch,
                                          index,
                                          dB,
                                        );
                                      }
                                    },
                                    onBandReset: (index) {
                                      for (final ch in _selectedChannels) {
                                        deviceProvider.setGeqBand(ch, index, 0);
                                      }
                                    },
                                    onDragEnd: () {
                                      setState(() => _activeBandIndex = null);
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _ScrollIndicator(
                            controller: _scrollController,
                          ),
                        ),
                      ],
                    );
                  }
                  // Desktop: graph fills available space
                  return _GeqGraph(
                    bands: bands,
                    drawMode: _drawMode,
                    activeBandIndex: _activeBandIndex,
                    rtaMagnitudes: _rtaEnabled ? _rtaService?.magnitudes : null,
                    rtaPeaks: _rtaEnabled ? _rtaService?.peaks : null,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    narrow: false,
                    onBandChanged: (index, dB) {
                      setState(() => _activeBandIndex = index);
                      for (final ch in _selectedChannels) {
                        deviceProvider.setGeqBand(ch, index, dB);
                      }
                    },
                    onBandReset: (index) {
                      for (final ch in _selectedChannels) {
                        deviceProvider.setGeqBand(ch, index, 0);
                      }
                    },
                    onDragEnd: () {
                      setState(() => _activeBandIndex = null);
                    },
                  );
                },
              ),
            ),
            // Quick-curve buttons + draw toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  _ActionButton(
                    label: 'Flat',
                    onPressed: () {
                      for (final ch in _selectedChannels) {
                        deviceProvider.resetGeqBands(ch);
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  _ActionButton(
                    label: bypass ? 'Bypass On' : 'Bypass',
                    active: bypass,
                    onPressed: () {
                      for (final ch in _selectedChannels) {
                        deviceProvider.setGeqBypass(ch, !bypass);
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _toggleRta,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _rtaEnabled
                            ? const Color(0xFF66D9EF)
                            : const Color(0xFF3E3D32),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'RTA',
                        style: TextStyle(
                          color: _rtaEnabled
                              ? const Color(0xFF272822)
                              : const Color(0xFFF8F8F2),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Channel selector
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12).copyWith(
                bottom: narrow
                    ? 6 + MediaQuery.of(context).viewPadding.bottom
                    : 10,
              ),
              child: Row(
                children: deviceProvider.inputChannels.map((ch) {
                  final active = _selectedChannels.contains(ch);
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: GestureDetector(
                        onTap: () => setState(() {
                          if (_selectedChannels.contains(ch)) {
                            if (_selectedChannels.length > 1) {
                              _selectedChannels.remove(ch);
                            }
                          } else {
                            _selectedChannels.add(ch);
                          }
                        }),
                        child: Container(
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active
                                ? const Color(0xFFA6E22E)
                                : const Color(0xFF3E3D32),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            ch,
                            style: TextStyle(
                              color: active
                                  ? const Color(0xFF272822)
                                  : const Color(0xFFF8F8F2),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Action button ───

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool active;

  const _ActionButton({
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFF92672) : const Color(0xFF3E3D32),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFF8F8F2),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─── Scroll indicator (same as Gain tab) ───

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
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3E3D32),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
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

// ─── Log-frequency helpers ───

const double _minFreq = 10; // log-floor (graph visually represents ~0 Hz)
const double _maxFreq = 30000;
final double _logMin = math.log(_minFreq);
final double _logMax = math.log(_maxFreq);
final double _logRange = _logMax - _logMin;

/// Map a frequency to a normalized 0..1 position on the log axis.
double _freqToNorm(double freq) => (math.log(freq) - _logMin) / _logRange;

/// Map a normalized 0..1 position back to frequency.
double _normToFreq(double norm) => math.exp(_logMin + norm * _logRange);

// ─── Graph + band interaction ───

class _GeqGraph extends StatelessWidget {
  final List<double> bands;
  final bool drawMode;
  final int? activeBandIndex;
  final List<double>? rtaMagnitudes;
  final List<double>? rtaPeaks;
  final double width;
  final double height;
  final bool narrow;
  final void Function(int index, double dB) onBandChanged;
  final void Function(int index) onBandReset;
  final VoidCallback onDragEnd;

  const _GeqGraph({
    required this.bands,
    required this.drawMode,
    required this.activeBandIndex,
    this.rtaMagnitudes,
    this.rtaPeaks,
    required this.width,
    required this.height,
    required this.narrow,
    required this.onBandChanged,
    required this.onBandReset,
    required this.onDragEnd,
  });

  double get _padLeft => narrow ? 40.0 : 36.0;
  static const double _padRight = 8;
  double get _padTop => narrow ? 14.0 : 10.0;
  double get _padBottom => narrow ? 36.0 : 28.0;

  double get _graphWidth => width - _padLeft - _padRight;
  double get _graphHeight => height - _padTop - _padBottom;

  /// Convert pixel X to the nearest band index using log-frequency mapping.
  int _bandIndexFromX(double x) {
    final norm = ((x - _padLeft) / _graphWidth).clamp(0.0, 1.0);
    final freq = _normToFreq(norm);
    // Find nearest band by log-distance
    int best = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < 31; i++) {
      final d = (math.log(_bandFrequencies[i]) - math.log(freq)).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  double _dBFromY(double y) {
    final local = y - _padTop;
    final ratio = 1.0 - (local / _graphHeight);
    return (ratio * 24 - 12).clamp(-12.0, 12.0);
  }

  void _handleDrag(Offset position) {
    final index = _bandIndexFromX(position.dx);
    final dB = _dBFromY(position.dy);
    onBandChanged(index, dB);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          final index = _bandIndexFromX(event.position.dx);
          final current = bands[index.clamp(0, 30)];
          final delta = -event.scrollDelta.dy / 50;
          onBandChanged(index, (current + delta).clamp(-12.0, 12.0));
        }
      },
      child: GestureDetector(
        onPanStart: drawMode ? (d) => _handleDrag(d.localPosition) : null,
        onPanUpdate: drawMode ? (d) => _handleDrag(d.localPosition) : null,
        onPanEnd: drawMode ? (_) => onDragEnd() : null,
        onVerticalDragStart: !drawMode
            ? (d) => _handleDrag(d.localPosition)
            : null,
        onVerticalDragUpdate: !drawMode
            ? (d) => _handleDrag(d.localPosition)
            : null,
        onVerticalDragEnd: !drawMode ? (_) => onDragEnd() : null,
        onDoubleTapDown: (d) {
          final index = _bandIndexFromX(d.localPosition.dx);
          onBandReset(index);
        },
        child: CustomPaint(
          size: Size(width, height),
          painter: _GeqPainter(
            bands: bands,
            activeBandIndex: activeBandIndex,
            rtaMagnitudes: rtaMagnitudes,
            rtaPeaks: rtaPeaks,
            padLeft: _padLeft,
            padRight: _padRight,
            padTop: _padTop,
            padBottom: _padBottom,
            narrow: narrow,
          ),
        ),
      ),
    );
  }
}

// ─── Custom painter ───

class _GeqPainter extends CustomPainter {
  final List<double> bands;
  final int? activeBandIndex;
  final List<double>? rtaMagnitudes;
  final List<double>? rtaPeaks;
  final double padLeft;
  final double padRight;
  final double padTop;
  final double padBottom;
  final bool narrow;

  _GeqPainter({
    required this.bands,
    this.activeBandIndex,
    this.rtaMagnitudes,
    this.rtaPeaks,
    required this.padLeft,
    required this.padRight,
    required this.padTop,
    required this.padBottom,
    required this.narrow,
  });

  /// Map frequency to pixel X using log scale.
  double _freqToX(double freq, double graphW) =>
      padLeft + _freqToNorm(freq) * graphW;

  @override
  void paint(Canvas canvas, Size size) {
    final graphW = size.width - padLeft - padRight;
    final graphH = size.height - padTop - padBottom;

    // Font sizes scaled for mobile
    final axisLabelSize = narrow ? 12.0 : 9.0;
    final freqCircleMaxSize = narrow ? 12.0 : 8.0;
    final freqCircleMinSize = narrow ? 8.0 : 5.0;
    final dbLabelSize = narrow ? 11.0 : 7.0;
    final bubbleFontSize = narrow ? 14.0 : 11.0;

    // Background
    final graphRect = Rect.fromLTWH(padLeft, padTop, graphW, graphH);
    canvas.drawRect(graphRect, Paint()..color = const Color(0xFF272822));
    canvas.drawRect(
      graphRect,
      Paint()
        ..color = const Color(0xFF75715E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    final gridPaint = Paint()
      ..color = const Color(0xFF75715E)
      ..strokeWidth = 0.5;

    final zeroPaint = Paint()
      ..color = const Color(0xFFF92672)
      ..strokeWidth = 1.0;

    // Horizontal grid + labels
    const dBSteps = [-12.0, -6.0, 0.0, 6.0, 12.0];
    final labelStyle = TextStyle(
      color: const Color(0xFF75715E),
      fontSize: axisLabelSize,
    );

    for (final dB in dBSteps) {
      final y = padTop + graphH * (1.0 - (dB + 12) / 24);
      final paint = dB == 0 ? zeroPaint : gridPaint;
      canvas.drawLine(Offset(padLeft, y), Offset(padLeft + graphW, y), paint);

      final tp = TextPainter(
        text: TextSpan(
          text: '${dB > 0 ? '+' : ''}${dB.toInt()}',
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(padLeft - tp.width - 4, y - tp.height / 2));
    }

    // Vertical grid lines — logarithmically positioned
    final thickGridPaint = Paint()
      ..color = const Color(0xFF75715E)
      ..strokeWidth = 1.5;

    final gridFreqs = <double>[
      for (double f = 20; f < 100; f += 10) f,
      for (double f = 100; f < 1000; f += 100) f,
      for (double f = 1000; f < 10000; f += 1000) f,
      10000,
      20000,
    ];

    for (final freq in gridFreqs) {
      final x = _freqToX(freq, graphW);
      final thick =
          freq == 100 || freq == 1000 || freq == 10000 || freq == 30000;
      canvas.drawLine(
        Offset(x, padTop),
        Offset(x, padTop + graphH),
        thick ? thickGridPaint : gridPaint,
      );
    }

    // Frequency labels along bottom at key positions
    // On mobile, show more labels since we have the space
    final freqLabels = narrow
        ? [
            20.0,
            31.5,
            50.0,
            80.0,
            100.0,
            160.0,
            250.0,
            500.0,
            800.0,
            1000.0,
            1600.0,
            2500.0,
            5000.0,
            8000.0,
            10000.0,
            16000.0,
            20000.0,
          ]
        : [
            20.0,
            50.0,
            100.0,
            200.0,
            500.0,
            1000.0,
            2000.0,
            5000.0,
            10000.0,
            20000.0,
          ];
    for (final freq in freqLabels) {
      final label = _formatFreq(freq);
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = _freqToX(freq, graphW) - tp.width / 2;
      tp.paint(canvas, Offset(x, padTop + graphH + 4));
    }

    // ── RTA overlay bars (drawn behind EQ controls) ──
    if (rtaMagnitudes != null && rtaMagnitudes!.length == rtaBandCount) {
      final rtaBarPaint = Paint()..color = const Color(0x4F66D9EF); // cyan ~31%
      final rtaPeakPaint = Paint()
        ..color =
            const Color(0x78FFFFFF) // white ~47%
        ..strokeWidth = 1.0;

      for (int b = 0; b < rtaBandCount; b++) {
        final loFreq = rtaBandEdges[b];
        final hiFreq = rtaBandEdges[b + 1];

        // Map RTA band edges to pixel X via GEQ's log axis
        final xLeft = _freqToX(loFreq.clamp(_minFreq, _maxFreq), graphW);
        final xRight = _freqToX(hiFreq.clamp(_minFreq, _maxFreq), graphW);
        if (xRight <= padLeft || xLeft >= padLeft + graphW) continue;

        // Squash full RTA range (-140..+10 dB) into the graph height
        final norm = (rtaMagnitudes![b] - rtaMinDb) / rtaDbRange;
        final barY = padTop + graphH * (1.0 - norm.clamp(0.0, 1.0));

        final clampedLeft = xLeft.clamp(padLeft, padLeft + graphW);
        final clampedRight = xRight.clamp(padLeft, padLeft + graphW);

        canvas.drawRect(
          Rect.fromLTRB(clampedLeft, barY, clampedRight, padTop + graphH),
          rtaBarPaint,
        );

        // Peak hold marker
        if (rtaPeaks != null && rtaPeaks!.length == rtaBandCount) {
          final peakNorm = (rtaPeaks![b] - rtaMinDb) / rtaDbRange;
          final peakY = padTop + graphH * (1.0 - peakNorm.clamp(0.0, 1.0));
          canvas.drawLine(
            Offset(clampedLeft, peakY),
            Offset(clampedRight, peakY),
            rtaPeakPaint,
          );
        }
      }
    }

    // Band bars + handles — positioned by log frequency
    final zeroY = padTop + graphH * 0.5; // 0 dB line

    for (int i = 0; i < 31; i++) {
      final dB = bands[i];
      final cx = _freqToX(_bandFrequencies[i], graphW);
      final bandY = padTop + graphH * (1.0 - (dB + 12) / 24);

      // Compute bar half-width from log midpoints to neighbors
      final logCenter = math.log(_bandFrequencies[i]);
      final logLeft = i > 0
          ? (logCenter + math.log(_bandFrequencies[i - 1])) / 2
          : logCenter - (math.log(_bandFrequencies[i + 1]) - logCenter) / 2;
      final logRight = i < 30
          ? (logCenter + math.log(_bandFrequencies[i + 1])) / 2
          : logCenter + (logCenter - math.log(_bandFrequencies[i - 1])) / 2;
      final xLeft = padLeft + (logLeft - _logMin) / _logRange * graphW;
      final xRight = padLeft + (logRight - _logMin) / _logRange * graphW;
      final halfW = (xRight - xLeft) / 2;

      // Bar from 0dB to value
      final barColor = dB >= 0
          ? const Color(0xFFA6E22E)
          : const Color(0xFFF92672);
      final barTop = dB >= 0 ? bandY : zeroY;
      final barBottom = dB >= 0 ? zeroY : bandY;
      final barRect = Rect.fromLTRB(
        cx - halfW * 0.7,
        barTop,
        cx + halfW * 0.7,
        barBottom,
      );
      canvas.drawRect(barRect, Paint()..color = barColor.withAlpha(180));

      // Handle circle
      final radius = halfW * 0.4;
      canvas.drawCircle(Offset(cx, bandY), radius, Paint()..color = barColor);

      // Frequency label inside the circle
      final freqLabel = _formatFreq(_bandFrequencies[i]);
      final freqTp = TextPainter(
        text: TextSpan(
          text: freqLabel,
          style: TextStyle(
            color: dB >= 0 ? const Color(0xFF272822) : const Color(0xFFF8F8F2),
            fontSize: (radius * 0.9).clamp(
              freqCircleMinSize,
              freqCircleMaxSize,
            ),
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      freqTp.paint(
        canvas,
        Offset(cx - freqTp.width / 2, bandY - freqTp.height / 2),
      );

      // dB value above the handle
      if (dB != 0.0) {
        final dbLabel = '${dB >= 0 ? '+' : ''}${dB.toStringAsFixed(1)}';
        final dbTp = TextPainter(
          text: TextSpan(
            text: dbLabel,
            style: TextStyle(
              color: const Color(0xFFF8F8F2),
              fontSize: dbLabelSize,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        // Position above handle for boost, below for cut
        final dbY = dB >= 0
            ? bandY - radius - dbTp.height - 1
            : bandY + radius + 1;
        final dbX = (cx - dbTp.width / 2).clamp(
          padLeft,
          padLeft + graphW - dbTp.width,
        );
        if (dbY >= padTop - 2 && dbY + dbTp.height <= padTop + graphH + 2) {
          dbTp.paint(canvas, Offset(dbX, dbY));
        }
      }
    }

    // dB popup bubble for active band
    if (activeBandIndex != null &&
        activeBandIndex! >= 0 &&
        activeBandIndex! < 31) {
      final i = activeBandIndex!;
      final dB = bands[i];
      final cx = _freqToX(_bandFrequencies[i], graphW);
      final bandY = padTop + graphH * (1.0 - (dB + 12) / 24);

      final label = '${dB >= 0 ? '+' : ''}${dB.toStringAsFixed(1)} dB';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: const Color(0xFFF8F8F2),
            fontSize: bubbleFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final bubblePadH = narrow ? 10.0 : 8.0;
      final bubblePadV = narrow ? 6.0 : 4.0;
      final bubbleW = tp.width + bubblePadH * 2;
      final bubbleH = tp.height + bubblePadV * 2;

      // Position above the handle; flip below if too close to top
      final above = bandY - bubbleH - 8;
      final bubbleY = above >= padTop ? above : bandY + 12;
      // Center horizontally, clamp within graph
      final bubbleX = (cx - bubbleW / 2).clamp(
        padLeft,
        padLeft + graphW - bubbleW,
      );

      final bubbleRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(bubbleX, bubbleY, bubbleW, bubbleH),
        const Radius.circular(4),
      );
      canvas.drawRRect(bubbleRect, Paint()..color = const Color(0xDD3E3D32));
      tp.paint(canvas, Offset(bubbleX + bubblePadH, bubbleY + bubblePadV));
    }
  }

  @override
  bool shouldRepaint(covariant _GeqPainter oldDelegate) => true;
}
