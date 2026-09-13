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

### `status_sink.rs` — localhost status ingress (cross-platform server, pure mapping)
- A tiny **synchronous** HTTP listener bound to **127.0.0.1:<port>** using the
  `tiny_http` crate (pinned `=0.12.0`) on a background thread — mirrors the
  `transport::usb_serial` reader-thread + stop-flag lifecycle; the app stays
  sync (no new async runtime). Requires header `X-AK-Status-Token` matching a
  token the companion generates at sink start (via `getrandom`, 32 hex chars)
  and writes to the handoff file. A wrong/absent token → `401`, callback not
  fired.
- The server + handoff + `--hook` client are **cross-platform** (no
  `#[cfg(windows)]`), so `cargo check` / `cargo test` build them on Linux. Only
  the callback that emits a `display` frame (needs the Tauri transport) is
  Windows-gated, in `lib.rs::app`.
- Body = the slimmed `{event, session_id, tool_name?, assistant_response?}`
  (`HookEvent`, tolerant to Kiro's `hook_event_name`/`sessionId`/`toolName`
  spellings via serde aliases). A **pure** `map_hook_event(&HookEvent) ->
  DisplayState` does the mapping (unit-tested, one test per branch):
  - `agentSpawn` → `{state:"running", text:"agent started"}`
  - `postToolUse` → `{state:"tool", text:"using <tool_name>"}` (`using tool` when absent)
  - `stop` → `{state:"idle", text:<assistant_response flattened+truncated 40ch>}` (`done` when empty)
  - `userPromptSubmit` → `{state:"received", text:"prompt received"}`
  - anything else → `{state:"running", text:<event>}`
- On each event: keep last-status per `session_id` (`Inner.kc_status`); emit a
  `display` frame; push a `kc-status` UI event `{session_id,agent_name,state,text}`.

### `lib.rs` wiring (Windows-gated app module)
- Tauri commands: `kc_bind_window(title)`, `kc_send_text`, `kc_command_bar`,
  `kc_chord`, `status_sink_start(port)` / `status_sink_stop`, `status_token()`.
- `handle_frame`: board events → `route_input` → `KiroCrewController`.
- Status events → `map_hook_event` → `write_board(display_payload)` (reuse the
  existing `send_display`).

## Kiro-Crew-side hook: `companion --hook` mode (Decision 2)

**Decision 2 (supersedes the earlier `scripts/ak-hook-status.(ps1|sh)` plan):**
the Kiro agent hook is a **mode of the companion binary itself**, invoked as
`companion --hook` — NOT a separate shell script. This removes the shell-vs-
PowerShell portability split and keeps one artifact to ship.

Flow:
- **GUI / sink side.** When the user starts the sink (`status_sink_start`), the
  companion binds `127.0.0.1:<port>`, generates a random token, and writes a
  **handoff file** `{port, token}` to a stable location:
  - Windows: `%LOCALAPPDATA%\ak-companion\hook.json`
  - else: `~/.config/ak-companion/hook.json`
  (resolved via `dirs::config_dir()`, `HOME/.config` fallback).
- **Hook side (`companion --hook`).** `main.rs` checks argv **before** launching
  Tauri: if `--hook` is present it runs the hook handler and `exit(0)` without
  starting the GUI. The handler:
  1. reads the Kiro hook JSON from **STDIN** (tolerant: empty/unparseable →
     default event);
  2. fills `session_id` from `$KIRO_SESSION_ID` when the body omitted it;
  3. reads the handoff file for `{port, token}` — **absent → silent `exit 0`**
     (no sink running is not an error, must never fail the agent turn);
  4. POSTs the slimmed event to `http://127.0.0.1:<port>/status` with header
     `X-AK-Status-Token: <token>`, **short 800ms timeout**, best-effort;
  5. exits 0 fast.
- This path is **cross-platform** (no `#[cfg(windows)]`, reuses `reqwest`
  blocking) so it `cargo check`s / `cargo test`s on the Linux CI host.

Sample agent config snippet (user applies to their LOCAL agent
`~/.kiro/agents/<name>.json`; the token lives in the handoff file, not here):
```json
{ "hooks": {
    "agentSpawn":  [{"command":"\"C:/path/to/companion.exe\" --hook"}],
    "postToolUse": [{"command":"\"C:/path/to/companion.exe\" --hook"}],
    "stop":        [{"command":"\"C:/path/to/companion.exe\" --hook"}]
} }
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
