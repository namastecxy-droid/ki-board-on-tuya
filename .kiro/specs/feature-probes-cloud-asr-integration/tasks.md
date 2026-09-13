# FP-7 云 ASR 集成 任务

## M1 — 云 ASR 编入产品固件（构建门）✅ 本轮完成
- [x] 确认 `ak_asr.c` 真实后端 + 调用点（`on_ptt_edge`/`on_asr_text`/`ak_proto_asr`）已就位（前序已提交）。
- [x] 确认 `Kconfig: AK_ASR_BOARD_CLOUD select ENABLE_AI_COMPONENTS` + CMake `-D` 翻译已就位。
- [x] 确认 profile `TUYA_T5AI_CORE_dual_cloudasr.config`（DUAL + 云 ASR + HOLD + EN）。
- [x] **EC2 构建验证**：`tos.py config choice -c TUYA_T5AI_CORE_dual_cloudasr.config`
      → `tos.py clean -f && tos.py build`（增量重跑收敛并行竞态）→ `BUILD_EXIT=0`，
      产出 `dist/app_0.1.0/app_QIO_0.1.0.bin`；我方代码/AI 栈零错误。
- [x] 还原默认 active profile 为 v1（`app_default.config`），不改变默认构建。
- [x] 文档化构建竞态对策（design.md「构建注意事项」）。

## M2 — 真机端到端验证（用户侧，需硬件 + License + 配网）
- [ ] 用 `dist/app_0.1.0/app_QIO_0.1.0.bin` 从 Windows 烧录（`scripts/flash.ps1`）。
- [ ] 写入设备 License（UUID/AuthKey），完成 2.4G Wi-Fi 配网，确认 `netmgr LINK_UP`。
- [ ] 确认 PID 已绑定 AI agent。
- [ ] 云模式按住 K4 说话 → 观察 UART/LOG 出现 `asr` 帧 → companion 输入框出现文字
      → **不自动提交** → K5 提交。
- [ ] 记录：识别延迟、准确率、断网/未授权时的降级行为。

## M3 — companion 降级增强（可选）
- [ ] 云选中但收到 `voice.start`（板子未做云 ASR）时，companion 降级激活 PC 听写，
      避免"没反应"。仅未打开云 ASR 后端时有意义。

## 验证门
- 固件：`tos.py build`（cloudasr profile）产出物存在 + 我方源零错。
- companion：`cargo check`/`cargo test` + `tsc`/`vite`（本探针不改 companion，除非做 M3）。
- 真机：M2 清单逐项过。

## 备注
- 授权文件（UUID/AuthKey）**严禁入库**。
- 默认 active profile 仍是 v1 UART；云 ASR 变体显式 `tos.py config choice -c` 选择。
