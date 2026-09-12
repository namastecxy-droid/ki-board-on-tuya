# FP-6 ble-hid-fallback · Design

## D1 — 可行性调查方法与证据基线

调查对象：`/data/projects/TuyaOpen`（TuyaOpen SDK，T5AI 平台）的 BLE 子系统。
两条候选 BLE 路线：

- **TAL 路线**：`src/tal_bluetooth/`（公有 API `include/tal_bluetooth.h`）+ TKL 适配层
  `nimble/tkl_bluetooth.c` —— FP-2 用的就是它的固定命令服务 `0x1910`。
- **原生 NimBLE 路线**：`src/tal_bluetooth/nimble/host/`（完整 vendored NimBLE host）。

以下每条结论均引用确切文件/符号。

## D2 — (a) SDK 是否含 HID Service / Report Map / Report 支持？ 结论：无现成 HID，但底座齐全

**没有任何 HID profile 实现**：

- 全树 grep `ble_svc_hid` / `0x1812` / `BLE_SVC_HID` / `hid_report` / `report_map`
  在 `src/tal_bluetooth/` 下**零真实命中**（唯一命中是通用的 `ble_gatts_add_svcs`）。
- NimBLE 只 vendored 了三个标准服务源：`nimble/host/ble_svc_gap.c`、
  `nimble/host/ble_svc_gatt.c`，以及 **DIS 仅有头 `nimble/include/ble_svc_dis.h`
  但无 `.c` 实现**。**没有 `ble_svc_hid.c`**。

**但通用 GATT 服务器底座是齐的**，足以手搓 HID：

- 通用注册 API：`ble_gatts_add_svcs(const struct ble_gatt_svc_def *svcs)`
  （声明 `nimble/include/ble_gatt.h:757`，实现 `nimble/host/ble_gatts.c:1977`）+
  `ble_gatts_count_cfg()`。标准服务正是这样注册的（`ble_svc_gatt.c:106`、`ble_svc_gap.c:287`）。
- **关键：NimBLE 原生 `struct ble_gatt_chr_def` 带 `struct ble_gatt_dsc_def *descriptors`
  字段（`nimble/include/ble_gatt.h:552`）** —— 即原生层**能表达任意描述符**，包括 HOGP
  强制的 **Report Reference 描述符 `0x2908`**。
- 通知发送 `ble_gatts_notify_custom()`、读回调 `ble_gatt_access_fn`（`ble_gatt.h:531-567`
  的 `chr_def` 含 `access_cb` + `arg`），足以：静态返回 Report Map、按加密态门禁 Report、
  向订阅方 notify Input Report。

## D3 — (b) SM 配对/绑定能否开启、如何开？ 结论：能，编译期宏，默认全关

- SM 全套 vendored：`nimble/host/ble_sm.c`(79KB)、`ble_sm_sc.c`（LE Secure Connections）、
  `ble_sm_lgcy.c`（Legacy）、`ble_sm_alg.c`、`ble_store.c`/`ble_store_util.c`（bond 持久化）。
- 默认配置（`nimble/include/tuya_ble_cfg.h`，本 cycle 实读）：
  - `TY_HS_BLE_SM_BONDING (0)`（475–476 行）—— **绑定默认关**；
  - `TY_HS_BLE_SM_SC (0)`、`TY_HS_BLE_SM_LEGACY (0)`、`TY_HS_BLE_SM_MITM (0)`；
  - `TY_HS_BLE_SM_IO_CAP (BLE_HS_IO_NO_INPUT_OUTPUT)` —— 即 **Just Works**。
- 这些是 `#ifndef` 保护的编译期常量，**可在 app 侧或平台配置里覆盖**：置
  `TY_HS_BLE_SM_BONDING=1`、`TY_HS_BLE_SM_SC=1`，并在运行期通过 `ble_hs_cfg.sm_*`
  字段（`ble_hs_cfg.c` / `ble_hs.h`）设 `sm_bonding/sm_sc/sm_our_key_dist/sm_their_key_dist`、
  注册 `ble_hs_cfg.store_*` bond 存储回调。HOGP 要求"读 Report 前必须加密"由
  `BLE_GATT_CHR_F_READ_ENC` / `_READ_AUTHEN` 特征标志表达（NimBLE 原生支持）。

## D4 — (c) 注册"带描述符"的自定义 GATT 服务走什么 API？ 结论：只有原生 NimBLE 能，TAL 不能

- **原生**：`ble_gatts_count_cfg()` + `ble_gatts_add_svcs()`，服务表 = 原生
  `struct ble_gatt_svc_def[]`，其 char 数组每项可挂 `.descriptors`（见 D2）。**完全够用**。
- **TAL/TKL 不行**：`tkl_bluetooth.c` 里 `tkl_ble_gatts_service_add()`（约 1080–1180 行，本
  cycle 实读）把调用方的 `TKL_BLE_GATTS_PARAMS_T` 翻译成内部 `tuya_gatt_svcs[]` 再调
  `ble_gatts_add_svcs()`。但 TKL 的抽象结构 **`TKL_BLE_CHAR_PARAMS_T`
  （`tools/porting/adapter/bluetooth/tkl_bluetooth_def.h:204`）没有描述符字段** —— 它只从
  `property` 位（WRITE/NOTIFY/INDICATE/READ）映射标志并**自动**加 CCCD，
  **无法表达 Report Reference `0x2908`**。且上限硬编码 `TKL_BLE_GATT_SERVICE_MAX_NUM (6)` /
  `TKL_BLE_GATT_CHAR_MAX_NUM (6)`（同文件 81–82 行）。
- 另外 TAL 的公有头 `include/tal_bluetooth.h` **根本不导出 service_add** —— 全表只有
  init/deinit/address/adv/scan/rssi/conn 等（本 cycle 实读 40–150 行），FP-2 用的
  `tal_ble_server_common_send` 是走固定命令服务，不是通用建服务入口。

**⇒ 要合规 HID，必须绕过 TAL，直接对原生 NimBLE 编程**，且要**接管 `tkl_bluetooth.c`
当前独占的初始化/广播链路**（HCI 起栈、`ble_gatts_add_svcs`、`ble_gap_adv_*`）——即"手搓"。

## D5 — 若 GO：GATT 布局（原生 NimBLE 服务表）

| Service | UUID | 关键特征 (UUID) | 描述符 | 说明 |
|---|---|---|---|---|
| GAP | `0x1800` | Device Name / **Appearance=`0x03C1`(Keyboard)** | — | 标准 |
| GATT | `0x1801` | Service Changed | — | 标准 |
| **DIS** | `0x180A` | PnP ID (`0x2A50`) 等 | — | HOGP 建议；需自建（无现成 .c） |
| **Battery** | `0x180F` | Battery Level (`0x2A19`) | CCCD | HOGP 建议 |
| **HID** | `0x1812` | HID Info(`0x2A4A`) / **Report Map(`0x2A4B`)** / HID Ctrl Pt(`0x2A4C`) / Protocol Mode(`0x2A4E`) / **Input Report(`0x2A4D`)** | Input Report 挂 **Report Reference `0x2908`** + **CCCD** | 核心 |

- Report Map / HID Info / PnP ID 静态字节由 `access_cb` 只读返回。
- Input Report 特征标志：`BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_NOTIFY | BLE_GATT_CHR_F_READ_ENC`。
- 发键：`ble_gatts_notify_custom(conn, input_report_val_handle, om)`，8 字节键盘 Report。

## D6 — 若 GO：Report Map 与按键→控制操作映射

标准 8 字节 Boot 键盘 Report Map（Usage Page Generic Desktop / Keyboard）：
`[Modifier(1B)] [Reserved(1B)] [Keycode ×6]`。发一个键 = 送"按下"Report 再送"全 0"抬起。

| 触发（复用 `ak_input`/`fsm`） | 动作 | HID |
|---|---|---|
| 语音键（短按） | 发送预设测试文本 | 逐字符 keycode 序列（大写自动加 LeftShift modifier） |
| 发送键 | 提交（= 回车） | Enter usage `0x28` |
| 取消键 | 退格 | Backspace usage `0x2A` |
| 5 向 左/右 | 切换对话 | 组合键：LeftCtrl(`0x01` modifier)+Tab(`0x2B`) / +Shift+Tab |
| 5 向 中心 | 连接/断开切换（测试用） | 无发键，仅链路操作 + UART 打点 |

ASCII→HID keycode 用一张查表（`a`–`z`=0x04–0x1D，`0`–`9`/符号/空格等），非 ASCII 本 probe 不支持。

## D7 — 若 GO：配对/加密流程

1. app 侧覆盖 `TY_HS_BLE_SM_BONDING=1` / `TY_HS_BLE_SM_SC=1`；
2. 运行期设 `ble_hs_cfg.sm_bonding=1; sm_sc=1; sm_our_key_dist=sm_their_key_dist=(ENC|ID)`；
   IO cap 保持 `NO_INPUT_OUTPUT`（Just Works）；
3. 注册 `ble_store_*` bond 持久化回调（存到 `tal_kv`）；
4. HID Report 特征加 `_READ_ENC`，未加密读被拒 → 主机自动发起配对；
5. `BLE_GAP_EVENT_ENC_CHANGE` / `_REPEAT_PAIRING` 事件处理 + UART 打 `link:encrypted/bonded`。

## D8 — 风险

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| R1 | **手搓整条原生 NimBLE 路线**（起栈+建 GATT+adv+SM），与 FP-2 的 TAL 路线毫无复用 | 工程量大、易与 SDK 的 TKL init 冲突 | 先做**最小 T1 探针**：仅"广播成 keyboard + 空 HID 服务能被枚举"，再逐步加 Report/SM |
| R2 | DIS `0x180A` 无现成 `.c`，需自建；Battery 也要手写 | 增量工作 | 用通用 `ble_gatts_add_svcs` 自建，字节静态 |
| R3 | SM 宏默认全关，且是否被平台/HCI 固件真正支持未在真机验证 | 配对可能失败 | T3 单独验证配对/绑定，失败则 NO-GO 上报 |
| R4 | TAL 与原生同时初始化 NimBLE 可能双初始化/符号冲突 | 编不过或运行崩 | probe **不** `tal_ble_bt_init`，改直接走 NimBLE host 起栈路径（须摸清 `tkl_bluetooth.c` 的 init 序列并复刻） |
| R5 | Flash/RAM：多服务 + SM + bond 存储增量 | 体积 | 复用 FP-2 已知 AP 0.83MB/3.5MB 余量，风险低 |
| R6 | 切换对话依赖前台应用支持所选快捷键 | 功能不通用 | 组合键做成可配置；文档标注 |

## D9 — GO / NO-GO 判定

**判定：NO-GO（本 cycle 不 scaffold 代码）。技术上可行，但不满足"清晰 GO 且低风险"门槛。**

依据：
- **可行性 = 技术可行**。原生 NimBLE 底座齐全：通用 `ble_gatts_add_svcs`
  （`ble_gatts.c:1977`）+ 原生 `ble_gatt_chr_def.descriptors`（`ble_gatt.h:552`）能表达
  HID Service `0x1812` + Report Map + Input Report + Report Reference `0x2908`；SM 全套
  （`ble_sm*.c`）在，绑定/加密可经编译期宏 + `ble_hs_cfg` 打开。**没有硬性拦路。**
- **但不低风险**：合规 HOGP **必须绕过 TAL 固定命令服务**（`TKL_BLE_CHAR_PARAMS_T` 无描述符
  字段、`tal_bluetooth.h` 不导出建服务入口），改为**手搓整条原生 NimBLE 路线**并复刻
  `tkl_bluetooth.c` 独占的起栈/广播 init（D8-R1/R4）。这属于"较大工程量 + 与现有 TAL 路线
  高冲突面 + 真机 SM 未验证"的高风险改动。
- 遵守项目准绳（"仅在清晰 GO 且低风险时 scaffold；否则 NO-GO 只留 spec 结论"）：**本 cycle
  不落地 probe 代码**，把可执行的实现拆分与验证前置留在 tasks.md，待专门排期启动。

**转 GO 的条件**：安排独立时间做 T1（原生 NimBLE 起栈 + 广播成 keyboard + 空 HID 服务可被
Windows 枚举）作 spike，通过后再逐步推进 T2–T5；其中 **T3（SM 配对/绑定真机验证）是关键闸门**，
失败即维持 NO-GO。

## D10 — T1 spike 执行结果（2026-09-12，实做实编译）

**判定：NO-GO（维持），并升级依据 —— 原生 NimBLE host API 在本 SDK 中不是 app 可用的头文件层，
compile+link spike 无法在不修改 vendored SDK 头的前提下通过。**

### 做了什么
- 按 ble_gatt_link 模式 scaffold 了 `firmware/feature-probes/ble_hid_fallback/`
  （`CMakeLists.txt` / `app_default.config` / `config/TUYA_T5AI_CORE.config` / `src/tuya_app_main.c`）。
- `src/tuya_app_main.c` 用**原生 NimBLE** 写出完整合规 HOGP 骨架：`ble_gatts_count_cfg()` +
  `ble_gatts_add_svcs()` 注册 HID `0x1812`（Report Map/HID Info/Ctrl Pt/Protocol Mode/Input Report）
  + DIS `0x180A` + Battery `0x180F`；Input Report 挂 **Report Reference 描述符 `0x2908`**（原生
  `ble_gatt_chr_def.descriptors` 字段，`ble_gatt.h:552`）+ `BLE_GATT_CHR_F_READ_ENC`；SM 经
  `ble_hs_cfg.sm_bonding/sm_sc/sm_our_key_dist/...` + `store_*` 回调开启；广播用
  `ble_gap_adv_set_fields()`（appearance `0x03C1` + 服务 `0x1812`）；发键用 `ble_gatts_notify_custom()`。
  **所有被引用的函数/结构/常量均在头文件中逐一核实存在**（见下"API 核实"）。

### 编译结果：BUILD FAILED（不是链接错，是**头文件层**根本进不去）
`source export.sh && tos.py config choice -c TUYA_T5AI_CORE.config && tos.py clean -f && tos.py build`
在编译 app 源文件 `tuya_app_main.c` 时报错（**编译单元的第 3 个文件即失败**，未走到链接）：

1. **`LIST_HEAD` 宏冲突（-Werror 直接失败）**：NimBLE 的 `tuya_ble_linkqueue.h:266`
   `#define LIST_HEAD(name, type)`（BSD queue 风格，**双参**）与 TuyaOS 的
   `platform/T5AI/tuyaos/tuyaos_adapter/include/utilities/include/tuya_list.h:34`
   `#define LIST_HEAD(name)`（**单参**）**定义不同、都无 `#ifndef` 守卫**，无法在同一编译单元共存。
   而 **`ble_att.h:30` 就 `#include "tuya_ble_linkqueue.h"`**，`ble_gatt.h:31` 又 include `ble_att.h`——
   即**任何** `ble_*.h` 一旦与 app 必需的 `tal_api.h`（其 `tal_event.h:31` → `tuya_list.h`）同时出现，
   就必然撞宏。
2. **host 私有头缺失**：`ble_hs.h:30 → hci_common.h:23 → tuya_ble.h:26/27` 里
   `#include "tuya_ble_mempool.h"` / `tuya_ble_mbuf.h`，而 **`tuya_ble_mempool.h` 只存在于
   `nimble/host/`（`LIB_PRIVATE_INC`，不导出给 app）**，app 编译时 `fatal error: No such file`。

### 根因（这是本 spike 相对 D9 的新增硬证据）
- SDK 的 `src/tal_bluetooth/CMakeLists.txt` 把 `nimble/include` 设为 PUBLIC，但把 `nimble/host`
  设为 **PRIVATE**。而 `nimble/include` 里的 `ble_hs.h`/`ble_gap.h`/`ble_att.h` 又**传递依赖**
  `host/` 里的私有头（mempool）与和 TuyaOS 冲突的 `linkqueue`（LIST_HEAD）。
- **全 SDK grep `#include "ble_gap.h"`/`"ble_hs.h"` 的 13 个 `.c` 文件，无一例外全在
  `nimble/host/`、`nimble/modules/` 或 `nimble/tkl_bluetooth.c` 内部**（这些编译单元把 `host/`
  放在私有 include 路径上，故能编过）。**没有任何 app / example 从应用层 include 这些头** ——
  原生 NimBLE host 根本不是本 SDK 对 app 暴露的编程界面。

### 结论
- **算法/协议层面仍然可行**：HID 描述符、Report Reference `0x2908`、SM 全套代码确实都在
  vendored NimBLE 里（API 核实无误）。
- **但工程上，在"只写 app 源、不碰 vendored SDK"的边界内，compile+link spike 无法通过**：
  头文件既撞宏（LIST_HEAD）又缺私有头（mempool）。要么
  (A) 把 HID 实现做进 SDK 内部（`src/tal_bluetooth/nimble/` 下新增 `ble_svc_hid.c` 之类，享有 host
  私有 include，等同 fork/patch SDK），要么 (B) 上游给出 app 级 HOGP 端口。二者都超出"最小
  probe + 不改 SDK"范畴。
- 遵守 spike 准绳（不 fake、不留坏 build）：**probe 源码保留作证据**（它对着真实 API 写、逻辑完整），
  但**清理 `.build/`**，不在树里留下编译失败产物。

### API 核实（头文件 + 符号，均实读）
| 能力 | 符号 | 头文件:行 |
|---|---|---|
| 注册带描述符的服务 | `ble_gatts_add_svcs` / `ble_gatts_count_cfg` | `ble_gatt.h:757 / 788` |
| 特征描述符字段（表达 0x2908） | `struct ble_gatt_chr_def.descriptors` | `ble_gatt.h:552` |
| 描述符定义结构 | `struct ble_gatt_dsc_def` | `ble_gatt.h`（chr_def 之后） |
| 加密门禁读 | `BLE_GATT_CHR_F_READ_ENC` (`0x0200`) / `_READ_AUTHEN` (`0x0400`) | `ble_gatt.h:71/72` |
| 发通知 | `ble_gatts_notify_custom` | `ble_gatt.h` |
| SM 配置字段 | `ble_hs_cfg.sm_bonding/sm_sc/sm_io_cap/sm_our_key_dist/store_*_cb` | `ble_hs.h:190–` |
| SM 密钥分发常量 | `BLE_SM_PAIR_KEY_DIST_ENC/ID` | `ble_sm.h:51/52` |
| Just Works IO cap | `BLE_HS_IO_NO_INPUT_OUTPUT` (`0x03`) | `ble_hs.h:163` |
| 广播设置/开始 | `ble_gap_adv_set_fields` / `ble_gap_adv_start` | `ble_gap.h:1131 / 1064` |
| appearance 广播字段 | `ble_hs_adv_fields.appearance` | `ble_hs_adv.h` |
| appearance/名字 设置 | `ble_svc_gap_device_appearance_set` / `_device_name_set` | `ble_svc_gap.h:47 / 45` |
| **阻断：宏冲突** | `LIST_HEAD`（双参 vs 单参，无守卫） | `tuya_ble_linkqueue.h:266` ↔ `tuya_list.h:34`（经 `ble_att.h:30`） |
| **阻断：私有头** | `tuya_ble_mempool.h` 仅在 `nimble/host/`（不导出） | 经 `ble_hs.h:30→hci_common.h:23→tuya_ble.h:27` |

## 偏差记录

- 无。本 spec 先于任何代码产出（符合"feature-probes 一律先 spec"准绳）。
