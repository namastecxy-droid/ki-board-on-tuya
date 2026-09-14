# MVP Demo · Design

## 1. 端到端架构

```
┌─────────────── Agentic Keyboard (T5AI-Core v1.2) ───────────────┐
│  Mic ── ai_chat ONESHOT ── 涂鸦云 ASR ──► 文字                    │  FP-3
│  5键+5向 ── ak_input/fsm ──► 逻辑事件 (JSONL v1)                  │
│  LCD(ST7789) + LED×3(WS2812) ◄── 状态/通知                       │  FP-1 复用
│                    │ notify 0x2B10 / write 0x2B11 (Tuya svc 0x1910)│
└────────────────────┼─────────────── BLE GATT (AK-KB) ────────────┘  FP-2
                     ▼
┌─────────────── PC companion (Rust/Tauri, 照搬 ki-board) ─────────┐
│  BLE client ── JSONL v1 解析(复用 protocol.rs)                   │
│  Windows 系统 ASR (WinRT)  ─────────────► 文字                    │  FP-5
│  Kiro Crew adapter ── REST + WebSocket ──► :5476                  │  FP-4
└────────────────────┼─────────────────────────────────────────────┘
                     ▼
              Kiro Crew Gateway (:5476)  ── slots / chat / tool / approval / task
                     ▲
              Kiro Crew Dashboard(同一 Gateway,与键盘并列的第二交互端)
```

**兜底路线(FP-6,独立固件)**:板子 ── 原生 NimBLE HID ──► PC(标准键盘,无 companion)。

## 2. 两条控制 Kiro Crew 的路线

| | 主路(FP-2+FP-4) | 兜底(FP-6) |
|---|---|---|
| 传输 | BLE GATT + companion | BLE HID 直连 |
| 能力 | 富交互:绑定/输入/发送/切换 + 状态回流 + 审批 | 键盘输入 + 回车发送 + 快捷键切换,无状态回流 |
| 依赖 | 需 companion 常驻 | 零依赖 |
| BLE 栈 | TAL 固定命令服务 | 原生 NimBLE(手搓描述符+SM) |

## 3. 传输层(FP-2)
- Tuya 固定命令服务(`0x1910`/notify`0x2B10`/write`0x2B11`),已在 `ble_gatt_link` probe 落地骨架。
- **复用 JSONL v1**:board→companion 走 notify(key/nav/asr_text/hello_ack/ping);companion→board 走 write(status/命令)。companion 的 `protocol.rs` 解析器不改,只把 `usb_serial.rs` 换成 BLE client。
- MTU:默认 23→请求 247;长帧(如 ASR 整句)协商后通过。

## 4. ASR 两路
- **板载云 ASR(FP-3)**:`ai_chat_init` ONESHOT → `ai_user_event_notify_register` → `AI_USER_EVT_ASR_OK`(`AI_NOTIFY_TEXT_T`);文字打成 JSONL `asr_text` 帧经 BLE 上报。需 Wi-Fi + 云激活(UUID+AuthKey MQTT bind,真机验证是否强制账号绑定)。
- **PC ASR(FP-5)**:板键发 `VOICE_PC_START/STOP` 逻辑事件 → companion 调 Windows WinRT ASR → 文字进同一 Crew 注入路径。

## 5. Companion 侧(FP-4/FP-5)
- 语言:**Rust/Tauri**(已移植底座,照搬 ki-board 紫色);Kiro Crew 交互用 Rust HTTP/WS 直连 `:5476`,镜像 `kirocrew-client`(交互设计 §9)的调用:`list_slots / create_slot / send_message / resolve_approval / spawn / list_subagents`,WS 订阅 `slots/chat_chunk/tool_call/approval/chat_done/chat_error/task_*/notification`。
- 鉴权:MVP 用 localhost:5476;正式用 app_name 换短期 Token(交互设计 §9.1)。
- 断线恢复:WS 断→LCD `CREW OFFLINE`+三灯紫慢闪→重连后 `list_slots()` 重建(不只靠增量)。

## 6. 模块复用/新增

| 层 | 复用 | 新增 |
|---|---|---|
| 板 传输 | `ak_protocol`(JSONL v1)、`ak_input`/`ak_input_fsm` | FP-2 BLE peripheral glue |
| 板 ASR | KB 08 事件模型 | FP-3 `ai_chat` 接线 + `asr_text` 帧 |
| 板 显示 | **FP-1** `ak_panel`/`ak_scene`/通知条(rotation 270) | FP-7 状态/通知/审批区接真实事件 + LED×3(`tdd_pixel_ws2812`) |
| companion | `protocol.rs`/前端(ki-board) | FP-2 BLE client 替 `usb_serial.rs`;FP-4 Crew adapter;FP-5 WinRT ASR |

## 7. 依赖与顺序

```
FP-1(显示层)✅
      │
FP-2(BLE GATT 地基)✅ ── 真机通过
      ├── FP-3(板载云 ASR)✅    ┐
      ├── FP-4(companion→Crew)  ├─ FP-2 之后可并行
      └── FP-5(PC ASR)          ┘
FP-6(BLE HID 兜底)── 相对独立(另一条 BLE 路线),可随时并行
      │
FP-7(整合)── 需要 FP-2+FP-3+FP-4(+FP-5),复用 FP-1 显示层
```

## 8. 风险/决策
| # | 风险 | 处理 |
|---|---|---|
| K1 | 云 ASR 是否强制账号绑定 | FP-3 真机验证;UUID+AuthKey MQTT bind 先试免 App |
| K2 | BLE HID 需手搓 NimBLE(描述符+SM,默认关) | FP-6 独立固件,风险隔离;失败不影响主路 |
| K3 | companion(Rust)vs `kirocrew-client`(Python) | FP-4 用 Rust 直连 Gateway REST/WS,镜像其调用;不引 Python |
| K4 | Gateway 免认证 localhost | MVP 用 localhost;正式换 app_name Token |
| K5 | BLE 帧长 vs MTU | 协商 247;ASR 整句必要时分片 |
| K6 | Wi-Fi(云 ASR)与 BLE 共存于 T5 | FP-3 上板验证并发;必要时分时 |

## 9. 每个 probe 的 spec
本 spec 是总计划。**每个 probe 开工前写自己的 `.kiro/specs/feature-probes-<name>/` 三件套**
(FP-1 已有 `feature-probes-agent-display`)。FP-2 与 FP-3 均已完成各自 spec、实现和真机验收。
