# FP-4 kirocrew-control · Tasks

> 本 spec 阶段 = **研究 + 决策 + 规格**（本任务完成 T1–T3）。companion 代码实现与
> Windows 真机验收标 **T-later**（需 Windows 机器，非本任务）。
> 勾选规则：`[ ]` 未开始 / `[~]` 进行中 / `[x]` 完成。

## 本任务范围（spec 阶段）

- [x] **T1 — 研究控制面并选路（R1/R6）** ✅ 2026-09-09
  - 用 `introspect` + 本机 `.../kiro_crew/docs` + 源码核实两条路线。
  - 结论：主路线 **(A) session-control API**；(B) 键盘注入兜底。
  - 关键证据锚点（见 design D1 E1–E7）：
    - `dashboard/server.py` `_STRICT_INTERNAL_API_PATHS`（session-control 四路由）
    - `dashboard/handlers/session_control.py`（create/send/stop/read + `_require_internal`）
    - `dashboard/session_control.py`（`send` = 作为下一轮 turn 运行；create 带 agent）
    - `docs/inbound-webhooks.md`（webhook ephemeral，不能作主路线）
    - `docs/dashboard.md`（127.0.0.1:5476，loopback 不豁免 token）
    - `routes/agents.py` / `routes/system.py`（`/api/agents`、`/api/sessions` 只读辅助）

- [x] **T2 — 写 requirements.md（四操作 EARS + 验收）** ✅ 2026-09-09
  - R1–R8 覆盖：选路 / bind / input / send / switch / 鉴权 / BLE 映射 / 兜底。

- [x] **T3 — 写 design.md（D1 选路+证据 / D2 四操作实现 / D3 BLE 映射 / D4 兜底）** ✅ 2026-09-09
  - D2 逐操作给端点+方法+请求体+触发语义；D3 给 FP-2 帧→控制映射表。

## 后续任务（companion 实现 + Windows 验收，非本任务）

- [ ] **T-later-1 — 校验凭据可达性（Windows 真机）**
  - 确认 companion（用户态）能读 `~/.kiro/crew/.local_secret`；确认网关运行的
    `KIROCREW_HOME` 与该文件一致（本机数据在 `/data/kiro`，网关靠 override）。
  - 若不可达 → 走兜底 (B)（D4 触发条件）。

- [x] **T-later-2 — companion "Kiro Crew driver"（Rust，reqwest）** ✅ 2026-09-12
  - `companion/src-tauri/src/kirocrew.rs`：`KiroCrewClient`（reqwest blocking，
    pinned `=0.13.4` + `rustls`，无 openssl，Linux 可编）。
    - `create_session(title,agent)->String` / `send(target,message)` /
      `read(target)->String` / `stop(target)`，每次调用带
      `X-Internal-Secret`（`.local_secret` 运行时读，仅驻内存，R6.3）+
      `Origin: http://127.0.0.1:5476`（CSRF）。
    - 纯 helper：`resolve_secret_path`（尊重 `KIROCREW_HOME`，否则
      `~/.kiro/crew`）、`Op::url` + `create/send/read/stop_body`、
      `parse_created_id` / `parse_reply` —— 全部无网络，单测覆盖。
  - `lib.rs`：`#[cfg(windows)]` app 模块内新增 Tauri 命令
    `kc_create/kc_send/kc_read/kc_stop`（已注册进 `invoke_handler`），
    `Inner.kc_target` 缓存当前绑定会话；`handle_frame` 把板端 `macro`
    文本帧经 `forward_asr_to_session` → `send()` 转发到绑定会话（D3：text→send）。
  - 平台中立模块保持在 Windows 门控之外：Linux `cargo fmt/clippy/test` 通过
    （clippy `-D warnings` 干净；41 tests passed，含 13 个新 `kirocrew` 单测）。
  - 错误码映射（400/403/404/409/429）→ 由 `post()` 透传为可读错误串，供上层回板
    `ack`/错误帧（R4.3）。**注**：Windows 真机端到端与凭据可达性仍待 T-later-1/6。

- [ ] **T-later-3 — 绑定/目标选择 UI（React）**
  - 列 agent（`/api/agents/installed` 或本地读 `~/.kiro/agents/*.json`）+ 列会话
    （`/api/sessions`）；维护"当前 target"指针（R2/R5）。

- [ ] **T-later-4 — BLE 事件 → 控制映射接线（承接 FP-2）**
  - 把 FP-2 解析出的 `text`/`key`/`nav` 帧按 design D3 表驱动 driver。

- [ ] **T-later-5 — 兜底注入实现 (B)**
  - Win32 `SendInput`/剪贴板粘贴 + `Enter`；命令面板（双击 Shift / Ctrl+K）切换；
    `/agent <name>` 切 agent。按 D4 触发条件降级。

- [ ] **T-later-6 — 端到端真机验收（Windows）**
  - 板说话 → ASR 文字 → BLE → companion → session-control `send` → Kiro Crew 跑一轮
    → `read` 回流到板/LCD。四操作各走一遍：bind / input / send / switch。

## 依赖顺序
T1 → T2 → T3（本任务，已完成）。
T-later-1 → T-later-2 → {T-later-3, T-later-4} → T-later-5 → T-later-6。
T-later-1（凭据可达性）是关键：决定主路线 (A) 是否成立或需兜底 (B)。
