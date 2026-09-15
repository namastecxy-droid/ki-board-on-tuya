# FP-WS2812 · WS2812 Chat 状态灯 · Requirements

## 背景与目标

扩展底板 v1.2 上有 **3× WS2812**(菊花链,数据脚 `P4 = SPI1_MOSI`,经 SN74LV1T34 电平转换,
官方 SPI 驱动 `tdd_pixel_ws2812`)。交互设计 `docs/agentic-keyboard-interaction-design.md` §6
明确定义了 **LED1–LED3 分别映射 K1–K3 三个 Agent 槽位** 的状态→颜色/效果表,但**产品固件
`firmware/app/` 至今完全没有 WS2812 的任何驱动、状态机或接线**——只有 `ak_board_io.h` 里的引脚宏。

本 spec 采用「**保险优先**」路线:先建 spec,再在 **feature-probe** 里做灯效原型(可上板、可单测),
验证通过后把可复用模块合并进产品固件 `firmware/app/`。

产出目标有三:
1. 一个 **可复用的 WS2812 驱动+状态机模块**(`ak_leds` + `ak_led_state`),纯逻辑部分带 host 单测;
2. 一个 **可上板运行的 feature-probe**,用板载 5 键/5 向开关或串口 `display` 帧驱动灯效,逐条验证 §6 状态表;
3. 模块以「**事件驱动**」边界暴露(输入槽位状态 → 更新灯),使合并进 `firmware/app/` 时只需把
   probe 的模拟事件源替换成真实的 `display` 帧处理点,**不改灯效层**。

**非目标**:不接真实 Kiro/Codex 事件(由 companion 侧 `display` 帧驱动,probe 用模拟源);
不做多于 3 槽位的翻页逻辑(灯永远只反映 LCD 当前显示的 3 槽位,翻页逻辑属产品固件 UI 层)。

## 术语

- **槽位 (slot)**:LED1–LED3 一一对应当前 LCD 显示的 3 个 Agent 会话槽位(index 0..2)。
- **槽位状态 (slot state)**:一个槽位的 chat 状态,来自协议 `display` 帧的 `state` 字段
  (`idle` / `running` / `error`)+ 固件派生态(未绑定 / 完成未读 / 需审批 / 当前选中)。
- **全局覆盖态 (override)**:优先级高于单槽状态的整链效果,当前仅 **Companion 断线 → 三灯紫慢闪**。
- **灯效 (effect)**:颜色 + 动态(常亮 / 呼吸 / 双闪 / 慢闪 / 短白闪叠加)。

## 状态 → 灯效映射(权威来源:交互设计 §6,本表为其固件化)

| 槽位状态 | 颜色 | 动态 |
|---|---|---|
| 未绑定 (unbound) | 熄灭 | 无 |
| Idle | 白 | 常亮 |
| Thinking/Running | 蓝 | 常亮 |
| Tool running | 蓝 | 轻呼吸 |
| Complete 未读 | 绿 | 常亮(数分钟后自动回落到 Idle 白) |
| Needs input / Approval | 琥珀 | 呼吸 |
| Error | 红 | 双闪 |
| 当前选中(叠加) | 当前颜色 | 叠加周期性短白闪 |
| **Companion 断线(全局覆盖)** | 紫 | 三灯慢闪(优先级最高) |

> `display.state` 三值(`idle`/`running`/`error`)与派生态的对应在 design §5 定义。

## 需求 (EARS)

### R1 — WS2812 驱动封装 (`ak_leds`)
- R1.1 THE 系统 SHALL 用官方 `tdd_pixel_ws2812` 在 `AK_WS2812_SPI_PORT`(SPI1)注册并打开
  `AK_WS2812_COUNT`(=3)颗设备,复用 bring-up 已验证的 register/open/refresh 序列。
- R1.2 THE `ak_leds` SHALL 暴露 `ak_leds_init()` / `ak_leds_set(slot, r,g,b)` / `ak_leds_show()`,
  slot 越界或未 init 时返回错误而非崩溃。
- R1.3 THE 系统 SHALL 全局限制亮度(峰值不超过 bring-up 已验证的安全档,应对 3× 白光峰值电流与
  电池开关 0.3A 额定),亮度上限做成编译期常量。
- R1.4 IF WS2812 驱动 register/open 失败, THEN THE 系统 SHALL 记录错误并以「灯功能不可用」降级继续
  (不得阻塞主流程或复位)。

### R2 — 灯效状态机 (`ak_led_state`,纯逻辑,可单测)
- R2.1 THE 状态机 SHALL 为 3 个槽位各持有一个槽位状态,并持有「当前选中槽位」与「全局覆盖态」。
- R2.2 WHEN 收到一个槽位的新状态, THE 状态机 SHALL 按上表把 (状态, 是否选中, 是否全局覆盖)
  解析为该槽位在下一 tick 应呈现的目标灯效。
- R2.3 THE 状态机 SHALL 提供一个纯函数 `ak_led_render(state, tick) -> rgb[3]`(或等价),
  给定当前逻辑状态与单调递增的 tick,计算三颗灯的即时 RGB —— **不碰 SDK**,以便 host 单测。
- R2.4 WHEN 槽位进入 Complete(绿), THE 状态机 SHALL 在可配置超时(默认数分钟)后自动回落为 Idle(白)。
- R2.5 WHEN 全局覆盖态为「断线」, THE 状态机 SHALL 让三颗灯统一紫慢闪,忽略各槽位状态,直至覆盖态清除。
- R2.6 动态效果(呼吸/双闪/慢闪/短白闪)SHALL 由 tick 驱动的确定性函数产生,相同 (state, tick)
  输出相同 RGB(便于单测断言关键相位)。

### R3 — Probe 事件源(模拟 chat 状态)
- R3.1 THE probe SHALL 提供两种驱动源之一(design 定):(a) 板载 5 键/5 向把物理输入映射为
  「给某槽位设某状态 / 切换选中 / 切换断线」;和/或 (b) 解析串口 `display` JSONL 帧
  (`chat_slot` 1..3 → slot 0..2,`state` → 槽位状态)。
- R3.2 THE probe SHALL 复用 agent_display 探针已建立的 **intent 事件层边界**(SDK-free intents),
  使真实事件源(FP-3 companion-link 的 `display` 帧)能替换模拟源而不改状态机/驱动层(满足 R5)。
- R3.3 每次状态变更 SHALL 通过串口打印一行 `[led] slot=.. state=.. selected=.. override=..` 便于验证。

### R4 — 自包含与工程约定
- R4.1 THE probe SHALL 是 `firmware/feature-probes/ws2812_status/` 下自包含 TuyaOpen app,`tos.py build` 可编译。
- R4.2 THE probe SHALL 复用产品固件 `firmware/app/common/include/ak_board_io.h` 的权威引脚宏,不得另抄引脚。
- R4.3 纯逻辑模块(`ak_led_state` 的 render/状态转移、`display` 帧解析映射)SHALL 带 host 单测,
  沿用现有 `run_host_tests.sh` 模式,`tos.py build` 与 host 单测均须通过。

### R5 — 为合并进产品固件打基础(可复用性)
- R5.1 `ak_leds.*`(驱动)与 `ak_led_state.*`(状态机)SHALL 与 probe 的模拟事件源解耦,
  可直接被 `firmware/app/` 引用。
- R5.2 合并阶段 SHALL 在 `firmware/app/` 处理 `display` 帧的既有位置调用 `ak_led_state_set_slot(...)`,
  并把 Complete 回落 / 动态 tick 挂到已有定时器或输入线程,**不改协议、不新增线程模型冲突**。
- R5.3 「Companion 断线」的判定源(心跳/连接丢失)在合并阶段接产品固件已有的连接状态,
  probe 阶段用一个按键/命令模拟触发即可。

## 验收 (Definition of Done)

### Probe 阶段
- 上板后默认三灯按未绑定/idle 呈现;能把任一槽位切到 §6 表中各状态并观察到正确颜色/动态。
- Complete 绿在超时后回落为 Idle 白;Approval 琥珀呼吸、Error 红双闪、Tool 蓝呼吸动态可见。
- 「当前选中」槽位可见叠加短白闪;触发「断线」后三灯紫慢闪并在清除后恢复。
- 每次变更串口有 `[led]` 日志;`tos.py build` 通过;host 单测(render + 帧解析)全绿。

### 合并阶段
- `ak_leds.*` / `ak_led_state.*` 落入 `firmware/app/common/`,在 `display` 帧处理点接线。
- 产品固件 `tos.py build` 通过,主机 `firmware/app/test/` 单测全绿(含新增 render/映射用例)。
- 真机:companion 发 `display` 帧,三灯随对应槽位 chat 状态实时变化;断线三灯紫慢闪。
- README / dev-implementation-steps 路线图状态更新。
