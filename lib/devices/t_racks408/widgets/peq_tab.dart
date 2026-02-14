// Parametric EQ (PEQ)

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../providers/device_provider.dart';
import '../services/protocol_service.dart';

// Monokai band colors for PEQ curves (one per band)
const _bandColors = [
  Color(0xFFF92672), // Pink
  Color(0xFFA6E22E), // Green
  Color(0xFF66D9EF), // Cyan
  Color(0xFFFD971F), // Orange
  Color(0xFFAE81FF), // Purple
  Color(0xFFE6DB74), // Yellow
  Color(0xFFFF6188), // Rose
  Color(0xFF4EC9B0), // Teal
  Color(0xFFFC9867), // Peach (9th band for outputs)
];

// Log-frequency helpers
const double _minFreq = 10;
const double _maxFreq = 30000;
final double _logMin = math.log(_minFreq);
final double _logMax = math.log(_maxFreq);
final double _logRange = _logMax - _logMin;

double _freqToNorm(double freq) =>
    (math.log(freq) - _logMin) / _logRange;

String _formatFreq(double freq) {
  if (freq >= 1000) {
    final k = freq / 1000;
    return k == k.truncateToDouble() ? '${k.toInt()}K' : '${k.toStringAsFixed(1)}K';
  }
  return freq == freq.truncateToDouble() ? '${freq.toInt()}' : freq.toStringAsFixed(1);
}

// Default PEQ frequencies (Hz) per band for inputs (8 bands) and outputs (9 bands)
const _inputDefaultFreqHz = [50.8, 101.5, 203.1, 500.0, 1000.0, 2000.0, 5040.0, 10080.0];
const _outputDefaultFreqHz = [40.3, 84.4, 176.8, 370.3, 757.9, 1590.0, 3320.0, 6810.0, 14250.0];

class PeqTab extends StatefulWidget {
  final DeviceProvider deviceProvider;

  const PeqTab({super.key, required this.deviceProvider});

  @override
  State<PeqTab> createState() => _PeqTabState();
}

class _PeqTabState extends State<PeqTab> with SingleTickerProviderStateMixin {
  DeviceProvider get deviceProvider => widget.deviceProvider;
  final _proto = ProtocolService();

  // I/O tab: 0=Inputs, 1=Outputs
  int _ioTab = 0;
  String _selectedChannel = 'In A';
  int _selectedBand = 0;

  late TabController _ioTabController;

  @override
  void initState() {
    super.initState();
    // Clamp in case of hot-reload from old 3-tab layout
    _ioTab = _ioTab.clamp(0, 1);
    _ioTabController = TabController(length: 2, initialIndex: _ioTab, vsync: this);
    _ioTabController.addListener(() {
      if (!_ioTabController.indexIsChanging) {
        setState(() {
          _ioTab = _ioTabController.index;
          if (_ioTab == 0 && !_selectedChannel.startsWith('In')) {
            _selectedChannel = 'In A';
            _selectedBand = 0;
          } else if (_ioTab == 1 && !_selectedChannel.startsWith('Out')) {
            _selectedChannel = 'Out 1';
            _selectedBand = 0;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _ioTabController.dispose();
    super.dispose();
  }

  List<String> get _channels {
    if (_ioTab == 0) return ['In A', 'In B', 'In C', 'In D'];
    return ['Out 1', 'Out 2', 'Out 3', 'Out 4', 'Out 5', 'Out 6', 'Out 7', 'Out 8'];
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final narrow = screenWidth < 500;

    return ListenableBuilder(
      listenable: deviceProvider,
      builder: (context, _) {
        final bands = deviceProvider.getPeqBands(_selectedChannel);
        final bandCount = bands.length;
        if (_selectedBand >= bandCount) _selectedBand = 0;

        return Column(
          children: [
            // Channel gain slider (horizontal, full width)
            _buildChannelGainSlider(narrow),

            // Graph area
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final graphHeight = math.max(constraints.maxHeight, 80.0);
                  return SizedBox(
                    height: graphHeight,
                    child: _PeqGraph(
                      bands: bands,
                      selectedBand: _selectedBand,
                      proto: _proto,
                      width: constraints.maxWidth,
                      height: graphHeight,
                      narrow: narrow,
                      hiPass: deviceProvider.getHiPass(_selectedChannel),
                      loPass: deviceProvider.getLoPass(_selectedChannel),
                      onBandSelected: (index) {
                        setState(() => _selectedBand = index);
                      },
                      onBandGainChanged: (index, dB) {
                        setState(() => _selectedBand = index);
                        deviceProvider.setPeqBand(_selectedChannel, index, gainDb: dB);
                      },
                    ),
                  );
                },
              ),
            ),

            // Band selector + sliders side by side
            _buildBandAndSliders(bands, narrow),

            // Filter controls (HPF/LPF) integrated per channel
            _buildFilterControls(narrow),

            // I/O tab bar + Channel selector
            _buildIOSelector(narrow),
          ],
        );
      },
    );
  }

  Widget _buildChannelGainSlider(bool narrow) {
    final isInput = _selectedChannel.startsWith('In');
    final gain = isInput
        ? deviceProvider.getInputGain(_selectedChannel)
        : deviceProvider.getOutputGain(_selectedChannel);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '${gain >= 0 ? "+" : ""}${gain.toStringAsFixed(1)} dB',
              style: const TextStyle(fontSize: 11, color: Color(0xFFF8F8F2)),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                activeTrackColor: const Color(0xFFA6E22E),
                inactiveTrackColor: const Color(0xFF3E3D32),
                thumbColor: const Color(0xFFA6E22E),
                overlayColor: const Color(0x29A6E22E),
              ),
              child: Slider(
                value: gain,
                min: -60.0,
                max: 12.0,
                onChanged: (v) => deviceProvider.setGain(_selectedChannel, v),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Band selector buttons (left) + Freq/Q/Gain sliders (right)
  Widget _buildBandAndSliders(List<PeqBand> bands, bool narrow) {
    final band = bands[_selectedBand];
    final freqHz = _proto.peqFreqToHz(band.freqRaw);
    final q = _proto.peqRawToQ(band.qRaw);
    final bandCount = bands.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: band selector buttons (compact column of 2 rows)
          SizedBox(
            width: narrow ? 120 : 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Band buttons in rows of 5
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: List.generate(bandCount, (i) {
                    final active = i == _selectedBand;
                    final b = bands[i];
                    final color = _bandColors[i % _bandColors.length];
                    return GestureDetector(
                      onTap: () => setState(() => _selectedBand = i),
                      child: Container(
                        width: narrow ? 22 : 26,
                        height: narrow ? 22 : 26,
                        alignment: Alignment.center,
                        decoration: ShapeDecoration(
                          color: active ? color : const Color(0xFF272822),
                          shape: BeveledRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                            side: BorderSide(
                              color: b.bypass ? const Color(0xFFF92672) : color,
                              width: b.bypass ? 2 : 1.5,
                            ),
                          ),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: const Color(0xFFF8F8F2),
                            fontWeight: FontWeight.w700,
                            fontSize: narrow ? 10 : 12,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 6),
                // Bypass + Type below band buttons
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        deviceProvider.setPeqBand(_selectedChannel, _selectedBand, bypass: !band.bypass);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: band.bypass
                              ? const Color(0xFFF92672)
                              : const Color(0xFF3E3D32),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Bypass',
                          style: TextStyle(
                            color: band.bypass
                                ? const Color(0xFFF8F8F2)
                                : const Color(0xFF75715E),
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Type dropdown
                Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3E3D32),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: band.type,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF3E3D32),
                      style: const TextStyle(fontSize: 10, color: Color(0xFFF8F8F2)),
                      items: List.generate(ProtocolService.peqTypeNames.length, (i) {
                        return DropdownMenuItem(
                          value: i,
                          child: Text(ProtocolService.peqTypeNames[i]),
                        );
                      }),
                      onChanged: (v) {
                        if (v != null) {
                          deviceProvider.setPeqBand(_selectedChannel, _selectedBand, type: v);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Right: Freq, Q, Gain sliders
          Expanded(
            child: Column(
              children: [
                _labeledSlider(
                  label: 'Freq',
                  value: band.freqRaw.toDouble(),
                  min: 0,
                  max: 1000,
                  displayText: _formatFreq(freqHz),
                  color: const Color(0xFF66D9EF),
                  onChanged: (v) {
                    deviceProvider.setPeqBand(_selectedChannel, _selectedBand, freqRaw: v.round());
                  },
                  onDoubleTap: () {
                    final isInput = _selectedChannel.startsWith('In');
                    final defaults = isInput ? _inputDefaultFreqHz : _outputDefaultFreqHz;
                    final defaultHz = defaults[_selectedBand % defaults.length];
                    deviceProvider.setPeqBand(_selectedChannel, _selectedBand,
                        freqRaw: _proto.peqHzToFreq(defaultHz));
                  },
                ),
                _labeledSlider(
                  label: 'Q',
                  value: band.qRaw.toDouble(),
                  min: 0,
                  max: 255,
                  displayText: q.toStringAsFixed(2),
                  color: const Color(0xFFFD971F),
                  onChanged: (v) {
                    deviceProvider.setPeqBand(_selectedChannel, _selectedBand, qRaw: v.round());
                  },
                  onDoubleTap: () {
                    deviceProvider.setPeqBand(_selectedChannel, _selectedBand,
                        qRaw: _proto.peqQToRaw(3.0));
                  },
                ),
                _labeledSlider(
                  label: 'Gain',
                  value: band.gainDb,
                  min: -12.0,
                  max: 12.0,
                  displayText: '${band.gainDb >= 0 ? "+" : ""}${band.gainDb.toStringAsFixed(1)} dB',
                  color: const Color(0xFFA6E22E),
                  onChanged: (v) {
                    deviceProvider.setPeqBand(_selectedChannel, _selectedBand, gainDb: v);
                  },
                  onDoubleTap: () {
                    deviceProvider.setPeqBand(_selectedChannel, _selectedBand, gainDb: 0.0);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _labeledSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayText,
    required Color color,
    required ValueChanged<double> onChanged,
    VoidCallback? onDoubleTap,
  }) {
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF75715E))),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  activeTrackColor: color,
                  inactiveTrackColor: const Color(0xFF3E3D32),
                  thumbColor: color,
                  overlayColor: color.withAlpha(40),
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ),
            SizedBox(
              width: 70,
              child: Text(
                displayText,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11, color: Color(0xFFF8F8F2)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterControls(bool narrow) {
    final hiPass = deviceProvider.getHiPass(_selectedChannel);
    final loPass = deviceProvider.getLoPass(_selectedChannel);
    final hiFreqHz = _proto.peqFreqToHz(hiPass.freqRaw);
    final loFreqHz = _proto.peqFreqToHz(loPass.freqRaw);
    final slopeDropdownWidth = narrow ? 80.0 : 90.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Column(
        children: [
          // Hi Pass row: [Toggle] [Slope] [Freq slider]
          Row(
            children: [
              GestureDetector(
                onTap: () => deviceProvider.setHiPass(_selectedChannel, enabled: !hiPass.enabled),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: hiPass.enabled ? const Color(0xFFA6E22E) : const Color(0xFF3E3D32),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'HPF',
                    style: TextStyle(
                      color: hiPass.enabled ? const Color(0xFF272822) : const Color(0xFF75715E),
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                height: 28,
                width: slopeDropdownWidth,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF3E3D32),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: hiPass.slope,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF3E3D32),
                    style: const TextStyle(fontSize: 10, color: Color(0xFFF8F8F2)),
                    items: List.generate(ProtocolService.crossoverSlopeNames.length, (i) {
                      return DropdownMenuItem(
                        value: i,
                        child: Text(ProtocolService.crossoverSlopeNames[i]),
                      );
                    }),
                    onChanged: (v) {
                      if (v != null) {
                        deviceProvider.setHiPass(_selectedChannel, slope: v);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _labeledSlider(
                  label: '',
                  value: hiPass.freqRaw.toDouble(),
                  min: 0,
                  max: 1000,
                  displayText: _formatFreq(hiFreqHz),
                  color: const Color(0xFFF92672),
                  onChanged: (v) {
                    deviceProvider.setHiPass(_selectedChannel, freqRaw: v.round());
                  },
                  onDoubleTap: () {
                    deviceProvider.setHiPass(_selectedChannel, freqRaw: 0);
                  },
                ),
              ),
            ],
          ),
          // Lo Pass row: [Toggle] [Slope] [Freq slider]
          Row(
            children: [
              GestureDetector(
                onTap: () => deviceProvider.setLoPass(_selectedChannel, enabled: !loPass.enabled),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: loPass.enabled ? const Color(0xFFA6E22E) : const Color(0xFF3E3D32),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'LPF',
                    style: TextStyle(
                      color: loPass.enabled ? const Color(0xFF272822) : const Color(0xFF75715E),
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                height: 28,
                width: slopeDropdownWidth,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF3E3D32),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: loPass.slope,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF3E3D32),
                    style: const TextStyle(fontSize: 10, color: Color(0xFFF8F8F2)),
                    items: List.generate(ProtocolService.crossoverSlopeNames.length, (i) {
                      return DropdownMenuItem(
                        value: i,
                        child: Text(ProtocolService.crossoverSlopeNames[i]),
                      );
                    }),
                    onChanged: (v) {
                      if (v != null) {
                        deviceProvider.setLoPass(_selectedChannel, slope: v);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _labeledSlider(
                  label: '',
                  value: loPass.freqRaw.toDouble(),
                  min: 0,
                  max: 1000,
                  displayText: _formatFreq(loFreqHz),
                  color: const Color(0xFF66D9EF),
                  onChanged: (v) {
                    deviceProvider.setLoPass(_selectedChannel, freqRaw: v.round());
                  },
                  onDoubleTap: () {
                    deviceProvider.setLoPass(_selectedChannel, freqRaw: 1000);
                  },
                ),
              ),
            ],
          ),
          // Filters bypass button — spans band selector width
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () {
                  final anyEnabled = hiPass.enabled || loPass.enabled;
                  if (anyEnabled) {
                    deviceProvider.setHiPass(_selectedChannel, enabled: false);
                    deviceProvider.setLoPass(_selectedChannel, enabled: false);
                  } else {
                    deviceProvider.setHiPass(_selectedChannel, enabled: true);
                    deviceProvider.setLoPass(_selectedChannel, enabled: true);
                  }
                },
                child: SizedBox(
                  width: narrow ? 120.0 : 150.0,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: (hiPass.enabled || loPass.enabled)
                          ? const Color(0xFF3E3D32)
                          : const Color(0xFFF92672),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Filters Bypass',
                      style: TextStyle(
                        color: (hiPass.enabled || loPass.enabled)
                            ? const Color(0xFF75715E)
                            : const Color(0xFFF8F8F2),
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIOSelector(bool narrow) {
    final channels = _channels;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12)
          .copyWith(bottom: narrow ? 6 + MediaQuery.of(context).viewPadding.bottom : 10),
      child: Column(
        children: [
          // I/O tabs (2 tabs: Inputs, Outputs)
          SizedBox(
            height: 30,
            child: TabBar(
              controller: _ioTabController,
              tabs: const [
                Tab(text: 'Inputs'),
                Tab(text: 'Outputs'),
              ],
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 12),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerHeight: 0,
            ),
          ),
          const SizedBox(height: 6),
          // Channel buttons
          Row(
            children: channels.map((ch) {
              final active = ch == _selectedChannel;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _selectedChannel = ch;
                      _selectedBand = 0;
                    }),
                    child: Container(
                      height: 32,
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
                          fontSize: narrow ? 10 : 12,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─── PEQ Graph ───

class _PeqGraph extends StatelessWidget {
  final List<PeqBand> bands;
  final int selectedBand;
  final ProtocolService proto;
  final double width;
  final double height;
  final bool narrow;
  final FilterState hiPass;
  final FilterState loPass;
  final void Function(int index) onBandSelected;
  final void Function(int index, double dB) onBandGainChanged;

  const _PeqGraph({
    required this.bands,
    required this.selectedBand,
    required this.proto,
    required this.width,
    required this.height,
    required this.narrow,
    required this.hiPass,
    required this.loPass,
    required this.onBandSelected,
    required this.onBandGainChanged,
  });

  double get _padLeft => narrow ? 40.0 : 36.0;
  static const double _padRight = 8;
  double get _padTop => narrow ? 14.0 : 10.0;
  double get _padBottom => narrow ? 36.0 : 28.0;

  double get _graphWidth => width - _padLeft - _padRight;
  double get _graphHeight => height - _padTop - _padBottom;

  int _bandFromX(double x) {
    final norm = ((x - _padLeft) / _graphWidth).clamp(0.0, 1.0);
    final freq = math.exp(_logMin + norm * _logRange);
    int best = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < bands.length; i++) {
      final bandFreq = proto.peqFreqToHz(bands[i].freqRaw);
      final d = (math.log(bandFreq) - math.log(freq)).abs();
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

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          final index = _bandFromX(event.position.dx);
          final current = bands[index].gainDb;
          final delta = -event.scrollDelta.dy / 50;
          onBandGainChanged(index, (current + delta).clamp(-12.0, 12.0));
        }
      },
      child: GestureDetector(
        onTapDown: (d) {
          final index = _bandFromX(d.localPosition.dx);
          onBandSelected(index);
        },
        onVerticalDragStart: (d) {
          final index = _bandFromX(d.localPosition.dx);
          onBandSelected(index);
        },
        onVerticalDragUpdate: (d) {
          final dB = _dBFromY(d.localPosition.dy);
          onBandGainChanged(selectedBand, dB);
        },
        child: CustomPaint(
          size: Size(width, height),
          painter: _PeqPainter(
            bands: bands,
            selectedBand: selectedBand,
            proto: proto,
            hiPass: hiPass,
            loPass: loPass,
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

class _PeqPainter extends CustomPainter {
  final List<PeqBand> bands;
  final int selectedBand;
  final ProtocolService proto;
  final FilterState hiPass;
  final FilterState loPass;
  final double padLeft;
  final double padRight;
  final double padTop;
  final double padBottom;
  final bool narrow;

  _PeqPainter({
    required this.bands,
    required this.selectedBand,
    required this.proto,
    required this.hiPass,
    required this.loPass,
    required this.padLeft,
    required this.padRight,
    required this.padTop,
    required this.padBottom,
    required this.narrow,
  });

  double _freqToX(double freq, double graphW) =>
      padLeft + _freqToNorm(freq) * graphW;

  double _dBToY(double dB, double graphH) =>
      padTop + graphH * (1.0 - (dB + 12) / 24);

  @override
  void paint(Canvas canvas, Size size) {
    final graphW = size.width - padLeft - padRight;
    final graphH = size.height - padTop - padBottom;

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

    final subGridPaint = Paint()
      ..color = const Color(0xFF75715E).withAlpha(80)
      ..strokeWidth = 0.3;

    final zeroPaint = Paint()
      ..color = const Color(0xFFF92672)
      ..strokeWidth = 1.0;

    // Horizontal grid + labels (with -3/-9/+3/+9 subdivisions)
    const dBStepsLabeled = [-12.0, -6.0, 0.0, 6.0, 12.0];
    const dBStepsSub = [-9.0, -3.0, 3.0, 9.0];
    final labelStyle = TextStyle(
      color: const Color(0xFF75715E),
      fontSize: axisLabelSize,
    );

    // Draw subdivision lines (no labels)
    for (final dB in dBStepsSub) {
      final y = _dBToY(dB, graphH);
      canvas.drawLine(Offset(padLeft, y), Offset(padLeft + graphW, y), subGridPaint);
    }

    // Draw labeled grid lines
    for (final dB in dBStepsLabeled) {
      final y = _dBToY(dB, graphH);
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

    // Frequency labels along bottom
    final freqLabels = [20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0];
    for (final freq in freqLabels) {
      final label = _formatFreq(freq);
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = _freqToX(freq, graphW) - tp.width / 2;
      tp.paint(canvas, Offset(x, padTop + graphH + 4));
    }

    // Clip to graph area for curves
    canvas.save();
    canvas.clipRect(graphRect);

    // Draw PEQ curves for each band
    for (int i = 0; i < bands.length; i++) {
      final band = bands[i];
      if (band.bypass) continue;
      if (band.gainDb.abs() < 0.05 && band.type == 0) continue;

      final color = _bandColors[i % _bandColors.length];
      final isSelected = i == selectedBand;

      _drawBandCurve(canvas, band, graphW, graphH, color, isSelected);
    }

    // Draw HPF curve
    if (hiPass.enabled && hiPass.freqRaw > 0) {
      _drawFilterCurve(canvas, graphW, graphH, hiPass.freqRaw, hiPass.slope,
          true, const Color(0xFFF92672));
    }

    // Draw LPF curve
    if (loPass.enabled && loPass.freqRaw < 1000) {
      _drawFilterCurve(canvas, graphW, graphH, loPass.freqRaw, loPass.slope,
          false, const Color(0xFF66D9EF));
    }

    // Draw composite curve (PEQ + HPF + LPF)
    _drawCompositeCurve(canvas, graphW, graphH);

    canvas.restore();

    // Draw band handles (on top, not clipped)
    for (int i = 0; i < bands.length; i++) {
      final band = bands[i];
      final freqHz = proto.peqFreqToHz(band.freqRaw);
      final cx = _freqToX(freqHz, graphW);
      final cy = _dBToY(band.gainDb, graphH);

      final color = _bandColors[i % _bandColors.length];
      final isSelected = i == selectedBand;
      final radius = isSelected ? 10.0 : 7.0;

      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()..color = band.bypass ? const Color(0xFF75715E) : color,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: const Color(0xFF272822),
            fontSize: isSelected ? 10.0 : 8.0,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));

      if (isSelected && band.gainDb.abs() >= 0.05) {
        final gainLabel = '${band.gainDb >= 0 ? "+" : ""}${band.gainDb.toStringAsFixed(1)} dB';
        final gainTp = TextPainter(
          text: TextSpan(
            text: gainLabel,
            style: const TextStyle(
              color: Color(0xFFF8F8F2),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final bubblePadH = 8.0;
        final bubblePadV = 4.0;
        final bubbleW = gainTp.width + bubblePadH * 2;
        final bubbleH = gainTp.height + bubblePadV * 2;
        final above = cy - bubbleH - radius - 4;
        final bubbleY = above >= padTop ? above : cy + radius + 4;
        final bubbleX = (cx - bubbleW / 2).clamp(padLeft, padLeft + graphW - bubbleW);

        final bubbleRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(bubbleX, bubbleY, bubbleW, bubbleH),
          const Radius.circular(4),
        );
        canvas.drawRRect(bubbleRect, Paint()..color = const Color(0xDD3E3D32));
        gainTp.paint(canvas, Offset(bubbleX + bubblePadH, bubbleY + bubblePadV));
      }
    }
  }

  /// Draw a single band's frequency response curve
  void _drawBandCurve(Canvas canvas, PeqBand band, double graphW, double graphH, Color color, bool isSelected) {
    final freqHz = proto.peqFreqToHz(band.freqRaw);
    final q = proto.peqRawToQ(band.qRaw);
    final gain = band.gainDb;

    final path = Path();
    const steps = 200;
    bool started = false;

    for (int s = 0; s <= steps; s++) {
      final norm = s / steps;
      final freq = math.exp(_logMin + norm * _logRange);
      final dB = _peqResponse(freq, freqHz, q, gain, band.type);
      final x = padLeft + norm * graphW;
      final y = _dBToY(dB, graphH);

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withAlpha(isSelected ? 200 : 100)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.0 : 1.0,
    );
  }

  /// Draw HPF or LPF filter curve
  void _drawFilterCurve(Canvas canvas, double graphW, double graphH,
      int freqRaw, int slope, bool isHighPass, Color color) {
    final cutoffHz = proto.peqFreqToHz(freqRaw);
    final slopeDbPerOct = _slopeToDbPerOct(slope);

    final path = Path();
    const steps = 300;
    bool started = false;

    for (int s = 0; s <= steps; s++) {
      final norm = s / steps;
      final freq = math.exp(_logMin + norm * _logRange);
      final dB = _filterResponse(freq, cutoffHz, slopeDbPerOct, isHighPass);
      final x = padLeft + norm * graphW;
      final y = _dBToY(dB, graphH);

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withAlpha(150)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  /// Draw the composite (sum of all bands + filters) curve
  void _drawCompositeCurve(Canvas canvas, double graphW, double graphH) {
    final path = Path();
    const steps = 300;
    bool started = false;

    final hpfActive = hiPass.enabled && hiPass.freqRaw > 0;
    final lpfActive = loPass.enabled && loPass.freqRaw < 1000;
    final hpfHz = hpfActive ? proto.peqFreqToHz(hiPass.freqRaw) : 0.0;
    final lpfHz = lpfActive ? proto.peqFreqToHz(loPass.freqRaw) : 0.0;
    final hpfSlope = hpfActive ? _slopeToDbPerOct(hiPass.slope) : 0.0;
    final lpfSlope = lpfActive ? _slopeToDbPerOct(loPass.slope) : 0.0;

    for (int s = 0; s <= steps; s++) {
      final norm = s / steps;
      final freq = math.exp(_logMin + norm * _logRange);

      double totalDb = 0;
      for (int i = 0; i < bands.length; i++) {
        final band = bands[i];
        if (band.bypass) continue;
        totalDb += _peqResponse(freq, proto.peqFreqToHz(band.freqRaw),
            proto.peqRawToQ(band.qRaw), band.gainDb, band.type);
      }

      // Add HPF/LPF contributions
      if (hpfActive) {
        totalDb += _filterResponse(freq, hpfHz, hpfSlope, true);
      }
      if (lpfActive) {
        totalDb += _filterResponse(freq, lpfHz, lpfSlope, false);
      }

      final x = padLeft + norm * graphW;
      final y = _dBToY(totalDb, graphH);

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFF8F8F2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  /// Convert slope index to dB/octave roll-off
  double _slopeToDbPerOct(int slope) {
    // BW -6 through -48 (indices 0-7), LR -12 through -48 (indices 8-11),
    // BS -6 through -48 (indices 12-19)
    const slopeValues = [
      6.0, 12.0, 18.0, 24.0, 30.0, 36.0, 42.0, 48.0,  // BW
      12.0, 24.0, 36.0, 48.0,                            // LR
      6.0, 12.0, 18.0, 24.0, 30.0, 36.0, 42.0, 48.0,   // BS
    ];
    if (slope >= 0 && slope < slopeValues.length) return slopeValues[slope];
    return 12.0;
  }

  /// HPF/LPF frequency response
  double _filterResponse(double freq, double cutoffHz, double slopeDbPerOct, bool isHighPass) {
    if (cutoffHz <= 0) return 0.0;
    if (isHighPass) {
      if (freq >= cutoffHz) return 0.0;
      return -slopeDbPerOct * math.log(cutoffHz / freq) / math.ln2;
    } else {
      if (freq <= cutoffHz) return 0.0;
      return -slopeDbPerOct * math.log(freq / cutoffHz) / math.ln2;
    }
  }

  /// Approximate PEQ frequency response for a single band at a given frequency
  double _peqResponse(double freq, double centerFreq, double q, double gainDb, int type) {
    if (gainDb.abs() < 0.01 && type == 0) return 0.0;
    if (q < 0.01) return 0.0;

    final ratio = freq / centerFreq;
    final logRatio = math.log(ratio);

    switch (type) {
      case 0: // Peak
        final bw = 1.0 / q;
        final x = logRatio / (bw * 0.5 * math.ln2);
        return gainDb / (1.0 + x * x);
      case 1: // Low Shelf
        final x = logRatio / (math.ln2 * 0.5);
        final t = 1.0 / (1.0 + math.exp(x * 3));
        return gainDb * t;
      case 2: // High Shelf
        final x = logRatio / (math.ln2 * 0.5);
        final t = 1.0 / (1.0 + math.exp(-x * 3));
        return gainDb * t;
      case 3: // LP -6dB
        if (freq <= centerFreq) return 0;
        return -6.0 * math.log(ratio) / math.ln2;
      case 4: // LP -12dB
        if (freq <= centerFreq) return 0;
        return -12.0 * math.log(ratio) / math.ln2;
      case 5: // HP -6dB
        if (freq >= centerFreq) return 0;
        return 6.0 * math.log(ratio) / math.ln2;
      case 6: // HP -12dB
        if (freq >= centerFreq) return 0;
        return 12.0 * math.log(ratio) / math.ln2;
      case 7: // All Pass 1
      case 8: // All Pass 2
        return 0;
      default:
        return 0;
    }
  }

  @override
  bool shouldRepaint(covariant _PeqPainter oldDelegate) => true;
}
