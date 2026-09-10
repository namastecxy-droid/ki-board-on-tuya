# MVP Demo · Requirements

## 北极星

一个**无线 AI 语音小键盘,用来控制 Kiro Crew**。端到端:板子(Mic+按键+LCD)
**--BLE GATT-->** PC companion **-->** Kiro Crew,状态/通知反向回流到板子 LCD/LED。

组织形式见 `firmware/feature-probes/README.md`:每个 probe 单功能验证,逐步拼出 MVP。
权威交互设计 `docs/agentic-keyboard-interaction-design.md`;本 spec 是**贯穿 FP-2..FP-7 的
开发计划**(FP-1 显示层已完成)。

## MVP 四条基本要求(北极星拆解)

- **M1 无线连接**:板子不走 USB,走 **BLE GATT** 连 PC companion。
- **M2 控制 Kiro Crew**:识别到的文字/命令经 companion 路由进 Kiro Crew(绑定 agent/对话、输入文字、发送/执行、切换)。
- **M3 板载 Mic → 涂鸦云 ASR**:`ai_chat` ONESHOT → `AI_USER_EVT_ASR_OK` 取文字 → 经 BLE 上报。
- **M4 PC 端 ASR**:一个键让 companion 激活 **Windows 系统 ASR**,识别文字同样进 Kiro Crew。
- **M5 兜底 BLE HID**:无 companion 时板子直接当标准 BLE HID 键盘(输入文字+回车发送+快捷键切换),能力受限但零依赖。

## 需求 (EARS)

### R1 — 无线传输(FP-2,地基)
- R1.1 THE 板子 SHALL 作为 BLE peripheral 广播(`AK-KB`),暴露 Tuya 固定命令服务(svc `0x1910` / notify `0x2B10` / write `0x2B11`)。
- R1.2 THE 板↔companion SHALL 复用 **JSONL 协议 v1**(`shared/protocol/protocol.md`),仅把线从 UART 换成 BLE,companion 解析器不改。
- R1.3 THE 链路 SHALL 处理 MTU 协商(默认 23→请求 247),长帧在协商后可完整通过;并镜像到 UART0 便于观测。

### R2 — 板载云 ASR(FP-3)
- R2.1 WHEN 语音键触发, THE 板子 SHALL 用 `ai_chat` ONESHOT 采集板载 Mic → 涂鸦云 ASR,取 `AI_USER_EVT_ASR_OK` 的文字。
- R2.2 THE 文字 SHALL 经 FP-2 的 BLE notify 以 JSONL 上报 companion。
- R2.3 IF 云 ASR 需账号绑定, THEN 用 UUID+AuthKey 走 MQTT bind 激活(真机验证点)。

### R3 — 控制 Kiro Crew(FP-4,companion 侧)
- R3.1 THE companion SHALL 连 Kiro Crew Gateway(`:5476`,REST+WebSocket),提供四类操作:①绑定 agent/对话槽位 ②输入文字 ③发送/执行 ④切换 agent/对话。
- R3.2 THE companion SHALL 订阅 Crew 事件(slots/chat_chunk/tool_call/approval/task_*),把状态回流给板子(复用 FP-1 显示层 + LED)。
- R3.3 审批 SHALL 遵守安全约束(§交互设计 §11):approve_once 默认;allow_always 需详情+确认;双端任一处理后另一端失效。

### R4 — PC 端 ASR(FP-5)
- R4.1 WHEN 专用键触发, THE companion SHALL 激活 Windows 系统 ASR(WinRT),识别文字进 Kiro Crew(与 R3 同一注入路径)。

### R5 — BLE HID 兜底(FP-6,独立路线)
- R5.1 WHEN 无 companion, THE 板子 SHALL 以原生 NimBLE 手搓 HID(描述符+SM/配对)直连 PC,当标准键盘:输入文字 + 回车发送 + 快捷键切换对话。
- R5.2 THE FP-6 SHALL 是独立 probe 固件(与 FP-2 的 TAL GATT 是两条 BLE 路线,不混用)。

### R6 — 整合(FP-7)
- R6.1 THE FP-7 SHALL 把无线 + 双 ASR + 控制 Kiro Crew 端到端串起,FP-1 显示层复用为状态/通知区。
- R6.2 THE 演示脚本 SHALL 覆盖:板载语音→Crew、PC ASR→Crew、状态回流上屏、审批双端一致。

## MVP 验收 (DoD)

- 板子无 USB 数据线(仅供电),BLE GATT 连上 companion;
- 按语音键说话 → 板载云 ASR 出文字 → 进 Kiro Crew 当前对话;
- 按 PC-ASR 键 → Windows ASR 出文字 → 进 Kiro Crew;
- Kiro Crew 的运行/完成/审批状态回流到板子 LCD + LED;
- 板上可切换 3 个 agent 槽位、可对审批 approve/reject;
- 兜底:拔掉 companion,板子仍能作 BLE HID 键盘输入(能力受限)。

## 非目标(MVP 阶段)
- 富信息 console UX 全量(FP-7 只做够用的状态/通知/审批区,不追求 agent-console spec 的完整布局)。
- 多于 3 槽位分页、Codex adapter、正式 Crew App 配置页(交互设计 §12 阶段 4/5,MVP 后)。
