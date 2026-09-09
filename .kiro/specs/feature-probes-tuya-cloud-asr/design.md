# FP-3 tuya-cloud-asr · Design

## D1 — 参考与裁剪

基线 = `TuyaOpen/apps/tuya.ai/your_chat_bot`（同板 `TUYA_T5AI_CORE`）。保留其
**激活 + 联网 + ai_chat ONESHOT + Mic + ASR 事件**，裁掉 TTS 播放 UX、LVGL 显示
(`# CONFIG_ENABLE_COMP_AI_DISPLAY is not set` 已如此)、低功耗 app、打印机等。

## D2 — license 注入（gitignored 头，用户指定方式）

沿用参考实现的 `tuya_config.h` 模式：

```
firmware/feature-probes/tuya_cloud_asr/include/
├── ak_tuya_authkey.h          # gitignored（**/*authkey* 命中）— 真实 UUID/AuthKey/PID
└── ak_tuya_authkey.h.example  # tracked 模板（占位值 + 填法说明）
```

`ak_tuya_authkey.h` 定义：
```c
#define AK_TUYA_PRODUCT_ID  "xxxxxxxxxxxxxxxx"
#define AK_TUYA_UUID        "uuidxxxxxxxxxxxxxxxx"     // 20 chars
#define AK_TUYA_AUTHKEY     "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" // 32 chars
```
`tuya_app_main.c` `#include "ak_tuya_authkey.h"`；若缺失，用 `#error` 提示从 `.example`
复制并填 `docs.local/tuya_keys.txt` 的值。`.gitignore` 追加显式一行
`ak_tuya_authkey.h`（双保险，除已有 `**/*authkey*`）。

> 值的来源：`docs.local/tuya_keys.txt`（gitignored）。**Agent 不读取/回显密钥值**；
> 由用户把值填入 `ak_tuya_authkey.h`（或我按用户口述/授权写入该 gitignored 文件）。

## D3 — 初始化时序（照搬 your_chat_bot/tuya_main.c，裁剪版）

```c
user_main():
  ak_uart_init(); ak_input_init();
  tuya_authorize_init();
  tuya_iot_license_t lic;
  if (tuya_authorize_read(&lic) != OPRT_OK) {          // 读不到走编译进的 license
      lic.uuid = AK_TUYA_UUID; lic.authkey = AK_TUYA_AUTHKEY;
  }
  tuya_iot_init(&client, {.productkey=AK_TUYA_PRODUCT_ID, .uuid=lic.uuid, .authkey=lic.authkey, ...});
  netmgr_init(NETCONN_WIFI);
  netmgr_conn_set(NETCONN_WIFI, NETCONN_CMD_NETCFG, {NETCFG_TUYA_BLE|NETCFG_TUYA_WIFI_AP});
  app_asr_init();          // 我们的：ai_chat_init(ONESHOT, evt_cb) + 语音键绑定
  tuya_iot_start(&client);
  loop: ak_input_poll(now, on_input);   // 语音键 -> 触发 ONESHOT
```

## D4 — ai_chat 初始化与触发

- `ai_chat_init(&(AI_CHAT_MODE_CFG_T){ .default_mode = <ONESHOT enum>, .default_vol = 70, .evt_cb = on_ai_evt });`
  - ONESHOT 的枚举来自 `ai_manage_mode.h` 的 `AI_CHAT_MODE_E`（编译时确认具体名）。
- 触发方式：一期用**语音键(KEY1)** 触发一次采集。ONESHOT 组件通常绑定 button
  （参考用 `ai_chat_button`）；两条可选，编译时择一：
  - (a) 复用参考的 button 绑定（`tdl_button` + `CONFIG_BUTTON_NAME`）；
  - (b) 用我们的 `ak_input`，在 `on_input` 里调用 ONESHOT 组件暴露的"开始采集"入口。
  设计倾向 (a)（与组件默认集成路径一致，少踩坑），KEY1 复用为 ai_chat button。

## D5 — ASR 事件 → 输出

```c
on_ai_evt(AI_NOTIFY_EVENT_T *e):
  case AI_USER_EVT_ASR_OK:  t=(AI_NOTIFY_TEXT_T*)e->data;
       ak_uart 输出 {"v":1,"type":"asr","payload":{"text":"<t->data>","ms":<t->timeindex>}}\n
  case AI_USER_EVT_ASR_ERROR/EMPTY: 输出 {"type":"asr","payload":{"error":...}}
```
- 文字里的 `"`/`\`/控制字符做最小 JSON 转义（复用/新增一个小 helper）。
- 协议扩展：现有 `ak_protocol` 无 ASR-text 帧；本 probe 先就地拼帧，若 FP-7 合流保留，
  再回填 `ak_proto_asr()` 到 `ak_protocol` + `shared/protocol/protocol.md`。

## D6 — config（组件集）

以 `your_chat_bot/config/TUYA_T5AI_CORE.config` 为基线（PID 换成占位/由头注入），
关键：`CONFIG_BOARD_CHOICE_TUYA_T5AI_CORE=y`、AI 组件默认集（COMP_AI_AUDIO / AI 模式
ONESHOT / tuya_cloud / netmgr / wifi / bluetooth 供配网），**关闭** LVGL 与 AI_DISPLAY
以省 AP。确切 `CONFIG_ENABLE_*` 集合在 T1/T2 编译时对齐参考实现逐一确认（ai_chat 的
组件依赖较隐式，靠 Kconfig 默认拉入）。

## D7 — 与正式 firmware 的关系

`app_asr_init` + `on_ai_evt` 是正式固件"板载云 ASR 语音源"的原型；FP-7 合流时，ASR 文字
不再打 UART，而是经 FP-2 的 BLE GATT notify 发给 companion → Kiro Crew。ONESHOT 触发键
最终对应交互设计里的"语音键"。

## D8 — 风险与回退

- ai_chat 组件集庞大/隐式：若最小裁剪编译困难，**回退策略** = 直接以 `your_chat_bot`
  为模板整体复制到 probe，再逐步删 UX，先保证"能取到 ASR 文字"。
- AP 上限：优先关 LVGL/AI_DISPLAY/TTS 播放；若仍超限，记录并在 spec 标注。
- ONESHOT 触发入口若组件未暴露非 button 接口，则采用 D4(a) button 路线。
