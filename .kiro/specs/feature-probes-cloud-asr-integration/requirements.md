# FP-7 云 ASR 集成（cloud-asr-integration）需求

> 目标：把 **FP-3 已验证的 Tuya 云 ASR** 真正集成进**产品固件** `firmware/app`，
> 让"涂鸦云 ASR"路径端到端跑通：板载麦克风 → 云 ASR → `asr` 文本帧 → PC companion
> 打进 Kiro Crew 输入框 → 用户按 K5 提交。

## 背景

- **FP-3（`feature-probes-tuya-cloud-asr`）** 已在真机验证云 ASR 可行（ai_chat HOLD
  模式 + Tuya AI agent），但那是**独立探针**。
- 产品固件 `firmware/app` 已把该能力移植为 `ak_asr.c`（真实后端 + stub），并接好了
  调用点（`on_ptt_edge` → `ak_asr_start/stop`，`on_asr_text` → `ak_proto_asr` 发 `asr`
  帧）。但真实后端由编译开关 **`AK_ASR_BOARD_CLOUD`（默认 0 = stub）** 关着。
- companion 侧已就绪：`route_input` 把 `asr`/`macro` 文本帧路由到 `Compose`（打进输入框、
  不自动提交）；云模式下 `route_voice(Cloud)=Ignore`（不抢 PC 的 Win+H）。

## 需求

### R1 云 ASR 可编入产品固件
- 存在一个构建 profile 打开 `AK_ASR_BOARD_CLOUD`，且真实后端所需的 AI 栈
  （`ENABLE_AI_COMPONENTS`）被正确拉入。
- **验收**：该 profile `tos.py build` 产出可烧录固件（EC2 可验证）。

### R2 K4 云路径行为正确
- 云模式下按住 K4 → `ak_asr_start`；松开 → `ak_asr_stop`；识别结果经
  `AI_USER_EVT_ASR_OK` → `on_asr_text` → `asr` 帧发给 PC。
- 后端不可用（stub / 未联网）时降级：板子发 `voice.start/stop`，由 PC 侧 ASR 兜底。
- **验收**：真机上云模式说话后，PC 端 Kiro Crew 输入框出现识别文字，且**不自动提交**。

### R3 不回归其它 profile
- v1 UART / v2 BLE / dual 等既有 profile 不受影响；仓库**默认 active profile 保持 v1**，
  云 ASR 变体用 `tos.py config choice -c <profile>` 显式选择。

### R4 运行前置条件文档化
- 明确列出真机跑云 ASR 的前置：设备 License（UUID/AuthKey，**不入库**）、Wi-Fi 配网、
  绑定 AI agent 的 PID、2.4G Wi-Fi。

## 非目标
- 不在本探针内做本地（离线）ASR（属 Phase 3）。
- 不改动 companion 的既有 route B / 状态 sink 行为。
