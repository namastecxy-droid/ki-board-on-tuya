# FP-6 ble-hid-fallback · Requirements

## 背景与目标

MVP 主路是 **BLE GATT + companion**（FP-2/4/5，富交互）。FP-6 是它的**最基本兜底**：
**无 companion** 时，板子直接把自己伪装成一只**标准 BLE HID 键盘**（HID-over-GATT /
HOGP），向**当前获得焦点的窗口**（例如 Kiro Crew dashboard 的聊天输入框）敲：

- **文字** —— 逐字符发键（板载 ASR 或预设文本转成 HID 用法码序列）；
- **回车（发送）** —— 一个 Enter usage 提交消息；
- **快捷键（切换对话）** —— 组合键（如 Ctrl+Tab / Ctrl+PgUp 等）切换会话。

能力受限（只能"盲敲焦点窗口"，无回读、无绑定 agent 语义），但**零依赖**：不需要装
companion，任何支持标准 BLE 键盘的 OS（Windows/macOS/Linux/iOS/Android）都能直接配对使用。

产出目标：
1. 一个**可上板运行的 BLE HID 键盘兜底测试程序**，证明"板子被 OS 识别为标准键盘、
   能向焦点窗口输入文字+回车+快捷键"这条链路通；
2. 判定在本 SDK（TuyaOpen NimBLE）上**能否/如何**搭出合规 HOGP，并把结论固化为
   GO/NO-GO（见 design.md D9）。

**非目标**：不接 companion、不做 GATT 命令服务（那是 FP-2 的 `0x1910` 路线，两条 BLE
路线**互斥、不共存**，分属不同 probe 固件）；不接语音/ASR（本 probe 用固定测试文本
+ 按键触发，ASR 集成留待 FP-7）；不做 LCD（链路状态用 UART0 JSONL 观测即可）。

## 术语

- **HOGP / HID-over-GATT**：BLE 上的标准键盘协议，核心 = HID Service `0x1812` +
  Report Map + Input Report 特征，且**必须**加密/配对（SM bonding）。
- **HID Service (`0x1812`)**：内含 HID Information (`0x2A4A`)、Report Map (`0x2A4B`)、
  HID Control Point (`0x2A4C`)、Protocol Mode (`0x2A4E`)、一个或多个 Report (`0x2A4D`)。
- **Report Reference 描述符 (`0x2908`)**：挂在每个 Report 特征上，声明 Report ID +
  类型（Input/Output/Feature）。**HOGP 强制要求**，缺它主机不认。
- **DIS (`0x180A`)** / **Battery (`0x180F`)**：HOGP 强烈建议同时提供的两个伴随服务。
- **SM (Security Manager)**：负责配对/绑定/加密。本 SDK **默认关闭**（见 design.md D3）。
- **原生 NimBLE 路线**：绕过涂鸦 TAL 固定命令服务，直接调 NimBLE host 的
  `ble_gatts_add_svcs()` 等 API 自建 GATT 表。

## 需求 (EARS)

> 说明：R1–R6 是"若判定 GO 才实现"的**目标需求**；R0 是**本 cycle 的实际交付**——
> 可行性判定本身。判定结果见 design.md D9 与 tasks.md T0。

### R0 — 可行性判定（本 cycle 必交付）
- R0.1 THE 团队 SHALL 在 design.md 给出**明确 GO / NO-GO**，并引用确切文件/符号为证据。
- R0.2 THE 判定 SHALL 覆盖三点：(a) SDK 是否含 HID Service/Report Map/Report 支持；
  (b) SM 配对/绑定能否开启、如何开；(c) peripheral 注册**带描述符**的自定义 GATT 服务走什么 API。
- R0.3 IF 判定为 NO-GO 或高风险, THEN THE 团队 SHALL NOT 在本 cycle 落地 probe 代码，
  仅在 spec 留下结论与后续条件（遵守"清晰 GO 且低风险才 scaffold"的准绳）。

### R1 — 被识别为标准 BLE HID 键盘
- R1.1 WHEN 固件启动并完成 BLE 栈初始化, THE 系统 SHALL 以 GAP Appearance = `0x03C1`
  (Keyboard) 广播 HID Service `0x1812`，本地名 `AK-KB-HID`。
- R1.2 WHEN 一台标准主机（Windows/macOS/Linux）扫描并配对, THE 系统 SHALL 被
  枚举为一个标准键盘输入设备，无需任何驱动/companion。

### R2 — 合规 HOGP GATT 布局
- R2.1 THE 系统 SHALL 暴露 HID Service `0x1812`，含 HID Information/Report Map/
  HID Control Point/Protocol Mode 及至少一个 **Input Report** 特征。
- R2.2 THE 每个 Input Report 特征 SHALL 携带 **Report Reference 描述符 `0x2908`**
  与 CCCD（notify）。
- R2.3 THE Report Map SHALL 声明一个标准 **Boot/Report 键盘**（8B：Modifier + Reserved
  + 6×Keycode）用法集。
- R2.4 THE 系统 SHALL 同时提供 DIS `0x180A`（PnP ID 等）与 Battery `0x180F`（HOGP 建议）。

### R3 — 配对/绑定与加密（HOGP 强制）
- R3.1 THE 系统 SHALL 启用 SM，允许 **Just Works** 配对与 **bonding**（保存 LTK，复连免重配）。
- R3.2 WHEN 未加密的主机尝试读 HID Report, THE 系统 SHALL 按 HOGP 要求拒绝（要求先加密）。

### R4 — 输入：文字 / 回车 / 快捷键
- R4.1 THE 系统 SHALL 把一段测试文本转成 HID keycode 序列，按键按下/抬起成对经 Input Report notify 发送。
- R4.2 WHEN 触发"发送", THE 系统 SHALL 发一个 Enter (usage `0x28`) 键。
- R4.3 WHEN 触发"切换对话", THE 系统 SHALL 发一个可配置组合键（默认 Ctrl+Tab）。
- R4.4 THE 输入触发源 SHALL 复用 `ak_input` + `ak_input_fsm`（去抖 20ms / 长按 800ms）
  扫描 5 键 + 5 向开关（映射表见 design.md D6），**不**复制输入逻辑。

### R5 — 可观测性（UART0 镜像）
- R5.1 THE 系统 SHALL 把链路状态（advertising/connected/encrypted/bonded）与每次发键
  以 JSONL 镜像到 UART0（P10/P11，115200 8N1），便于无主机 UI 时用串口验证。
- R5.2 涂鸦调试日志 SHALL 保持在 UART1 @ 460800，与 UART0 数据面分离。

### R6 — 自包含与工程约定
- R6.1 THE probe SHALL 是 `firmware/feature-probes/ble_hid_fallback/` 下自包含 TuyaOpen app，`tos.py build` 可编译。
- R6.2 THE probe SHALL 复用 `firmware/app/common` 的 `ak_uart`/`ak_input`/`ak_input_fsm`，不复制其逻辑。
- R6.3 THE probe SHALL 通过 `clang-format --Werror` 格式门禁。

## 验收 (Definition of Done)

> 仅在判定 GO 且实现后适用。本 cycle 的 DoD 见 R0（判定已交付）。

- 上电后 UART0 打出 `link:advertising`（appearance=keyboard, svc=0x1812）。
- Windows 蓝牙设置能扫到 `AK-KB-HID`、配对成功（Just Works），设备类型显示为"键盘"。
- 焦点放到记事本/Kiro Crew 输入框：触发发文字 → 文本出现；触发发送 → 换行/提交；
  触发切换 → 组合键生效。UART0 同步打出对应发键 JSONL。
- 断开后自动重广播；复连**免重新配对**（bonding 生效）。
- `tos.py build` 通过；`clang-format --Werror` clean。

## 已知限制 / 风险（详见 design.md D8）

- **能力受限**：盲敲焦点窗口，无回读、无 FP-4 的"绑定 agent/发送/切换"语义层；
  切换对话靠 OS 级快捷键，依赖前台应用支持该快捷键。
- **工程量大**：本 SDK 的 TAL 固定命令服务搭不出合规 HID（无描述符表达能力），
  须走**原生 NimBLE 手搓**（自建 GATT 表 + Report Map + 开 SM），是与 FP-2 完全不同的一条重路线。
- **平台差异**：键盘布局/keycode 与主机键盘布局相关；测试文本先用纯 ASCII 规避。
