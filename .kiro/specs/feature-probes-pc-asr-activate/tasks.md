# FP-5 pc-asr-activate — Tasks

Legend: [ ] todo · [x] done · [~] partial/seam

> **状态：✅ 完成（含 Windows 真机验收）** — 2026-09-14 用户确认。

- [x] **T1 — `pc_asr.rs` activator trait + platform impls** ✅ 2026-09-14
  - `PcAsrActivator { activate(), is_available() }`, `activator()` cfg-selector.
  - Windows: `SendInput` Win+H (LWIN 0x5B + H 0x48 down/up), raw `user32` FFI.
  - Non-Windows stub: log + Ok, `is_available()=false`.

- [x] **T2 — Pure voice-source router** ✅ 2026-09-14
  - `VoiceSource::{Cloud, System}`, `VoiceAction::{Activate, Ignore}`,
    `route_voice(src, VoiceState) -> VoiceAction` (no IO).
  - Reuse `protocol::VoiceState`.

- [x] **T3 — Wire into the Tauri app (`lib.rs` app module, Windows-gated)** ✅ 2026-09-14
  - `Inner.voice_source` (default `System`).
  - `handle_frame`: on `Voice{Start}` → `route_voice`; on `Activate` call
    `activator().activate()`, log `[PC-ASR] ...`.
  - `set_voice_source` command (+ mirror to board via `send_config`).
  - `get_status` exposes `voice_source`; register the new command.

- [x] **T4 — Route B seam (documented, not wired)** ✅ 2026-09-14
  - Note in code where WinRT (`asr.rs`) → `inject.type_text` → optional FP-4
    forward would attach. No behavior change.

- [x] **T5 — Tests + gates (Linux)** ✅ 2026-09-14
  - Unit tests: `route_voice` truth table; stub activator unavailable+Ok.
  - `cargo test`, `cargo clippy -- -D warnings`, `cargo fmt --check` green.

- [x] **T6 — UI toggle (React) [optional for probe]** ✅ 2026-09-14
  - Voice-source selector (cloud/system) calling `set_voice_source`; show active
    source. Backend command and UI are both implemented.

- [x] **T7 — Windows on-hardware verification [user]** ✅ 2026-09-14
  - source=`system`, hold K4 → Windows dictation bar appears and types into the
    focused window; source=`cloud` → no PC dictation. User confirmed hardware acceptance.

## Notes
- Firmware unchanged; board already emits `voice.start/stop`.
- Route A (Win+H) is the probe's pass criterion; route B is a follow-up.
- Mirror of source to board uses the existing `config{voice_engine}` frame.
