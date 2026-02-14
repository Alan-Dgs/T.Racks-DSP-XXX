// Real-Time Analysis (RTA) — Microphone spectrum analyzer

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/rta_service.dart';
import '../../../services/rta_settings_provider.dart';

// ─── Log-frequency helpers ───

const double _minFreq = 20;
const double _maxFreq = 20000;
final double _logMin = math.log(_minFreq);
final double _logMax = math.log(_maxFreq);
final double _logRange = _logMax - _logMin;

double _freqToNorm(double freq) => (math.log(freq) - _logMin) / _logRange;

String _formatFreq(double freq) {
  if (freq >= 1000) {
    final k = freq / 1000;
    return k == k.truncateToDouble() ? '${k.toInt()}K' : '${k}K';
  }
  return freq == freq.truncateToDouble() ? '${freq.toInt()}' : '$freq';
}

class RtaTab extends StatefulWidget {
  const RtaTab({super.key});

  @override
  State<RtaTab> createState() => _RtaTabState();
}

class _RtaTabState extends State<RtaTab> {
  final RtaService _rtaService = RtaService();
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _rtaService.onUpdate = () {
      if (!_disposed) setState(() {});
    };
  }

  @override
  void dispose() {
    _disposed = true;
    _rtaService.release();
    super.dispose();
  }

  Future<void> _startCapture() async {
    final rtaSettings = context.read<RtaSettingsProvider>();
    if (!_isMobile) {
      rtaSettings.enumerateDevices();
    }
    final deviceId = rtaSettings.deviceId;

    final permitted = await _rtaService.requestPermission();
    if (!permitted || !mounted) return;

    try {
      await _rtaService.startCapture(deviceId: deviceId);
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start: $e')),
        );
      }
    }
  }

  void _stopCapture() {
    _rtaService.stopCapture();
    setState(() {});
  }

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final narrow = screenWidth < 500;

    return Column(
      children: [
        // Graph area
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (narrow) {
                return _RtaGraphWidget(
                  magnitudes: _rtaService.magnitudes,
                  peaks: _rtaService.peaks,
                  viewportWidth: constraints.maxWidth,
                  height: constraints.maxHeight,
                );
              }
              return CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _RtaPainter(
                  magnitudes: _rtaService.magnitudes,
                  peaks: _rtaService.peaks,
                  padLeft: 36.0,
                  padRight: 8,
                  padTop: 10.0,
                  padBottom: 28.0,
                  narrow: false,
                ),
              );
            },
          ),
        ),
        // Controls row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              GestureDetector(
                onTap: _rtaService.isRunning ? _stopCapture : _startCapture,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _rtaService.isRunning
                        ? const Color(0xFFF92672)
                        : const Color(0xFFA6E22E),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _rtaService.isRunning ? 'Stop' : 'Start',
                    style: const TextStyle(
                      color: Color(0xFF272822),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$rtaBandCount bands @ ${rtaSampleRate}Hz',
                style: const TextStyle(
                  color: Color(0xFF75715E),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (!_isMobile)
          const SizedBox(height: 10),
        if (_isMobile)
          SizedBox(height: 6 + MediaQuery.of(context).viewPadding.bottom),
      ],
    );
  }
}

// ─── Scrollable graph wrapper for mobile ───

class _RtaGraphWidget extends StatefulWidget {
  final List<double> magnitudes;
  final List<double> peaks;
  final double viewportWidth;
  final double height;

  const _RtaGraphWidget({
    required this.magnitudes,
    required this.peaks,
    required this.viewportWidth,
    required this.height,
  });

  @override
  State<_RtaGraphWidget> createState() => _RtaGraphWidgetState();
}

class _RtaGraphWidgetState extends State<_RtaGraphWidget> {
  double _scale = 3.5;
  double _scaleAtStart = 3.5;
  double _offset = 0.0;
  double _offsetAtStart = 0.0;

  double get _maxOffset =>
      math.max(0.0, widget.viewportWidth * _scale - widget.viewportWidth);

  void _clampOffset() {
    _offset = _offset.clamp(0.0, _maxOffset);
  }

  @override
  Widget build(BuildContext context) {
    final graphWidth = widget.viewportWidth * _scale;

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onScaleStart: (details) {
              _scaleAtStart = _scale;
              _offsetAtStart = _offset;
            },
            onScaleUpdate: (details) {
              if (!mounted) return;
              setState(() {
                final newScale =
                    (_scaleAtStart * details.scale).clamp(1.0, 6.0);
                final focalX = details.localFocalPoint.dx;

                final contentX = _offsetAtStart + focalX;
                final ratio =
                    contentX / (widget.viewportWidth * _scaleAtStart);

                _scale = newScale;
                _offset = ratio * widget.viewportWidth * _scale - focalX;

                if (details.pointerCount == 1) {
                  _offset = _offsetAtStart - (details.focalPointDelta.dx);
                }

                _clampOffset();
              });
            },
            child: ClipRect(
              child: CustomPaint(
                size: Size(widget.viewportWidth, widget.height),
                painter: _RtaPainter(
                  magnitudes: widget.magnitudes,
                  peaks: widget.peaks,
                  padLeft: 40.0,
                  padRight: 8,
                  padTop: 14.0,
                  padBottom: 36.0,
                  narrow: true,
                  contentWidth: graphWidth,
                  scrollOffset: _offset,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        if (_scale > 1.0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _ManualScrollIndicator(
              viewportWidth: widget.viewportWidth,
              contentWidth: graphWidth,
              offset: _offset,
            ),
          ),
      ],
    );
  }
}

// ─── Scroll indicator ───

class _ManualScrollIndicator extends StatelessWidget {
  final double viewportWidth;
  final double contentWidth;
  final double offset;

  const _ManualScrollIndicator({
    required this.viewportWidth,
    required this.contentWidth,
    required this.offset,
  });

  @override
  Widget build(BuildContext context) {
    final maxOffset = contentWidth - viewportWidth;
    if (maxOffset <= 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewFraction = viewportWidth / contentWidth;
        final thumbWidth =
            (constraints.maxWidth * viewFraction).clamp(24.0, constraints.maxWidth);
        final scrollFraction = offset / maxOffset;
        final thumbOffset = scrollFraction * (constraints.maxWidth - thumbWidth);

        return SizedBox(
          height: 6,
          child: Stack(
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
          ),
        );
      },
    );
  }
}

// ─── Custom painter ───

class _RtaPainter extends CustomPainter {
  final List<double> magnitudes;
  final List<double> peaks;
  final double padLeft;
  final double padRight;
  final double padTop;
  final double padBottom;
  final bool narrow;
  final double? contentWidth;
  final double scrollOffset;

  _RtaPainter({
    required this.magnitudes,
    required this.peaks,
    required this.padLeft,
    required this.padRight,
    required this.padTop,
    required this.padBottom,
    required this.narrow,
    this.contentWidth,
    this.scrollOffset = 0.0,
  });

  double _freqToX(double freq, double graphW) =>
      padLeft + _freqToNorm(freq) * graphW;

  @override
  void paint(Canvas canvas, Size size) {
    final virtualW = contentWidth ?? size.width;
    final graphW = virtualW - padLeft - padRight;
    final graphH = size.height - padTop - padBottom;

    if (contentWidth != null) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.translate(-scrollOffset, 0);
    }

    final axisLabelSize = narrow ? 12.0 : 9.0;

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

    final labelStyle = TextStyle(
      color: const Color(0xFF75715E),
      fontSize: axisLabelSize,
    );

    // Horizontal grid lines + dB labels
    const dbSteps = [10.0, 0.0, -20.0, -40.0, -60.0, -80.0, -100.0, -120.0, -140.0];
    for (final dB in dbSteps) {
      final y = padTop + graphH * (1.0 - (dB - rtaMinDb) / rtaDbRange);
      canvas.drawLine(
          Offset(padLeft, y), Offset(padLeft + graphW, y), gridPaint);

      if (contentWidth == null) {
        final tp = TextPainter(
          text: TextSpan(text: '${dB.toInt()}', style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(padLeft - tp.width - 4, y - tp.height / 2));
      }
    }

    // Vertical grid lines
    final thickGridPaint = Paint()
      ..color = const Color(0xFF75715E)
      ..strokeWidth = 1.5;

    final gridFreqs = <double>[
      for (double f = 20; f < 100; f += 10) f,
      for (double f = 100; f < 1000; f += 100) f,
      for (double f = 1000; f < 10000; f += 1000) f,
      10000, 20000,
    ];

    for (final freq in gridFreqs) {
      final x = _freqToX(freq, graphW);
      final thick = freq == 100 || freq == 1000 || freq == 10000;
      canvas.drawLine(Offset(x, padTop), Offset(x, padTop + graphH),
          thick ? thickGridPaint : gridPaint);
    }

    // Frequency labels
    final freqLabels = narrow
        ? [
            20.0, 31.5, 50.0, 80.0, 100.0, 160.0, 250.0, 500.0, 800.0,
            1000.0, 1600.0, 2500.0, 5000.0, 8000.0, 10000.0, 16000.0, 20000.0
          ]
        : [
            20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0,
            20000.0
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

    // Clip bars to graph area
    canvas.save();
    canvas.clipRect(graphRect);

    // Draw equal-width log-spaced bars
    final barPaint = Paint()..color = const Color(0xFFA6E22E).withAlpha(180);
    final peakPaint = Paint()
      ..color = const Color(0xFFF8F8F2)
      ..strokeWidth = 1.5;

    for (int b = 0; b < rtaBandCount && b < magnitudes.length; b++) {
      final xLeft = _freqToX(rtaBandEdges[b], graphW);
      final xRight = _freqToX(rtaBandEdges[b + 1], graphW);
      final gap = (xRight - xLeft) > 3 ? 0.5 : 0.0;

      final dB = magnitudes[b];
      final norm = (dB - rtaMinDb) / rtaDbRange;
      final barHeight = (norm * graphH).clamp(0.0, graphH);

      final barRect = Rect.fromLTRB(
        xLeft + gap,
        padTop + graphH - barHeight,
        xRight - gap,
        padTop + graphH,
      );
      canvas.drawRect(barRect, barPaint);

      if (b < peaks.length) {
        final peakDb = peaks[b];
        if (peakDb > rtaMinDb) {
          final peakNorm = (peakDb - rtaMinDb) / rtaDbRange;
          final peakY = padTop + graphH - (peakNorm * graphH).clamp(0.0, graphH);
          canvas.drawLine(
            Offset(xLeft + gap, peakY),
            Offset(xRight - gap, peakY),
            peakPaint,
          );
        }
      }
    }

    canvas.restore();

    if (contentWidth != null) {
      canvas.restore();

      final viewGraphH = size.height - padTop - padBottom;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, padLeft, size.height),
        Paint()..color = const Color(0xFF272822),
      );
      for (final dB in dbSteps) {
        final y = padTop + viewGraphH * (1.0 - (dB - rtaMinDb) / rtaDbRange);
        final tp = TextPainter(
          text: TextSpan(text: '${dB.toInt()}', style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(padLeft - tp.width - 4, y - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RtaPainter oldDelegate) => true;
}
