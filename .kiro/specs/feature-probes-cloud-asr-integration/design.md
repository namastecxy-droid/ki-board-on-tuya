# FP-7 云 ASR 集成 设计

## 端到端数据流（云模式）

```
K4 按下/松开
  └─(firmware) on_ptt_edge():
        if s_voice_source==CLOUD && ak_asr_available():
            ak_asr_start() / ak_asr_stop()          # tuya_ai_input_start/stop
        else:                                        # stub / 未联网 → 降级
            send_voice("start"/"stop")               # 交给 PC 侧 ASR
  └─(firmware) 云识别完成 → AI_USER_EVT_ASR_OK
        └─ on_asr_text(text) → ak_proto_asr() → transport_write_frame  # `asr` 帧
  └─(companion) Inbound::Asr → route_input → ControlAction::Compose(text)
        └─ WinController::compose(): focus() + type_text_raw(text)     # 不自动提交
  └─ 用户按 K5 → Enter → 提交
```

## 编译期装配（Mechanism A）

- `firmware/app/Kconfig`：`config AK_ASR_BOARD_CLOUD ... select ENABLE_AI_COMPONENTS`
  —— 设 `CONFIG_AK_ASR_BOARD_CLOUD=y` 时，Kconfig 反向依赖自动把 AI 栈
  （`src/ai_components/*`、`src/tuya_ai_service/*`）纳入构建（**已验证**：编译命令
  中出现 `ai_agent/include`、`tuya_ai_service` 等 include 路径）。
- `firmware/app/CMakeLists.txt`：`CONFIG_AK_ASR_BOARD_CLOUD==y` → `-DAK_ASR_BOARD_CLOUD=1`；
  `ak_asr.c` 据此选择真实后端 vs stub。
- Profile：`config/TUYA_T5AI_CORE_dual_cloudasr.config` 设
  `AK_TRANSPORT_DUAL=y` + `AK_ASR_BOARD_CLOUD=y` + `ENABLE_COMP_AI_MODE_HOLD=y`
  + `ENABLE_AI_LANGUAGE_ENGLISH=y` + `TUYA_PRODUCT_ID`（绑定 AI agent 的 PID）。

## 真实后端（ak_asr.c，`#if AK_ASR_BOARD_CLOUD`）

- `ak_asr_init`：`ai_chat_init(AI_CHAT_MODE_HOLD, evt_cb=__ai_event_cb)`。K4 仍归
  `ak_input` 所有（不注册 ai_chat 按钮），由 `on_ptt_edge` 直接驱动
  `tuya_ai_input_start/stop`，故同一物理键同时服务 system / cloud 两路。
- `ak_asr_available`：`s_ai_ready && netmgr LINK_UP`（联网即已授权/配网）。
- `__ai_event_cb`：仅 `AI_USER_EVT_ASR_OK` → `__emit_text` → 回调；其余（ASR_ERROR/
  TTS_*）不转发（键盘场景不朗读回复）。

## 构建注意事项（重要，operational）

- 云 ASR profile 会拉入完整 AI 栈 + `WIFI_BLE_COEXIST`，**冷构建可能触发 SDK
  平台构建（armino/ninja）的并行竞态**：表现为
  `sdkconfig.h: No such file or directory`、`*.obj.d: No such file or directory`、
  `ar: unable to copy 'libbk7258.a'; No such file or directory` —— 这些是**目标目录/
  生成头文件未就绪时并行任务抢先写入**，**不是本 app 代码或云 ASR 配置的问题**。
- **对策**：不 clean，**重跑 `tos.py build`（增量）几次直到收敛**。本探针实测：
  第 1 次冷构建失败(sdkconfig/obj.d)、第 2 次越过到 `libbk7258.a`、第 3 次
  `BUILD_EXIT=0` 产出 `dist/app_0.1.0/app_QIO_0.1.0.bin`。

## 运行前置（真机，用户侧）

1. 设备 License（UUID/AuthKey）—— 授权文件，**不入库**（见 `ak_tuya_authkey.h.example`）。
2. Wi-Fi 配网（2.4G）；`ak_asr_available` 依赖 `netmgr LINK_UP`。
3. PID 绑定到一个 Tuya AI agent（profile 里的 `TUYA_PRODUCT_ID`）。
4. `AI_LANGUAGE` 与实际说话语言匹配。

## companion 侧可选增强（R2 降级）

当前云模式下 companion `route_voice(Cloud)=Ignore`；若板子因后端未编入而 fallthrough
发 `voice.start`，PC 端不会兜底激活 Win+H。可选改进：companion 在"云选中但收到
`voice.start`（说明板子没做云 ASR）"时降级激活 PC 听写，避免"没反应"。**仅在不打开
云 ASR 后端时才有意义**；打开后端后板子会发 `asr` 帧，无需此降级。
