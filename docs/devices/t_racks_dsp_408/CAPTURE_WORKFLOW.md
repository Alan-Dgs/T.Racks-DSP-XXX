# DSP408 capture workflow

Use `tools/capture_helper` to create small, named captures.

Requirements:
- Wireshark installed, including `dumpcap.exe`.
- Official t.racks DSP editor connected to the same network as the DSP.
- DSP IP known, for example `192.168.0.99`.

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\capture_helper\run_capture_helper.ps1
```

Capture filter used by the helper:

```text
host <DSP_IP> or tcp port 9761
```

Rules for useful captures:
- Change one value at a time.
- Click `Action faite` immediately after each manual action.
- Stop the scenario after the last action.
- Keep the `.json` sidecar with the `.pcapng`.

Do not publish raw `.pcapng` captures by default. They may contain local IP addresses, timing, device names, and network metadata.

Useful extraction command:

```powershell
& 'C:\Program Files\Wireshark\tshark.exe' -r capture.pcapng -Y 'tcp.len > 0' -T fields -e frame.time_relative -e ip.src -e ip.dst -e tcp.payload
```
