# Testing plan for DSP 204

## Current status

- `flutter analyze`: passing.
- `flutter test`: passing.
- `flutter build web`: passing.
- Web preview served successfully on `http://127.0.0.1:54545`.
- Windows native build: passing.
- Windows release executable:
  `build\windows\x64\runner\Release\dsp.exe`

## Why native Windows matters

The app uses raw TCP sockets through `dart:io`. The web build is useful for UI rendering, but a browser is not the right target for talking directly to a DSP over TCP. For real DSP tests, use the Windows desktop build/run target.

## To enable Windows native test

Run:

```powershell
.\tools\test_all.ps1
.\build\windows\x64\runner\Release\dsp.exe
```

## DSP 204 protocol capture

To add real DSP 204 support, capture the official editor traffic first. Minimum useful capture:

1. PC and DSP 204 on the same network.
2. Open Wireshark on the network interface used for the DSP.
3. Filter by DSP IP or port, for example:

```text
ip.addr == <DSP_204_IP> || tcp.port == 9761
```

4. Start the official Thomann editor.
5. Connect to the DSP 204.
6. Perform these actions:
   - initial connect and preset list;
   - change gain on In A, In B, Out 1, Out 4;
   - mute/unmute the same channels;
   - change matrix routing;
   - load one preset;
   - save one test preset if safe;
   - wait 10 seconds for keepalive/meter packets.
7. Save as `.pcapng` locally. Do not commit raw captures.

Once the capture is available, compare it with the DSP 408 protocol in `lib/devices/t_racks408` and split the code into device profiles.
