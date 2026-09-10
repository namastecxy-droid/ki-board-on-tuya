# MVP Demo · Tasks (里程碑计划)

> 每个 probe 是一个里程碑;开工前先写该 probe 的 `.kiro/specs/feature-probes-<name>/` 三件套,
> 再实现 + 构建 + host 单测。`[ ]/[~]/[x]`。

- [x] **FP-1 · agent-display**(MVP 显示层)✅ — LVGL 场景+吉祥物+通知条+按键意图,rotation 270 真机 OK。spec `feature-probes-agent-display`。

- [~] **FP-2 · ble-gatt-link**(无线地基)🔨
  - 已有骨架(Tuya svc 0x1910 / notify 0x2B10 / write 0x2B11 / 广播 AK-KB / JSONL v1 镜像 UART0)
  - 待补:**FP-2 spec 三件套**;广播+连接+CCCD 订阅+MTU 协商;key/nav→notify;write→UART 回显计数
  - 验收:nRF Connect 连上、订阅、按键出 JSONL notify、write 有 `link_rx`;`tos.py build` + host 单测(如有纯逻辑)
  - 出口门:companion 的 `usb_serial.rs` 可无改动换成 BLE client 收到同样 JSONL

- [ ] **FP-3 · tuya-cloud-asr**(板载云 ASR)
  - spec;`ai_chat` ONESHOT 接线 + `AI_USER_EVT_ASR_OK` 取字 + `asr_text` JSONL 帧
  - 云激活(UUID+AuthKey MQTT bind)真机验证是否免 App;Wi-Fi 与 BLE 并发验证(K6)
  - 验收:说一句 → UART/BLE 出 `asr_text`

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
1. **FP-2 收口**(补 spec + 完成/验证,地基)→
2. **FP-4**(companion→Crew,先用 UART 或 FP-2 BLE 喂假文字打通 Crew 注入)∥ **FP-3**(板载云 ASR)→
3. **FP-5**(PC ASR,挂 FP-4 注入路径)→
4. **FP-7 整合** + FP-1 显示层接真实事件 →
5. **FP-6 兜底**(独立,可择机并行)

## 每个 probe 的门禁(沿用项目约定)
`tos.py build` 通过 · clang-format clean · 纯逻辑 host 单测 · check_pins(涉及引脚时)· README(操作/预期)。
