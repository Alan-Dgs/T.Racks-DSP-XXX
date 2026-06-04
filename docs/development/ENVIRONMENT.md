# Development environment

This project is a Flutter application targeting the t.racks DSP family.

Validated local toolchain:
- Flutter `3.38.9`
- Dart `3.10.8`
- Windows desktop build with Visual Studio C++ workload
- Wireshark `4.6.6` for capture tooling
- Python `3.13` for `tools/capture_helper`

Useful commands:

```powershell
flutter analyze
flutter test
flutter build windows
```

Run the capture helper:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\capture_helper\run_capture_helper.ps1
```
