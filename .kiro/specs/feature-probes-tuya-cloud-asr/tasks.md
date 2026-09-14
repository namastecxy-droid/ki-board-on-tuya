# FP-3 tuya-cloud-asr · Tasks

> spec→编码一气做完。风险优先：先把"能激活+联网+ai_chat 编译通过"打通(硬门槛)，
> 再接 ASR 事件输出。勾选：`[ ]` 未开始 / `[~]` 进行中 / `[x]` 完成。

- [x] **T1 — 脚手架 + license 头机制（R1/R5）** ✅ 2026-09-09
  - license 头基础设施：`ak_tuya_authkey.h.example`(tracked) + `.gitignore` 负向规则；`tuya_config.h` 把 `AK_TUYA_*` 接到 SDK 宏
- [x] **T2 — 激活 + 联网 + tuya_iot（R1/R2）** ✅ 2026-09-09（D8 派生自 your_chat_bot 的 tuya_main.c，`tuya_authorize`→`tuya_iot_init`→`netmgr` 配网）
- [x] **T3 — ai_chat + 语音键（R3）** ✅ 2026-09-09
  - **偏差**：`ai_chat` 用 `AI_CHAT_MODE_HOLD`(按住说话/PTT) 而非 ONESHOT——更贴合 K4-PTT 交互设计；可在 `app_chat_bot_init` 改
- [x] **T4 — ASR 事件 → UART JSONL（R4）** ✅ 2026-09-09
  - `app_chat_bot.c` 加 `__fp3_emit_asr()` + `AI_USER_EVT_ASR_OK/ERROR/EMPTY` 分支，经 `ak_uart` 输出；`ak_uart_init()` 在 init
  - **BUILD SUCCESS**，AP 1.77MB/3.5MB
- [x] **T5 — 收尾** ✅ 2026-09-09
  - probe README（含 D8 provenance/Apache-2.0）+ 路线图状态更新；Kconfig `select ENABLE_AI_COMPONENTS` 拉 AI 组件栈
  - **实现方式**：D8 整体派生 your_chat_bot 后裁剪(去 display2/battery/其他板 config)，非最小手写

- [x] **T6 — 真机验收（DoD）** ✅ 2026-09-13（用户确认）
  - v1.2 板完成烧录、2.4G Wi-Fi 配网和设备激活/联网
  - 按语音键说话后，云 ASR 识别结果通过 UART0 `asr` 文字帧输出
  - FP-3 板载 Mic → Tuya 云 ASR → JSONL 链路真机通过

## 依赖顺序
T1 → T2（硬门槛）→ T3 → T4 → T5 →（真机）T6。
若 T2/T3 最小裁剪编译受阻，走 D8 回退：整体复制 your_chat_bot 再删减。

## 构建命令
```bash
cd /data/projects/TuyaOpen && . ./export.sh
cd /data/projects/tuya-powered-agentic-keyboard-for-kiro/firmware/feature-probes/tuya_cloud_asr
cp include/ak_tuya_authkey.h.example include/ak_tuya_authkey.h   # 首次：填入真实 license
tos.py config choice -c TUYA_T5AI_CORE.config
tos.py clean -f && tos.py build
```
