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
- Added config-dump parser coverage for DSP408 dynamics and delay state.
- Added a bottom Test Tone panel wired to the captured DSP408 test tone command.
- Added a bottom Parsed Config panel for comparing decoded app state with the official editor.

### Changed
- Refactored selected widgets/providers to use the DSP408 device profile.
- Updated HPF command handling from captured protocol behavior: last byte is slope/type.
- Moved protocol and capture documentation under `docs/`.

### Fixed
- Fixed Gate, Compressor, Limiter, and Delay tabs so they load current/preset config instead of starting from defaults.
- Fixed DSP408 output config offsets for Compressor, Limiter, and Delay parsing.
- Fixed DSP408 output PEQ config parsing so the 9 output bands start at the correct offset.
- Fixed app test bootstrap to pump the real provider tree.
- Replaced the default Flutter widget test with a DSP controller smoke test.

### Security / Privacy
- Excluded local captures, screenshots, logs, and scratch reverse-engineering files from Git.
- Documented that `.pcapng` and official editor screenshots must not be published by default.
