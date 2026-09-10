# FP-lcd-showcase · Requirements

## 背景

FP-1 `agent_display` 已把 CodeTank 的**吉祥物场景引擎 + 19 动画精灵 + 通知条**移植到
v1.2 硬件（CL28CK230-18A / ST7789 / 320×240 横屏 rotation 270），并真机验证过。但 FP-1 的
屏幕**只有一个居中的大吉祥物**——它验证的是「场景/动画/通知」这条链路，不是产品最终的
**信息密集状态界面**。

本 probe（`lcd_showcase`）是一个**纯显示示例（LCD 界面示例）**：把
`docs/agentic-keyboard-interaction-design.md` 定义的**富信息布局**画出来，作为后期
FP-4/FP-7 真实数据驱动时的**界面模板与观感基准**。吉祥物按已定方向**降为角落点缀**
（复用 FP-1 的 `ak_scene` 迷你精灵），主体让位给功能状态信息。

> 关联决策（memory / lessons）：
> - 产品交互以 `docs/agentic-keyboard-interaction-design.md` 为唯一准绳（Agent 物理控制 +
>   状态界面），旧语音听写器/backspace 设计作废。
> - **吉祥物保留作角落点缀提供情绪价值，同时屏幕主体反馈丰富功能状态信息**——两者并存，
>   不是二选一。
> - 键位：K1–K3 = 三 Agent 槽位；K4 大键 = PTT 语音；K5 = 主操作；5 向 = 上下文导航。
>   本 probe 用**按键模拟数据源**切换界面状态，与 FP-1 同层（意图层解耦），不接真实事件。

## 范围

- **纯显示 + 按键模拟**：不接 Wi-Fi / BLE / 云 / 麦克风。按键只用来在示例状态间切换，
  演示各种界面态长什么样。
- 复用（不重写）FP-1 已验证模块：`ak_panel.c`、`ak_scene.*`、`app_rle_sprite.h`、
  精灵 `.h`、`ak_input.*`、`ak_event.h`；以及 `firmware/app/common` 的输入栈。
- 新增仅一层：`ak_hud.*`（富信息 HUD 布局）+ `showcase_state.*`（示例状态机）+
  `showcase_map.*`（按键→示例意图，纯函数可 host 测）+ `tuya_app_main.c`。

## 需求

### R1 面板与布局
- **R1.1** 屏幕 320×240 横屏，rotation 270（与 FP-1 `ak_panel.c` 一致，直接复用）。
- **R1.2** 整屏划分为四区（参考 ki-board `ui_render.cpp` 观感 + 交互设计文档）：
  - **顶栏（Status Bar）**：平台（Kiro Crew / Kiro CLI / Codex）· 模式 · effort 档位 ·
    连接状态（ON/OFF）· 固件版本。
  - **槽位区（Slots）**：K1–K3 三个 Agent 槽位卡片，显示槽名 + 状态（Empty/Idle/Run/Error）
    + 简短 cwd/会话名；当前聚焦槽高亮。
  - **上下文主区（Context）**：显示当前聚焦槽的详情 / 最近一条消息 / 语音转写占位，
    以及**吉祥物角落点缀**（迷你精灵，随聚焦槽状态切换动画）。
  - **底栏（Nav Hints）**：5 向方向义（左 Back·Reject / 右 Approve·Continue /
    中心 Details·Confirm）+ K4 PTT / K5 主操作 提示。
- **R1.3** 吉祥物**不占据主区中心**，作为角落（右下或上下文区一角）小尺寸元素存在；
  复用 `mascot_anim_*`，可用 `mini_mascot` 或缩放后的常规动画。

### R2 示例状态机（按键模拟数据源）
- **R2.1** 至少覆盖这些**界面态**，可用按键循环切换，逐一展示：
  1. 三槽位常态（一个 Run、一个 Idle、一个 Empty）
  2. 聚焦切换（K1/K2/K3 高亮不同槽）
  3. PTT 语音录音态（上下文区显示"listening…"+ 声波占位，吉祥物 thinking/typing）
  4. 待确认态（Approve/Reject 提示高亮，吉祥物 alert one-shot）
  5. 通知态（复用 FP-1 通知条，注入一条示例通知）
  6. 断连态（顶栏 OFF，吉祥物 disconnected）
- **R2.2** 每次按键在串口打印 `[showcase] <intent> -> state=<name>`，便于无屏调试。
- **R2.3** 界面态与吉祥物动画的映射集中在 `showcase_state.c`，界面绘制集中在 `ak_hud.c`，
  两者通过一个明确的 `showcase_view_t` 快照解耦（便于 FP-4 用真实数据填同一个快照）。

### R3 按键映射（模拟，非最终产品键位）
- **R3.1** 映射为**纯函数** `showcase_map.c`（`showcase_map_translate()`），host 可单测：
  - K1/K2/K3 短按 → 聚焦槽 1/2/3
  - K4 短按 → 切换 PTT 录音态 on/off
  - K5 短按 → 循环切换聚焦槽的模拟状态（Idle→Run→待确认→Idle）
  - 5 向 左/右 → 上一/下一**示例场景**（R2.1 的 6 个态整体遍历）
  - 5 向 中心短按 → 注入/清除示例通知
  - 5 向 上/下 → 切换连接态 ON/OFF（演示断连）
- **R3.2** 映射表只产出**示例意图**（`showcase_intent_t`），不直接碰 LVGL；与 `ak_event.h`
  分层一致（FP-4 可用 JSONL 解析器产出等价意图驱动同一 HUD）。

### R4 构建与验证
- **R4.1** `tos.py build` 在 T5AI-Core 上 **BUILD SUCCESS**；AP 分区不超上限（3.5MB）。
- **R4.2** 纯逻辑模块（`showcase_map` + `showcase_state` 的状态推进）带 **host 单测**，
  沿用 `run_host_tests.sh` 模式，**ALL PASSED**。
- **R4.3** `clang-format` clean；`check_pins.py` 无关（不改脚位，复用 `ak_board_io.h`）。
- **R4.4** 真机观感（COM6 扩展板烧录）**留待用户验收**——EC2 只保证编译通过 + 逻辑正确。

## 归属
显示层的吉祥物场景/动画/RLE/通知逻辑移植自 CodeTank（`ref_projects/CodeTank`，其精灵/场景
改编自 clawd-tank MIT）。富信息 HUD 布局参考 ki-board `ui_render.cpp` 观感（3 槽位卡片 +
状态栏 + 底栏提示），按本项目 320×240 横屏与交互设计文档重写，不复制其代码。
