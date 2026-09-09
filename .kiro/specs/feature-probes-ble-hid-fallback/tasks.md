# FP-6 ble-hid-fallback · Tasks

> 勾选规则：`[ ]` 未开始 / `[~]` 进行中 / `[x]` 完成。
> **当前判定 = NO-GO（design.md D9）**：T0 已完成；T1–T5 为"转 GO 后"的实现路线，暂不启动。

- [x] **T0 — 可行性判定（R0）** ✅ 2026-09-09
  - 调查 TAL vs 原生 NimBLE 两条路线，引证：
    - 无现成 HID：`src/tal_bluetooth/` 下 `ble_svc_hid`/`0x1812`/`report_map` 零命中；无 `ble_svc_hid.c`；DIS 仅头无 `.c`。
    - 底座齐：`ble_gatts_add_svcs`（`ble_gatts.c:1977`）+ `ble_gatt_chr_def.descriptors`（`ble_gatt.h:552`）能表达 `0x2908`。
    - SM 全套在（`ble_sm*.c`），默认全关：`TY_HS_BLE_SM_BONDING(0)` 等（`tuya_ble_cfg.h:475`）。
    - TAL 不能建带描述符的服务：`TKL_BLE_CHAR_PARAMS_T` 无描述符字段（`tkl_bluetooth_def.h:204`），`tal_bluetooth.h` 不导出建服务入口。
  - **结论：NO-GO（技术可行但非低风险，须手搓原生 NimBLE + 复刻 init）** → 不 scaffold 代码。

- [ ] **T1 — （转 GO 前置 spike）原生 NimBLE 起栈 + keyboard 广播 + 空 HID 服务枚举（R1/R2 子集）**
  - 建 `firmware/feature-probes/ble_hid_fallback/{src,config}` + `app_default.config` + `CMakeLists.txt` + `README.md`
  - config：`ENABLE_GPIO/UART/BLUETOOTH=y`；复刻 `tkl_bluetooth.c` 的 HCI 起栈序列（**不** `tal_ble_bt_init`，避免双初始化）
  - `ble_gatts_count_cfg`+`ble_gatts_add_svcs` 注册最小 GATT（GAP appearance=0x03C1 + 空 `0x1812`）
  - **闸门**：Windows 蓝牙能扫到 `AK-KB-HID` 且识别为键盘类；不通则维持 NO-GO 并回填结论

- [ ] **T2 — 完整 HOGP GATT：Report Map + Input Report + 描述符（R2）**
  - HID Info/Report Map/Ctrl Pt/Protocol Mode + Input Report（挂 Report Reference `0x2908` + CCCD）
  - DIS `0x180A`(PnP ID) + Battery `0x180F` 自建（静态 access_cb）
  - Report Map = 标准 8B Boot 键盘

- [ ] **T3 — SM 配对/绑定/加密（R3）【关键闸门】**
  - 覆盖 `TY_HS_BLE_SM_BONDING=1`/`_SC=1`；运行期 `ble_hs_cfg.sm_*` + `ble_store_*` bond 持久化(tal_kv)
  - Input Report 加 `_READ_ENC`；处理 `ENC_CHANGE`/`REPEAT_PAIRING`
  - **闸门**：真机 Windows Just Works 配对 + 复连免重配成功；失败即 NO-GO 上报

- [ ] **T4 — 发键：文字/回车/快捷键（R4）**
  - ASCII→keycode 查表；发键 = 按下 Report + 抬起(全0) 经 notify
  - `ak_input`/`fsm` 触发映射（design.md D6）；每次发键镜像 UART0 JSONL

- [ ] **T5 — 真机验收（DoD）**
  - v1.2 板 + COM6 烧录：`.\flash.ps1 -Port COM6 -App "firmware/feature-probes/ble_hid_fallback" -Monitor`
  - 记事本/Kiro Crew 输入框：发文字→出现；发送→提交；切换→组合键生效；断开复连免重配
  - 回填本 spec 与 feature-probes README 的 FP-6 状态

## 依赖顺序

T0（已完成）→ **T1 spike 闸门** → T2 → **T3 SM 闸门** → T4 →（真机）T5。
T1 与 T3 是两道闸门：任一不通即回退为 NO-GO 并停在 spec，不继续投入。

## 构建/烧录命令（转 GO 后 T1 起适用）

```bash
cd /data/projects/TuyaOpen && . ./export.sh
cd /data/projects/tuya-powered-agentic-keyboard-for-kiro/firmware/feature-probes/ble_hid_fallback
tos.py config choice          # TUYA_T5AI_CORE.config
tos.py clean -f && tos.py build   # 改 .config 后必须先 clean
# 本机 Windows 烧录（扩展板 = COM6）：
# .\flash.ps1 -Port COM6 -App "firmware/feature-probes/ble_hid_fallback" -Monitor
```
