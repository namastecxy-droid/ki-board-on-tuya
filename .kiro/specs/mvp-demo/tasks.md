# MVP Demo · Tasks (里程碑计划)

> 每个 probe 是一个里程碑;开工前先写该 probe 的 `.kiro/specs/feature-probes-<name>/` 三件套,
> 再实现 + 构建 + host 单测。`[ ]/[~]/[x]`。

- [x] **FP-1 · agent-display**(MVP 显示层)✅ — LVGL 场景+吉祥物+通知条+按键意图,rotation 270 真机 OK。spec `feature-probes-agent-display`。

- [x] **FP-2 · ble-gatt-link**(无线地基)✅ — BLE 广播/连接/订阅、按键/导航 notify、PC→板 write、断开重广播均已实现并真机通过；companion 已兼容 Tuya BLE V1/V2。

- [x] **FP-3 · tuya-cloud-asr**(板载云 ASR)✅ — HOLD/PTT、设备激活与 2.4G Wi-Fi、`AI_USER_EVT_ASR_OK` → UART0 `asr` JSONL 均已实现并真机通过（2026-09-13 用户确认）。

- [ ] **FP-4 · kirocrew-control**(companion→Crew)
  - spec;Rust 连 Gateway `:5476` REST+WS;四类操作(绑定/输入/发送/切换)+ 事件订阅回流
  - 审批 approve_once/reject + 双端一致 + 断线 `list_slots()` 重建
  - 验收:companion 收到板端文字 → 进 Crew 当前对话;Crew 状态回流(先打印,后接 FP-1 显示层)

- [ ] **FP-5 · pc-asr-activate**(PC ASR)
  - spec;板键 `VOICE_PC_*` → companion WinRT ASR → 文字进 Crew(复用 FP-4 注入路径)
  - 验收:按键说话 → Windows ASR 文字进 Crew

- [ ] **FP-6 · ble-hid-fallback**(兜底,独立)
  - spec;原生 NimBLE HID(描述符+SM/配对)独立固件;输入文字+回车+快捷键切换
  - 验收:无 companion,板子被 PC 识别为键盘并能输入/发送/切换

- [ ] **FP-7 · mvp-integration**(端到端)
  - spec;无线+双 ASR+控制 Crew 串起;FP-1 显示层接真实 Crew 事件(状态/通知/审批区)
  - 演示脚本覆盖 DoD 全部;真机走查

## 推荐推进顺序
1. ~~**FP-2 BLE GATT + FP-3 云 ASR**~~ ✅ 已完成并真机通过→
2. **FP-4 / FP-5 Windows 验收**（companion 控制、系统 ASR）→
3. **FP-7 整合** + FP-1 显示层接真实事件 →
4. **FP-6 BLE HID 真机闸门**（配对、复连、发键）

## 每个 probe 的门禁(沿用项目约定)
`tos.py build` 通过 · clang-format clean · 纯逻辑 host 单测 · check_pins(涉及引脚时)· README(操作/预期)。
