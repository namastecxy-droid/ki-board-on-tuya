# P2-agent-console · Tasks

> 增量推进,每步可 `tos.py build` 或 host 单测通过。复用 P2-1 底座(ak_panel/ak_scene/sprites)。
> `[ ]` 未开始 / `[~]` 进行中 / `[x]` 完成。

- [ ] **T1 — 脚手架 + 富信息 LCD 骨架**
  - 建 `firmware/phase2/agent_console/{src,include,config,test}` + config(LVGL/SPI/DISPLAY,DISPLAY_NAME=ak_lcd)+ CMake + README
  - 复用 `ak_panel`(rotation 270);`ak_console_ui`:顶栏(平台·模式·effort)+ 三槽位卡 + 底栏方向提示(静态占位)
  - `tos.py build` 通过

- [ ] **T2 — 槽位状态模型 + 吉祥物点缀**
  - `ak_slots.c/h`:3 槽位 + 状态枚举 + 聚焦 + complete 回落(时间可注入,host 单测)
  - 复用 `ak_scene` 加"缩放 + 角落定位"入口;吉祥物随聚焦槽位状态切动画(≤64px,不遮挡)
  - `ak_console_ui` 按槽位模型渲染(高亮聚焦)

- [ ] **T3 — LED 状态(WS2812×3)**
  - `ak_led.c/h`:复用 `tdd_pixel_ws2812`(SPI1/P4);按 §6 映射渲染;呼吸/闪烁相位 tick
  - 上板确认 SPI1(LED)与 SPI0(LCD)并存

- [ ] **T4 — 上下文主区(normal/approval/voice/task)+ 底栏联动**
  - `console_state.c/h`:上下文切换;approval/voice/task 主区覆盖式渲染 + 底栏方向提示随之变化
  - approval 显示 工具/命令/风险/持久授权(§5.2,R8 占位)

- [ ] **T5 — 输入 → 逻辑事件 + 消费**
  - `agent_event.h` + `input_map.c/h`(纯映射,host 单测):K1–3 focus/bind、K4 PTT、K5 submit/panel、摇杆上下文
  - `console_state_apply(event)` 驱动 slots/ui/led/scene;`[evt]` 串口日志
  - 空闲摇杆方向**模拟注入** approval/task/平台切换,便于真机走查各主区
  - 上板走一遍全部事件

- [ ] **T6 — 收尾**
  - README(布局图/键位表/操作)+ phase2 路线图更新
  - 标注复用给**阶段 2(Kiro Crew Companion)**的模块:`console_state`/`ak_slots`/`agent_event` 换事件源即可(`kirocrew-client` 订阅 slots/approval/task)
  - MIT 归属(吉祥物/精灵来自 CodeTank→clawd-tank)

## 依赖顺序
T1 → T2 →(T3 ∥ T4)→ T5 → T6

## 阶段 2 预告(不在本 spec)
`docs/agentic-keyboard-interaction-design.md` §9:Companion 用 `kirocrew-client` 连 Gateway(:5476),
订阅 `slots/chat_chunk/tool_call/approval/task_*`,把本 spec 的模拟事件源替换为真实 Kiro Crew 事件;
键盘审批双向同步 Dashboard;断线走 `list_slots()` 重建。
