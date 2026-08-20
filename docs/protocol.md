# 通信协议说明

> 协议的**权威定义**在 [`shared/protocol/protocol.md`](../shared/protocol/protocol.md)。
> 本文件仅作导读，避免两处内容漂移；实现请以 `shared/protocol/` 为准。

## 快速索引

- **载体**：阶段1 UART/USB-CDC（115200 8N1）→ 阶段2 BLE GATT → 阶段3 BLE HID
- **编码**：UTF-8 JSON Lines，每帧以 `\n` 结尾，未知 `type` 忽略
- **帧字段**：`v` / `seq` / `type` / `payload`
- **板→PC 事件**：`key`、`nav`、`voice`、`macro`
- **PC→板 命令**：`led`、`display`、`config`、`ack`
- **握手/心跳**：`hello`/`hello_ack`、`ping`/`pong`

## 设计要点

1. 协议跨阶段复用：从有线到 BLE，`type`/`payload` 语义不变，只换载体。
2. 传输层与协议层解耦：固件与 Companion 各自实现可替换的 transport 后端。
3. 参照已克隆的 ki-board `shared/protocol/serial-protocol.md`，减少重复设计。

详细字段、示例、状态机、配对鉴权见权威源文档。
