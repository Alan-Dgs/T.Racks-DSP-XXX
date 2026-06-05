# t.racks DSP206 notes

Assumed channel layout from model naming:
- Inputs: InA, InB
- Outputs: Out1..Out6

This must be confirmed from a real DSP206 capture before implementing support.

Use the DSP206 scenarios in `tools/capture_helper/scenarios/`:
- `dsp206.fr.json`
- `dsp206.en.json`

Minimum facts to capture:
- TCP connection and initial dump.
- Channel indexes.
- Config chunk count.
- Gain/mute/phase commands.
- Matrix routing and attenuation.
- PEQ/GEQ/HPF/LPF.
- Gate, Comp, Limit, Delay.
