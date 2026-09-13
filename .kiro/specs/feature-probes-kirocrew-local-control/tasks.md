# FP-4b kirocrew-local-control — Tasks

Legend: [ ] todo · [x] done · [~] partial/seam

## Milestone 1 — Control MVP (companion, "the hands")
- [x] **T1 — `kirocrew_control.rs` KeyInputBackend (Windows-gated)**
  - `KiroCrewController { focus, send_text, command_bar, chord }` over raw `user32`
    FFI, reusing `inject.rs` VK-injection helpers.
  - `focus()`: enumerate top-level windows, match configurable title substring,
    `SetForegroundWindow`; verify match before any inject (AC1.5).
  - `command_bar(cmd)`: Ctrl+K → type cmd → Enter. `chord(Chord)`: named VK chords.
  - Non-Windows stub compiles + is a no-op/Err.
- [x] **T2 — Pure `ControlRouter` (Linux-tested)**
  - `route_input(&BoardEvent, &ControlCtx) -> ControlAction`, table-driven map
    (K4→CommandBar(text), K5→Enter, nav→arrows, K1–K3→session jump). No IO. Unit tests.
- [x] **T3 — Tauri commands + handle_frame wiring (Windows-gated)**
  - `kc_bind_window`, `kc_send_text`, `kc_command_bar`, `kc_chord`; register them.
  - `handle_frame`: board events → `route_input` → controller; log `[KC-CTL] …`.
- [x] **T4 — UI: KIRO CREW panel → Local Control**
  - Bind-window input + focus indicator; free-text + Send / Command-Bar buttons;
    quick chords (Enter/Esc/arrows). Match ki-board style.

## Milestone 2 — Status read (companion, "the eyes")
- [x] **T5 — Pure `map_hook_event` (Linux-tested)**
  - `HookEvent -> DisplayState` (agentSpawn→running, postToolUse→tool+<tool_name>,
    stop→idle+<assistant_response trunc>). Unit tests, no IO.
- [x] **T6 — `status_sink.rs` localhost HTTP ingress (cross-platform server)**
  - Bind 127.0.0.1:<port> with `tiny_http` (sync, reader-thread + stop-flag);
    require `X-AK-Status-Token`; parse body → `map_hook_event`; keep last-status
    per `session_id`; push to UI + emit `display` frame.
  - `status_sink_start/stop`, `status_token()` commands.
  - Generate a random token; write `{port,token}` to a handoff file
    (`%LOCALAPPDATA%\ak-companion\hook.json` / `~/.config/ak-companion/hook.json`).
- [x] **T7 — `companion --hook` mode + sample agent config (Decision 2)**
  - Hook is a MODE of this binary, not a shell script: `main.rs` runs the hook
    handler and `exit(0)` before Tauri when argv has `--hook`. Reads STDIN hook
    JSON + `$KIRO_SESSION_ID`, reads the handoff file, POSTs to the sink with the
    token; absent sink → silent exit 0. Cross-platform (reqwest blocking).
  - Document the `hooks` snippet the user adds to their LOCAL agent config
    (in the Status panel hint + this design doc).
- [x] **T8 — UI: Status area**
  - Start/stop sink, show token + the exact `companion --hook` command and an
    example `hooks` JSON, live per-session status list (`kc-status` event).

## Milestone 3 — Reflect to the board (firmware follow-on)
- [x] **T9 — `firmware/app` renders the `display` frame**
  - Merge the FP-1 LCD renderer into `firmware/app`; add a `display`-frame handler
    (agent_name/state/text). Build both UART + BLE profiles. (Separate work item.)
  - DONE: rendered via the lightweight shared ak_gfx + ak_statuslcd (no LVGL,
    consistent with FP-2/FP-3) rather than FP-1's LVGL sprite UI. display frame
    -> ak_render_status(agent,state,text): title bar colored by state
    (running=green/tool=orange/idle=gray/received=cyan) + agent/state lines +
    wrapped ASCII text. Both UART + BLE profiles BUILD SUCCESS.

## Milestone 4 — per-key jump-to-chat number (§3.2)
Model: each of K1-K3 binds to a chat NUMBER (1..9). Short press -> `Alt+<number>`
(Kiro Crew "Jump to chat N", client-side, NO reload). The number is configurable
per key, persisted in `binds.json` as `{"chats":[1,2,3]}`. The earlier
title-capture / command-bar-by-title / long-press-bind design was REMOVED per
user decision (see design.md M4 "Decision").
- [x] **T10 — deterministic shortcut foundation** (Alt+N/Prev/Next/FocusInput/
  NewChat chords + Compose for K4 voice). DONE (commit ab2ef24).
- [x] **T11 — pure router: K1-K3 Down -> Alt+configured-number**
  - K1-K3 `Down` -> `Chord(JumpChat(n))` where n = `ctx.jump_chats[idx]` (1..9);
    `None` when the index is missing or n is out of 1..9. K1-K3 `Long`/`Up` ->
    `None` (jump fires on Down only). `FocusSlot`/`BindSlot` + the long/short
    split REMOVED. Unit tests assert the configured-number jump and the None edges.
- [x] **T12 — bind store: 3 chat NUMBERS** (`BindStore{chats:Vec<u8>}`, default
    `[1,2,3]`, `config_dir/ak-companion/binds.json` `{"chats":[..]}`) + load/save,
    get/set(clamp 1..9)/clear(reset to default), normalize-to-3 tests. `Slot{url,
    label}` + `parse_chat_slug` REMOVED.
- [x] **T13 — controller cleanup (Windows)**
  - REMOVED `capture_current_title`, `strip_conversation_title` (+ tests),
    `navigate_url`, and the now-unused `VK_L`/`ctrl_tap` helpers. Kept
    `JumpChat`/`PrevChat`/`NextChat`/`FocusInput`/`NewChat` + `inject_chord`,
    `command_bar` (still a UI button), `compose`, `send_text`, `chord`, `focus`.
    Stub + facade dropped the removed methods. (arboard was already absent.)
- [x] **T14 — lib.rs execution + commands**
  - Inner loads the 3 numbers from `BindStore` at startup and seeds
    `kc_router.ctx.jump_chats`. exec: all actions via `kc_controller.apply` (no
    `FocusSlot`/`BindSlot` special-casing). `kc_bind_get() -> Vec<u8>`;
    `kc_bind_set(slot, number)` validates 1..9, saves, and updates the live
    router ctx; `kc_bind_clear(slot)` resets to the slot default + updates ctx.
    `kc_bind_current` REMOVED. `describe_control_action` dropped the slot arms.
- [x] **T15 — UI: bindings panel** per key K1/K2/K3 a NUMBER selector (1..9)
    reading `K<n> -> Alt+<n> (jump to chat n)`; loaded via `kc_bind_get` on mount;
    on change calls `kc_bind_set(slot, number)`; "Reset to <n>" -> `kc_bind_clear`.
    Neobrutalist style + existing invoke pattern.

## Verification gates
- Linux each milestone: `cargo check` + `cargo test` (T2, T5, T11, T12 pure tests) +
  `tsc --noEmit` + `vite build`.
- Windows (user): `tauri build`; live focus/inject; hook POST round-trip; board LCD;
  K1-K3 short press jumps to the configured chat number (`Alt+N`, no reload).

## Notes / decisions
- Supersedes FP-4 Route A (`session-control`, `caller_unidentified`) — see
  requirements Context. Route A code is left in place but not the control path.
- Webhook (`/api/hooks/agent`) intentionally unused: send-only, no status read.
- Assumes a **local** gateway (no tunnel); remote hook delivery is out of scope.
