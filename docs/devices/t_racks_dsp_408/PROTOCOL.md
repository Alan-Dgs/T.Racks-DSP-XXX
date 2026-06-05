# t.racks DSP408 TCP protocol

The official editor communicates with the DSP over TCP port `9761`.

Observed request frame shape:

```text
10 02 00 01 [length] [command] [payload...] 10 03 [checksum]
```

Checksum:
- XOR bytes between prefix and footer, starting with `0x01`.
- The checksum byte follows `10 03`.

Keepalive request:

```text
10 02 00 01 01 40 10 03 41
```

Known channel indexes:
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

Captured command details are in `CAPTURED_COMMANDS.md`.
