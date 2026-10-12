# 固件 UART 吞吐诊断报告：PC 写 `pong` 阻塞 300ms~7000ms 根因调查

> 只读调查，未修改任何固件文件。调查范围：`firmware/app/src/tuya_app_main.c`、
> `firmware/app/common/src/{ak_uart.c, ak_rx.c, ak_protocol.c, ak_statuslcd.c, ak_gfx.c, ak_input.c, ak_asr.c, ak_voice_route.c}`。
> `/data/projects/TuyaOpen/`（TAL/TKL UART 驱动源码）与 `/data/projects/tuya-kb/` 在本机（Windows）
> 均不存在/不可达（已用 `Test-Path` 验证），因此 TAL UART 驱动内部的 RX/TX 缓冲与是否中断驱动
> 这一层**无法直接读源码核实**，已在下文明确标出为证据缺口，不做臆测。

## (a) 摘要结论

**最可能根因：固件主循环是单线程轮询结构，`ak_render_status()` 在该循环里同步调用
`ak_statuslcd_flush()`，而 `ak_statuslcd_flush()` 内部用 `while (!s_flush_done) { tal_system_sleep(1); }`
忙等 ST7789 SPI DMA 完成，超时上限 1000ms（`firmware/app/common/src/ak_statuslcd.c:286-291`，
`FLUSH_TIMEOUT_MS = 1000`，第22行定义）。这段忙等发生时，主循环无法回到 `ak_transport_read()`
读取 UART RX，导致板子消费 PC 写入的 `pong`（23 字节）不及时，PC 侧 `write_all` 因对端
USB-UART 桥/板载 RX 缓冲（256 字节，`AK_UART_RX_BUFFER_SIZE`）被占满而阻塞。**

- 300ms~2000ms 的普遍耗时：与单次或叠加 1-2 次 `ak_statuslcd_flush()` 调用（理论 DMA 时间
  ~25.6ms/全屏，但观测需要更长，说明还有 CPU 调度/优先级因素，见证据缺口）量级吻合，
  也与 `ak_statuslcd_flush()` 的 1000ms 超时上限吻合。
- 偶发 5000~7000ms：超出单次 flush 1000ms 上限，说明不是单次 flush 能解释的，更像是
  **多次事件在短时间内连续触发 `ak_render_status()`**（例如 WiFi 状态变化 + transport
  feedback + 其它 UI 刷新连续排队），或者 CPU/调度层面的额外阻塞（任务优先级、Wi-Fi/BLE
  中断占用总线等），这部分在本仓库代码里**没有直接证据**，需要运行时计时日志才能定论（见 (e)）。
- 板子完全空闲、无其它流量时也慢：说明问题**不依赖输入事件**，而是心跳本身触发的渲染路径
  （见下文 `ak_voice_route_update`/`ak_refresh_link_header`/`ak_transport_feedback` 调用链），
  或者是固定存在的调度延迟（主循环每轮 `tal_system_sleep(POLL_INTERVAL_MS=5)`，加上任何一次
  渲染都会把下一次 UART 读取推迟数十毫秒）。

## (b) 固件串口数据通路的实际结构

### 线程模型：单线程轮询，无独立 RX 线程/中断回调

`tuya_app_main.c:1934-2083`（`user_main()` 的主循环）：

```c
while (1) {
    now = tal_system_get_millisecond();
    ...                                   // 电压/UI 状态机检查（轻量）
    ak_input_poll(now, on_input_event);   // 10 个 GPIO 读 + FSM + 手势，轻量
    uint8_t rx[64];
    int got = ak_transport_read(rx, sizeof(rx));   // <- UART RX 在这里被消费
    if (got > 0) {
        ...
        ak_rx_reader_feed(&s_rx, rx, (size_t)got, on_rx_line);  // 同步调用 send_pong() 等
    }
    ...
    if ((uint32_t)(now - last_heartbeat) >= HEARTBEAT_INTERVAL_MS) {
        last_heartbeat = now;
        send_heartbeat(now);              // 板子每 2000ms 发一次 ping
    }
    tal_system_sleep(POLL_INTERVAL_MS);   // 固定 5ms sleep，不管本轮做了多少工作
}
```

整个应用跑在单个 FreeRTOS 任务 `ak_app`（`tuya_app_main.c:2097-2101`，`THREAD_PRIO_1`，
栈 5KB）里。**没有独立的 UART RX 线程、没有 RX 中断回调**：UART 读取完全依赖这个循环
轮询调用 `ak_transport_read()` → `ak_uart_read()` → `tal_uart_read(AK_UART_PORT, ...)`
（`ak_uart.c:33-36`）。

> 证据缺口：`tal_uart_read()`/`tal_uart_write()` 的具体实现（TAL 层是否在更底层用了
> UART 中断 + 环形缓冲，还是纯轮询）在 TuyaOpen SDK 源码里，本机不可达，无法核实。
> 但从应用层看，即使 TAL 内部有中断驱动的 RX 环形缓冲，**应用层把数据从该环形缓冲
> "取出"这一步仍然只在主循环的这一行发生**，所以如果主循环被阻塞住，TAL 内部缓冲
> （由 `AK_UART_RX_BUFFER_SIZE=256` 字节定义，`ak_board_io.h:28`）迟早会被填满，
> 进而影响到板子对 PC 发来的字节的 ACK/流控（USB-UART 桥一般没有真正的硬件流控，
> 表现为板子不再从总线上"取字节"，PC 内核驱动的 TX 缓冲被填满后 `write()` 阻塞）。

### RX 侧：轮询读取 + 同步行组装 + 同步回调

- `ak_transport_read()`（`AK_TRANSPORT_UART` 宏展开为 `ak_uart_read`，`tuya_app_main.c:109-113`）
  每轮最多读 64 字节（`uint8_t rx[64]`，`tuya_app_main.c:2055`）。
- 读到的字节立刻喂给 `ak_rx_reader_feed()`（`ak_rx.c:18-41`），这是纯逐字节扫描，开销很小
  （对 23 字节的 `pong` 帧来说可忽略）。
- 一旦遇到 `\n`，**同步**调用 `on_rx_line()`（`tuya_app_main.c:1517`），在同一调用栈里处理
  `hello`/`ping`/`bye`/`config`/`device_settings` 等类型。对于板子收到的 `pong`（PC 对板子
  `ping` 心跳的应答），`on_rx_line()` 里没有匹配 `"pong"` 的分支，会被忽略——这本身不是问题，
  只是确认了"消费掉这几十字节"这件事本身开销极小，**瓶颈不在于处理 pong 帧的逻辑，而在于
  main loop 多久才能转回来调用一次 `ak_transport_read()`**。

### TX 侧：加锁后直接阻塞式 `tal_uart_write`

`send_pong()`（`tuya_app_main.c:748-752`）→ `transport_write_frame()` 宏 →
`transport_write_frame_sized()`（`tuya_app_main.c:258-266`）：拿 `s_tx_mutex`
（`tal_mutex_lock`），调 `ak_transport_write()` → `ak_uart_write()` → `tal_uart_write()`
（`ak_uart.c:38-41`），再解锁。整个关键区只包一次写调用，**没有在持锁期间做任何耗时操作**
（已逐一核对 `transport_lock()`/`transport_unlock()` 的所有调用点，`tuya_app_main.c`
全文搜索结果显示每个临界区都只包一次 `ak_uart_write`）。所以**互斥锁争用不是本案瓶颈**。

但注意：**板子的 TX（`send_pong`/`send_heartbeat`）和 PC 的问题方向是反的**。用户日志里
`board-tx ... type=pong` 是 PC companion 侧日志，记录的是 **PC 写入 `pong` 帧到板子耗时**。
链路是：板子每 2000ms 主动发 `ping`（`send_heartbeat`，`tuya_app_main.c:741-747`）；
PC 收到后回复 `pong`（PC 侧代码，不在本次调查范围）；**板子必须读到这个 `pong`，PC 的
`write_all` 才能把数据交给内核缓冲并返回**。所以真正的瓶颈环节是板子"读 UART RX"这一步
多久被主循环调度到，而不是板子自己发 `ping`/`pong` 的写入路径。

### 波特率

`AK_UART_BAUDRATE = 115200U`（`ak_board_io.h:27`），`ak_uart_init()`
（`ak_uart.c:14-31`）直接把它填进 `TAL_UART_CFG_T.base_cfg.baudrate`，`flowctrl = NONE`。
115200 的理论速率是 ~11.5KB/s，对十几字节的帧完全够用，**波特率本身不是瓶颈**：
23 字节在 115200 下理论传输时间 <2ms。调试串口（UART1）确实配置为 460800
（`firmware/bringup/key1_uart/.../tuya_app_main.c:107`：
"Debug log remains on UART1 at 460800 baud"），但那是日志口，不是 Companion 通信口
（UART0）。提高 UART0 波特率到 460800 在传输时间上帮助有限（原本就只需 <2ms），
**不会解决主循环被阻塞导致不读 RX 的问题**，只是锦上添花（见 (d) 候选 3）。

### ak_input_poll 频率与开销

每轮主循环都调用一次（`tuya_app_main.c:2052`），`POLL_INTERVAL_MS = 5`
（`tuya_app_main.c:159`），即≈5ms+处理耗时一轮。`ak_input_poll()`
（`ak_input.c:66-91`）对 10 个输入（5 键 + 5 向导航）各做一次 `tkl_gpio_read`
+ FSM 更新，K1-K3 额外跑 `ak_gesture_feed`/`ak_gesture_tick`。这些都是纯 CPU 操作，
GPIO 读取在 Cortex-M33F@480MHz 上通常是亚微秒到微秒级，10 次读取 + 简单状态机，
总开销预计在个位数微秒到低两位数微秒，**不足以解释观测到的几百毫秒级延迟**。

### ping/pong 心跳触发路径

- 板子每 `HEARTBEAT_INTERVAL_MS = 2000ms` 调 `send_heartbeat(now)`
  （`tuya_app_main.c:741-747, 2079-2082`），写出 `{"v":1,...,"type":"ping",...}`。
- PC 收到 `ping` 后回 `pong`（PC 侧实现，不在本仓库调查范围内）。
- 板子收到 `pong` 走 `ak_transport_read` → `ak_rx_reader_feed` → `on_rx_line`，
  因为 `on_rx_line` 没有 `"pong"` 分支所以什么也不做——仅仅是被"读走"这个动作本身，
  对 PC 的 `write_all` 来说就足够让它返回。
- 用户日志里 pong 耗时记录的时间戳间隔（2-10 秒不等）符合 2000ms 心跳周期叠加其它
  触发 RX 读取的事件（如外部 USB 插拔检测、WiFi 状态轮询等）的综合结果。

## (c) 候选根因（按可能性排序）

### 候选 1（最可能）：`ak_render_status()` 内的同步 SPI flush 忙等阻塞主循环

**证据**：
- `ak_statuslcd_flush()`（`ak_statuslcd.c:230-293`）在发起 DMA 后：
  ```c
  s_flush_done = false;                       // ak_statuslcd.c:275
  ...
  rt = tdl_disp_dev_flush(s_disp, s_frame);   // ak_statuslcd.c:278，入队，立即返回
  ...
  uint32_t started_ms = tal_system_get_millisecond();   // ak_statuslcd.c:286
  while (!s_flush_done &&
         (uint32_t)(tal_system_get_millisecond() - started_ms) < FLUSH_TIMEOUT_MS) {
      tal_system_sleep(1U);                   // ak_statuslcd.c:290，忙等，最长 1000ms
  }
  ```
  （`FLUSH_TIMEOUT_MS` 定义在 `ak_statuslcd.c:22`）
- 这个忙等运行在 **主循环所在的同一个 `ak_app` 任务**里（`ak_render_status` 由
  `user_main()` 的主循环直接或间接调用，没有切换任务），期间该任务被 `tal_system_sleep(1)`
  挂起/唤醒，但**不会去执行 `ak_transport_read()`**，因为调用栈卡在 `ak_render_status` →
  `ak_statuslcd_flush` 里，还没返回到 `while(1)` 顶部。
- 全屏 320x240x2 字节 = 153600 字节，SPI 时钟 `AK_LCD_SPI_CLOCK_HZ = 48000000`
  （`ak_board_io.h:65`），理论 DMA 传输时间 ≈153600×8/48e6 ≈25.6ms。但观测到的
  阻塞远大于此，说明 DMA 实际完成时间比理论值高得多（可能受 Wi-Fi/BLE 共享总线、
  PSRAM 带宽、cache 维护 `SCB_CleanDCache_by_Addr`（`ak_statuslcd.c:274`）开销影响），
  或者是多次 flush 连续排队。这部分缺乏运行时实测数据，见 (e)。
- `ak_render_status()` 的触发点很多，且**在板子完全空闲时也会触发**：
  - `ak_voice_ui_tick()`（每轮主循环都调用，`tuya_app_main.c:1946`）在 ASR 结果/超时时
    调 `ak_refresh_link_header()` → `ak_render_status()`；空闲时这条本身不触发，但确认了
    "空闲判断"逻辑本身每轮都要跑。
  - WiFi 状态变化（`s_wifi_status_dirty`，`tuya_app_main.c:1951-1957`）→
    `ak_refresh_link_header()` → `ak_render_status()`：**WiFi 连接状态在空闲时仍可能
    周期性抖动/重连检查**，是空闲场景下仍会触发全屏重绘的来源之一。
  - `ak_transport_feedback()`（`tuya_app_main.c:1432-1443`）在 USB/BLE 连接状态变化、
    provisioning 状态变化（`tuya_app_main.c:1981-1991`，每轮都 `ak_cloud_provisioning()` 判断
    一次，变化时触发）时调用，也会同步重绘整屏。
  - `on_rx_line` 处理 `"hello"` 分支会设置 `s_pc_connected` 并调 `ak_transport_feedback`
    （`tuya_app_main.c:1540-1546`），即**companion 每次重连都会触发一次全屏重绘 + flush**，
    这段时间板子读不到任何后续 RX 字节。
- **一个尤其值得关注的恶性循环**：板子收到 PC 的某个请求 → 触发 `ak_render_status()` →
  进入 1000ms 忙等 flush → 这期间板子完全不读 UART → PC 侧串口驱动 TX 缓冲因为板子
  不读而被填满 → PC 下一次 `write_all`（无论是普通帧还是 `pong`）被阻塞，**直到板子
  下一次循环转回来读 RX**。因为 `ak_render_status` 不是只在用户操作时触发（上面列的
  WiFi/provisioning/transport feedback 都可能在板子空闲时周期性发生），这解释了
  "即使板子空闲、没有其他流量时也慢"这一观测。

**结论**：这是目前仓库代码里唯一能找到的、量级（几十到上千毫秒）与观测现象（300ms~2000ms
常见，偶发到 7000ms）直接吻合的同步阻塞点。多次 flush 连续排队（例如 provisioning 状态
抖动 + WiFi 状态抖动 + hello 重连在短时间内先后触发）可以解释偶发 5000~7000ms（3-7 次
flush 累加,每次最多 1000ms上限）。

### 候选 2（可能，证据不完整）：主循环固定 `tal_system_sleep(POLL_INTERVAL_MS=5)` 叠加任务调度延迟

**证据**：`tuya_app_main.c:2082`，每轮循环结束无条件 sleep 5ms，不是"做完事就立刻继续"
而是"固定节奏"。如果某一轮因为候选1的 flush 多用了几十到上千毫秒，**下一次读 RX 的
时间点也会相应推迟相同的量**，二者是同一个问题的两个描述角度，不是独立根因。

单独来看，如果没有 flush 阻塞，5ms 节奏本身对 23 字节/115200 波特率的心跳帧完全够用
（PC 的 write 缓冲几十字节，板子每 5-10ms 读一次 64 字节完全跟得上）。所以**候选 2
不能独立解释观测现象，只是放大候选 1 的影响**。

### 候选 3（低可能，纯粹辅助因素）：UART RX 缓冲偏小 + 轮询批量读取上限 64 字节

**证据**：`AK_UART_RX_BUFFER_SIZE = 256`（`ak_board_io.h:28`），主循环每轮最多读 64 字节
（`tuya_app_main.c:2055`，`uint8_t rx[64]`）。在 115200 波特率下 256 字节的缓冲可以撑住
约 22ms 的"无人读取"窗口；64 字节/轮如果 RX 积压较多需要多轮才能读完。这个限制在
"主循环被 flush 卡住几十到上千毫秒"的场景下会**加剧**溢出风险（因为 22ms 的缓冲撑不住
动辄几十到上千毫秒的 flush 阻塞），但**不是本案的触发因——即使缓冲更大，PC 的问题
是写阻塞而不是丢数据，只是把"溢出点"推后，并不能消除根本的"板子长时间不读 RX"问题**。

### 候选 4（证据不足，需运行时验证）：TAL UART 驱动层 RX 是否中断驱动、TX FIFO 多大、是否存在额外阻塞

**证据缺口**：TuyaOpen SDK 的 `tal_uart`/`tkl_uart` 源码在本机不可达
（已用 `Test-Path "/data/projects/TuyaOpen"` 确认不存在），因此：
- 无法确认 `tal_uart_read()` 是否命中一个由中断填充的环形缓冲（更合理的实现方式），
  还是每次调用才去查询底层 FIFO（纯轮询，命中率受 CPU 调度影响更大）。
- 无法确认 `tal_uart_write()` 是否在 TX FIFO 满时阻塞板子自身的发送（`send_pong`/
  `send_heartbeat` 侧），但从用户描述（PC 侧阻塞，板子空闲）看，这个方向不是重点。
- 无法确认 `ak_app` 任务的 `THREAD_PRIO_1` 在 TuyaOpen 的优先级体系里相对 Wi-Fi/BLE/
  显示任务是高还是低；如果显示驱动任务（处理 `tdl_disp_dev_flush` 的 DMA 完成中断/任务）
  优先级低于 Wi-Fi/BLE 任务，繁忙的网络活动可能进一步拖慢 flush 完成时间，间接拉长
  候选 1 的忙等时长，这会解释偶发的 5000-7000ms 尖峰。这纯属推测，需运行时实测。

## (d) 修复建议（在 EC2 上实施，按优先级排列）

### 修复 1（直接针对候选 1，优先级最高）：让 LCD flush 变成异步，不阻塞主循环的 UART 读取节奏

**改哪个文件**：`firmware/app/common/src/ak_statuslcd.c`（`ak_statuslcd_flush`），
`firmware/app/src/tuya_app_main.c`（`ak_render_status` 调用处）。

**怎么改**（二选一，推荐方案 A）：

- **方案 A（侵入最小）**：把 `ak_statuslcd_flush()` 改为"入队后立即返回"，不在调用处
  忙等 `s_flush_done`；改为在**下一次主循环顶部**（读 UART 之后）检查 `s_flush_done`，
  如果还没完成就跳过本轮渲染（已有 `s_lcd_redraw_pending` 机制可以复用）。
  即：把当前 `ak_statuslcd_flush()` 尾部那个 `while (!s_flush_done) { tal_system_sleep(1); }`
  拆出来，变成一个新的非阻塞函数（例如 `ak_statuslcd_flush_poll()`），在
  `tuya_app_main.c` 的 `while(1)` 循环里、`ak_transport_read()` **之前**调用一次，
  用来推进"上一次 flush 是否完成"的状态机，而不是在 `ak_render_status()` 里原地等。
- **方案 B（改动更大）**：把渲染/flush 整体移到独立的低优先级任务里，`ak_render_status()`
  只是把"需要重绘"这个标志位设置好（类似现有的 `s_lcd_redraw_pending`），由新任务
  异步消费并调用 `tdl_disp_dev_flush`，彻底与 UART 读取解耦。

**预期效果**：主循环不再因为等待 SPI DMA 完成而延迟数十到上千毫秒去读 UART RX，
`ak_transport_read()` 的调用周期回到稳定的 ~5-10ms，PC 侧 `write_all` 不再因为对端
长时间不读而阻塞。

**验证建议**：复测 PC 侧 `board-tx ... type=pong` 的 `elapsed_ms`，应该从当前的
300-7000ms 收敛到个位数到低两位数毫秒（主要由 5ms 轮询间隔决定）。

### 修复 2（候选 1 的根因缓解，次优先级）：减少空闲时触发全屏重绘的事件数量/频率

**改哪个文件**：`firmware/app/src/tuya_app_main.c`（`ak_voice_route_update`、
`s_wifi_status_dirty` 处理、`ak_transport_feedback` 调用点）。

**怎么改**：
- 给 `ak_render_status()` 增加节流（例如最小重绘间隔 100-200ms），短时间内多次触发
  只保留最后一次，用已有的 `s_lcd_redraw_pending` 标志延后到节流窗口结束再绘制一次,
  避免 provisioning/WiFi/transport feedback 几个来源在同一两秒内各触发一次全屏 flush
  叠加成 5000-7000ms。
- 评估是否真的需要在每次 `on_rx_line` 收到 `"hello"` 时都做一次全屏重绘
  （`tuya_app_main.c:1540-1546`），如果只是刷新连接图标，可以考虑只重绘状态栏/图标区域
  而非整屏（需要 `ak_gfx`/`tdl_disp_dev_flush` 支持局部刷新，是否支持需要再确认 SDK 能力）。

**预期效果**：降低候选 1 事件的触发频率和叠加概率，是修复 1 之外的第二层防御，
即使修复 1 暂不实施，也能缓解偶发的 5000-7000ms 尖峰。

### 修复 3（辅助，低优先级）：加大 UART RX 缓冲 + 每轮多读字节数

**改哪个文件**：`firmware/app/common/include/ak_board_io.h`（`AK_UART_RX_BUFFER_SIZE`），
`firmware/app/src/tuya_app_main.c`（`uint8_t rx[64]` 的大小）。

**怎么改**：把 `AK_UART_RX_BUFFER_SIZE` 从 256 提高到 512 或 1024，把主循环里的
`rx[64]` 提高到 `rx[256]`（注意 `ak_rx_reader_feed` 内部 `AK_RX_LINE_MAX` 要能装下
一整行，确认不会因为单帧超长而触发 `overflow` 丢弃逻辑，见 `ak_rx.c:35-38`）。

**预期效果**：在修复 1 没有完全消除阻塞之前，让 RX 侧能撑住更长时间的主循环阻塞
窗口而不丢数据，但**不能解决 PC 写阻塞的根本问题**，因为 PC 侧阻塞的原因是对端
不读而不是对端丢数据——即使板子缓冲更大，PC 的 `write_all` 仍然会等到板子某次
主循环转回来读取为止。此修复的意义仅是降低"因缓冲溢出导致协议丢帧/错位"的风险，
是防御性而非性能修复。

### 修复 4（辅助，低优先级，仅在确认瓶颈不在 flush 之后再考虑）：UART0 波特率提升到 460800

**改哪个文件**：`firmware/app/common/include/ak_board_io.h`（`AK_UART_BAUDRATE`），
需同步修改 PC companion 侧的串口配置（超出本次固件调查范围）。

**预期效果**：对十几字节的心跳帧传输时间本来就 <2ms，提升波特率收益有限
（不能解决"板子不读 RX"的根本问题）。只有在确认 RX/TX 的瓶颈确实是"字节数据量大、
传输时间本身占比高"（例如将来传输 ASR 音频/大 payload 帧）时才有意义。**不建议
作为本次 pong 延迟问题的首选修复**。

## (e) 仍需的运行时证据（如果以上代码级证据不足以让 EC2 团队直接定论）

建议在固件里加如下计时日志（通过 UART1 的 `PR_NOTICE`/`PR_DEBUG`，不要走 UART0 以免
干扰协议），验证候选 1：

1. 在 `ak_render_status()` 入口和 `ak_statuslcd_flush()` 调用前后各打一个
   `tal_system_get_millisecond()` 时间戳，日志输出本次渲染+flush总耗时，确认是否
   经常达到几十到上千毫秒量级，以及触发源（通过在每个调用点传入不同的 tag 区分
   WiFi/provisioning/hello/ASR 等触发原因）。
2. 在主循环 `while(1)` 顶部记录"上一轮循环耗时"（`now - 上一次记录的 now`），
   统计耗时分布（P50/P95/P99/Max），确认是否存在偶发几百到几千毫秒的单轮循环耗时，
   并与候选 1 的 flush 日志时间戳对齐，确认是否同时发生。
3. 在 `ak_transport_read()` 调用前后记录调用间隔（即两次成功进入这一行之间经过了
   多久），直接量化"板子多久才读一次 UART"，这是与 PC 侧 `elapsed_ms` 最直接可比的指标。
4. 如果怀疑候选 4（TAL UART 驱动/任务调度），需要 TuyaOpen SDK 源码环境（在 EC2 或
   有 `/data/projects/TuyaOpen/` 的机器上）读 `tal_uart_read`/`tal_uart_write`
   的具体实现，确认 RX 是否中断驱动、TX FIFO 大小、以及 `ak_app`（`THREAD_PRIO_1`）
   相对显示/网络任务的实际调度优先级。

---

**结论先行复述**：代码证据指向 `ak_statuslcd.c` 中 `ak_statuslcd_flush()` 的同步忙等
（最长 1000ms/次）是在主循环里阻塞 UART RX 消费的直接原因，而触发它的事件
（WiFi 状态变化、USB/BLE 连接状态变化、provisioning 状态变化、companion hello 重连）
在板子空闲时仍可能发生，这解释了"板子空闲、无其它流量时 pong 也慢"的现象。
偶发的 5000-7000ms 尖峰超出单次 1000ms 上限，推测是多次触发叠加或 CPU/调度层面的
额外因素，这部分需要运行时计时日志才能定论（见 (e)）。
