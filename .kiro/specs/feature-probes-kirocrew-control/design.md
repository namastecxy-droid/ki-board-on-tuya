# FP-4 kirocrew-control · Design

## D1 — 控制面路线：**选定 (A) Kiro Crew 本机 API — session-control**（兜底 (B) 键盘注入）

**结论：主路线 = (A)，用网关的 `session-control` API；(B) 键盘/UI 注入降为兜底。**
理由：(A) 能**干净地覆盖全部四操作**（bind/input/send/switch），且复用仪表盘自身的
会话生命周期，被控会话"与人手输入的会话行为完全一致"；(B) 脆弱（依赖窗口聚焦、快捷键、
DOM 稳定），只当 (A) 不可用时兜底。符合 R1.2（(A) 可行则优先）。

### 证据（均可在本机核实）

**E1 — 网关就是本机 loopback HTTP 服务，有 API 面。**
- 仪表盘/网关在 `http://localhost:5476`，`curl http://localhost:5476/api/status` 可测；
  "loopback requests are not exempt from token authentication"。
  证据：`.../kiro_crew/docs/dashboard.md`（Accessing / Remote Access Troubleshooting）。

**E2 — 存在持久会话的控制 API：`/api/session-control/{create,send,stop,read}`。**
- 这组路由正是 `session_create` / `session_stop` / `session_read_message` MCP 工具的
  底层；语义："opening, stopping, and reading ANOTHER live conversation"。
  证据：`.../kiro_crew/dashboard/server.py`（`_STRICT_INTERNAL_API_PATHS` 里
  `"/api/session-control/create|stop|send|read"` 及其注释）；
  handler：`.../kiro_crew/dashboard/handlers/session_control.py`
  （`api_session_control_create/stop/send/read`）；
  业务层：`.../kiro_crew/dashboard/session_control.py`。

**E3 — `create` 可指定 agent；`send` = "输入 + 触发"合一（作为下一轮 turn 运行）。**
- `create_session(..., title=..., agent=...)`："open an empty session in the user's
  sidebar"（handler `api_session_control_create` 读 body 的 `agent`/`title`）。
- `send_to_target(..., message=...)`："delivers a message the target **runs as its
  next turn**"；"An IDLE target runs it …; a BUSY target queues it"。即 send 既是
  input 又是 execute，一步到位。
  证据：`.../kiro_crew/dashboard/session_control.py` 顶部 docstring + 第 1212/1216 行
  `send_to_target` 注释；handler `api_session_control_send`（`message` required）。

**E4 — 鉴权：strict-internal = loopback + `X-Internal-Secret`（取自 `~/.kiro/crew/.local_secret`），无 cookie 回退。**
- `_require_internal()`：仅当 `request["internal_auth"] is True`（常量时间密钥匹配后
  才置位）才放行，否则 `403 internal_secret_required`。
  证据：`session_control.py` handler 的 `_require_internal`；`X-Internal-Secret` 值源
  `~/.kiro/crew/.local_secret`（`token_auth.py` 注释，第 ~2026 行）。

**E5 — 另有 inbound-webhook `POST /api/hooks/agent`（bearer token），但 ephemeral。**
- fire-and-forget，"session is created … then released and reset when the turn ends"；
  `sessionKey` 是**路由键不是句柄**，两次同 key 是"两次无关的 turn，不是一个线程"；
  必须以 `hook:` 前缀（命名空间守卫，禁止把 turn 导入仪表盘/Slack 会话）。
  证据：`.../kiro_crew/docs/inbound-webhooks.md`（fire-and-forget contract / Session
  lifecycle / Security）。
  → **结论**：webhook 能"执行一次"，但**不能 bind/switch 持久会话**（违反 R2/R5），
  故只作 (A) 不可用时的"一次性执行"备选，不是四操作主路线。

**E6 — 辅助只读端点（cookie-authed，非 internal）：`/api/agents`、`/api/agents/installed`、`/api/sessions`。**
- 用于列出可选 agent / 列出会话，供绑定 UI 用。
  证据：`.../kiro_crew/dashboard/routes/agents.py`（`add_get("/api/agents")`、
  `/api/agents/installed`）、`.../dashboard/routes/system.py`（`add_get("/api/sessions")`）。
  注意：这些是 cookie/token 认证（非 `X-Internal-Secret`），companion 若要读取需持
  dashboard token；也可退化为"companion 侧本地读 `~/.kiro/agents/*.json` 列 agent"
  （agent 配置就是本地 JSON 文件，见 `docs` agent-configuration）。

**E7 — 为何不是主选注入 (B)：**
- 命令面板/快捷键切 agent 存在（`/agent <name>` 切 agent；命令面板默认双击 Shift，
  可配 Ctrl+K），但注入只能"把文字送进聚焦窗口 + 敲回车"，对"选定/新建具体 session、
  拿到稳定句柄"无干净接口，且强依赖窗口聚焦与 DOM 稳定。故降级为兜底（R8）。

## D2 — 四操作的实现（基于路线 A：session-control API）

所有请求：`http://127.0.0.1:5476`，头 `X-Internal-Secret: <~/.kiro/crew/.local_secret 的值>`
（companion 启动时读取一次并缓存到内存），`Content-Type: application/json`，并带
`Origin: http://127.0.0.1:5476`（满足 CSRF Origin 检查）。caller 身份用 `X-Session-Key`
标识（`_read_session_key`）——companion 用一个固定的自有 caller key。

| 操作 | 端点 / 方法 | 请求体 / 参数 | 触发语义 |
|------|-------------|----------------|-----------|
| ① bind（选定/新建目标） | `POST /api/session-control/create` | `{"title": "...", "agent": "<agent name>"}` | 新建一个空会话（出现在 sidebar），返回其标识 → companion 缓存为"当前 target"。选定**已有**会话则跳过 create，直接把已知 session id 作为 target（可先经 E6 的 `/api/sessions` 列举供用户选）。 |
| ② input（送入文字） | 与 ③ 合一 | — | session-control 无"只填输入框不执行"的分离动作；input 通过 ③ 的 `message` 承载。 |
| ③ send/execute | `POST /api/session-control/send` | `{"target": "<session id/key>", "message": "<文字>"}` | 目标"作为下一轮 turn 运行"；忙则排队下一轮（R4.2）。消息经 `sanitize_outbound` 并加 `[sent by session … via session_send]` 前缀，永不冒充人手输入。 |
| ④ switch（切目标/agent） | 切会话：改 companion 缓存的 `target`（无需网关调用）；切/新 agent：`POST /api/session-control/create` 指定另一 `agent` | 切会话：本地改指针；新 agent 会话：同 ① | 切"当前会话"是 companion 侧状态切换；"切 agent"= 新建/改绑到目标 agent 的会话（`/agent` 是 in-chat 命令，仅在同一会话内改 agent，session-control 侧以新建带 agent 的会话表达 R5.2）。 |
| 读回执/状态 | `GET /api/session-control/read?target=...&limit=...&since=...` | query | 读目标转录 tail，用于把 agent 回复反馈回板子的 LCD（承接产品交互设计）。 |

**应答语义（R4.3）**：`send` 的错误码来自 `_refusal`：`400`（`invalid_json`/
`message_required`/`target_required`）、`403`（`internal_secret_required` 或授权拒绝）、
`404`（target 不存在）、`409`（冲突/忙）、`429`（限流/容量）。companion 据此给板子回
`ack`（成功）或带原因的错误帧。

**辅助（供绑定 UI）**：`GET /api/agents/installed` 列可选 agent；`GET /api/sessions`
列现有会话（均 cookie/token 认证，E6）。若 companion 不便持 dashboard token，可改为
本地读取 `~/.kiro/agents/*.json` 枚举 agent（配置即本地 JSON）。

## D3 — BLE 逻辑事件（FP-2 帧）→ 控制映射

承接 FP-2：板经 `0x2B10` notify 上行协议 v1 JSONL 帧；companion 解析后按下表驱动 A 路线。
（帧种类以 `shared/protocol/protocol.md` 为准；下表给映射意图。）

| FP-2 逻辑事件 | companion 动作（A 路线调用） | 对应操作 |
|----------------|-------------------------------|-----------|
| `text`（ASR/听写文字帧，payload=识别文本） | `POST /session-control/send {target, message: <text>}` | ②+③ |
| `key`（功能键，如"发送/确认"） | 提交当前累积文本：`send`；或若采用"先攒后发"模型，确认键触发一次 `send` | ③ |
| `nav`（方向：上/下 = 在会话列表移动选择） | 本地移动"候选 target"指针（配合 `read`/`/api/sessions` 列表） | ④ bind 预选 |
| `nav`（确认方向/中键 = 绑定选中会话） | 把选中会话设为 `target`（本地指针）；若"新建"项则 `create` | ①/④ |
| `key`（"切 agent"专用键 / 长按） | `create {agent: <下一个 agent>}` 或在预设 agent 间轮转 | ④（切 agent） |
| `ping`（心跳） | 无控制动作；仅刷新链路存活 | — |
| `ack`（板确认） | 无控制动作 | — |

回流方向（agent → 板 LCD）：companion 周期性 `GET /session-control/read` 取目标会话
tail，把状态/回复摘要经 FP-2 下行 write（`0x2B11`）或后续 LCD probe 显示。

## D4 — 兜底路线 (B) 与已知限制

**兜底 (B)：Win32 键盘/UI 注入（仅当 (A) 不可用时启用，R8.1）**
- input：`SendInput` 逐字符，或剪贴板 + `Ctrl+V` 粘贴进聚焦的仪表盘 Chat 输入框。
- send：注入 `Enter`。
- switch：命令面板（默认**双击 Shift**，可配 **Ctrl+K**）→ 输入会话/命令；切 agent 用
  in-chat 命令 `/agent <name>`（`docs` /agent-swap）。
- bind：注入无法拿到"稳定 session 句柄"，只能操作"当前聚焦窗口的当前会话"，故 bind 在
  (B) 下退化为"确保正确的仪表盘 tab 处于聚焦"。
- 触发条件：companion 读不到 `~/.kiro/crew/.local_secret`（权限/路径不符）、或网关
  以不同 `KIROCREW_HOME` 运行导致 internal-secret 不匹配。

**已知限制**
- **(A) 凭据敏感**：webhook token / internal-secret "等价于对网关主机的 shell 访问"。
  companion 读到的 `.local_secret` 必须只驻内存，绝不写入被 git 跟踪的文件；本地存储
  需 OS 级保护。
- **(A) 可达性未验**：spec 阶段未在 Windows 真机确认 companion 能读 `.local_secret`
  且网关 `KIROCREW_HOME` 一致（记忆：本机数据迁到 `/data/kiro`，网关靠 override 带
  `KIROCREW_HOME`；Windows 路径另论）——列入后续验证任务。
- **webhook 不可作主路线**：ephemeral、`sessionKey` 非句柄、`hook:` 前缀强制、
  fire-and-forget，天然不支持 bind/switch 持久会话（E5）。
- **(B) 脆弱**：强依赖窗口聚焦、快捷键配置、DOM/焦点稳定；无稳定会话句柄。
- **`send` 前缀**：被控消息带 `[sent by session … via session_send]` 前缀且经
  `sanitize_outbound`，这是安全特性（防冒充），companion 需接受这一呈现，不追求"看起来
  像人手输入"。

## D5 — 与 FP-2 / companion 架构的关系

```
板(FP-2 BLE) --0x2B10 notify--> companion(Tauri) --HTTP 127.0.0.1:5476--> Kiro Crew 网关
   逻辑事件(JSONL)                 解析+映射(D3)         session-control API(D2)
        ▲                              │                        │
        └────0x2B11 write / LCD◀───────┴──GET /read (回流)◀──────┘
```

- companion 内：Rust 侧持有 BLE 客户端（承接 FP-2）+ HTTP 客户端（reqwest）调
  session-control；React 侧做绑定/目标选择 UI（列 agent/session）。
- session-control 客户端是 companion 的一个"Kiro Crew driver"模块，兜底 (B) 是同一
  driver 接口的另一实现，按 D4 触发条件切换。
