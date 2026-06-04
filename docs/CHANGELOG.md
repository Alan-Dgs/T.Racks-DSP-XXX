# Changelog

## Unreleased

### Added
- Added saved connection profiles for DSP host/port presets.
- Added DSP408 device profile groundwork to reduce hard-coded channel lists.
- Added guided capture helper based on Wireshark `dumpcap`.
- Added French and English capture scenarios for DSP408, DSP206, and DSP204.
- Added DSP408 captured TCP command documentation.
- Added real DSP408 commands for phase, matrix attenuation, GEQ bypass, and channel names.
- Added DSP408 protocol builders for Gate, Compressor, Limiter, Delay, delay unit, and Test Tone.
- Added real DSP408 Gate, Compressor, Limiter, and Delay tabs wired to captured TCP commands.
- Added protocol tests based on captured DSP408 frames.

### Changed
- Refactored selected widgets/providers to use the DSP408 device profile.
- Updated HPF command handling from captured protocol behavior: last byte is slope/type.
- Moved protocol and capture documentation under `docs/`.

### Fixed
- Fixed app test bootstrap to pump the real provider tree.
- Replaced the default Flutter widget test with a DSP controller smoke test.

### Security / Privacy
- Excluded local captures, screenshots, logs, and scratch reverse-engineering files from Git.
- Documented that `.pcapng` and official editor screenshots must not be published by default.
