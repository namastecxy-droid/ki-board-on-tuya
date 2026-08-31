# scripts/

本机（Windows）辅助脚本。开发/编译在 EC2 devbox，本机只负责烧录与调试。

## flash.ps1 — 一键烧录

从 devbox（EC2）scp 拉取最新固件 `_QIO_` bin（兼容当前 `dist/<version>/`
和旧版 `.build/bin/` 输出结构），用 tyutool 烧录到 T5AI-Core，可选打开串口监视。

### 前置
- 已装 **WCH CH343SER** 驱动（板载 CH342F，插上出现 2 个 COM 口）。
- **tyutool CLI** 在 PATH（或用 `-TyuTool <path>` 指定）。下载：https://tuyaopen.ai/tyutool
  - 也可不用 tyutool：脚本拉下来的 `fw.bin` 可用 WebTool 手动烧 https://tuyaopen.ai/web-serial
- OpenSSH client（Win10/11 自带）+ 已配置 `ssh devbox` 主机别名（`~/.ssh/config`）。

### 用法
```powershell
# 拉最新 ref_projects/signal_light_demo 的 bin 并烧录到 COM5
.\flash.ps1 -Port COM5

# 先在 devbox 上 tos.py build，再拉、再烧、再开监视
.\flash.ps1 -Port COM5 -Build -Monitor

# 烧录指定测试 app 的 bin（后续我们自己的测试程序）
.\flash.ps1 -Port COM5 -App "firmware/tests/lcd/source/embedded"

# 不带 -Port 时会列出可用 COM 口并询问
.\flash.ps1
```

### 参数
| 参数 | 默认 | 说明 |
|------|------|------|
| `-Port` | （询问） | 烧录串口，如 COM5 |
| `-App` | `ref_projects/signal_light_demo/source/embedded` | devbox 上项目内的 app 目录 |
| `-Build` | 关 | 拉 bin 前先在 devbox `tos.py build` |
| `-Monitor` | 关 | 烧录后打开串口监视 |
| `-Baud` | 460800 | T5 烧录/监视波特率 |
| `-SshHost` | `devbox` | SSH 主机别名 |
| `-RemoteProjectRoot` | `/data/projects/tuya-powered-agentic-keyboard-for-kiro` | 远端项目根 |
| `-TuyaOpenRoot` | `/data/projects/TuyaOpen` | 远端 TuyaOpen 根（source export.sh） |
| `-TyuTool` | `tyutool_cli` | tyutool 可执行名/路径 |
| `-Device` | `t5ai` | tyutool 设备型号 |

> ⚠️ 烧录前**打开板上电源拨动开关**。
> ⚠️ tyutool 的确切子命令/参数以 `tyutool_cli --help` 为准，如不同请调整脚本中 `write`/`monitor` 行。
> 拉下来的 `fw.bin` 已被 `.gitignore` 忽略（`*.bin`），不入库。

## 排障记录：tyutool monitor 的端口/波特率坑

> 环境：tyutool v3.2.9 (windows/x86_64)。记录日期：2026-08-31。

排查 LCD 自测日志时遇到的两个问题，均已定位，结论如下。

### 现象

测 LCD 时的连接方式：开发板由**电池供电**（不接开发板 USB），日志通过**自制 USB/串口（CH340 → COM6）** 引出。

- `.\tyutool_cli.exe monitor`（不带参数）：打印 `Using port: COM6` 后立刻 `--- Monitor stopped ---`，**收不到任何数据**。
- `.\tyutool_cli.exe monitor -p COM6 -b 115200`（显式指定）：**正常收到** bringup JSON 日志。
- 用第三方串口调试助手打开 COM6：也能正常收到数据。

### 结论一：monitor 不带 `-p` 时自动选口会异常退出

两次运行的端口与波特率**完全相同**（都是 COM6 / 115200），唯一区别是"自动选口" vs "显式 `-p`"。
不带 `-p` 时 tyutool 虽然打印了 `Using port: COM6`，却紧接着 `Monitor stopped` 直接退出——
这是 tyutool v3.2.9 自动选口路径的行为怪癖（疑似探测端口时打开又关闭串口，或单端口场景下的交互逻辑异常），
**不是端口选错或波特率错**。

**规避**：调用 `monitor` / `write` 一律**显式传 `-p` 和 `-b`**，不要依赖其默认值。
`flash.ps1` 本身已经是显式传参（`monitor -d $Device -p $Port -b $Baud`），不受此坑影响。

### 结论二：不同串口链路的波特率不同，必须显式指定

本项目当前存在两条物理串口链路，波特率不一样：

| 链路 | 端口 | 波特率 | 用途 | 供电 |
|------|------|--------|------|------|
| 开发板板载 CH342F **A 口**（`SERIAL-A`） | 如 COM8 | **460800** | 烧录 / 主调试口 (Uart1) | 开发板 USB |
| 自制 USB 串口 CH340 | COM6 | **115200** | LCD 等 bringup 日志引出 | 开发板电池供电 |

- tyutool `monitor` 不带 `-d` 时默认波特率 115200；带 `-d t5ai` 时默认 460800。
- 所以监视自制串口（115200）时若误用 460800，会收到乱码或收不到。
- 监视和烧录**可能是不同端口 + 不同波特率**，不能假设同一套参数通用。

### 结论三：CH342F 的 A 口不一定是较小 COM 号

实测真板子上 A 口是 **COM8（较大号）**、B 口是 COM7；而历史残留的幽灵端口里 A 口曾是 COM4（较小号）。
因此**不能用 COM 号大小判断 A/B 口**，应按端口名里的 `USB-Enhanced-SERIAL-A` / `-B` 识别。
`flash.ps1` 的默认端口选择已按 `SERIAL-A` 匹配，实测能正确选中 A 口。

### 速查命令

```powershell
# 列出 tyutool 实际能看到的端口（能不能烧/监的唯一权威视角）
.\tyutool_cli.exe list-ports --plain

# 监视自制 CH340 日志口（LCD bringup 等），必须显式端口 + 波特率
.\tyutool_cli.exe monitor -p COM6 -b 115200

# 监视开发板板载调试口（A 口），用设备默认波特率 460800
.\tyutool_cli.exe monitor -d t5ai -p COM8 -b 460800
```
