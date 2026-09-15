# FP-WS2812 · WS2812 Chat 状态灯 · Design

## 1. 架构总览

```
 [Probe 阶段]
 5键+5向 ──► ak_input_fsm ──► led_input_map ──┐
                                              ├─► ak_led_intent_t ──► ak_led_state ──► ak_leds ──► SPI1/P4 ──► 3× WS2812
 串口 display 帧 ──► led_frame_parse ──────────┘   (纯逻辑/可单测)   (SDK 驱动)

 [合并进 firmware/app 后]
 companion display 帧 ──► 既有帧处理 ──► ak_led_state_set_slot(...) ──► ak_led_state ──► ak_leds ──► WS2812
 连接状态(心跳丢失)  ──► ak_led_state_set_override(DISCONNECTED)
```

- **接口边界不变**:probe 用 `led_input_map` / `led_frame_parse` 产出 `ak_led_intent_t`;
  合并时用产品固件既有的 `display` 帧处理点直接调 `ak_led_state_set_slot(...)`。
  中间的 `ak_led_state`(状态机)与 `ak_leds`(驱动)**两层完全不变** —— 这就是「保险优先、原型再合并」
  能低风险落地的原因,与 agent_display 探针(`app_event_t` 边界不变)同一套思路。

## 2. 模块清单

### 2.1 本 spec 新增(可复用,合并时随迁 `firmware/app/common/`)
| 文件 | 职责 | 可单测 |
|---|---|---|
| `ak_leds.h` / `ak_leds.c` | 官方 `tdd_pixel_ws2812` 封装:register/open/set/show + 亮度上限 + 失败降级(R1) | 否(碰 SDK,firmware-only) |
| `ak_led_state.h` / `ak_led_state.c` | 灯效状态机:3 槽 + 选中 + 覆盖态;`set_slot/set_selected/set_override/tick`;**纯函数** `ak_led_render`(R2) | 是(SDK-free) |

### 2.2 Probe 专用(合并时**不迁**,被真实事件源替换)
| 文件 | 职责 |
|---|---|
| `led_input_map.h` / `led_input_map.c` | 板载键/5 向 → `ak_led_intent_t`(纯逻辑,可单测) |
| `led_frame_parse.h` / `led_frame_parse.c` | 串口 `display` JSONL 帧 → `ak_led_intent_t`(纯逻辑,可单测) |
| `tuya_app_main.c` | 入口:`ak_leds_init` → 起 tick 线程(动态效果)+ 输入/串口事件源 → `ak_led_state_*` |

### 2.3 复用本项目已有
- `firmware/app/common/include/ak_board_io.h`:`AK_WS2812_SPI_PORT` / `AK_WS2812_DATA_PIN` / `AK_WS2812_COUNT`(R4.2)。
- `firmware/app/common/src/ak_input.c` / `ak_input_fsm.c`:5 键+5 向去抖/长按(与 agent_display 同一套)。
- `firmware/bringup/common/src/bringup_uart.c`:串口收发(probe 的 `display` 帧输入 + `[led]` 日志)。
- **已验证驱动序列**(`firmware/bringup/ws2812/src/tuya_app_main.c`):`tdd_ws2812_driver_register`
  → `tdl_pixel_dev_find` → `tdl_pixel_dev_open` → `tdl_pixel_set_single_color` → `tdl_pixel_dev_refresh`,
  config `CONFIG_ENABLE_LEDS_PIXEL=y`,亮度 level=16。`ak_leds` 就是这段的模块化封装。

## 3. 驱动层 `ak_leds`(R1)

```c
#define AK_LEDS_MAX_LEVEL  16u   /* 编译期亮度上限;3x 全白 ≤ 电池开关 0.3A 安全档(bring-up 已验证) */

OPERATE_RET ak_leds_init(void);                       /* register + open 3 颗;失败返回错误,调用方降级 */
OPERATE_RET ak_leds_set(uint8_t slot, uint8_t r, uint8_t g, uint8_t b); /* 缓存一颗,内部按上限裁剪 */
OPERATE_RET ak_leds_show(void);                       /* refresh 整链 */
bool        ak_leds_ready(void);                      /* init 是否成功,供降级判断 */
```

- `set` 内部对 r/g/b 做 `min(v, AK_LEDS_MAX_LEVEL)` 缩放(R1.3);slot ≥ `AK_WS2812_COUNT` 返回
  `OPRT_INVALID_PARM`(R1.2)。
- init 失败(register/open 任一步)记 `PR_ERR` 并置 `ready=false`,`set/show` 变 no-op(R1.4)——
  灯不亮但设备照常跑。

## 4. 状态机层 `ak_led_state`(R2,纯逻辑)

### 4.1 数据模型(SDK-free,可 host 编译)
```c
typedef enum {                 /* 槽位逻辑状态,对齐交互设计 §6 */
    AK_LED_UNBOUND = 0,        /* 熄灭 */
    AK_LED_IDLE,               /* 白 常亮 */
    AK_LED_RUNNING,            /* 蓝 常亮 */
    AK_LED_TOOL,               /* 蓝 轻呼吸 */
    AK_LED_COMPLETE,           /* 绿 常亮,超时回落 IDLE */
    AK_LED_APPROVAL,           /* 琥珀 呼吸 */
    AK_LED_ERROR,              /* 红 双闪 */
} ak_led_slot_state_t;

typedef enum { AK_LED_OV_NONE = 0, AK_LED_OV_DISCONNECTED } ak_led_override_t; /* 紫 三灯慢闪 */

typedef struct { uint8_t r, g, b; } ak_rgb_t;

typedef struct {
    ak_led_slot_state_t slot[AK_WS2812_COUNT];
    uint32_t            complete_since_tick[AK_WS2812_COUNT]; /* 进入 COMPLETE 的 tick,用于回落计时 */
    int8_t              selected;      /* 当前选中槽 0..2,-1=无 */
    ak_led_override_t   override;
    uint32_t            complete_timeout_ticks;               /* 默认 = 数分钟 / tick 周期 */
} ak_led_state_t;
```

### 4.2 API
```c
void ak_led_state_init(ak_led_state_t *st);
void ak_led_state_set_slot(ak_led_state_t *st, uint8_t slot, ak_led_slot_state_t s, uint32_t now_tick);
void ak_led_state_set_selected(ak_led_state_t *st, int8_t slot);
void ak_led_state_set_override(ak_led_state_t *st, ak_led_override_t ov);
/* 纯函数:给定逻辑状态 + 单调 tick,算出 3 颗即时 RGB。不碰 SDK,可单测断言相位。(R2.3/R2.6) */
void ak_led_render(const ak_led_state_t *st, uint32_t tick, ak_rgb_t out[AK_WS2812_COUNT]);
```

### 4.3 render 规则(基色 × 动态)
- 基色:UNBOUND=(0,0,0)、IDLE=白、RUNNING/TOOL=蓝、COMPLETE=绿、APPROVAL=琥珀(R,~G/2,0)、ERROR=红、
  紫=(R,0,B)。峰值都用 `AK_LEDS_MAX_LEVEL`。
- 动态(`tick` 驱动的确定性函数):
  - **常亮**:恒定基色。
  - **呼吸**(TOOL/APPROVAL):三角波或正弦 LUT,周期 ~2s,亮度在 [level/8, level] 间。
  - **双闪**(ERROR):一个周期内两个短亮 + 长暗(如 100ms 亮/100ms 暗/100ms 亮/700ms 暗)。
  - **慢闪**(断线):方波,周期 ~2s,全紫。
  - **选中叠加短白闪**:选中槽在其基色上,每 N tick 叠加一次极短白(如每 2s 亮 80ms 白),不改其余槽。
- **优先级**:`override==DISCONNECTED` → 三灯全紫慢闪,忽略 slot(R2.5)。否则逐槽算基色+动态,
  选中槽再叠白闪。
- **Complete 回落**(R2.4):`set_slot(COMPLETE)` 记 `complete_since_tick`;render 时若
  `tick - since ≥ complete_timeout_ticks` 视作 IDLE(状态机也可在 tick 里 latch 成 IDLE,二选一,
  design 采用 render 时判定 + tick 时 latch,避免依赖 render 被调用)。

### 4.4 状态机 tick(firmware 侧)
`tuya_app_main` 起一个 ~50ms tick 线程:`ak_led_render(&st, tick++, rgb)` → 逐 slot `ak_leds_set` →
`ak_leds_show`。tick 周期决定动态平滑度与 CPU 占用,50ms(20Hz)足够且开销可忽略。

## 5. display.state → 槽位状态映射(R3.1b / 合并 R5.2)

协议 `display` 帧:`{chat_slot:1..3, agent_name, state:"idle"|"running"|"error", text}`。映射:

| display.state | ak_led_slot_state_t | 备注 |
|---|---|---|
| `idle` | `AK_LED_IDLE` | 若该 slot 上一态是 RUNNING/TOOL 且这是「完成」语义,由 companion 用后续帧或约定表达;probe 阶段 idle 直接映 IDLE |
| `running` | `AK_LED_RUNNING` | Tool running 的「蓝呼吸」由 companion 侧细分(如 `postToolUse` 阶段)映到 `AK_LED_TOOL`;协议未细分时 running=RUNNING |
| `error` | `AK_LED_ERROR` | |
| (slot 无绑定) | `AK_LED_UNBOUND` | 无该 slot 的帧 / 显式解绑 |

> **COMPLETE / APPROVAL / TOOL** 三态在当前协议 `display.state` 三值里没有直接字段。design 决策:
> - probe 阶段:用**按键**直接注入这三态(验证灯效),不依赖协议扩展。
> - 合并阶段:走 companion 的语义细分(Kiro CLI hook 的 `stop`=完成、审批事件=approval、
>   `postToolUse`=tool),由 companion 决定发什么。**是否需要给协议 `display.state` 增枚举值
>   (complete/approval/tool)留作 open 决策 D2**,不阻塞 probe。

## 6. Probe 输入映射(R3.1a,初版,可评审调整)

`led_input_map`:`ak_input_fsm` 产出 (key_id, PRESS/LONG_PRESS) → `ak_led_intent_t`:

| 物理输入 | intent |
|---|---|
| K1/K2/K3 短按 | 选中 slot 0/1/2(`set_selected`) |
| K1/K2/K3 长按 | 该 slot 状态循环 next(UNBOUND→IDLE→RUNNING→TOOL→COMPLETE→APPROVAL→ERROR→UNBOUND) |
| 5向 上/下 | 选中槽状态 prev/next |
| 5向 左/右 | 切换选中槽(-1↔0↔1↔2) |
| 5向 中心 短按 | 切换 override(NONE↔DISCONNECTED) |
| K4/K5 | 预留(空 / 一键全 IDLE 复位) |

每个 intent 落地后打印 `[led] slot=.. state=.. selected=.. override=..`(R3.3)。

## 7. 测试策略

- **host 单测**(x86,SDK-free):
  - `ak_led_render`:各状态基色正确;呼吸在相位 0/半周期的亮度关系;双闪一个周期内亮暗序列;
    断线覆盖忽略 slot;选中叠白闪只影响选中槽;Complete 超时后按 IDLE 渲染。
  - `led_input_map`:全按键→intent 映射表。
  - `led_frame_parse`:合法 `display` 帧解析、`chat_slot` 越界(非 1..3)拒绝、缺字段拒绝。
- **构建验证**:EC2 `tos.py build` 出 bin(probe);合并后 `firmware/app` `tos.py build`。
- **真机验证**(v1.2 板):逐条走 §6 映射,肉眼核对颜色/动态与 §6 表一致;`[led]` 日志匹配。

## 8. 风险与决策

| # | 风险/决策 | 处理 |
|---|---|---|
| D1 | SPI1 与其它外设冲突 | SPI1 整组 P2/P3/P4/P5 已在 `ak_board_io.h` 保留给 WS2812;bring-up 已验证,无冲突。非阻塞 |
| D2 | 协议 `display.state` 仅 idle/running/error,缺 complete/approval/tool | probe 用按键注入这三态验证灯效;合并阶段由 companion 语义细分驱动;**是否扩协议枚举**留 open,不阻塞原型 |
| D3 | 3× 全白峰值电流 vs 电池开关 SK12D07VG5 0.3A | `AK_LEDS_MAX_LEVEL=16`(bring-up 已验证安全档),编译期上限;需要更亮再评估换开关(硬件待办已记录) |
| D4 | tick 线程与已有输入/显示线程 | probe 独立 tick 线程;合并时挂产品固件已有软 timer / 输入线程,不新增冲突(R5.2) |
| D5 | Complete 回落计时依赖 tick 单调性 | `complete_since_tick` 记录 + render 判定 + tick latch 双保险,不依赖 render 调用频率 |
