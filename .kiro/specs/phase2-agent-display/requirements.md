# P2-1 agent-display · Requirements

## 背景与目标

把 CodeTank 的 **Agent 状态显示层**(LVGL 场景 + 吉祥物动画 + 通知 UI)移植到本项目
**v1.2 硬件**(CL28CK230-18A / ST7789 / 320×240 横屏),并用**板载 5 键 + 5 向开关模拟
事件源**(替代 CodeTank 的 Wi-Fi/TCP + Codex Bridge),在真机上切换不同 Agent 状态和通知。

产出目标有二:
1. 一个**可上板运行的二期测试程序**,证明"屏上按产品样子显示 Agent 状态"这条链路通;
2. 把场景/动画/通知做成**可复用模块**,作为后期"氛围显示 / 三区 UI 的 Agent 区"的底座。

**非目标**:不接 Wi-Fi/TCP、不接真实 Kiro/Codex 事件、不做语音、不做触摸交互。
真实事件源在 P2-3(companion-link)接入。

## 术语

- **Agent 状态**:吉祥物动画所表达的 Agent 当前活动(idle/thinking/typing/building/…)。
- **通知**:带 id/project/message 的一条消息,进通知 store,由通知 UI 呈现。
- **场景 (scene)**:LVGL 画布,负责吉祥物定位、动画切换、(可选)多会话排布与 HUD。

## 需求 (EARS)

### R1 — LVGL 在本项目面板上跑通
- R1.1 WHEN 固件启动, THE 系统 SHALL 在 CL28CK230-18A(ST7789,320×240 横屏,复用 bring-up 的 INVOFF 初始化序列)上初始化 LVGL 并稳定刷新。
- R1.2 IF 目标板 `TUYA_T5AI_CORE` 无法启用 LVGL 组件, THEN THE 团队 SHALL 在 design 中记录替代路径,且本需求视为阻塞项优先解决。

### R2 — 吉祥物动画引擎移植
- R2.1 THE 系统 SHALL 复用 CodeTank 的 RLE 精灵 runtime(`app_rle_sprite.h`)与动画注册表(`mascot_anim_defs`),渲染吉祥物逐帧动画。
- R2.2 THE 系统 SHALL 支持至少 CodeTank 定义的核心动画状态:idle/thinking/typing/building/sweeping/debugger/wizard/conducting/beacon/confused/alert/happy/sleeping/disconnected。
- R2.3 WHEN 一个 looping 动画被选中, THE 场景 SHALL 循环播放;WHEN 一个 one-shot 动画(alert/happy/going_away 等)被触发, THE 场景 SHALL 播完后回落到当前主状态。
- R2.4 THE 吉祥物素材 SHALL 直接复用 CodeTank 现有 RGB565/RLE 资源(尺寸 ≤136×97,无需按屏幕分辨率重生成);仅**场景布局**按 320×240 调整。

### R3 — 通知子系统移植
- R3.1 THE 系统 SHALL 复用 `notification_store`(环形 8 条,add/dismiss/clear,按 id 去重)。
- R3.2 THE 系统 SHALL 复用通知 UI(`app_notification_ui`)在屏上呈现当前通知,布局适配 320×240。
- R3.3 WHEN 通知被 add/dismiss/clear, THE 屏幕 SHALL 相应更新。

### R4 — 按键模拟事件源
- R4.1 THE 系统 SHALL 用 5 个轴体键 + 5 向开关,把物理输入映射为 `app_event_t`(状态切换 / 通知 add / dismiss / clear / connected / disconnected),替代 TCP 事件。
- R4.2 THE 输入映射 SHALL 复用本项目已有的 `ak_input_fsm`(去抖 20ms / 长按 800ms)。
- R4.3 THE 按键映射表 SHALL 在 design 中明确定义,且每次按键 SHALL 通过串口打印一行 `[evt] ...` 便于验证。
- R4.4 具体映射(初版,可在 design 评审时调整):
  - 语音键:在主状态序列中循环 (thinking→typing→building→sweeping→…)
  - 发送键:注入一条模拟通知 (add)
  - 取消键:短按 dismiss 最新;长按 clear 全部
  - backspace 键:切换 connected / disconnected
  - 第5键:触发 one-shot (happy / alert)
  - 5 向方向:直接选中某个具体动画;中心短按:idle↔sleeping 切换

### R5 — 自包含与工程约定
- R5.1 THE test SHALL 是 `firmware/phase2/agent_display/` 下自包含 TuyaOpen app,`tos.py build` 可编译。
- R5.2 THE test SHALL NOT 依赖 Wi-Fi、TCP、云或主机 Bridge。
- R5.3 纯逻辑模块(通知 store、输入→事件映射)SHALL 带 host 单测,沿用现有 `run_host_tests.sh` 模式。

### R6 — 为氛围显示打基础(可复用性)
- R6.1 场景/动画/通知模块 SHALL 以"事件驱动"接口暴露(输入 `app_event_t` → 更新显示),使 P2-3 能用真实事件源替换按键而不改显示层。
- R6.2 移植代码 SHALL 保留 CodeTank 的 MIT 归属(见其 `LICENSES/clawd-tank-MIT.txt`)。

## 验收 (Definition of Done)

- 上板后默认显示 idle 吉祥物;按键能切换到 R2.2 列出的各状态并循环/回落正确。
- 发送键注入通知、取消键 dismiss/clear、backspace 切 connected/disconnected 均在屏上可见。
- 每个事件串口有 `[evt]` 日志。
- `tos.py build` 通过;host 单测(通知 store + 输入映射)全绿。
- README 写清操作方式与预期;phase2 路线图更新。
