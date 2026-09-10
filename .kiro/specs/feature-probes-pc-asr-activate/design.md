# FP-5 pc-asr-activate — Design

## Overview

FP-5 adds a **voice-source router** to the companion. Board voice events already
arrive in `lib.rs::app::handle_frame`. FP-5 introduces:

1. `pc_asr.rs` — a `PcAsrActivator` trait: activate the OS's own dictation.
   - Windows impl: `SendInput` the **Win+H** chord (LWIN down, H down, H up,
     LWIN up), which toggles Windows Voice Typing. Raw `user32` FFI, no new
     crate — same pattern as `inject.rs`.
   - Non-Windows stub: logs "unsupported", returns Ok.
2. A **voice source** state (`VoiceSource::{Cloud, System}`) held in `AppState`,
   default `System` for this probe.
3. A pure router function `route_voice(source, voice_state) -> VoiceAction` that
   decides `Activate` vs `Ignore`, unit-tested on Linux.
4. Wiring in `handle_frame`: on `Inbound::Voice{Start}`, consult `route_voice`;
   if `Activate`, call the activator and log the outcome.
5. Tauri commands `set_voice_source` / (source surfaced in `get_status`), and the
   existing `send_config{voice_engine}` frame mirrors the choice to the board.

Route A (Win+H, OS dictation) is the **primary** path: it is the literal
"activate the PC's own ASR", needs no API keys, and types into the focused
window natively. Route B (companion-embedded WinRT via `asr.rs` →
`inject.type_text` → optional FP-4 forward) reuses existing seams and is left as
a documented follow-up.

## Module: `pc_asr.rs`

```rust
pub trait PcAsrActivator: Send {
    /// Activate the OS's built-in dictation (types into the focused window).
    fn activate(&self) -> Result<(), String>;
    fn is_available(&self) -> bool;
}
pub fn activator() -> Box<dyn PcAsrActivator>; // cfg-selected

// Windows: SendInput LWIN(0x5B)+H(0x48) down/up. VK_LWIN with KEYEVENTF_KEYUP.
// Non-Windows: stub logs and returns Ok, is_available()=false.
```

The Win32 `INPUT`/`KEYBDINPUT` layout and `SendInput` binding are identical to
`inject.rs`; to avoid duplicating the FFI, `pc_asr.rs`'s Windows impl defines its
own small `vkey_event` helpers (kept local so the two modules stay independent;
a later refactor may share a `win32input` module).

## Router (pure, host-independent)

```rust
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum VoiceSource { Cloud, System }

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum VoiceAction { Activate, Ignore }

pub fn route_voice(src: VoiceSource, state: VoiceState) -> VoiceAction {
    match (src, state) {
        (VoiceSource::System, VoiceState::Start) => VoiceAction::Activate,
        _ => VoiceAction::Ignore,
    }
}
```

`route_voice` lives in `pc_asr.rs` (no IO) so it is unit-tested on Linux without
Tauri/Windows. `VoiceState` is reused from `protocol.rs`.

## State & commands (Windows app module)

- `Inner` gains `voice_source: VoiceSource` (default `System`).
- `#[tauri::command] set_voice_source(source: String)` — parse `"cloud"|"system"`,
  store it, and mirror to the board via `send_config(voice_engine=source)`.
- `get_status` gains a `voice_source` field for the UI.
- `handle_frame`: for `Inbound::Voice { payload: { state: Start }, .. }`, read the
  current `voice_source`, call `route_voice`; on `Activate` invoke
  `activator().activate()` and log `[PC-ASR] activate -> ok/err`.

The activator is constructed once (cheap) or per-activation; per-activation keeps
`handle_frame` lock-free around the FFI call.

## Data flow

```
board K4 hold ──voice.start──▶ transport ──▶ handle_frame
                                              │
                                              ├─ source=System ─▶ route_voice=Activate ─▶ pc_asr.activate() ─▶ Win+H ─▶ OS dictation types into focused window
                                              └─ source=Cloud  ─▶ Ignore (board mic + FP-3 cloud ASR own the audio)
```

## Cross-platform strategy
Same as `inject.rs`/`asr.rs`: trait + `#[cfg(windows)]` real impl + non-Windows
stub. No new dependency; `user32` is linked only on the Windows target. The Linux
CI build compiles the stub and the pure router, and `cargo test` exercises the
router + stub.

## Risks / notes
- Win+H requires Windows 10 1709+ with Voice Typing available; on older/again
  it silently no-ops at the OS level — acceptable for the probe (logged).
- Win+H types into the *focused* window; ensuring Kiro has focus is the user's
  responsibility for the probe (route B + FP-4 can target explicitly later).
- Win+H toggles: `voice.stop` handling is optional; leaving the bar open is fine
  for the probe. A future refinement sends Win+H again on stop.
