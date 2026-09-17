# Windows 本机鉴权可行性验证 (feat/companion-crew-api)

在你的 **Windows 机器上**（companion 和 Kiro Crew 客户端所在的那台）跑，验证
本地 API 鉴权能不能打通。全程只读取本机自己的凭据，不外泄。

先决条件：Kiro Crew gateway 正在这台机上运行（仪表盘能打开）。
PowerShell 5+ 自带 curl 别名指向 Invoke-WebRequest，下面直接用原生 cmdlet 更稳。

---


## 最终统一鉴权：`.local_secret` 换 owner token（REST + WS）

正式 Companion 实现使用 gateway 专为 Electron / local apps 提供的
`GET /api/token/local`，而不是把 `.local_secret` 长期当每个 REST 请求的凭据：

```powershell
$secret = (Get-Content "$home_crew\.local_secret" -Raw).Trim()
$r = Invoke-WebRequest -Uri "$base/api/token/local" `
     -Headers @{ "X-Local-Secret" = $secret } -UseBasicParsing
$tokenPayload = $r.Content | ConvertFrom-Json
$token = $tokenPayload.token
"local token -> $($r.StatusCode), len=$($token.Length), expires=$($tokenPayload.expires_in)s"

# 用端口隔离 cookie 验证 REST
$cookie = "mc_token_$port=$token"
$r2 = Invoke-WebRequest -Uri "$base/api/chat/slots" `
      -Headers @{ Cookie = $cookie } -UseBasicParsing
"token cookie /slots -> $($r2.StatusCode), chats=$(($r2.Content | ConvertFrom-Json).Count)"
```

预期两步都是 200。该 owner token 同时用于 `/api/ws?token=...`；Companion 会自动
设置 `Origin: $base`、处理 Ping/Pong、解析 `slots/chat_message/dashboard`，断线后
指数退避并重新读取已轮换的 `.local_secret`。

## 步骤 0：确定 KIROCREW_HOME 和端口

Windows 上默认 home 是 `~/.kiro/crew`（即 `$env:USERPROFILE\.kiro\crew`），
除非你设了 `KIROCREW_HOME`。端口默认 5476，可被 `KIROCREW_PORT` 覆盖。

```powershell
$home_crew = if ($env:KIROCREW_HOME) { $env:KIROCREW_HOME } else { "$env:USERPROFILE\.kiro\crew" }
$port = if ($env:KIROCREW_PORT) { $env:KIROCREW_PORT } else { 5476 }
$base = "http://127.0.0.1:$port"
Write-Host "home=$home_crew  base=$base"

# 网关活着吗（health 无需鉴权，应 200）
(Invoke-WebRequest -Uri "$base/api/health" -UseBasicParsing).StatusCode
```

---

## 方式 B：Internal Secret（推荐先测，最省事）

`.local_secret` 每次网关启动重写（32 hex），位于 `<KIROCREW_HOME>\.local_secret`。
loopback 请求带 `X-Internal-Secret` 头即可访问 `/api/chat`、`/api/chat/slots`
（`/api/chat` 在 gateway 的 `_MIXED_INTERNAL_API_PATHS` 集合里，已核实）。

> 注意：`/api/chat/slots`（列表）严格来说不在 mixed-internal 前缀里，只有
> `/api/chat` 前缀被覆盖。所以方式 B 用来测 **发消息** `POST /api/chat` 最直接；
> 列表读取如果 403，就说明列表端点需要 cookie/token 而非 internal-secret——
> 这正是要在真机上测出来的关键点，别预设结论。

```powershell
$secret = (Get-Content "$home_crew\.local_secret" -Raw).Trim()
$hdr = @{ "X-Internal-Secret" = $secret }

# 1) 无凭据调 /api/chat/slots —— 预期 403
try {
  $r = Invoke-WebRequest -Uri "$base/api/chat/slots" -UseBasicParsing
  "no-auth -> $($r.StatusCode)"
} catch { "no-auth -> $($_.Exception.Response.StatusCode.value__)" }

# 2) 带 Internal-Secret 调 /api/chat/slots
try {
  $r = Invoke-WebRequest -Uri "$base/api/chat/slots" -Headers $hdr -UseBasicParsing
  "with-secret /slots -> $($r.StatusCode)"
  ($r.Content | ConvertFrom-Json) | Select-Object -First 3 | ForEach-Object { "  slot: $($_.key)  title=$($_.title)  running=$($_.running)" }
} catch { "with-secret /slots -> $($_.Exception.Response.StatusCode.value__)  (若 403 说明列表端点要 cookie，不属 mixed-internal)" }

# 3) 带 Internal-Secret 发一条消息到某个 slot（把 <SLOT_KEY> 换成真实 key）
#    先别真发，确认 /slots 拿到 key 后再放开下面这段
<#
$body = @{ message = "hello from companion test"; slot = "<SLOT_KEY>" } | ConvertTo-Json
try {
  $r = Invoke-WebRequest -Uri "$base/api/chat" -Method POST -Headers $hdr `
        -ContentType "application/json" -Body $body -UseBasicParsing
  "POST /api/chat -> $($r.StatusCode)"
} catch { "POST /api/chat -> $($_.Exception.Response.StatusCode.value__)" }
#>
```

判读：
- 步骤 1 = 403，步骤 2 = 200 且列出 slot → 方式 B 完全可行，companion 读 `.local_secret` 即可。
- 步骤 2 = 403 但步骤 3(POST /api/chat) = 200 → 列表端点需 cookie，但**发消息**用 internal-secret 可行（够用，控制走 POST，同步走 WS/cookie）。
- 全 403 → 该机 gateway 版本/配置不同，回来贴输出再判。

---

## 方式 A：App Token（更正规，权限可控）

需要一个 manifest 声明了 `permissions.api: ["/api/chat"]` 的**自有 app**，且 gateway
为它写出了 `<KIROCREW_HOME>\apps\<name>\.app_secret`。EC2 上已验证：换 token
流程 200 通，但蹭现成的 `crew-companion`（没声明 /api/chat）会被 scope 403 拦。

先看这台 Windows 上哪些 app 有 secret、有没有你自己的 app：

```powershell
Get-ChildItem "$home_crew\apps" -Directory | ForEach-Object {
  $has = Test-Path "$($_.FullName)\.app_secret"
  "{0,-24} secret={1}" -f $_.Name, $has
}
```

若要用某个有 secret 的 app 验证换 token 机制本身（不代表能调 /api/chat）：

```powershell
$app = "crew-companion"   # 换成你的 app 名
$appsecret = (Get-Content "$home_crew\apps\$app\.app_secret" -Raw).Trim()
try {
  $r = Invoke-WebRequest -Uri "$base/api/apps/$app/token" -Method POST `
        -Headers @{ "X-App-Secret" = $appsecret } -UseBasicParsing
  $tok = ($r.Content | ConvertFrom-Json).token
  "exchange -> $($r.StatusCode)  token_len=$($tok.Length)"
  # 用 token 调 /api/chat/slots —— 若该 app 没声明 /api/chat 会 403 forbidden（预期）
  try {
    $r2 = Invoke-WebRequest -Uri "$base/api/chat/slots?token=$tok" -UseBasicParsing
    "app-token /slots -> $($r2.StatusCode)"
  } catch { "app-token /slots -> $($_.Exception.Response.StatusCode.value__)  (403=该app未声明/api/chat，符合deny-by-default)" }
} catch { "exchange -> $($_.Exception.Response.StatusCode.value__)" }
```

结论走向：
- 换 token 200 + /slots 403 → 机制通，只差一个声明了 `/api/chat` 的自有 app。
- 换 token 403 → 该 app 无 secret 或 secret 不符，换一个 `secret=True` 的 app 再试。

---

## 建议

先跑**方式 B**。它最能一步定死"companion 到底能不能免注册直接调 API"。
把三步输出贴回来，我据此决定 companion 端 `crew_api.rs` 走 B（读 .local_secret）
还是 A（自建 app + 换 token）。
