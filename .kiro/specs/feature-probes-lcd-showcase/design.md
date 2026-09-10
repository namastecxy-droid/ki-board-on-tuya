# FP-lcd-showcase · Design

## 总体

一个**纯显示示例** probe：在 FP-1 已验证的 LVGL + ST7789 底座上，画出产品的
**信息密集状态界面**，吉祥物降为角落点缀。按键只用来在若干**示例界面态**间切换，
逐一展示界面长什么样。

```
5键+5向 --(ak_input, 复用)--> showcase_map(纯映射) --> showcase_intent_t
   --> showcase_state --> showcase_view_t 快照
        --> ak_hud (LVGL 富信息布局) + ak_scene (角落吉祥物, 复用) + ak_notify_ui (通知条, 复用)
        --> LVGL --> ST7789 (320x240 横屏 rotation 270)
```

**关键分层**：`showcase_view_t` 是「状态」与「绘制」之间的稳定快照边界。FP-4 用真实
Kiro 数据填同一个 `showcase_view_t`，即可驱动同一套 HUD，无需改绘制层。

## 复用 vs 新增

| 模块 | 来源 | 处理 |
|---|---|---|
| `ak_panel.c/.h` | FP-1 | **原样复用**（ST7789 rotation 270 注册） |
| `ak_scene.c/.h` | FP-1 | **原样复用**（角落吉祥物；用 `ak_scene_set_anim` / `play_oneshot`） |
| `app_rle_sprite.h` + `assets/generated/sprite_mascot_*.h` | FP-1（移植自 CodeTank） | **原样复用** |
| `ak_notify_ui.c/.h` + `app_notification.c/h` | FP-1 | **原样复用**（示例通知态） |
| `ak_input.c/.h` + `ak_input_fsm.c/.h` | `firmware/app/common` | **原样复用**（5 键+5 向扫描） |
| `ak_event.h` | FP-1 | 参考分层；本 probe 用自己的 `showcase_intent_t` |
| `ak_hud.c/.h` | **新增** | 富信息 HUD 布局（顶栏/槽位/上下文/底栏） |
| `showcase_state.c/.h` | **新增** | 示例状态机 + 界面态↔吉祥物映射 |
| `showcase_map.c/.h` | **新增** | 按键→示例意图（纯函数, host 可测） |
| `tuya_app_main.c` | **新增** | 入口，串起来 |

> 复用方式与 FP-1 CMakeLists 一致：`AK_APP_COMMON = ../../app/common`，把
> `ak_input.c` / `ak_input_fsm.c` 加进 `target_sources`；`ak_panel.c` / `ak_scene.c` /
> `ak_notify_ui.c` / `app_notification.c` 需从 FP-1 目录**软复制到本 probe 的 src/**
> （probe 之间自包含，不跨目录引 src，与 bring-up 约定一致）。头文件同理复制到 include/。

## 屏幕布局（320×240 横屏）

```
┌───────────────────────────────────────────────────────────┐  y=0
│  KiroCrew  ·  PTT  ·  eff:High         [WiFi] ON   v0.1.0   │  顶栏 h=22
├──────────────┬──────────────┬─────────────────────────────┤  y=22
│  K1  ▸Kilo   │  K2   Sonnet │  K3   —                      │  槽位区 h=64
│  ● Run       │  ○ Idle      │    Empty                     │  (三卡片横排)
│  kiro/crew   │  keyboard    │                              │
├──────────────┴──────────────┴──────────────┬──────────────┤  y=86
│  Context                                    │              │
│  > building firmware...                     │   ╭──────╮   │  上下文主区
│  last: "add rate limiting to upload"        │   │ 吉祥 │   │  h=120
│  [ listening ▁▃▅▂ ]  (录音态时)              │   │ 物角 │   │  右下角吉祥物
│                                             │   ╰──────╯   │
├─────────────────────────────────────────────┴──────────────┤  y=206
│ ◀Back  ▶Approve  ●Details   K4:PTT  K5:Send                │  底栏 h=18
└───────────────────────────────────────────────────────────┘  y=224..240 通知条(复用)
```

- 顶栏、槽位卡片、上下文文本、底栏提示都用 **LVGL label + 圆角矩形/线**（Montserrat 14/28，
  已在 .config 打开）。配色沿用 FP-1 深色底（0x101018）+ Kiro 紫 0xC8B4FF + 青 0x07FF +
  绿 0x07E0 + 红 0xF800 + 灰 0x8410（与 ki-board 一致的语义色）。
- 吉祥物：`ak_scene` 的 LVGL image 对齐到**右下角**（`LV_ALIGN_BOTTOM_RIGHT`），尺寸不放大
  （常规精灵 ~54×68，落在上下文区右侧留白），随聚焦槽状态 `set_anim`。
- 通知条：`ak_notify_ui` 原样，占屏幕最底部；有通知时上浮显示，无则隐藏（与 FP-1 同）。

## 数据结构

```c
/* showcase_state.h */
typedef enum { SLOT_EMPTY, SLOT_IDLE, SLOT_RUN, SLOT_CONFIRM, SLOT_ERROR } slot_status_t;

typedef struct {
    bool          occupied;
    slot_status_t status;
    char          name[16];   /* 槽名/agent 名 */
    char          detail[24]; /* cwd / 会话名 */
} showcase_slot_t;

typedef enum { PLAT_KIROCREW, PLAT_KIROCLI, PLAT_CODEX } platform_t;

typedef struct {
    platform_t      platform;
    char            mode[8];       /* "PTT" / "IDLE" */
    char            effort[8];     /* "High"/"Med"/"Low" */
    bool            connected;
    char            fw[8];         /* "0.1.0" */
    showcase_slot_t slots[3];
    uint8_t         focus;         /* 0..2 当前聚焦槽 */
    bool            recording;     /* PTT 录音态 */
    char            context[40];   /* 上下文主区文本 */
    char            last_msg[40];  /* 最近消息 */
    bool            awaiting_confirm;
} showcase_view_t;                 /* 「状态→绘制」稳定快照 */
```

```c
/* showcase_map.h — 纯函数, 无 SDK/LVGL */
typedef enum {
    SC_INTENT_NONE = 0,
    SC_INTENT_FOCUS_SLOT,   /* arg = 0/1/2 */
    SC_INTENT_PTT_TOGGLE,
    SC_INTENT_SLOT_CYCLE,   /* 聚焦槽状态循环 */
    SC_INTENT_SCENE_STEP,   /* dir = +1/-1 遍历 6 个示例场景 */
    SC_INTENT_NOTIF_TOGGLE,
    SC_INTENT_CONN_TOGGLE,
} showcase_intent_type_t;

typedef struct { showcase_intent_type_t type; int arg; int dir; } showcase_intent_t;

bool showcase_map_translate(bool is_nav, const char *id,
                            int event /* AK_INPUT_EVENT_* */, uint32_t held_ms,
                            showcase_intent_t *out);
```

`showcase_state.c` 消费 `showcase_intent_t`，维护一个 `showcase_view_t`，并派生：
- 调 `ak_hud_render(&view)` 重画 HUD；
- 调 `ak_scene_set_anim()` / `ak_scene_play_oneshot()` 让角落吉祥物随态切换：
  - focus 槽 Run → `THINKING`/`TYPING`，Idle → `IDLE`，Confirm → `ALERT`(one-shot)，
    Error → `CONFUSED`；录音态 → `THINKING`；断连 → `DISCONNECTED`。
- 通知态调 `ak_notify_ui_update()`。

## 6 个示例场景（5 向左右整体遍历）

| # | 场景 | view 关键字段 | 吉祥物 |
|---|---|---|---|
| 0 | 三槽常态 | slots=[Run,Idle,Empty], focus=0 | thinking |
| 1 | 聚焦 K2 | focus=1, slot1=Idle | idle |
| 2 | PTT 录音 | recording=true, context="listening…" | thinking |
| 3 | 待确认 | awaiting_confirm=true, slot0=Confirm | alert(one-shot)→回落 |
| 4 | 通知 | 注入一条 "Build finished" | happy(one-shot) |
| 5 | 断连 | connected=false | disconnected |

K1/K2/K3/K4/K5 在**任意场景内**做局部微调（聚焦/录音/状态循环），5 向左右做**场景整体切换**。

## 线程模型（复用 FP-1）
- `app_thread`：LVGL 初始化 → `ak_panel_register` → `lv_vendor_init/start` → `ak_hud_init` →
  `ak_scene_init` → `ak_notify_ui_init` → `showcase_state_init`（画首屏场景 0）。
- `input_thread`：`ak_input_poll` → `on_input` → `showcase_map_translate` → `showcase_state_apply`。
- 所有 LVGL 对象操作持 `lv_vendor_disp_lock()`（HUD 与 scene 一致）。

## Host 单测
- `test_lcd_showcase.c`：
  - `showcase_map_translate`：各按键→意图正确（不依赖 SDK/LVGL，桩掉 `AK_INPUT_EVENT_*`）。
  - `showcase_state` 场景推进：连续 SCENE_STEP 遍历 0..5 环回；FOCUS/PTT/CONN toggle 改对字段。
  - HUD/scene 绘制不进 host 测（依赖 LVGL），只测纯逻辑。
