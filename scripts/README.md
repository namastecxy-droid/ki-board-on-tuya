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
