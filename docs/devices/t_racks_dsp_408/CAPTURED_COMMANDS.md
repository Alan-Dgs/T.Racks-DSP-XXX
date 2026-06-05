# t.racks DSP 408 protocol capture notes

Captured on 2026-06-04 with the official `the t.racks DSP 408 Processor Editor V1.05`.

Capture context:
- Transport: TCP
- DSP port: `9761`
- Capture filter template: `host <DSP_IP> or tcp port 9761`
- Raw `.pcapng` files are intentionally not published.

Frame format used by the official TCP editor:
- Request prefix: `10 02 00 01`
- Footer: `10 03 [checksum]`
- Checksum: XOR over bytes between prefix and footer, starting from `0x01`.
- Keepalive request, ignored below: `10 02 00 01 01 40 10 03 41`

Channel indexes observed/used:
- `0x00`: In A
- `0x01`: In B
- `0x02`: In C
- `0x03`: In D
- `0x04`: Out 1
- `0x05`: Out 2
- `0x06`: Out 3
- `0x07`: Out 4
- `0x08`: Out 5
- `0x09`: Out 6
- `0x0a`: Out 7
- `0x0b`: Out 8

## Confirmed commands

### Phase, cmd `0x36`

Scenario: `001_phase_input_output`

Format:

```text
10 02 00 01 03 36 [channel] [phase] 10 03 [checksum]
```

Values:
- `phase = 0x00`: normal
- `phase = 0x01`: inverted

Observed:

```text
InA inverse  10 02 00 01 03 36 00 01 10 03 34
InA normal   10 02 00 01 03 36 00 00 10 03 35
Out1 inverse 10 02 00 01 03 36 04 01 10 03 30
Out1 normal  10 02 00 01 03 36 04 00 10 03 31
```

### Matrix attenuation, cmd `0x41`

Scenario: `002_matrix_attenuation_out1_ina`

Format:

```text
10 02 00 01 05 41 [output] [input] [gain_lo] [gain_hi] 10 03 [checksum]
```

Gain encoding matches channel gain:
- `raw = 0x0118` -> `+0.0 dB`
- `raw = 0x00dc` -> `-6.0 dB`
- `raw = 0x0050` -> `-20.0 dB`
- `raw = 0x0000` -> `-60.0 dB`

Observed for Out1/InA:

```text
+0.0 dB  10 02 00 01 05 41 04 00 18 01 10 03 59
-6.0 dB  10 02 00 01 05 41 04 00 dc 00 10 03 9c
-20.0 dB 10 02 00 01 05 41 04 00 50 00 10 03 10
-60.0 dB 10 02 00 01 05 41 04 00 00 00 10 03 40
```

### Gate, cmd `0x3e`

Scenario: `003_gate_ina_threshold_attack_hold_release`

Observed on InA only. Official UI exposes Gate on inputs.

Probable format:

```text
10 02 00 01 0a 3e [channel]
  [attack_minus_1_lo] [attack_minus_1_hi]
  [release_minus_1_lo] [release_minus_1_hi]
  [hold_minus_1_lo] [hold_minus_1_hi]
  [threshold_raw_lo] [threshold_raw_hi]
10 03 [checksum]
```

Threshold raw appears to use `raw = (dB + 90) * 2`, so `-40.0 dB -> 100 -> 0x0064`.

Observed InA:

```text
Threshold -40.0 dB 10 02 00 01 0a 3e 00 00 00 63 00 63 00 64 00 10 03 50
Attack 10 ms       10 02 00 01 0a 3e 00 09 00 63 00 63 00 64 00 10 03 59
Hold 250 ms        10 02 00 01 0a 3e 00 09 00 63 00 f9 00 64 00 10 03 c3
Release 750 ms     10 02 00 01 0a 3e 00 09 00 ed 02 f9 00 64 00 10 03 4f
```

### Compressor, cmd `0x30`

Scenario: `004_comp_out1_threshold_ratio_knee_attack_release`

Observed on Out1. Official UI exposes Compressor on outputs.

Probable format:

```text
10 02 00 01 0c 30 [channel]
  [ratio_raw_lo] [ratio_raw_hi]
  [attack_minus_1_lo] [attack_minus_1_hi]
  [release_minus_1_lo] [release_minus_1_hi]
  [knee_db_lo] [knee_db_hi]
  [threshold_raw_lo] [threshold_raw_hi]
10 03 [checksum]
```

Threshold raw appears to use `raw = (dB + 90) * 2`, so `-20.0 dB -> 140 -> 0x008c`.

Observed Out1:

```text
Threshold -20.0 dB 10 02 00 01 0c 30 04 00 00 31 00 f3 01 00 00 8c 00 10 03 77
Ratio 1:4.0        10 02 00 01 0c 30 04 09 00 31 00 f3 01 00 00 8c 00 10 03 7e
Knee 6 dB          10 02 00 01 0c 30 04 09 00 31 00 f3 01 06 00 8c 00 10 03 78
Attack 25 ms       10 02 00 01 0c 30 04 09 00 18 00 f3 01 06 00 8c 00 10 03 51
Release 800 ms     10 02 00 01 0c 30 04 09 00 18 00 1f 03 06 00 8c 00 10 03 bf
```

Ratio mapping confirmed by UI for the tested point:
- `0x0009` -> `1:4.0`

### Limiter, cmd `0x3f`

Scenario: `005_limit_out1_threshold_attack_release`

Observed on Out1. Official UI exposes Limiter on outputs.

Probable format:

```text
10 02 00 01 0a 3f [channel]
  [attack_minus_1_lo] [attack_minus_1_hi]
  [release_minus_1_lo] [release_minus_1_hi]
  [unknown_lo] [unknown_hi]
  [threshold_raw_lo] [threshold_raw_hi]
10 03 [checksum]
```

Threshold raw appears to use `raw = (dB + 90) * 2`, so `-10.0 dB -> 160 -> 0x00a0`.

Observed Out1:

```text
Threshold -10.0 dB 10 02 00 01 0a 3f 04 e6 03 b7 0b 00 00 a0 00 10 03 c8
Attack 20 ms       10 02 00 01 0a 3f 04 13 00 b7 0b 00 00 a0 00 10 03 3e
Release 500 ms     10 02 00 01 0a 3f 04 13 00 f3 01 00 00 a0 00 10 03 70
```

### Delay, cmd `0x38`; delay unit, cmd `0x15`

Scenario: `006_delay_ina_out1_ms_m_ft`

Delay value format:

```text
10 02 00 01 04 38 [channel] [delay_raw_lo] [delay_raw_hi] 10 03 [checksum]
```

Delay raw appears to use 96 ticks per ms:
- `1.000 ms -> 96 -> 0x0060`
- `10.000 ms -> 960 -> 0x03c0`

Observed:

```text
InA 1.000 ms   10 02 00 01 04 38 00 60 00 10 03 5c
Out1 10.000 ms 10 02 00 01 04 38 04 c0 03 10 03 fb
```

Unit display command:

```text
10 02 00 01 02 15 [unit] 10 03 [checksum]
```

Observed:

```text
Unit m  10 02 00 01 02 15 01 10 03 16
Unit ft 10 02 00 01 02 15 02 10 03 15
```

Probable unit mapping:
- `0x00`: ms
- `0x01`: m
- `0x02`: ft

### Test tone, cmd `0x39`

Scenario: `009_test_tone_sources_sine`

Format:

```text
10 02 00 01 03 39 [source] [frequency_index] 10 03 [checksum]
```

Source mapping:
- `0x00`: Analog Input
- `0x01`: Pink Noise
- `0x02`: White Noise
- `0x03`: Sine Wave

Sine frequency index uses the GEQ 31-band frequency list:
- `0x00`: 20 Hz
- `0x11`: 1 kHz
- `0x1e`: 20 kHz

Observed:

```text
Analog input 10 02 00 01 03 39 00 00 10 03 3a
Pink noise   10 02 00 01 03 39 01 00 10 03 3b
White noise  10 02 00 01 03 39 02 00 10 03 38
Sine 20 Hz   10 02 00 01 03 39 03 00 10 03 39
Sine 1 kHz   10 02 00 01 03 39 03 11 10 03 28
Sine 20 kHz  10 02 00 01 03 39 03 1e 10 03 27
```

### Channel name, cmd `0x3d`

Scenario: `010_channel_name_8chars`

Format:

```text
10 02 00 01 0a 3d [channel] [8 ASCII bytes, nul padded] 10 03 [checksum]
```

Observed:

```text
InA  "12345678" 10 02 00 01 0a 3d 00 31 32 33 34 35 36 37 38 10 03 3f
Out1 "12345678" 10 02 00 01 0a 3d 04 31 32 33 34 35 36 37 38 10 03 3b
InA  "InA"      10 02 00 01 0a 3d 00 49 6e 41 00 00 00 00 00 10 03 51
Out1 "Out1"     10 02 00 01 0a 3d 04 4f 75 74 31 00 00 00 00 10 03 4c
```

### GEQ bypass/reset, cmds `0x49` and `0x48`

Scenario: `008_geq_bypass_reset_ina`

Band command is already implemented as cmd `0x48`.

Bypass format observed:

```text
10 02 00 01 03 49 [channel] [bypass] 10 03 [checksum]
```

Observed:

```text
InA EQ bypass on 10 02 00 01 03 49 00 01 10 03 4b
```

Reset behavior:
- The official editor asks for confirmation.
- After OK, it sends 31 `0x48` band commands for channel InA with value `0x78` (`0.0 dB`), not a dedicated reset command.

## Existing/partially known commands reconfirmed

### PEQ band, cmd `0x33`

Scenario: `007_peq_hpf_lpf_ina_out1`

Current implementation matches the observed shape:

```text
10 02 00 01 0a 33 [channel] [band] [gain] 00 [freq_lo] [freq_hi] [q] [type] [bypass] 10 03 [checksum]
```

Observed examples:

```text
InA band 1 +3.0 dB      10 02 00 01 0a 33 00 00 96 00 29 00 23 00 00 10 03 a5
InA band 1 Low Shelf    10 02 00 01 0a 33 00 00 96 00 29 00 0a 01 00 10 03 8d
InA band 1 bypass on    10 02 00 01 0a 33 00 00 96 00 29 00 0a 01 01 10 03 8c
Out1 band 9 -3.0 dB     10 02 00 01 0a 33 04 08 5a 00 1d 01 23 00 00 10 03 50
```

### HPF/LPF, cmds `0x32` and `0x31`

Scenario: `007_peq_hpf_lpf_ina_out1`

Observed shape:

```text
10 02 00 01 05 32 [channel] [freq_lo] [freq_hi] [slope] 10 03 [checksum]
10 02 00 01 05 31 [channel] [freq_lo] [freq_hi] [slope] 10 03 [checksum]
```

Observed examples:

```text
HPF InA freq/slope 10 02 00 01 05 32 00 78 00 09 10 03 46
HPF InA slope      10 02 00 01 05 32 00 78 00 08 10 03 47
LPF InA freq       10 02 00 01 05 31 00 e5 00 13 10 03 c2
LPF InA freq       10 02 00 01 05 31 00 2c 01 13 10 03 0a
LPF InA slope      10 02 00 01 05 31 00 2c 01 14 10 03 0d
```

Note: the current code should be adjusted before implementation:
- `buildHiPassCommand` currently treats the last byte as enable, but capture shows it is the slope/type byte.
- `buildLoPassCommand` already sends slope as the last byte, but bypass semantics still need a targeted capture if exact on/off state is required.

## No command observed / inconclusive captures

### File / Setting ID-IP / Lock

Scenario: `012_file_setting_lock_low_priority`

No non-keepalive PC -> DSP payload was observed. Opening these dialogs without applying changes does not send TCP commands.

### Link / Copy

Scenario: `011_link_copy_in_out`

Observed commands include:
- `0x2a`, likely link selection, examples:
  - `10 02 00 01 03 2a 00 01 10 03 28`
  - `10 02 00 01 03 2a 04 05 10 03 28`
- Follow-up routing/config/preset queries (`0x12`, `0x14`, `0x22`, `0x27`, `0x29`) make the capture noisy.
- Copy appears to trigger broad state sync/dump behavior rather than a single isolated parameter command.

Treat Link/Copy as observed but not yet implementation-ready. If needed, recapture each one alone with no additional parameter edits.
