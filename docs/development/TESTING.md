# Testing

## Automated checks

Run before pushing:

```powershell
flutter analyze
flutter test
flutter build windows
```

Current protocol tests cover captured commands for:
- gain
- mute
- phase
- matrix routing
- matrix attenuation
- GEQ band
- GEQ bypass
- PEQ/HPF/LPF command shapes
- channel name

## Hardware checks

Hardware validation must be done with the Windows build, not Flutter Web, because Web cannot open the raw TCP socket used by the DSP.

Recommended smoke test against a DSP408:
1. Connect to the DSP IP on port `9761`.
2. Verify presets load.
3. Toggle phase on InA and Out1.
4. Change matrix attenuation Out1/InA.
5. Toggle GEQ bypass.
6. Rename InA with an 8-character name, then restore it.
