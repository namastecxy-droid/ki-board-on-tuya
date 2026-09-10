# P2-agent-console · Requirements

# P2-agent-console · Requirements

> ⚠️ **已作废(SUPERSEDED,2026-09-09)**。另一 session 已把 `phase2/` 重组为 `firmware/feature-probes/`,
> 并确立 MVP demo 北极星(无线语音键盘控制 Kiro Crew)+ FP-1..FP-7 路线图。本 `agent-console` 单体设备 UX
> 方案不再作为组织主线。**现行计划见 `.kiro/specs/mvp-demo/` 与 `firmware/feature-probes/README.md`。**
> 本文的富信息 LCD 布局 / LED 状态映射 / 摇杆上下文表**保留作 FP-7(整合)阶段的显示层设计参考**。

---

## 背景

产品定位从"语音听写器"转向 **Agent 的物理控制 + 状态界面**,权威交互设计见
`docs/agentic-keyboard-interaction-design.md`(2026-09-09)。本 spec 落地该文档的**阶段 1
(设备侧:输入 + LCD/LED 状态机)**,在 P2-1 已跑通的底座上演进,用按键**模拟事件源**
(Companion/真实 Agent 事件在阶段 2 接入)。

旧的 `phase2-agent-display` 与 KB `04-interaction-design.md` 的听写按键设计**已作废**。

## 已定的产品决策(本轮确认)

- **吉祥物保留**,作**点缀 / 情绪价值**;屏幕主体是**富信息功能界面**(吉祥物不得遮挡信息)。
- **无 backspace 键**,相关语义直接忽略。
- 一切以 `docs/agentic-keyboard-interaction-design.md` 为准。

## 控件基线(取自新文档 §3,对照 v1.2 硬件)

| 控件 | 职责 | v1.2 对照 |
|---|---|---|
| K1–K3 | 三个 Agent 槽位 | 3 颗轴体 |
| K4 | Push-to-Talk 语音(按住) | 1 颗轴体(文档称"大键";当前为相同轴体,非阻塞) |
| K5 | 主操作 Submit/Continue;长按=控制面板 | 1 颗轴体 |
| 5 向摇杆 | 上下文导航 / Reject / Approve / Details | 5 向开关 |
| LED1–LED3 | 对应 K1–K3 的 Agent 状态 | **3 颗 WS2812(P4/SPI1)** ✅ 恰好对应 |
| LCD | 会话/审批/工具/语音/任务 富信息 | ST7789 320×240 横屏(rotation 270) |

## 需求 (EARS)

### R1 — 富信息 LCD 布局
- R1.1 THE 屏幕 SHALL 常驻:**顶栏**(平台·模式·effort,如 `KIRO CREW · PLAN · HIGH`)、**三槽位区**(A1/A2/A3 标题 + 状态 + 颜色,当前聚焦高亮)、**底栏**(实时方向提示 ←/→/↑↓/OK,随上下文变化)。
- R1.2 THE 屏幕 SHALL 在一个**上下文主区**按当前状态切换呈现:normal / approval / voice / task(见 R5)。
- R1.3 底栏方向含义 SHALL 与当前上下文一致(新文档 §3.5 表)。

### R2 — 吉祥物点缀
- R2.1 THE 吉祥物 SHALL 以**小尺寸**显示在固定角落,复用 P2-1 的 `ak_scene`(缩放/重定位),**不遮挡**顶栏/槽位/底栏。
- R2.2 吉祥物动画 SHALL 反映**当前聚焦槽位的状态**(idle/thinking/typing/building/happy/alert/sleeping/disconnected 映射),提供情绪反馈。

### R3 — 槽位状态模型
- R3.1 THE 系统 SHALL 维护 3 个槽位,每个状态 ∈ {unbound, idle, running, tool_running, complete_unread, needs_approval, error}。
- R3.2 WHEN 焦点切换, THE 高亮 + 吉祥物 SHALL 跟随聚焦槽位。
- R3.3 complete_unread 数分钟后 SHALL 回落到 idle(避免旧完成态长期占用注意力)。

### R4 — LED 状态(WS2812 ×3)
- R4.1 LED1–3 SHALL 按新文档 §6 映射:unbound=灭 / idle=白 / running=蓝 / tool=蓝流动或呼吸 / complete=绿 / approval=琥珀呼吸 / error=红双闪 / 聚焦=叠加短白闪 / Companion 断线=三灯紫慢闪。
- R4.2 复用 `firmware/bringup/ws2812` 验证过的 `tdd_pixel_ws2812`(SPI1/P4)驱动。

### R5 — 上下文主区(4 态)
- R5.1 **normal**:三槽位概览。
- R5.2 **approval**:显示所属槽位 / 工具名 / Shell 命令或路径或 MCP 参数摘要 / 风险等级 / 是否持久授权;底栏 `← Reject  OK Details  → Approve once`。
- R5.3 **voice**:录音时长 + 音量条(PTT 期间);松开后显示转写预览 + `K5 Send / ← Discard`。
- R5.4 **task**:Task Runner 名称 + 步骤进度 + 底栏 `←Pause OK Details →Open`。

### R6 — 输入 → 逻辑事件层(不写死快捷键)
- R6.1 THE 固件 SHALL 只产出**逻辑事件**,复用 P2-1 的意图边界思路(`ak_event`→本 spec 扩为 agent 事件):`FOCUS_SLOT_1/2/3`、`BIND_SLOT`、`APPROVE`、`REJECT`、`INTERRUPT`、`SUBMIT`、`VOICE_START`、`VOICE_STOP`、`OPEN_ACTIVITY`、`OPEN_DETAILS`、`OPEN_PANEL`、`NAV_UP/DOWN`。
- R6.2 键位语义(新文档 §3):K1–K3 短按=聚焦/建会话、长按 800ms=绑定(需 LCD 确认);K4 按住=`VOICE_START`、松开=`VOICE_STOP`;K5 短按=`SUBMIT`(上下文相关)、长按=`OPEN_PANEL`;摇杆 左=`REJECT/INTERRUPT/Back`、右=`APPROVE`、中心=`OPEN_DETAILS/Confirm`、上下=`NAV_*`、长按中心=`OPEN_PANEL`。
- R6.3 EACH 事件 SHALL 串口打印 `[evt]` 一行,便于验证。

### R7 — 自包含与工程约定
- R7.1 THE test SHALL 是 `firmware/phase2/agent_console/` 自包含 TuyaOpen app,`tos.py build` 可编译。
- R7.2 THE test SHALL NOT 依赖 Companion/云;按键**模拟**事件源(聚焦、注入审批、触发语音、跑任务)。
- R7.3 纯逻辑(槽位状态机、输入→事件映射)SHALL 带 host 单测。
- R7.4 事件层与状态机 SHALL 为阶段 2(Kiro Crew Companion,`kirocrew-client` 订阅 slots/approval/task)预留:替换事件源即可,不改显示层。

### R8 — 安全(显示层,新文档 §11)
- R8.1 approval 主区 SHALL 显示命令/目标路径与风险等级;摇杆右默认仅 `approve_once`。
- R8.2 `allow_always` 一类 SHALL 需进 Details 并长按确认(本阶段先做交互占位,真实鉴权在 Companion)。

## 验收 (DoD)
- 上板显示顶栏+三槽位+底栏+角落吉祥物;按 K1–K3 切焦点(高亮+LED+吉祥物跟随);模拟进入 approval/voice/task 主区并正确切换底栏提示;LED 按状态变色;每事件有 `[evt]` 日志。
- `tos.py build` 通过;host 单测(槽位状态机 + 输入映射)全绿;clang-format clean。
- README + phase2 路线图更新;标注可复用给阶段 2/正式 app 的模块。
