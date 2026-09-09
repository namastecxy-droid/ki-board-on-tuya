# FP-4 kirocrew-control · Requirements

> 说明：本 spec 为 **研究 + 决策 + 规格** 阶段的产出。本任务**不写 companion 代码**
> （companion 端实现与 Windows 真机验收需要 Windows 机器，列为后续任务）。本文件确定
> "PC companion 如何控制 Kiro Crew"的控制面路线，并把四类控制操作固化为可跟踪的
> 需求与验收项。

## 背景与目标

MVP 北极星：板子（无线，走 BLE，不走 USB 线）把识别到的语音/命令，经 PC companion
**路由进 Kiro Crew** 并驱动其运行。FP-2 已打通"板 → companion"的 BLE GATT 逻辑事件
链路；FP-4 负责链路的**另一半**：companion 拿到逻辑事件后，**如何驱动本机运行的
Kiro Crew**。

Kiro Crew 网关/仪表盘在本机监听 `http://127.0.0.1:5476`（loopback）。companion 是
`repo/companion` 下的 Tauri（Rust + React）应用，与 Kiro Crew 同机运行。

FP-4 必须覆盖**四类控制操作**（硬性要求）：
1. **绑定 agent/对话**（bind）：选定目标 agent + conversation/session。
2. **输入文字**（input）：把 companion 收到的文字送入目标会话。
3. **发送/执行**（send/execute）：提交消息并让 agent 真正跑一轮。
4. **切换 agent/对话**（switch）：改变当前目标 agent 或 conversation/session。

产出目标：
1. 一个明确的**控制面路线决策**（本地 API vs 键盘/UI 注入），带**引用证据**；
2. 覆盖上述四操作的**需求 + 验收**，作为后续 companion 实现的契约；
3. **BLE 逻辑事件 → 控制操作**的映射（承接 FP-2 帧）。

**非目标**：本任务不实现 companion 代码；不做真机验收（需 Windows）；不做语音 ASR
本身（FP-3/FP-5 范畴）；不改 Kiro Crew 网关源码。

## 术语

- **companion**：`repo/companion` 的 Tauri 应用，与 Kiro Crew 同机（本机 Windows）。
- **Kiro Crew 网关**：常驻进程，仪表盘 SPA 在 `http://127.0.0.1:5476`，单一 WebSocket
  承载所有实时事件。
- **会话 / conversation / session**：仪表盘 Chat 的一个 tab = 一个 agent session；
  历史会话可 resume。session 由 `sessionKey` / session id 标识。
- **agent**：agent 配置（`~/.kiro/agents/<name>.json` 或 `.kiro/agents/`），决定
  工具集/权限/模型/系统提示。
- **session-control API**：网关的 `/api/session-control/{create,send,stop,read}` 一组
  路由，即 `session_create`/`session_stop`/`session_read_message` MCP 工具的底层。
- **inbound-webhook**：网关的 `POST /api/hooks/agent`，供外部系统触发**一次性**
  agent turn（ephemeral session，fire-and-forget）。
- **X-Internal-Secret**：strict 内部路由要求的头，其值取自 `~/.kiro/crew/.local_secret`。
- **逻辑事件**：FP-2 定义的协议 v1 JSONL 帧（`key`/`nav`/`text`/`ack`/`ping`…），
  companion 侧解析后得到的抽象事件。

## 需求 (EARS)

### R1 — 控制面路线选定（研究结论）
- R1.1 THE spec SHALL 在两条候选路线间给出**唯一选定路线**并说明理由：
  (A) 调用 Kiro Crew 本机 API；(B) Win32 键盘/UI 注入到聚焦的仪表盘窗口。
- R1.2 IF 路线 (A) 可行（能干净覆盖四操作）, THEN THE spec SHALL 优先选 (A)，并把
  (B) 降级为兜底。
- R1.3 THE 决策 SHALL 引用**具体证据**（端点/方法/鉴权模型或注入受限的原因），
  可在本机文档/源码中核实。

### R2 — 绑定 agent/对话（bind，操作①）
- R2.1 THE companion SHALL 能选定一个**目标会话**（现有 session 或新建）与其 **agent**。
- R2.2 WHEN 目标会话尚不存在, THE companion SHALL 能**新建**一个会话并指定其 agent。
- R2.3 THE companion SHALL 持有该目标的稳定标识（session id / sessionKey），供后续
  input/send/switch 复用。

### R3 — 输入文字（input，操作②）
- R3.1 WHEN companion 收到一条待输入文字, THE companion SHALL 能把该文字定向送入
  **当前绑定的目标会话**。
- R3.2 THE 送入路径 SHALL 保证文字进入目标会话，而非被路由到无关会话（命名空间
  安全）。

### R4 — 发送/执行（send/execute，操作③）
- R4.1 WHEN companion 提交一条消息, THE 目标会话 SHALL 把它作为**下一轮 agent turn**
  运行（agent 真正执行，而不仅仅是把文字放进输入框）。
- R4.2 IF 目标会话正忙, THEN 该消息 SHALL 排队，在其下一轮运行（不丢弃）。
- R4.3 THE companion SHALL 能处理提交后的即时应答语义（接受/冲突/忙/容量），并据此
  给板子回一个 `ack`/错误。

### R5 — 切换 agent/对话（switch，操作④）
- R5.1 THE companion SHALL 能把"当前目标"从一个会话切到**另一个已有会话**。
- R5.2 THE companion SHALL 能触发**切换/新建 agent 会话**（新建指定 agent 的会话，
  或改绑到另一 agent 的会话）。
- R5.3 WHEN 采用兜底路线 (B), THE 切换 SHALL 通过仪表盘命令面板/快捷键实现
  （命令面板默认双击 Shift，可配置为 Ctrl+K；`/agent <name>` 切 agent）。

### R6 — 鉴权与本机可达性
- R6.1 THE 方案 SHALL 明确所选控制面的**鉴权模型**，并说明 companion 如何取得凭据
  （session-control 走 `X-Internal-Secret` = `~/.kiro/crew/.local_secret`；webhook 走
  bearer token；loopback 不豁免 token）。
- R6.2 THE companion 与网关 SHALL 同机经 `127.0.0.1:5476` 通信；方案 SHALL NOT 要求
  把网关对外暴露。
- R6.3 THE spec SHALL 记录该凭据的**安全等级**（等价于对网关主机的 shell 访问），并
  要求凭据不落入被 git 跟踪的文件。

### R7 — BLE 事件 → 控制映射
- R7.1 THE spec SHALL 给出 FP-2 逻辑事件（`text`/`key`/`nav`/…）到四操作的映射表。
- R7.2 THE 映射 SHALL 覆盖：文字帧→input+send；导航/功能键→switch/bind；且对每类给出
  companion 侧应触发的控制调用。

### R8 — 兜底与降级
- R8.1 IF 所选主路线在某环境不可用（如无 `.local_secret` 读权限）, THEN THE spec
  SHALL 定义降级到路线 (B) 的条件与行为。
- R8.2 THE spec SHALL 记录各路线的**已知限制**（如 webhook 的 ephemeral 语义无法
  bind/switch 持久会话；注入依赖窗口聚焦）。

## 验收 (Definition of Done)

> 本 spec 阶段 DoD = **文档层可核验**；companion 代码与 Windows 真机验收为后续任务
> （见 tasks.md T-later）。

- design.md 的 D1 给出**唯一选定路线**，且每条证据均可在本机
  `/data/kiro/.kiro/crew-venv/.../kiro_crew`（源码）或 `.../docs`（文档）中定位。
- design.md 的 D2 对**四操作逐一**给出具体实现（端点 + 方法 + 请求体 + 触发语义），
  且能对应到源码/文档中的真实路由或行为。
- design.md 的 D3 给出 **BLE 事件 → 控制** 映射表，承接 FP-2 帧定义。
- design.md 的 D4 给出兜底路线 (B) 与各路线已知限制。
- requirements 的 R1–R8 均在 design/tasks 中有对应落点。
- **不做** git commit / push。

## 已知限制 / 待办（spec 阶段）

- **凭据可达性未在本机验证**：本任务在 agent 环境下**不读取** `~/.kiro/crew/.local_secret`
  的值（安全策略拦截凭据路径，且读了也无意义）；companion（Windows，用户态）能否读到
  该文件、以及网关是否以同一 `KIROCREW_HOME` 运行，需在 Windows 真机核验（记忆：本机
  数据已迁到 `/data/kiro`，网关靠 systemd override 带 `KIROCREW_HOME`；Windows 侧路径
  另论）。
- **webhook 语义局限**：`/api/hooks/agent` 是 ephemeral、fire-and-forget，天然不支持
  "绑定/切换一个持久会话"，仅可作为"一次性执行"的备选，不能作为四操作主路线。
- **注入路线脆弱性**：路线 (B) 依赖仪表盘窗口聚焦、快捷键配置、DOM/焦点稳定性，作为
  兜底而非主路线。
