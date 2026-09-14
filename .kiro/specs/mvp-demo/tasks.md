# MVP Demo · Tasks (里程碑计划)

> 每个 probe 是一个里程碑;开工前先写该 probe 的 `.kiro/specs/feature-probes-<name>/` 三件套,
> 再实现 + 构建 + host 单测。`[ ]/[~]/[x]`。

- [x] **FP-1 · agent-display**(MVP 显示层)✅ — LVGL 场景+吉祥物+通知条+按键意图,rotation 270 真机 OK。spec `feature-probes-agent-display`。

- [x] **FP-2 · ble-gatt-link**(无线地基)✅ — BLE 广播/连接/订阅、按键/导航 notify、PC→板 write、断开重广播均已实现并真机通过；companion 已兼容 Tuya BLE V1/V2。

- [x] **FP-3 · tuya-cloud-asr**(板载云 ASR)✅ — HOLD/PTT、设备激活与 2.4G Wi-Fi、`AI_USER_EVT_ASR_OK` → UART0 `asr` JSONL 均已实现并真机通过（2026-09-13 用户确认）。

- [ ] **FP-4 · kirocrew-control**(companion→Crew；Hook 待完成)
  - ✅ 本地控制已完成：K1–K3 `Alt+N` 切换会话、K4 输入、K5 提交、摇杆快捷键
  - ⏳ Hook 尚缺：实际安装 → Kiro 事件接收 → 状态映射 → BLE/USB `display` 回流 → LCD 显示
  - 验收：在真实 Kiro Crew 会话中走通 Hook 状态回流，并确认断开/重启后的恢复行为

- [x] **FP-5 · pc-asr-activate**(PC ASR)✅ — Win+H 系统听写激活、cloud/system 路由、
  companion/固件接线与自动降级均已实现，Windows 真机验收通过（2026-09-14 用户确认）。

- [ ] **FP-6 · ble-hid-fallback**(兜底,独立；暂缓处理)
  - compile+link GO；原生 NimBLE HID/HOGP/SM/发键代码已就位
  - 真机配对、复连和键入验收留待后续处理

- [ ] **FP-7 · mvp-integration**(端到端)
  - spec;无线+双 ASR+控制 Crew 串起;FP-1 显示层接真实 Crew 事件(状态/通知/审批区)
  - 演示脚本覆盖 DoD 全部;真机走查

## 推荐推进顺序
1. ~~**FP-2 BLE GATT + FP-3 云 ASR**~~ ✅ 已完成并真机通过→
2. ~~**FP-5 PC ASR Windows 验收**~~ ✅ 已完成并真机通过→
3. **FP-4 Windows 验收 + FP-7 整合**，FP-1 显示层接真实事件 →
4. **FP-6 BLE HID 真机闸门**（已明确暂缓，后续再处理）

## 每个 probe 的门禁(沿用项目约定)
`tos.py build` 通过 · clang-format clean · 纯逻辑 host 单测 · check_pins(涉及引脚时)· README(操作/预期)。
