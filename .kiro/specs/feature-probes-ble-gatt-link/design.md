# FP-2 ble-gatt-link · Design

## D1 — BLE 栈选型：TAL BLE peripheral（而非原生 NimBLE）

用涂鸦 **TAL BLE** 外设角色 + 其**固定命令服务**（`0x1910`），而不是手搓 GATT。理由：

- MVP 主路是"板 ↔ 自家 companion"，两端都我们控，不需要标准 profile，只要一条
  可靠的双向字节管道；涂鸦命令服务天然提供 notify(板→中心) + write(中心→板)。
- TAL 路线代码量小、与 bring-up `wireless_selftest` 已验证的初始化序列一致。
- BLE HID 兜底（FP-6）才需要标准 HID 描述符 + SM，那条走原生 NimBLE，是**另一个
  probe 固件**，与本 probe 不共存（见 feature-probes README 的"两条 BLE 路线"）。

## D2 — GATT 布局（涂鸦固定命令服务）

| 属性 | UUID | 方向 | 用途 |
|------|------|------|------|
| Service | `0x1910` | — | 命令服务 |
| Notify | `0x2B10` | 板 → 中心 | 协议 v1 帧：key/nav/hello_ack/ping |
| Write  | `0x2B11` | 中心 → 板 | 命令/状态（计数 + UART 回显） |

- 上行发送：`tal_ble_server_common_send(&data)`（notify `0x2B10`）。
- 下行接收：`TAL_BLE_EVT_WRITE_REQ` → `ble_event.write_report.report`。
- 索引常量：`TAL_COMMON_NOTIFY_CHAR_INDEX=1` / `TAL_COMMON_WRITE_CHAR_INDEX=0`（`tal_bluetooth_def.h`）。

## D3 — 广播数据

- adv：`02 01 06`（LE General + BR/EDR not supported） + `03 03 10 19`（16-bit 服务
  UUID 列表 = `0x1910`，小端）。
- scan rsp：`06 09 'A' 'K' '-' 'K' 'B'`（complete local name = `AK-KB`）。

## D4 — 事件处理（`ble_event_cb`）

| TAL 事件 | 处理 |
|----------|------|
| `TAL_BLE_STACK_INIT` (init==0) | 设 adv+rsp → `tal_ble_advertising_start`；UART 打 `link:advertising` |
| `TAL_BLE_EVT_PERIPHERAL_CONNECT` | 存 peer，`connected=true`，UART 打 `link:connected` |
| `TAL_BLE_EVT_MTU_REQUEST` | `tal_ble_server_exchange_mtu_reply(peer, 247)` |
| `TAL_BLE_EVT_SUBSCRIBE` | `subscribed = cur_notify`；订阅成功即推 `hello_ack` |
| `TAL_BLE_EVT_WRITE_REQ` | 读 report → 计数 + 以 `link_rx` JSONL 回显 UART |
| `TAL_BLE_EVT_DISCONNECT` | `connected=subscribed=false`，重新广播 |

## D5 — 数据流与 main loop

```
按键/摇杆 --ak_input/fsm--> on_input --ak_protocol--> JSONL 帧
                                          │
                    ┌─────────────────────┴─────────────────────┐
                    ▼(总是)                                      ▼(connected && subscribed)
                UART0 镜像                              tal_ble_server_common_send (0x2B10 notify)
中心 write(0x2B11) --WRITE_REQ--> 计数 + link_rx 回显 UART
```

- main loop：`ak_input_poll(now, on_input)` 每 5ms；每 5s 发 `ping`（UART + 已连则 BLE）。
- 初始化顺序：`tal_log_init → ak_uart_init → ak_input_init → tal_kv_init /
  tal_sw_timer_init / tal_workq_init → tal_ble_bt_init(PERIPHERAL, cb)`
  （与 `wireless_selftest` 一致）。

## D6 — 协议复用

发送即 `ak_proto_key/nav/hello_ack/ping` 产出的同一 JSONL；`hello_ack` 的 transport
字段填 `"ble-gatt"`，是 UART 后端与 BLE 后端在协议层唯一的区分点。companion 解析器
因此可原样复用。

## D7 — 配置

`CONFIG_ENABLE_GPIO/UART/BLUETOOTH=y`（无 DISPLAY/LVGL/LEDS，保持精简）。

## D8 — 与正式 firmware/app 的关系

本 probe 的 BLE 收发胶水（`start_advertising` / `emit_frame` / `ble_event_cb`）是
`firmware/app/` 里 `AK_TRANSPORT_BLE_GATT` 后端的原型：将来抽成
`ak_ble.c` 与 `ak_uart.c` 并列，由 `ak_features.h` 的 transport 选择切换。

## 偏差记录

- **流程**：本 probe 先写代码后补 spec（已改为教训：feature-probes 一律先 spec）。
- **无 host 单测**：本 probe 逻辑几乎全是 SDK BLE 回调，纯逻辑部分（协议/输入）已由
  `firmware/app/test` 覆盖，故本 probe 不单独加 host 单测（与 FP-1 的纯逻辑模块不同）。
