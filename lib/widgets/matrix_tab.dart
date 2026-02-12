// Matrix Tab Widget
//
// 8-section grid (Out 1-8), each with 4 input gain controls (In A-D).
// Each crossing point shows a button with the input name and a dB modifier.
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 4 columns x 2 rows grid
          final cellWidth = (constraints.maxWidth - 3 * 8) / 4; // 3 gaps
          final cellHeight = (constraints.maxHeight - 8) / 2;   // 1 gap

          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _outputs.map((output) {
              return SizedBox(
                width: cellWidth,
                height: cellHeight,
                child: _OutputSection(
                  output: output,
                  inputs: _inputs,
                  deviceProvider: deviceProvider,
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _OutputSection extends StatelessWidget {
  final String output;
  final List<String> inputs;
  final DeviceProvider deviceProvider;

  const _OutputSection({
    required this.output,
    required this.inputs,
    required this.deviceProvider,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF3E3D32),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF75715E), width: 0.5),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Output label
          Text(
            deviceProvider.getAlias(output),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Color(0xFFA6E22E),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          // Input rows
          ...inputs.map((input) {
            final gain = deviceProvider.getMatrixGain(output, input);
            final enabled = deviceProvider.getMatrixEnabled(output, input);
            return Expanded(
              child: _MatrixInputRow(
                output: output,
                input: input,
                gain: gain,
                enabled: enabled,
                deviceProvider: deviceProvider,
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _MatrixInputRow extends StatelessWidget {
  final String output;
  final String input;
  final double gain;
  final bool enabled;
  final DeviceProvider deviceProvider;

  const _MatrixInputRow({
    required this.output,
    required this.input,
    required this.gain,
    required this.enabled,
    required this.deviceProvider,
  });

  double get _stepSize => gain <= -20.0 ? 0.5 : 0.1;

  String _formatGain(double dB) {
    final sign = dB >= 0 ? '+' : '';
    return '$sign${dB.toStringAsFixed(1)}dB';
  }

  void _adjust(double delta) {
    final newValue = (gain + delta).clamp(-60.0, 0.0);
    deviceProvider.setMatrixGain(output, input, newValue);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          // Down button
          _StepButton(
            icon: Icons.remove,
            onPressed: () => _adjust(-_stepSize),
          ),
          const SizedBox(width: 2),
          // Main button: input name + dB value (tap to toggle, long-press for gain)
          Expanded(
            child: GestureDetector(
              onTap: () => deviceProvider.toggleMatrixInput(output, input),
              onLongPress: () => _showGainDialog(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      deviceProvider.getAlias(input),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: enabled
                            ? const Color(0xFF272822)
                            : const Color(0xFFF8F8F2),
                      ),
                    ),
                    Text(
                      _formatGain(gain),
                      style: TextStyle(
                        fontSize: 10,
                        color: enabled
                            ? const Color(0xFF272822).withAlpha(180)
                            : (gain == 0.0
                                ? const Color(0xFF75715E)
                                : const Color(0xFFFD971F)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          // Up button
          _StepButton(
            icon: Icons.add,
            onPressed: () => _adjust(_stepSize),
          ),
        ],
      ),
    );
  }

  void _showGainDialog(BuildContext context) {
    final controller = TextEditingController(text: gain.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$output \u2190 $input'),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: const InputDecoration(
            labelText: 'dB (-60.0 to +0.0)',
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

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _StepButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 12),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFF3E3D32),
          foregroundColor: const Color(0xFFF8F8F2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(3),
            side: const BorderSide(color: Color(0xFF75715E), width: 0.5),
          ),
        ),
      ),
    );
  }
}
