# FP-5 pc-asr-activate — Tasks

Legend: [ ] todo · [x] done · [~] partial/seam

- [ ] **T1 — `pc_asr.rs` activator trait + platform impls**
  - `PcAsrActivator { activate(), is_available() }`, `activator()` cfg-selector.
  - Windows: `SendInput` Win+H (LWIN 0x5B + H 0x48 down/up), raw `user32` FFI.
  - Non-Windows stub: log + Ok, `is_available()=false`.

- [ ] **T2 — Pure voice-source router**
  - `VoiceSource::{Cloud, System}`, `VoiceAction::{Activate, Ignore}`,
    `route_voice(src, VoiceState) -> VoiceAction` (no IO).
  - Reuse `protocol::VoiceState`.

- [ ] **T3 — Wire into the Tauri app (`lib.rs` app module, Windows-gated)**
  - `Inner.voice_source` (default `System`).
  - `handle_frame`: on `Voice{Start}` → `route_voice`; on `Activate` call
    `activator().activate()`, log `[PC-ASR] ...`.
  - `set_voice_source` command (+ mirror to board via `send_config`).
  - `get_status` exposes `voice_source`; register the new command.

- [ ] **T4 — Route B seam (documented, not wired)**
  - Note in code where WinRT (`asr.rs`) → `inject.type_text` → optional FP-4
    forward would attach. No behavior change.

- [ ] **T5 — Tests + gates (Linux)**
  - Unit tests: `route_voice` truth table; stub activator unavailable+Ok.
  - `cargo test`, `cargo clippy -- -D warnings`, `cargo fmt --check` green.

- [ ] **T6 — UI toggle (React) [optional for probe]**
  - Voice-source selector (cloud/system) calling `set_voice_source`; show active
    source. Can defer; backend command is the gated deliverable.

- [ ] **T7 — Windows on-hardware verification [user]**
  - source=`system`, hold K4 → Windows dictation bar appears, types into focused
    window; source=`cloud` → no PC dictation. (EC2 cannot run this.)

## Notes
- Firmware unchanged; board already emits `voice.start/stop`.
- Route A (Win+H) is the probe's pass criterion; route B is a follow-up.
- Mirror of source to board uses the existing `config{voice_engine}` frame.
