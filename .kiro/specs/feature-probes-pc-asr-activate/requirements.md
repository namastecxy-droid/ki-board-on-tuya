# FP-5 pc-asr-activate — Requirements

## Context

Feature-probe tier (post-bringup single-function verification), part of the MVP
demo. MVP requirement **(4)**: besides the board's own mic → Tuya cloud ASR
(FP-3), the system must also let the user **one-key activate the PC's own ASR**
(Windows system dictation), so recognized speech is typed straight into the
focused window (e.g. the Kiro window / Kiro Crew composer).

This probe is **companion-side** (Tauri/Rust). The firmware is unchanged: the
board already emits logical `voice.start` / `voice.stop` events (K4 PTT) over the
FP-2 BLE link or the USB transport. FP-5 decides, on the PC, what a voice event
*does* based on the active **voice source**.

Depends on:
- **FP-2** ble-gatt-link — board→companion event stream (`voice`, `key`, `nav`).
- **FP-4** kirocrew-control (route A) — for the follow-on where recognized text
  is routed into Kiro Crew; FP-5 itself only has to get text into the focused
  window, which the OS dictation does natively.

## Voice-source model

The companion holds a **voice source** setting with two values:
- `cloud` — the board records on its own mic and does Tuya cloud ASR (FP-3);
  the companion does nothing on `voice.start` except reflect state.
- `system` — the **PC's own ASR** handles it: on `voice.start` the companion
  activates Windows dictation so the OS types recognized speech into the focused
  app. This is the FP-5 path.

The setting is user-selectable in the companion UI and mirrored to the board via
the existing `config{voice_engine}` frame (so the board LCD can show which source
is active). Default for this probe: `system`.

## User stories & acceptance criteria

### R1 — One-key activation of Windows dictation
As a user, holding the board's voice key (K4) while voice source = `system`
activates the PC's built-in dictation.
- **AC1.1** On an inbound `voice.start` frame with source=`system`, the companion
  invokes the OS dictation activator (route A: Win+H).
- **AC1.2** With source=`cloud`, a `voice.start` does **not** activate PC
  dictation (the board owns the mic); the companion only logs/relays.
- **AC1.3** Activation is idempotent-safe: a second `voice.start` while already
  dictating must not crash or wedge (Win+H toggles the dictation bar).

### R2 — Text lands in the focused window
As a user, my dictated speech is typed into whatever window has focus.
- **AC2.1** Route A relies on the OS: after Win+H, Windows types into the focused
  control. The companion does not need to inject the text itself.
- **AC2.2** (Route B, alternative) If the companion runs its own recognizer
  (`asr.rs` WinRT), it injects the final text via `inject.rs` `type_text`, and
  MAY forward it to Kiro Crew (FP-4). Route B is out of scope for the probe's
  minimum pass but the seam must exist.

### R3 — Cross-platform build, Windows-gated behavior
As a developer, the code compiles on the Linux CI host.
- **AC3.1** The activator is a trait with a real `#[cfg(windows)]` SendInput impl
  and a non-Windows stub, mirroring `inject.rs` / `asr.rs`.
- **AC3.2** `cargo test` + `cargo clippy` pass on Linux; the Windows path is
  cfg-gated and does not pull new crates into the Linux build.
- **AC3.3** A unit test asserts the source-router logic (voice.start + system →
  activate; + cloud → no activate) on the pure, host-independent seam.

### R4 — Observability
- **AC4.1** Every activation attempt and its result is logged to the companion
  log stream and emitted as a UI event.
- **AC4.2** The active voice source is queryable (`get_status`) and settable
  (`set_voice_source`) from the UI.

## Non-goals
- Real Windows on-hardware verification of Win+H (user's Windows machine).
- Full WinRT continuous recognition (route B) — seam only.
- Routing recognized text into Kiro Crew (that is FP-4's job; FP-5 exposes the
  hook).
- Any firmware change.

## Verification
- Linux: `cargo test` (router unit tests) + `cargo clippy` green.
- Windows (user): source=`system`, hold K4 → Windows dictation bar appears and
  types into the focused window; source=`cloud` → no PC dictation.
