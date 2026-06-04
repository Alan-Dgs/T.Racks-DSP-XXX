# DSP capture helper

Small Python/Tkinter utility used to guide manual protocol captures of the official t.racks DSP editor.

It does not control the official editor. It only:
- starts/stops `dumpcap`;
- names `.pcapng` files consistently;
- records step timestamps in a `.json` sidecar;
- guides the operator through one action at a time.

## Requirements

- Windows
- Python with Tkinter
- Wireshark installed at `C:\Program Files\Wireshark`

## Run

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\capture_helper\run_capture_helper.ps1
```

## Scenarios

Scenario files live in `tools/capture_helper/scenarios/`:
- `dsp408.fr.json`
- `dsp408.en.json`
- `dsp206.fr.json`
- `dsp206.en.json`
- `dsp204.fr.json`
- `dsp204.en.json`

## Output

Default output:

```text
captures/<MODEL>/<YYYY-MM-DD>/
```

Each scenario writes:
- one `.pcapng`;
- one `.json` sidecar with timestamps and steps.

## Privacy

Do not commit captures. `.pcapng` files may contain local IPs, hostnames, timings, and device/network metadata.
