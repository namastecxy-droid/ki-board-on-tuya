# P2-agent-console · Design

## 1. LCD 布局(320×240 横屏)

```
┌──────────────────────────────────────────────┐
│ KIRO CREW · PLAN · HIGH               [🐱]     │  顶栏(平台·模式·effort) + 角落吉祥物(点缀)
├───────────────┬───────────────┬───────────────┤
│ A1 API        │ A2 WEB        │ A3 TEST       │  三槽位卡:标题
│ ● Running     │ ! Input       │ ✓ Done        │            + 状态(色点+词)
│ [focus 高亮]  │               │               │  聚焦槽位描边高亮
├───────────────┴───────────────┴───────────────┤
│ <上下文主区>  normal 时此区可并入槽位/留空       │  approval/voice/task 时铺满此区
├──────────────────────────────────────────────┤
│ ←Stop   ↑Activity   OK Detail   →Approve       │  底栏:随上下文变化的方向提示
└──────────────────────────────────────────────┘
```

- **吉祥物**:约 56–64px,固定右上(顶栏右侧)或右下角;反映聚焦槽位状态;`lv_image`,复用 `ak_scene` 缩放版。
- approval/voice/task 主区**覆盖**中部槽位概览(顶栏+底栏保留),退出回 normal。
- 字体:Montserrat 14(正文)+ 一个大字号(时长/进度)。图标用 LVGL symbol 或 8×8。

## 2. 模块(复用 P2-1 + 新增)

| 模块 | 处置 |
|---|---|
| `ak_panel.c/h` | **复用**(ST7789 rotation 270 横屏) |
| `ak_scene.c/h` + sprite 资源 | **复用**,新增"缩放 + 角落定位"入口(点缀吉祥物) |
| `app_rle_sprite.h`, `sprite_*` | 复用 |
| `ak_console_ui.c/h` | **新增**:富信息 LVGL 布局(顶栏/槽位卡/底栏/上下文主区) |
| `ak_slots.c/h` | **新增**:3 槽位状态机(纯逻辑,可单测) |
| `ak_led.c/h` | **新增**:WS2812×3 状态渲染,复用 `tdd_pixel_ws2812`(SPI1/P4,见 `firmware/bringup/ws2812`) |
| `agent_event.h` | **新增**:逻辑事件枚举(FOCUS_SLOT_x/BIND/APPROVE/REJECT/INTERRUPT/SUBMIT/VOICE_*/OPEN_*/NAV_*) |
| `input_map.c/h` | **新增**(替代 P2-1 版):键/摇杆 → agent_event(纯映射,可单测) |
| `console_state.c/h` | **新增**:持有槽位 + 当前上下文(normal/approval/voice/task)+ 聚焦,消费 event → 更新 ui/led/scene |
| `ak_input`/`ak_input_fsm` | 复用(共享 common) |

> P2-1 的 `ak_notify_ui`/`app_notification`/`app_state`/旧 `ak_event`/旧 `input_map` **不带入**本 app(定位已变);P2-1 目录保留作历史。

## 3. 上下文状态机

```
              K1-3 focus
   normal ─────────────────► normal(切焦点)
     │  ▲ REJECT/退出          │
 approval│  │              VOICE_START(K4按住)
 事件到达│  │                  ▼
     ▼  │              voice(录音→松开转写预览)──K5 SUBMIT──► normal
  approval(← Reject / → Approve once / OK Details)
     │
 task_update ──► task(←Pause OK Details →Open) ── task_complete ──► normal
```
本阶段"事件到达"由**按键模拟**:如某键注入一条 approval、某键推进 task。

## 4. 键位 → 事件映射(新文档 §3;short=UP<800ms, long=LONG)

| 输入 | 短按 | 长按 |
|---|---|---|
| K1 / K2 / K3 | `FOCUS_SLOT_1/2/3` | `BIND_SLOT`(LCD 确认) |
| K4 | (按下)`VOICE_START` / (松开)`VOICE_STOP` | — |
| K5 | `SUBMIT`(上下文) | `OPEN_PANEL` |
| 摇杆 左 | `REJECT` / `INTERRUPT` / Back(按上下文) | — |
| 摇杆 右 | `APPROVE`(仅 once) | — |
| 摇杆 上/下 | `NAV_UP` / `NAV_DOWN` | — |
| 摇杆 中心 | `OPEN_DETAILS` / Confirm | `OPEN_PANEL` |

> 本阶段为演示,额外用未占用的组合(如摇杆上/下在 normal 下)**模拟注入** approval / 推进 task / 切平台·模式,方便真机走查各主区;真实来源在阶段 2。映射细节在实现时定,evt 日志为准。

## 5. LED 映射(WS2812 §6)

| 槽位状态 | 颜色/效果 |
|---|---|
| unbound | 灭 |
| idle | 白 |
| running | 蓝 |
| tool_running | 蓝呼吸/流动 |
| complete_unread | 绿 |
| needs_approval | 琥珀呼吸 |
| error | 红双闪 |
| 聚焦叠加 | 当前色 + 短白闪 |
| Companion 断线 | 三灯紫慢闪(本阶段可由一个模拟键触发) |

用一个周期性 `lv_timer` 或独立 tick 做呼吸/闪烁相位。

## 6. 线程/锁
- LVGL 对象操作在 `lv_vendor` 锁内(沿用 P2-1)。
- 输入轮询线程(10ms)`ak_input_poll` → `input_map` → `console_state_apply`。
- LED 更新可在输入线程或单独 tick;WS2812 刷新走 SPI1,不与 LCD(SPI0)冲突。

## 7. 测试
- host 单测:`ak_slots`(状态迁移 + complete 回落逻辑,时间可注入)、`input_map`(键→事件全表)。
- `tos.py build` 出 bin;真机走查各主区 + LED + 吉祥物跟随。

## 8. 风险/决策
| # | 项 | 处理 |
|---|---|---|
| C1 | 富信息布局在 320×240 挤 | 上下文主区**覆盖式**切换,不同时显示全部;字体 14 |
| C2 | 吉祥物占地 vs 信息 | 限 ≤64px 角落,可配置隐藏 |
| C3 | WS2812(SPI1)与 LCD(SPI0)并存 | 两路独立 SPI,bringup 已各自验证;同时用需上板确认时序 |
| C4 | K4"大键"/无 backspace | 布局差异不阻塞;backspace 语义已删 |
| C5 | 模拟事件如何触发各主区 | 用空闲摇杆方向/组合注入,evt 日志标注;阶段 2 换真实源 |
