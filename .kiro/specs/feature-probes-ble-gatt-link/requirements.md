# FP-2 ble-gatt-link · Requirements

> 说明：本 spec 为 **回填**。FP-2 的实现先于 spec 完成（一次流程偏差，已记录为教训：
> 此后所有 feature-probes 先出 spec 再编码）。本文件把已实现的现状固化为可跟踪的
> 需求与验收项，真机验收仍待执行。

## 背景与目标

MVP 的**无线传输地基**：把板↔PC companion 的链路从 USB 串口换成 **BLE GATT**，
且**复用与 UART 后端完全相同的 JSONL 协议 v1**（`shared/protocol/protocol.md`），
使 companion 解析器零改动即可复用——本 probe 只换"线"，不换"话"。

产出目标：
1. 一个**可上板运行的无线链路测试程序**，证明"按键/文字帧经 BLE 空中送达、companion
   下行 write 可收"这条链路通；
2. 一个可复用的 **BLE GATT 传输后端**雏形，后续可与 `ak_uart` 并列成为 `firmware/app/`
   的可插拔 transport。

**非目标**：不做 BLE HID（那是 FP-6 兜底，走 NimBLE，另一条路线）；不接语音/ASR；
不做 LCD 显示（链路状态用 UART0 JSONL 观测即可）；不实现 companion 端（本 probe 用
手机 nRF Connect 当测试 central）。

## 术语

- **中心 (central)**：连接本板的一方——最终是 PC companion，验收阶段用 nRF Connect。
- **命令服务**：涂鸦固定 GATT 服务 `0x1910`；notify 特征 `0x2B10`（板→中心），
  write 特征 `0x2B11`（中心→板）。
- **协议 v1 帧**：`ak_protocol` 产出的一行 JSONL（key/nav/ack/ping 等）。

## 需求 (EARS)

### R1 — BLE 外设广播与连接
- R1.1 WHEN 固件启动并完成 BLE 栈初始化, THE 系统 SHALL 以本地名 `AK-KB` 开始可连接广播，广播数据中列出命令服务 `0x1910`。
- R1.2 WHEN 一个 central 发起连接, THE 系统 SHALL 接受连接并记录 peer。
- R1.3 WHEN 连接断开, THE 系统 SHALL 自动重新开始广播。

### R2 — GATT 传输通道（复用涂鸦命令服务）
- R2.1 THE 系统 SHALL 使用涂鸦固定命令服务（service `0x1910` / notify `0x2B10` / write `0x2B11`），不自定义 128-bit 服务，也不需要 HID 描述符。
- R2.2 WHEN central 订阅 notify 特征 `0x2B10` (CCCD), THE 系统 SHALL 记录订阅状态并据此决定是否空中发送。
- R2.3 WHEN central 请求 MTU 交换, THE 系统 SHALL 回复 server MTU 247，以容纳完整 JSONL 帧。

### R3 — 上行：输入事件经 BLE notify
- R3.1 THE 系统 SHALL 复用 `ak_input` + `ak_input_fsm`（去抖 20ms / 长按 800ms）扫描 5 键 + 5 向开关。
- R3.2 WHEN 产生一个按键/摇杆事件, THE 系统 SHALL 用 `ak_protocol` 生成协议 v1 JSONL 帧（`key`/`nav`），并在已连接且已订阅时经 `0x2B10` notify 给中心。
- R3.3 THE 系统 SHALL 周期性（5s）发送 `ping` 心跳作为链路存活信标。
- R3.4 WHEN 中心刚订阅成功, THE 系统 SHALL 主动推送一条 `hello_ack`（transport 标记为 `ble-gatt`）。

### R4 — 下行：中心 write 接收
- R4.1 WHEN 中心写入 write 特征 `0x2B11`, THE 系统 SHALL 接收该数据并计数。
- R4.2 THE 系统 SHALL 把收到的字节以可观测的 `link_rx` JSONL 帧回显到 UART0。

### R5 — 可观测性（UART0 镜像）
- R5.1 THE 系统 SHALL 把每一帧（上行帧、链路状态、下行 rx）同时镜像到 UART0（P10/P11，115200 8N1）为 JSONL，便于无 companion 时用串口验证。
- R5.2 涂鸦调试日志 SHALL 保持在 UART1 @ 460800，与 UART0 数据面分离。

### R6 — 自包含与工程约定
- R6.1 THE probe SHALL 是 `firmware/feature-probes/ble_gatt_link/` 下自包含 TuyaOpen app，`tos.py build` 可编译。
- R6.2 THE probe SHALL 复用 `firmware/app/common` 的 `ak_uart`/`ak_input`/`ak_input_fsm`/`ak_protocol`，不复制协议逻辑。
- R6.3 THE probe SHALL 通过 `clang-format --Werror` 格式门禁。

## 验收 (Definition of Done)

- 上电后 UART0 打出 `hello_ack`(transport `ble-gatt`) 与 `link:advertising`。
- nRF Connect 能扫到 `AK-KB` 并连接；对 `0x2B10` 开 notify 后，按键/摇杆在 nRF Connect
  的 notify 日志**和** UART0 同时出现 `key`/`nav` 帧。
- 对 `0x2B11` 写数据，UART0 打出对应 `link_rx` 帧。
- 断开后自动重广播、可再次连上。
- `tos.py build` 通过；`clang-format --Werror` clean。

## 已知限制 / 待办

- **MTU**：默认 ATT MTU 23（20B 载荷）；超长帧需先做 MTU 交换（本板应答 247）。未协商前
  的长帧可能被截断——nRF Connect / companion 均会请求更大 MTU，故连接后正常。
- **分片**：未实现应用层分片；依赖 MTU 协商容纳单帧（当前帧 < 244B 均可）。
- **配对/加密**：本 probe 未启用 SM/绑定（明文 GATT），MVP 阶段可接受；产品化再评估。
- **真机验收**：待在 v1.2 板 + COM6 烧录后用 nRF Connect 走一遍上述 DoD。
