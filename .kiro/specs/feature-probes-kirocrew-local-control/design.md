# FP-4b kirocrew-local-control — Design

## Overview

Two independent planes, both against a **local** Kiro Crew, unified behind one
companion module. Neither touches `session-control` or the webhook.

```
 CONTROL (companion -> Kiro Crew, "the hands")
   board key/voice ──▶ ControlRouter ──▶ KeyInputBackend ──▶ focus window + SendInput
                                            send_text / command_bar(Ctrl+K) / chord

 STATUS  (Kiro Crew -> companion -> board, "the eyes")
   agent hook ──POST 127.0.0.1──▶ StatusSink ──▶ display frame ──▶ send_display ──▶ board LCD
   (agentSpawn/postToolUse/stop, carries KIRO_SESSION_ID)
```

## Companion modules (Rust / Tauri)

### `kirocrew_control.rs` — KeyInputBackend (Windows-gated)
Reuses the raw `user32` FFI pattern already in `inject.rs` (no new crate).
```rust
pub struct KiroCrewController { hwnd: Option<isize>, title_match: String }
impl KiroCrewController {
    pub fn focus(&mut self) -> Result<(), String>;      // FindWindow by title substring + SetForegroundWindow
    pub fn send_text(&mut self, t: &str) -> Result<(), String>;   // focus, then inject.type_text
    pub fn command_bar(&mut self, cmd: &str) -> Result<(), String>; // focus, Ctrl+K, type cmd, Enter
    pub fn chord(&mut self, keys: &Chord) -> Result<(), String>;  // focus, send a named chord
}
```
- `focus()` enumerates top-level windows, matches a configurable title substring
  (default candidates: "Kiro Crew", "Agentic" — configurable), `SetForegroundWindow`.
- `command_bar`: VK sequence LCTRL↓ K↓ K↑ LCTRL↑ → `type_text(cmd)` → RETURN↓↑.
- `chord`: a small `enum Chord { Enter, Esc, Up, Down, Left, Right, CtrlK }` → VK.
- Non-Windows: stub returning `Err("control: windows only")`, `focus` a no-op — so
  the module still compiles and unit-tests on Linux.

### `ControlRouter` (pure, unit-tested on Linux)
```rust
enum ControlAction { CommandBar(String), Chord(Chord), SendText(String), None }
fn route_input(ev: &BoardEvent, ctx: &ControlCtx) -> ControlAction
```
Table-driven map (R2.3): K4+recognized-text→CommandBar; K5→Chord(Enter);
nav→arrows; K1–K3→CommandBar("<session name>"). No IO — testable.

### `status_sink.rs` — localhost status ingress (Windows-gated runtime, pure mapping testable)
- A tiny HTTP listener bound to **127.0.0.1:<port>** (reuse the app's async runtime;
  a minimal `tiny_http`-style loop or `tauri`'s bundled hyper — prefer a dependency
  already present; otherwise `tiny_http`). Requires header `X-AK-Status-Token`
  matching a token the companion generated at startup and the hook script reads.
- Body = the hook event JSON (or a slimmed `{event, session_id, tool_name?,
  assistant_response?}`). A **pure** `map_hook_event(&HookEvent) -> DisplayState`
  does the mapping (unit-tested):
  - `agentSpawn` → `{state:"running", text:"agent started"}`
  - `postToolUse` → `{state:"tool", text:"using <tool_name>"}`
  - `stop` → `{state:"idle", text:<assistant_response truncated>}`
  - `userPromptSubmit`/`preToolUse` → optional finer states.
- On each event: keep last-status per `session_id`; emit a `display` frame for the
  bound/active session; push to the UI.

### `lib.rs` wiring (Windows-gated app module)
- Tauri commands: `kc_bind_window(title)`, `kc_send_text`, `kc_command_bar`,
  `kc_chord`, `status_sink_start(port)` / `status_sink_stop`, `status_token()`.
- `handle_frame`: board events → `route_input` → `KiroCrewController`.
- Status events → `map_hook_event` → `write_board(display_payload)` (reuse the
  existing `send_display`).

## Kiro-Crew-side hook script (not this repo's runtime; shipped under `scripts/`)
`scripts/ak-hook-status.(ps1|sh)`:
- Reads hook JSON from STDIN, extracts `hook_event_name`, `tool_name`,
  `assistant_response`, and `$KIRO_SESSION_ID`.
- POSTs `{event,session_id,tool_name?,assistant_response?}` to
  `http://127.0.0.1:<port>/status` with `X-AK-Status-Token`.
- Exits 0 fast (never blocks the agent turn; short timeout).

Sample agent config snippet (documented in the spec, applied by the user to their
LOCAL agent `~/.kiro/agents/<name>.json`):
```json
{ "hooks": { "agentSpawn": [{"command":"…/ak-hook-status.ps1"}],
             "postToolUse":[{"command":"…/ak-hook-status.ps1"}],
             "stop":       [{"command":"…/ak-hook-status.ps1"}] } }
```

## Protocol
- Reuses the existing `display` frame `{v,type:"display",payload:{agent_name,state,text}}`.
- No new board→PC frame; control is out-of-band (keystrokes to Kiro Crew, not the board).
- Optional: extend `display.state` enum documentation with `running|tool|idle`.

## Firmware follow-on (separate task, target only)
`firmware/app` gains the FP-1 LCD renderer and a `display`-frame handler so the
board actually shows the status. Tracked as milestone 3; not built here.

## UI (main.tsx)
KIRO CREW panel becomes **Local Control**:
- "Bind window" (title input + bind), Focus indicator.
- Free-text + Send / Command-Bar buttons; quick chords (Enter/Esc/arrows).
- A **Status** area: start/stop the sink, show the token to paste into the hook,
  and a live per-session status list (session id · state · text).

## Verification
- Linux: `cargo check`, `cargo test` (ControlRouter + map_hook_event pure tests),
  `tsc --noEmit`, `vite build`.
- Windows (user): `tauri build`, live focus/inject against Kiro Crew, hook POST
  round-trip, `display` on the board.

## Security notes
- Status sink binds 127.0.0.1 only + shared-token header (AC3.4): a network-exposed
  unauthenticated listener would let any local process spoof board status.
- The controller injects into whatever window matches the title; `focus()` verifies
  the match before injecting (AC1.5) to avoid typing into the wrong app.
