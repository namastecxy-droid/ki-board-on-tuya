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

## M1.5 — 修复启动崩溃：ai_chat_init 前先起 Tuya IoT 栈 ✅ 本轮完成
> 真机烧录 dual_cloudasr 后**黑屏**。日志:`ai chat mode register mode 0 success`
> 之后立刻 MemFault @ `0x00000008`(thread `ak_app`)。根因:`ak_asr_init` 调
> `ai_chat_init` 时**从未初始化 Tuya IoT/AI-service 上下文**(FP-3 在 ai_chat_init
> 前做了 `tuya_iot_init`+`netmgr`,产品 app 没有)→ 解引用空句柄硬崩。
- [x] 新增门控模块 `ak_cloud.c/.h`(`#if AK_ASR_BOARD_CLOUD`):
      `ak_cloud_init()` = tal_kv/sw_timer/workq/time_service + tuya_authorize +
      `tuya_iot_init({PID,uuid,authkey,event_handler,network_check})` + netmgr_init +
      netmgr_conn_set(NETCFG_TUYA_BLE|WIFI_AP);`ak_cloud_start()` = tuya_iot_start +
      独立 `tuya_iot_yield` 线程(不阻塞输入/RX 主循环)。v1/BLE 为编译 stub。
- [x] 新增 `tuya_config.h` + `ak_tuya_authkey.h.example`(同 FP-3):PID + License 宏;
      真实 `ak_tuya_authkey.h` 被 gitignore(`**/*authkey*`)。
- [x] `user_main` 接线:**LCD 最先**(显示不依赖云栈)→ `ak_cloud_init()` →
      **仅当 IoT 起栈成功才** `ak_asr_init()`(否则跳过,避免再崩,退化为纯键盘)→
      `ak_cloud_start()`。
- [x] `dual_cloudasr.config`:禁 `ENABLE_COMP_AI_DISPLAY` + 非 HOLD 的 AI 模式(对齐 FP-3)。
- [x] **EC2 验证**:cloudasr `BUILD_EXIT=0`(我方代码 + AI 栈零错、产出 QIO bin)
      **且** v1 UART 仍 `BUILD_EXIT=0`(门控未破坏默认档)。

### 构建前置(重要)
- cloudasr 构建**需要** `firmware/app/include/ak_tuya_authkey.h`(gitignored)。从
  `ak_tuya_authkey.h.example` 复制并填入 PID/UUID/AuthKey;或先用占位值编译、真机烧
  License 后由 `tuya_authorize_read()` 运行时提供。缺此文件编译会报头文件缺失。

## M2 — 真机端到端验证（用户侧，需硬件 + License + 配网）
- [ ] 用 `dist/app_0.1.0/app_QIO_0.1.0.bin` 从 Windows 烧录（`scripts/flash.ps1`）。
- [ ] **验证不再黑屏/崩溃**:应先显示 "waiting for Kiro Crew",且 `ai_chat_init`
      不再 MemFault(有了 IoT 上下文 + 守卫)。
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
