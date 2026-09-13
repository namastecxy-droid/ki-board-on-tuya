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

## Milestone 4 — per-conversation binding (interaction-design §3.2)

Implements the real "bind a specific conversation to a key" from
`docs/agentic-keyboard-interaction-design.md` §3.2 (K1-K3 = Agent slots): short
press focuses the bound conversation, long press binds the CURRENT conversation
to that slot. This is a STABLE per-conversation binding, not the position-based
`Alt+N` jump (which stays as the empty-slot / fallback behavior).

**Chat focus (client-side, no reload):** the Kiro Crew dashboard is a
history/pushState SPA, so navigating its **address bar** (`Ctrl+L` + type +
Enter) triggers a FULL page reload every time — bad UX. Its OWN in-app
navigation (Command Bar / search) is client-side and does NOT reload. So we
focus a bound conversation by typing its **title** into the client-side Command
Bar (`Ctrl+K` + title + Enter), which navigates in-app with no reload. URL
navigation is kept only as a manual fallback.

**Bind store:** three slots persisted to `config_dir/ak-companion/binds.json`:
`{ slot: 1..3, url: Option<String>, label: Option<String> }`. `label` is the
PRIMARY handle — the conversation TITLE typed into the command bar; `url` is the
optional `/chat/<slug>` manual-navigate fallback. A slot is "bound" when EITHER
is non-empty.

**Long/short split (stateless, from the firmware's own classification):** the
`ak_input_fsm` already emits a one-shot `long` at ~800 ms plus `down`/`up`
(with `held_ms`). The pure router decides without state:
- K1-K3 `Long`                          -> `BindSlot(n)`
- K1-K3 `Up` with `held_ms < LONG_MS`   -> `FocusSlot(n)`   (short tap)
- K1-K3 `Up` with `held_ms >= LONG_MS`  -> `None`           (tail of a long press; bind already fired)
- K1-K3 `Down`                           -> `None`           (wait for release/long, so a long press does NOT focus-then-clobber)

New `ControlAction`s: `FocusSlot(u8)`, `BindSlot(u8)` (both carry the 1-based
slot). They are stateful IO, executed in `lib.rs` (Windows) against the bind
store + controller, not in the pure router.

**Controller (Windows) additions:**
- `capture_current_title() -> Option<String>`: focus, then read the window title
  via `GetWindowTextLengthW`/`GetWindowTextW`. Reads only — no clipboard, no
  navigation, so it cannot reload. Returns None when the title is empty.
- `strip_conversation_title(raw) -> String` (pure): take the segment before the
  first of `" -- "`, `" - "`, `" | "`, `" · "`, or a bare `"·"`, trimmed — drops
  the `" - Kiro Crew - <Browser>"` / `"· Kiro Crew"` app/browser suffix, leaving
  the chat title.
- `navigate_url(url)`: focus, Ctrl+L, type url, Enter — kept as the manual
  fallback only.

**lib.rs execution:**
- `FocusSlot(n)`: look up slot n. Non-empty label -> `command_bar(label)`
  (client-side, no reload). Else url present -> `navigate_url(url)` (manual
  fallback). Else -> `chord(NewChat)` (Alt+Shift+N) per §3.2 "empty slot ->
  create new session".
- `BindSlot(n)`: `capture_current_title()` -> `strip_conversation_title` -> store
  into slot n as the LABEL (url = None) -> emit a `display` frame
  `{state:"bound", text:"K<n> -> <label>"}` so the board LCD confirms the bind
  (M3 renders it). (Unbind-confirm from §3.2 is a later refinement.)

**UI:** Local Control panel shows the 3 bindings (slot -> title/url) with
edit/clear + a "bind current" button mirroring a long press. The edit field is
primarily the conversation TITLE; a `/chat/<slug>` URL is accepted for the
manual fallback.

**Honest limits:** title capture reads whatever the OS reports as the focused
window's title; a window with a non-standard or truncated title binds a
non-matching label. The `held_ms` threshold must match the firmware's
`AK_FSM_LONG_PRESS_MS`.
