# FP-2 ble-gatt-link · Tasks

> 实现与真机验收均已完成；T1–T5 全部通过。
> 勾选规则：`[ ]` 未开始 / `[~]` 进行中 / `[x]` 完成。

- [x] **T1 — 脚手架 + 协议/输入复用（R6）** ✅ 2026-09-09
  - 建 `firmware/feature-probes/ble_gatt_link/{src,config}` + `app_default.config` +
    `CMakeLists.txt` + `README.md`
  - CMakeLists 复用 `firmware/app/common` 的 `ak_uart.c`/`ak_input.c`/`ak_input_fsm.c`/`ak_protocol.c`
  - config：`ENABLE_GPIO/UART/BLUETOOTH=y`

- [x] **T2 — BLE 外设：广播 + 连接 + MTU + 订阅（R1/R2）** ✅ 2026-09-09
  - `tal_ble_bt_init(PERIPHERAL, cb)`；`ble_event_cb` 处理 STACK_INIT/CONNECT/MTU_REQUEST/SUBSCRIBE/DISCONNECT
  - adv=`AK-KB` + 服务 `0x1910`；MTU 应答 247；断开自动重广播

- [x] **T3 — 上行：输入事件经 notify + 心跳（R3）** ✅ 2026-09-09
  - `ak_input_poll` → `on_input` → `ak_proto_key/nav` → `tal_ble_server_common_send`（已连+已订阅）
  - 订阅成功推 `hello_ack`(transport `ble-gatt`)；5s `ping` 心跳；全部镜像 UART0

- [x] **T4 — 下行：write 接收 + 回显（R4/R5）** ✅ 2026-09-09
  - `TAL_BLE_EVT_WRITE_REQ` → 计数 + `link_rx` JSONL 回显 UART0
  - **BUILD SUCCESS**（AP 0.83MB/3.5MB）；`clang-format --Werror` clean

- [x] **T5 — 真机验收（DoD）** ✅ 2026-09-13（用户确认）
  - v1.2 板完成 BLE 广播、连接、notify 订阅和按键/导航帧验证
  - PC→board write 与断开后重新广播/复连通过
  - companion 已验证 Tuya BLE V2 notify/write，并保留 V1 兼容

## 依赖顺序
T1 → T2 → T3 → T4 →（真机）T5。T2 是关键（BLE 外设不通则整体链路要改）。

## 构建/烧录命令
```bash
cd /data/projects/TuyaOpen && . ./export.sh
cd /data/projects/tuya-powered-agentic-keyboard-for-kiro/firmware/feature-probes/ble_gatt_link
tos.py clean -f && tos.py build      # 改 .config 后必须 clean
# 本机 Windows 烧录（扩展板 = COM6）：
# .\flash.ps1 -Port COM6 -App "firmware/feature-probes/ble_gatt_link" -Monitor
```
