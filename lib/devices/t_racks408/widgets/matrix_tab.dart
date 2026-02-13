// Matrix Tab Widget
//
// 8x4 matrix grid: 8 output columns x 4 input rows.
// Each cell toggles routing on tap and shows a clickable dB gain value.
//
// Matrix routing protocol (from PCAP analysis):
//   cmd 0x3a, data: [output_byte, input_bitmask]
//   Output byte: 0x04 = Out 1, 0x05 = Out 2, ..., 0x0b = Out 8
//   Input bitmask: 0x01 = In A, 0x02 = In B, 0x04 = In C, 0x08 = In D

import 'package:flutter/material.dart';

import '../providers/device_provider.dart';

class MatrixTab extends StatelessWidget {
  final DeviceProvider deviceProvider;

  const MatrixTab({super.key, required this.deviceProvider});

  static const _outputs = [
    'Out 1', 'Out 2', 'Out 3', 'Out 4',
    'Out 5', 'Out 6', 'Out 7', 'Out 8',
  ];

  static const _inputs = ['In A', 'In B', 'In C', 'In D'];

  static const _labelWidth = 56.0;
  static const _headerHeight = 20.0;
  static const _gap = 3.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Compute square cell size from available space
          final gridWidth = constraints.maxWidth - _labelWidth;
          final gridHeight = constraints.maxHeight - _headerHeight - _gap;
          final cellFromWidth = (gridWidth - _gap * 7) / 8;
          final cellFromHeight = (gridHeight - _gap * 3) / 4;
          final cellSize = cellFromWidth < cellFromHeight
              ? cellFromWidth
              : cellFromHeight;

          final totalGridWidth = cellSize * 8 + _gap * 7;

          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Column headers
                SizedBox(
                  height: _headerHeight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: _labelWidth),
                      SizedBox(
                        width: totalGridWidth,
                        child: Row(
                          children: _outputs.map((output) {
                            return SizedBox(
                              width: cellSize + (output != _outputs.last ? _gap : 0),
                              child: Text(
                                deviceProvider.getAlias(output),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFA6E22E),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: _gap),
                // 4 input rows
                ...List.generate(_inputs.length, (ri) {
                  final input = _inputs[ri];
                  return Padding(
                    padding: EdgeInsets.only(bottom: ri < 3 ? _gap : 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: _labelWidth,
                          height: cellSize,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text(
                                deviceProvider.getAlias(input),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFF8F8F2),
                                ),
                              ),
                            ),
                          ),
                        ),
                        ...List.generate(_outputs.length, (ci) {
                          final output = _outputs[ci];
                          final enabled = deviceProvider.getMatrixEnabled(output, input);
                          final gain = deviceProvider.getMatrixGain(output, input);
                          return Padding(
                            padding: EdgeInsets.only(right: ci < 7 ? _gap : 0),
                            child: SizedBox(
                              width: cellSize,
                              height: cellSize,
                              child: _MatrixCell(
                                output: output,
                                input: input,
                                enabled: enabled,
                                gain: gain,
                                deviceProvider: deviceProvider,
                                cellSize: cellSize,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MatrixCell extends StatelessWidget {
  final String output;
  final String input;
  final bool enabled;
  final double gain;
  final DeviceProvider deviceProvider;
  final double cellSize;

  const _MatrixCell({
    required this.output,
    required this.input,
    required this.enabled,
    required this.gain,
    required this.deviceProvider,
    required this.cellSize,
  });

  String _formatGain(double dB) {
    final sign = dB >= 0 ? '+' : '';
    return '$sign${dB.toStringAsFixed(1)}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => deviceProvider.toggleMatrixInput(output, input),
      child: Container(
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFFA6E22E)
              : const Color(0xFF272822),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: enabled
                ? const Color(0xFFA6E22E)
                : const Color(0xFF75715E),
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            // dB value at top — underlined to convey clickability
            GestureDetector(
              onTap: () => _showGainDialog(context),
              child: Container(
                width: double.infinity,
                height: cellSize / 4,
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: enabled
                          ? const Color(0xFF272822).withAlpha(60)
                          : const Color(0xFF75715E).withAlpha(80),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Text(
                  _formatGain(gain),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.dotted,
                    decorationColor: enabled
                        ? const Color(0xFF272822).withAlpha(120)
                        : const Color(0xFF75715E),
                    color: enabled
                        ? const Color(0xFF272822).withAlpha(200)
                        : (gain == 0.0
                            ? const Color(0xFF75715E)
                            : const Color(0xFFFD971F)),
                  ),
                ),
              ),
            ),
            // Remaining area for toggle
            const Spacer(),
          ],
        ),
      ),
    );
  }

  void _showGainDialog(BuildContext context) {
    final controller = TextEditingController(text: gain.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$input \u2192 $output'),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: const InputDecoration(
            labelText: 'dB (-60.0 to 0.0)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) {
            final dB = double.tryParse(value);
            if (dB != null && dB >= -60.0 && dB <= 0.0) {
              deviceProvider.setMatrixGain(output, input, dB);
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              deviceProvider.setMatrixGain(output, input, 0.0);
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
              final dB = double.tryParse(controller.text);
              if (dB != null && dB >= -60.0 && dB <= 0.0) {
                deviceProvider.setMatrixGain(output, input, dB);
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
