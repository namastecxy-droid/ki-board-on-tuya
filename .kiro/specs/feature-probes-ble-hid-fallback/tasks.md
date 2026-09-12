# FP-6 ble-hid-fallback · Tasks

> 勾选规则：`[ ]` 未开始 / `[~]` 进行中 / `[x]` 完成。
> **当前判定 = compile+link GO（design.md D11，2026-09-12）**：D10 单 TU spike 失败后，改用
> **隔离架构**（`ak_ble_hid.c` 只见 nimble 头 / `tuya_app_main.c` 只见 TAL 头 / 纯 C 桥接头
> `ak_ble_hid.h`），在 **0 改 SDK** 前提下 `tos.py build` = **BUILD SUCCESS**（compile 且 link，
> 原生 HID/SM/adv 符号非桩引用、由 `libtal_bluetooth.a` 解析）。主线 FP-2/3/4/5 构建不受影响。
> T2 内容（完整 Report/DIS/BAS/SM）已在本次骨架内实现并编过；T3（真机 Just Works 配对）仍是关键闸门，
> 留待硬件测试。

- [x] **T0 — 可行性判定（R0）** ✅ 2026-09-09
  - 调查 TAL vs 原生 NimBLE 两条路线，引证：
    - 无现成 HID：`src/tal_bluetooth/` 下 `ble_svc_hid`/`0x1812`/`report_map` 零命中；无 `ble_svc_hid.c`；DIS 仅头无 `.c`。
    - 底座齐：`ble_gatts_add_svcs`（`ble_gatts.c:1977`）+ `ble_gatt_chr_def.descriptors`（`ble_gatt.h:552`）能表达 `0x2908`。
    - SM 全套在（`ble_sm*.c`），默认全关：`TY_HS_BLE_SM_BONDING(0)` 等（`tuya_ble_cfg.h:475`）。
    - TAL 不能建带描述符的服务：`TKL_BLE_CHAR_PARAMS_T` 无描述符字段（`tkl_bluetooth_def.h:204`），`tal_bluetooth.h` 不导出建服务入口。
  - **结论：NO-GO（技术可行但非低风险，须手搓原生 NimBLE + 复刻 init）** → 不 scaffold 代码。

- [x] **T1 — （T1 spike，已执行 2026-09-12）单 TU 原生 NimBLE 起栈骨架** → **结论 NO-GO（升级依据）**
  - 已 scaffold `firmware/feature-probes/ble_hid_fallback/`，`src/tuya_app_main.c` 把 `tal_api.h`
    与 `ble_*.h` 塞进**同一个** `.c`，对着**已核实存在**的 API 编写完整合规 HOGP 骨架（见 design D10 表）。
  - **`tos.py build` = BUILD FAILED**（头文件层，app 源第 3 个编译单元即失败）：
    1. **`LIST_HEAD` 宏冲突（-Werror）**：`ble_att.h`→`tuya_ble_linkqueue.h`（双参）与 `tal_api.h`→
       `tuya_list.h`（单参）无守卫、定义不同，在同一 TU 无法共存。
    2. **私有头缺失**：`ble_hs.h`→`hci_common.h`→`tuya_ble.h`→`tuya_ble_mempool.h`，仅在
       `nimble/host/`（不导出）→ `fatal error: No such file`。
  - **闸门结果：单 TU 方案不通过**。probe 源码保留作证据；`.build/` 已清理。

- [x] **T1b — 隔离架构 compile+link 闸门（2026-09-12）** → **结论 GO（compile+link 通过，0 改 SDK）**
  - 纠正 D10 归因：阻断在"单 TU 塞两套头"的**打包**，不在能力。改用隔离架构（design D11）：
    - `src/ak_ble_hid.c`：**仅** nimble 头，承载全部原生 HOGP（HID 0x1812 + Report Map + Input
      Report + Report Reference `0x2908` + DIS 0x180A + BAS 0x180F）、SM(Just Works/bonding/SC)、
      原生广播(appearance 0x03C1 + 0x1812)、`ble_gattc_notify_custom` 发键。
    - `include/ak_ble_hid.h`：纯 C 桥接（无 nimble/TAL 类型）。
    - `src/tuya_app_main.c`：**仅** `tal_api.h`+桥接头；`tal_ble_bt_init` 起栈、`TAL_BLE_STACK_INIT`
      调 `ak_ble_hid_init()`、按键→桥接 API、状态 LCD。
  - **两阻断均消解**：#1 两套 `LIST_HEAD` 永不共处一 TU；#2 probe CMakeLists 给 `ak_ble_hid.c`
    追加 `${OPEN_SDK_ROOT}/src/tal_bluetooth/nimble/{include,host}`（**未改任何 SDK 文件**）。
  - **`tos.py build` = BUILD SUCCESS**（compile 且 link）；产物 `dist/ble_hid_fallback_0.1.0/*.bin`。
    `nm ak_ble_hid.c.o`：`ble_gatts_add_svcs/ble_gatts_count_cfg/ble_gattc_notify_custom/
    ble_gap_adv_*/ble_svc_gap_device_appearance_set/tuya_ble_hs_cfg/...` 均为 `U`（非桩、由
    `libtal_bluetooth.a` 解析）。
  - API 表两处实编译修正：发通知用 `ble_gattc_notify_custom`（无 `ble_gatts_notify_custom`）；
    SM 全局为 `tuya_ble_hs_cfg`（无 `ble_hs_cfg` 别名）。
  - **主线不受影响**：include dir 仅作用于本 probe 目标。`.build/`/`dist/` 均 `.gitignore` 排除。

- [x] **T2 — 完整 HOGP GATT：Report Map + Input Report + 描述符（R2）** ✅ 已实现并编过（2026-09-12，见 T1b）
  - HID Info/Report Map/Ctrl Pt/Protocol Mode + Input Report（挂 Report Reference `0x2908`，NOTIFY 自动加 CCCD）
    —— 全部落在 `src/ak_ble_hid.c` 的 `s_hid_chrs[]` / `s_report_dscs[]`，静态 `access_cb` 返回字节。
  - DIS `0x180A`(PnP ID 0x2A50) + Battery `0x180F`(0x2A19) 自建（静态 access_cb）—— `s_dis_chrs[]`/`s_bas_chrs[]`。
  - Report Map = 标准 8B Boot 键盘（`s_report_map[]`）。
  - 编译层已验证：`ble_gatts_count_cfg`/`ble_gatts_add_svcs` 链接通过。**真机枚举留 T5**。

- [~] **T3 — SM 配对/绑定/加密（R3）【关键闸门】** — 代码已就位并编过；真机配对**未验证**
  - 运行期 `tuya_ble_hs_cfg.sm_*`（Just Works `NO_INPUT_OUTPUT`、`sm_bonding=1`、`sm_sc=1`、
    `sm_our/their_key_dist=ENC|ID`）+ `store_*_cb`（本 spike 为最小桩，返回 not-found）已在
    `configure_security()` 里设好并链接通过。Input Report 带 `_READ_ENC`。
  - **仍待**：`ble_store_*` 换成 `tal_kv` 真持久化；`REPEAT_PAIRING` 事件处理；编译期覆盖
    `TY_HS_BLE_SM_BONDING=1`/`_SC=1` 是否必要（运行期已设，待真机确认）。
  - **闸门（未过）**：真机 Windows Just Works 配对 + 复连免重配 —— **硬件测试，留待用户**；失败即 NO-GO 上报。

- [~] **T4 — 发键：文字/回车/快捷键（R4）** — 代码已就位并编过；真机发键未验证
  - ASCII→keycode 查表（`ascii_to_keycode`）；发键 = 按下 Report + 抬起(全0) 经 `ble_gattc_notify_custom`。
  - `ak_input` 触发映射（design.md D6）：k1=发文本、k2=Enter、k3=Backspace、nav 左右=Ctrl+Tab。
  - **仍待**：每次发键镜像 UART0 JSONL（本 spike 未接 UART，仅 LCD 状态）；真机键入验证留 T5。

- [ ] **T5 — 真机验收（DoD）**
  - v1.2 板 + COM6 烧录：`.\flash.ps1 -Port COM6 -App "firmware/feature-probes/ble_hid_fallback" -Monitor`
  - 记事本/Kiro Crew 输入框：发文字→出现；发送→提交；切换→组合键生效；断开复连免重配
  - 回填本 spec 与 feature-probes README 的 FP-6 状态

## 依赖顺序

T0（已完成）→ ~~T1 单 TU spike（NO-GO）~~ → **T1b 隔离架构闸门（GO，compile+link 通过）** →
T2（已实现/编过）→ **T3 SM 真机闸门（未过，待硬件）** → T4（已实现/编过）→（真机）T5。
compile+link 闸门已通过；下一道硬闸门是 T3 真机 Just Works 配对，失败即回退 NO-GO 上报。

## 构建/烧录命令

```bash
cd /data/projects/TuyaOpen && . ./export.sh
cd /data/projects/tuya-powered-agentic-keyboard-for-kiro/firmware/feature-probes/ble_hid_fallback
tos.py config choice -c TUYA_T5AI_CORE.config
tos.py clean -f && tos.py build   # 改 .config 后必须先 clean
# 本机 Windows 烧录（扩展板 = COM6）：
# .\flash.ps1 -Port COM6 -App "firmware/feature-probes/ble_hid_fallback" -Monitor
```
