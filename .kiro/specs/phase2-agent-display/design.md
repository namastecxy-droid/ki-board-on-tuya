# P2-1 agent-display · Design

## 1. 架构总览

```
 5键+5向开关 ──► ak_input_fsm ──► input_map ──► app_event_t ──► app_state ──► scene / notif_ui ──► LVGL ──► ST7789
 (物理输入)      (去抖/长按)     (本test新增)    (复用CodeTank)   (显示状态机)   (移植CodeTank)         (320×240横屏)
```

- **替换点**:CodeTank 的 `app_tcp_server`/`app_network`/`app_protocol`(TCP→`app_event_t`)整段拿掉,
  换成 `input_map`(按键→`app_event_t`)。**`app_event_t` 这个接口边界不变**,所以 P2-3 只需把
  `input_map` 换成"串口 JSONL 解析器"就能接真实 Kiro 事件——满足 R6.1。

## 2. 模块清单

### 2.1 从 CodeTank 移植(原样/微调)
| 源文件 | 处理 |
|---|---|
| `include/app_rle_sprite.h` | 原样复用(纯解码,分辨率无关) |
| `include/assets/generated/sprite_mascot_*.h` + `sprite_mascot_registry.h` + `sprite_mini_mascot.h` + `sprite_wifi_icon.h` | 原样复用(素材 ≤136×97) |
| `include/app_scene.h` / `src/app_scene.c` | 移植;**布局改 320×240**(见 §4) |
| `include/app_notification.h` / `src/app_notification.c` | 原样复用(纯逻辑) |
| `include/app_notification_ui.h` / `src/app_notification_ui.c` | 移植;布局适配 320×240 |
| `include/app_pixel_font.h` / `src/app_pixel_font.c` | 原样复用 |
| `include/app_event.h` | 原样复用(事件模型) |
| `src/app_sound.c` + `assets/audio` | **可选**(Task6),本 test 默认不启用 |

### 2.2 本 test 新增
| 文件 | 职责 |
|---|---|
| `src/input_map.c` / `include/input_map.h` | `ak_input` 回调 → 构造 `app_event_t`,打印 `[evt]`(R4) |
| `src/app_state.c` / `include/app_state.h` | 持有当前主状态 + 通知 store,消费 `app_event_t` 更新 scene/notif_ui(替代 CodeTank 主循环里的事件消费段) |
| `src/tuya_app_main.c` | 入口:显示初始化 → LVGL → scene/notif_ui → 输入扫描任务 |
| `test/` | host 单测:通知 store + input_map(纯逻辑部分) |

### 2.3 复用本项目已有
- `firmware/app/common/{src,include}/ak_input_fsm.*`、`ak_input.*`(5键+5向去抖/长按状态机)
- `ak_display.*` 的 CL28CK230 INVOFF 初始化序列知识(但 LVGL 走 TDD→TDL→LVGL,见 §3)

## 3. 显示栈:ST7789 → LVGL(R1,最大风险)

- CodeTank 用官方板 `CONFIG_TUYA_T5AI_BOARD_LCD_35565`(ILI9488),**不能直接用**。
- 本项目路径:`tdd_disp_spi_st7789_register()`(用 bring-up 验证过的 no-INVON 序列)→ TDL 显示设备 → 
  TuyaOpen 的 LVGL 移植层(`CONFIG_ENABLE_LIBLVGL`)。参考 KB `08-ai-audio-lcd/03-lcd-st7789-lvgl.md`。
- **朝向**:CL28CK230 native 240(W)×320(H) 竖屏;产品用 320×240 横屏 → LVGL 旋转 90°(`lv_display_set_rotation` 或 MADCTL)。
- **风险 R1.2**:需先确认 `TUYA_T5AI_CORE` 能启用 LVGL 组件且能挂自定义 ST7789 TDD。→ Task1 先只做 "LVGL hello on our panel" 验证,不通则记录替代路径(如自绘 framebuffer blit,不走 LVGL)。

### LVGL 相关 config(初版,Task1 校准)
```
CONFIG_ENABLE_LIBLVGL=y
CONFIG_ENABLE_LVGL_TP=n        # 本test无触摸
CONFIG_LV_FONT_MONTSERRAT_12=y
CONFIG_LV_FONT_MONTSERRAT_18=y
CONFIG_ENABLE_SPI=y
CONFIG_ENABLE_DISPLAY=y
```

## 4. 场景布局适配 (480×320 → 320×240)

- CodeTank 单会话:吉祥物居中 + 顶部时间/Wi-Fi。多会话:最多 4 只并排 + `+N` HUD。
- 本 test **一期只做单会话**(R2 足够);多会话/子代理 HUD 列为可选 Task6。
- 320×240 横屏布局:
  - 吉祥物居中偏下(`y_offset` 沿用,底边留通知条空间)。
  - 顶部窄状态条:连接状态点 + (可选)状态文字。
  - 通知:屏底单行/双行气泡,复用 `app_notification_ui` 但缩小尺寸。
- `scene_set_width()` 传 320;字体降到 Montserrat 12/18。

## 5. 输入 → 事件映射 (R4)

`ak_input_fsm` 产出 (key_id, event: PRESS/LONG_PRESS)。`input_map` 转 `app_event_t`:

| 物理输入 | 动作 | app_event |
|---|---|---|
| 语音键 短按 | 主状态循环 next | `SET_STATUS`(thinking→typing→building→sweeping→confused→thinking…) |
| 发送键 短按 | 注入模拟通知 | `NOTIFICATION_ADD`(id 递增, project="demo", message 轮换) |
| 取消键 短按 | dismiss 最新 | `NOTIFICATION_DISMISS` |
| 取消键 长按 | 清空 | `NOTIFICATION_CLEAR` |
| backspace 短按 | 连接切换 | `CONNECTED` / `DISCONNECTED` 交替 |
| 第5键 短按 | one-shot | scene one-shot(happy↔alert 交替),播完回落主状态 |
| 5向 上/下 | 直接选动画 | 在全动画表里 prev/next 选中(调试用) |
| 5向 左/右 | 主状态微调 | 同语音键循环的反向/正向 |
| 5向 中心 短按 | 休眠切换 | `SET_STATUS` idle↔sleeping |

> `app_display_status_t` 只有 8 个(sleeping/idle/thinking/typing/juggling/building/confused/sweeping);
> debugger/wizard/conducting/beacon 这类走 scene 直接选动画(5向上下)。映射表可在评审时调整。

## 6. 数据流与主循环

```c
tuya_app_main():
  ak_display_lvgl_init();           // §3
  scene = scene_create(lv_scr_act());
  notif_ui = notif_ui_create(...);
  app_state_init(scene, notif_ui);  // 持有 notification_store + 当前状态
  ak_input_init(input_map_on_key);  // 每次按键 → input_map → app_state_apply(event)
  // LVGL tick/timer 任务 + input 扫描任务(沿用 bringup 线程模型)
```
`app_state_apply(app_event_t)` 就是 CodeTank 主循环事件 switch 的抽取版(SET_STATUS→scene_set_mascot_anim / 
NOTIFICATION_*→notif_store_* + notif_ui 刷新 / CONNECTED→取消 disconnected 动画 等)。

## 7. 测试策略

- **host 单测**(纯逻辑,x86 编译):`notification_store` add/dismiss/clear/去重/满溢;`input_map` 按键→事件映射表。
- **构建验证**:EC2 `tos.py build` 出 bin。
- **真机验证**(v1.2 板到手后):逐条走 R4 映射,核对屏显与 `[evt]` 日志;记入 phase2 的 TEST_RESULTS。

## 8. 风险与决策

| # | 风险/决策 | 处理 |
|---|---|---|
| D1 | LVGL 能否挂本项目 ST7789 TDD | Task1 风险优先验证;不通则退化为直接 framebuffer blit(不依赖 LVGL 的 scene) |
| D2 | 90° 旋转性能/撕裂 | 优先 LVGL 软件旋转;不行则 MADCTL 硬件方向 + 素材坐标转换 |
| D3 | Flash 占用 | **已实测**:精灵编译后仅 **1.17MB**(非 4MB;4MB 是 .h 文本源大小)。T5AI-Core(bk7258)主应用分区 `primary_ap_app` = **3808KB≈3.72MB**,OTA 分区 2940KB。当前 app ~1.9–2.1MB + 精灵 1.17MB + LVGL ~0.3MB ≈ **3.4MB < 3.72MB(余量~0.3MB,紧但够)**。更宽松可:用单 app 分区(免 OTA)/ 只编核心动画子集。**非阻塞** |
| D4 | 映射表是否合理 | 评审时可调;不阻塞架构 |
| D5 | 是否上多会话/HUD/SFX | 列为可选 Task6,默认不做 |
