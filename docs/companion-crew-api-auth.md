# Companion → Kiro Crew 本地 API 鉴权 (feat/companion-crew-api)

调研基准：安装态 gateway 包 `kiro_crew` (KIROCREW_HOME=/data/kiro/.kiro/crew)。
目标：Companion(Tauri，同机)通过本地 HTTP+WS API 控制 Crew 并同步 chat 状态，
保留现有 Hook 机制作 fallback。全程只读 gateway 源码，未改 gateway。

## 最终实现选择（2026-09-17 Windows 实测后）

采用 gateway 官方本地桌面入口：

1. 每次启动/重连读取 `<KIROCREW_HOME>/.local_secret`（默认 `~/.kiro/crew/.local_secret`）。
2. `GET /api/token/local`，请求头 `X-Local-Secret`，换取短期 owner token。
3. REST 用端口隔离 cookie `mc_token_<port>=<token>`；WebSocket 用
   `/api/ws?token=<token>` + 同源 `Origin`。
4. gateway 重启会轮换 `.local_secret`，客户端重连时重新读文件并换 token，自愈。

这是 `dashboard/handlers/core.py:2504 api_token_local` 明确标注给
“Electron / local apps”的 bootstrap，不需要把硬件 Companion 注册成 App，也不受
App Token 的 `permissions.api` scope 限制。现有 Hook sink/SendInput 保留作 fallback。

Windows 真机已验证：无凭据 `/api/chat/slots` 403；`X-Internal-Secret` 读 slots 200；
真实 slot key `POST /api/chat` 200；App Secret 换 token 200。正式实现改用上述
`X-Local-Secret -> owner token`，因为它同时覆盖 REST 与 `/api/ws`。

## 网关绑定
- 默认 `127.0.0.1:5476`（`dashboard/urls.py` `_DEFAULT_PORT=5476`，`is_local_only` 恒 True）。
- 端口可被 env `KIROCREW_PORT` 覆盖；绑定地址可被 `KIROCREW_BIND` 覆盖（默认仅 loopback）。

## 鉴权：loopback 不再自动放行
`dashboard/token_auth.py` 中间件明确：所有请求都要凭据（防 socat/ssh -R 把远程流量伪装成 127.0.0.1）。
三条可用路径，推荐 App Token。

### 方式 A：App Token（推荐，网关正规入口）
1. 安装/注册一个 app（app 名如 `ak-companion`），gateway 在 app 目录写
   `~/.kiro/crew/apps/<name>/.app_secret`（0600）。
   - 参考内置范例 `apps/builtins/crew_companion/`（注意它是无关的 pet/reminder app，
     只借鉴其 manifest + backend 结构，不是本硬件 companion）。
2. 换 token：`POST /api/apps/<name>/token`，请求头 `X-App-Secret: <secret 内容>`。
   - 处理器 `dashboard/handlers/core.py:2817 api_app_token`，路由注册 `routes/system.py:173`。
   - 该端点在 token 中间件里被 bypass（regex `^/api/apps/[a-z0-9][a-z0-9_-]*/token$` + POST）。
   - 成功返回 `{"token": "<payload>.<sig>"}`，payload 带 `app=<name>` 声明。
   - 缺头/密钥错 → 403 `{"error":...}`。
3. 之后每个请求带该 token（`?token=` 或 cookie `mc_token_<port>`）。

**scope（deny-by-default，CWE-269）**：app token 只能访问
  - 自己命名空间 `/apps/<name>/*`、`/api/apps/<name>/*`（`_app_owns_path`）
  - 隐式放行 `/api/ws`（WS 层再按 `permissions.events` 过滤事件）
  - manifest `permissions.api` 显式声明的前缀（`_api_pattern_matches`）
  - `/api/notifications/push`
其余一律 403（`_enforce_app_scope`）。

**因此 manifest 必须声明**（`app.json` → `permissions`）：
```json
"permissions": {
  "api": ["/api/chat", "/api/chat/slots"],
  "events": ["...需要订阅的 WS 事件..."],
  "network": true
}
```
- `_api_pattern_matches` 前缀边界匹配：`"/api/chat"` 覆盖 `/api/chat` 和 `/api/chat/slots`
  （但不覆盖 `/api/chatx`）。支持结尾 `/*`、`*` 通配。
- `permissions.api` 有 30s TTL 缓存（`_app_perms_cache`），enable/disable/update 后自愈。

### 方式 B：Internal Secret（loopback 直连，简单）
- loopback 请求带头 `X-Internal-Secret: <~/.kiro/crew/.local_secret 内容>`
  可访问 internal/mixed-internal 路径（`/api/chat` 属 mixed-internal）。
- 适合 companion 能读该文件的场景，绕过 app 注册流程。

### 方式 C：读签名密钥自签（不推荐）
- 同 uid 进程能读 `/data/kiro/.kiro/crew/token_signing.key`(0600) 自算 HMAC。
- 能用但非预期用法，属同 uid 文件信任模型的副作用，不要走。

## 控制端点（REST）
- `GET  /api/chat/slots` → 列 chat，含稳定 `slot key`。
- `GET  /api/chat/slots/{slot}` → 某 chat 消息+状态。
- `POST /api/chat` body `{message, slot, agent, meta}` → 发消息到指定 slot（按 key 路由，不碰窗口焦点）。
- `POST /api/chat/slots/{slot}/stop|interrupt|continue|reset-conversation`、`POST /api/chat/slots`(新建)、`.../agent`(切 agent)。
- slot key 跨重启稳定（== transcript 文件名去 `dashboard_` 前缀），取代 Alt+N 位置猜测。

## 同步（WebSocket 优先）
- `GET /api/ws`（同源 + app token，强制 Origin 校验，heartbeat=30）。
- 连上即推全量 `slots`；持续推 `chat_message` / `slots` / `dashboard`(5s) / `slot_title` / `refresh`。
- 客户端可发 `subscribe_subagents` / `subscribe_logs`。
- 每 slot 实时字段：`running / stopping / pending_approval / waiting_for_input / needs_input / subagents_running / last_message` —— 推 AK LCD 的状态源。

## 与 Hook 的关系
- 互补不冲突。Hook = agent 主动 push 生命周期(回板)；API = companion 主动 pull + WS 订阅。
- 新分支加 API 通道，不删 Hook。路由优先级：API 可用走 API，连不上自动降级 Hook + SendInput。

## 动手前唯一待验证
- app 如何"安装/注册"以让 gateway 写出 `.app_secret`（`apps/manager.py:752 write_app_secret`
  在 register/install 流程里调用）——需确认硬件 companion 能否走这条注册路，
  否则退方式 B（Internal Secret）更省事。
