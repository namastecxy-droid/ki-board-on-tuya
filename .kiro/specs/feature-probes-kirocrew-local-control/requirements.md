# FP-4b kirocrew-local-control — Requirements

## Context

Feature-probe tier, part of the MVP demo. This probe **supersedes FP-4's Route A**
(`feature-probes-kirocrew-control`), which drove Kiro Crew through the gateway's
`/api/session-control/*` API. Route A was proven **unworkable from the companion**:
those routes identify the caller by an `X-Session-Key` that is only trusted behind
the gateway's unix-socket peer check (`SO_PEERCRED`), and a TCP loopback — including
an SSH tunnel — carries no peer credentials, so every call returns
`caller_unidentified`. Running the gateway locally does **not** unlock it either:
on Windows the unix socket is skipped entirely (TCP-only), so an external
(non-browser, non-MCP) caller can never present a trusted session identity.

FP-4b instead drives Kiro Crew **the way the user's own hands and eyes do**, against
a **locally-running** Kiro Crew (companion and Kiro Crew on the same Windows
machine, no tunnel):

- **Control** = local keyboard injection into the focused Kiro Crew window
  (browser tab or desktop client), using the dashboard's own **Command Bar**
  (`Ctrl+K`, enabled by default) plus text entry and shortcut chords.
- **Status read** = Kiro **agent lifecycle hooks** (`agentSpawn` / `postToolUse` /
  `stop` …) POST live status to a small **localhost HTTP sink** in the companion;
  the companion reflects it to the board as a `display` frame.

Neither path uses `session-control` or the inbound webhook (`/api/hooks/agent`);
the webhook is send-only and cannot read status.

Depends on:
- **FP-5** pc-asr-activate — board `voice`/`key`/`nav` event stream + the
  focused-window text-injection seam (`inject.rs`).
- **FP-2** ble-gatt-link / USB transport — board↔companion link and the existing
  `send_display` down-link.
- **FP-1** agent-display — the LCD renderer to be merged into `firmware/app` so the
  board can show the `display` frame (out of scope here except as the target).

## Scope

In scope (companion + a Kiro-Crew-side hook script + a firmware follow-on):
- Control MVP: focus the Kiro Crew window and drive it by keystrokes.
- Status MVP: receive agent hooks locally and surface per-chat status.
- Reflect status to the board via the existing `display` frame.

Out of scope: `session-control` API, the inbound webhook, remote (tunneled)
operation, and rich remapping UI. The gateway is assumed **local**.

## User stories & acceptance criteria

### R1 — Focus + control the local Kiro Crew window
As a user, the companion can bring the Kiro Crew window to the foreground and
inject keystrokes into it.
- **AC1.1** The companion can locate the Kiro Crew window by title (browser tab or
  desktop client) and set it foreground before injecting.
- **AC1.2** `send_text(t)` types `t` into the focused input.
- **AC1.3** `command_bar(cmd)` sends `Ctrl+K`, types `cmd`, presses `Enter`
  (launcher: new agent request / jump to a session).
- **AC1.4** `chord(keys)` sends a named chord (`Enter`, `Esc`, arrows).
- **AC1.5** No window found → a clear, non-fatal error surfaced in the UI; nothing
  is injected into the wrong window.

### R2 — Board input drives control
As a user, board keys/voice map to control actions.
- **AC2.1** K4 PTT recognized text → `command_bar(text)` (new agent request).
- **AC2.2** K5 → `Enter`; 5-way nav → arrows; K1–K3 → session-jump commands.
- **AC2.3** The mapping is table-driven so it can be edited without touching the
  injection code.

### R3 — Read a specific chat's status via hooks
As a user, I see the running status of the Kiro Crew chat I care about.
- **AC3.1** A hook script, invoked by the agent on `agentSpawn` / `postToolUse` /
  `stop`, reads the hook JSON on STDIN (incl. `KIRO_SESSION_ID`) and POSTs a status
  event to the companion's localhost sink.
- **AC3.2** The companion's sink maps events to states: `running` (agentSpawn),
  `using <tool>` (postToolUse, from `tool_name`), `idle` + reply summary (stop,
  from `assistant_response`).
- **AC3.3** Status carries `KIRO_SESSION_ID`, so the companion can filter/label by
  a specific chat.
- **AC3.4** The sink binds **127.0.0.1 only** and requires a shared token (the
  hook script and the companion agree on it) so no other local process can spoof
  status.

### R4 — Reflect status to the board
- **AC4.1** On a status event, the companion emits a `display` frame
  (`{agent_name,state,text}`) over the active transport via `send_display`.
- **AC4.2** The companion UI (KIRO CREW panel) shows the latest per-chat status.

## Non-goals / honest limits
- Window lookup depends on the window title; control depends on the Command Bar
  (`Ctrl+K`) staying the launcher.
- The hook path requires editing the **local** Kiro Crew agent config (not this
  repo). Cross-machine (tunneled) hook delivery is explicitly out of scope.
- All window/SendInput/HTTP-listener code is Windows-gated: EC2 verifies only the
  cross-platform + type-correct parts (`cargo check`, `tsc`, `vite`); the WinRT/
  Win32 build and live behavior are verified on the user's Windows machine.
