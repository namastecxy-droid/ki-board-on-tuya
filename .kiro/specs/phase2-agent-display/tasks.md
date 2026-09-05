# P2-1 agent-display · Tasks

> 增量推进,每个 task 结束应能 `tos.py build` 通过(或 host 单测通过)。风险优先。
> 勾选规则:`[ ]` 未开始 / `[~]` 进行中 / `[x]` 完成。

- [x] **T1 — 脚手架 + LVGL 上板验证(风险优先, R1/D1)** ✅ 2026-09-05
  - 建 `firmware/phase2/agent_display/{src,config,include}` + `app_default.config` + `CMakeLists.txt` + `README.md`
  - `ak_panel.c` 只注册面板(INVOFF 序列, rotation 90 → 320×240);`lv_vendor_init/start` 负责 open+双缓冲+旋转
  - `tuya_app_main.c` 画 "hello" label(deep bg + 紫标题)
  - **BUILD SUCCESS + clang-format clean**;实测 AP app 仅 **1.03MB / 3.5MB 上限**(LVGL 已含),精灵后估 ~2.15MB,余量充足
  - 真机刷新验证待 v1.2 板到手(D1:LVGL 能挂本项目 ST7789 已在**编译层**确认,SDK 的 `lv_vendor`+TDD 路径可用)

- [x] **T2 — 精灵 runtime + 单动画渲染(R2.1)** ✅ 2026-09-05
  - 拷入 `app_rle_sprite.h` + `assets/generated/sprite_mascot_idle.h`(CodeTank 原样,vendored)
  - `ak_sprite.c/h`:RLE→RGB565A8 解码(透明键 0x18C5)+ `lv_image` + `lv_timer` 每 166ms 送帧,idle 16 帧循环
  - `tuya_app_main.c`:标题移到上/下端,中央跑 idle 吉祥物
  - **BUILD SUCCESS + clang-format clean**;真机观感待板到手

- [ ] **T3 — 全动画注册表 + 场景引擎(R2.2/R2.3/R2.4)**
  - 拷入全部 `sprite_mascot_*.h` + `sprite_mascot_registry.h`(D3:超 flash 则先核心子集)
  - 移植 `app_scene.c/h`,布局改 320×240 单会话(§4),接口 `scene_set_mascot_anim` / one-shot 回落

- [x] **T4 — 通知子系统(R3)** ✅ 2026-09-05
  - 原样拷 `app_notification.c/h`(CodeTank,纯逻辑)
  - **偏差**:未移植 canvas+像素字体的 `app_notification_ui.c`(480×320 重),改写轻量 LVGL 通知条 `ak_notify_ui.c/h`(屏底显示最新通知 + `(N)` 计数,空则隐藏),等价验证 R3.2/R3.3 且更适配 320×240
  - host 单测:store add/dismiss/clear/去重/满溢 **ALL PASSED**

- [x] **T5 — 输入→事件映射 + 状态消费(R4/R6.1)** ✅ 2026-09-05
  - 意图事件层 `ak_event.h`(SDK-free intents)保住 R6.1 边界;`input_map.c/h` 纯映射(可单测)
  - `app_state.c/h` 消费 intent → `ak_scene` / `ak_notify_ui`,持有 store + 状态循环索引
  - 复用 `ak_input`/`ak_input_fsm`;main 起输入轮询线程(10ms),`on_input` 打 `[evt]` 日志
  - host 单测:input_map 全映射表 **ALL PASSED**;firmware **BUILD SUCCESS**(AP 2.27MB/3.5MB)

- [~] **T6 —(可选)多会话 / 子代理 HUD / SFX(D5)** — 按设计默认**跳过**(单会话已满足 P2-1 目标)

- [x] **T7 — 收尾** ✅ 2026-09-05
  - README(操作/预期/按键表)+ phase2 路线图状态更新 + MIT 归属(R6.2)
  - 可复用模块标注(R6):`ak_scene.*` / `ak_notify_ui.*` / `ak_event.h` / `app_state.*` 可被正式 `firmware/app/` 的 Agent 区直接复用;P2-3 只需用串口 JSONL 解析器替换 `input_map` 产出相同 intents

## 依赖顺序
T1 → T2 → T3 → (T4 ∥ T5 的逻辑部分) → T5 集成 → T6 → T7
T1 是硬门槛(LVGL 不通则整体方案要改),必须先做。

## 构建/测试命令
```bash
cd /data/projects/TuyaOpen && . ./export.sh
cd /data/projects/tuya-powered-agentic-keyboard-for-kiro/firmware/phase2/agent_display
tos.py clean -f && tos.py build      # 改 .config 后必须 clean
# host 单测(纯逻辑):
cd test && ./run_host_tests.sh
```
