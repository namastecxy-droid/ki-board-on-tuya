# FP-3 tuya-cloud-asr · Requirements

## 背景与目标

MVP 要求(3)：**板载 Mic → 涂鸦云 ASR → 取到识别文字**。本 probe 在真机上把这条链路
跑通：一个按键触发一次语音采集（ONESHOT），语音上云做 ASR，`AI_USER_EVT_ASR_OK`
回调里拿到文字，并以协议 v1 JSONL 输出（UART0 观测；后续与 FP-2 合流后走 BLE 给
companion → Kiro Crew）。

参考实现：`/data/projects/TuyaOpen/apps/tuya.ai/your_chat_bot`（同板 `TUYA_T5AI_CORE`）。
本 probe 是它**裁剪到"只取 ASR 文字"**的最小版：保留激活 + 联网 + `ai_chat` ONESHOT +
Mic 采集 + ASR 事件；去掉 TTS 播放 UX、LVGL 显示、低功耗等与"取文字"无关的部分。

**非目标**：不做 TTS 语音回复播放、不做 LCD 显示、不做 FREE/唤醒词模式（一期 ONESHOT）、
不做 companion/BLE 下发（FP-2 已单独验证，合流在 FP-7）。

## 术语

- **激活/license**：设备用 UUID+AuthKey(+PID) 向涂鸦云认证，取得连接 token。
- **ONESHOT**：按一下键采集一段语音、上云识别一次的模式（`ai_chat` 模式之一）。
- **ASR 文字**：`AI_USER_EVT_ASR_OK` 回调携带的 `AI_NOTIFY_TEXT_T{data,datalen,timeindex}`。

## 需求 (EARS)

### R1 — 设备激活（license 走 gitignored 头）
- R1.1 THE 固件 SHALL 通过 `tuya_authorize_init` + `tuya_authorize_read` 读取 license；读不到时回退到编译进固件的 `TUYA_OPENSDK_UUID/AUTHKEY`(+`TUYA_PRODUCT_ID`)。
- R1.2 THE UUID/AuthKey/PID SHALL 存放在**一个不被 git 跟踪的头文件** `ak_tuya_authkey.h`（命名匹配 `.gitignore` 的 `**/*authkey*`）；仓库只跟踪一份 `ak_tuya_authkey.h.example` 模板（占位值）。真实头文件绝不提交。
- R1.3 IF 头文件缺失, THEN 编译 SHALL 明确报错并提示从 `.example` 复制并填入 `docs.local/tuya_keys.txt` 的值。

### R2 — 联网
- R2.1 THE 固件 SHALL 用 `tuya_iot_init` + `netmgr` 建立联网；配网方式沿用参考实现（`NETCFG_TUYA_BLE | NETCFG_TUYA_WIFI_AP`），首连需一次配网。
- R2.2 设备只连 2.4GHz Wi-Fi（硬件约束）。

### R3 — ai_chat ONESHOT
- R3.1 THE 固件 SHALL 以 `ai_chat_init(AI_CHAT_MODE_CFG_T{default_mode=ONESHOT, default_vol, evt_cb})` 初始化对话，注册事件回调。
- R3.2 THE 系统 SHALL 用一个**语音键**（默认 KEY1）触发一次 ONESHOT 采集。

### R4 — 取 ASR 文字并输出
- R4.1 WHEN 收到 `AI_USER_EVT_ASR_OK`, THE 回调 SHALL 从 `AI_NOTIFY_TEXT_T` 取出文字，并以协议 v1 JSONL 帧 `{"v":1,"type":"asr","payload":{"text":"…","ms":<timeindex>}}` 输出到 UART0。
- R4.2 WHEN 收到 `AI_USER_EVT_ASR_ERROR` / `AI_USER_EVT_ASR_EMPTY`, THE 系统 SHALL 输出相应的错误/空结果 JSONL，便于排障。
- R4.3 THE 系统 SHALL 打印联网/激活状态变化到 UART0（`link`/`net` 状态帧）。

### R5 — 自包含与工程约定
- R5.1 THE probe SHALL 是 `firmware/feature-probes/tuya_cloud_asr/` 下自包含 TuyaOpen app，`tos.py build` 可编译。
- R5.2 THE probe SHALL 复用 `firmware/app/common` 的 `ak_uart`（UART0 输出）；输入沿用 `ak_input`。
- R5.3 THE probe SHALL 通过 `clang-format --Werror`。
- R5.4 license 头文件 SHALL 被 `.gitignore` 排除；提交前 `git status` 不得出现真实 authkey 文件。

## 验收 (Definition of Done)

- 从 `.example` 复制出 `ak_tuya_authkey.h` 并填入 `docs.local/tuya_keys.txt` 的 UUID/AuthKey/PID 后，`tos.py build` 通过、`clang-format` clean。
- 上板首连完成配网后，设备激活并联网成功（UART 打出 `net:online` 类状态）。
- 按语音键说一句话 → UART0 打出 `{"type":"asr","payload":{"text":…}}`，文字与所说内容一致。
- ASR 错误/空结果有对应 JSONL。
- README 写清 license 填法、配网步骤、操作与预期；feature-probes 路线图更新。

## 已知风险 / 待办

- **组件依赖大**：ai_chat 需要一整套 AI 组件 + audio codec + tuya_cloud + netmgr，config 组件集以参考 `your_chat_bot/config/TUYA_T5AI_CORE.config` 为准，编译时迭代确认。
- **AP 用量**：ai_chat 组件较大，需关注是否逼近 3.5MB AP 上限（去掉 LVGL/TTS 可省）。
- **真机验收**：激活/联网/Mic/云 ASR 全部只能在 v1.2 板 + 2.4G Wi-Fi + 有效 license 下验证；EC2 只保证编译通过。
