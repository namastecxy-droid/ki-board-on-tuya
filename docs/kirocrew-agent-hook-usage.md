# Kiro Crew 与 Companion 全局 Hook 配置

> 核实日期：2026-09-14
> 用途：说明 FP-4 Kiro Crew 状态回流的持久安装方式与真实验收步骤。

## 1. 安装模型

Kiro Crew 会管理并可能在启动时恢复内置 Agent 配置，因此不再向
`~/.kiro/agents/kirocrew.json` 等 Agent JSON 写入 AK Hook。

Companion 使用 Kiro Crew 当前支持的独立 v1 Hook 文件，全局覆盖所有 Crew Agent：

- Windows：`C:\Users\<user>\.kiro\crew\hooks\ak-companion-status.json`
- 其他平台：`~/.kiro/crew/hooks/ak-companion-status.json`
- 设置 `KIRO_HOME` 时：`$KIRO_HOME/crew/hooks/ak-companion-status.json`

点击 **Install globally** 后立即生效，无需重启 Kiro Crew。重复安装是幂等操作，
并会刷新 Hook 中的 Companion 可执行文件绝对路径。

## 2. Hook 文件格式

安装器生成一个 `version: "v1"` 文档，包含四个 command action：

| v1 Trigger | Hook 输入事件 | LCD 状态含义 |
|---|---|---|
| `SessionStart` | `agentSpawn` | `running` / `agent started` |
| `UserPromptSubmit` | `userPromptSubmit` | `received` / `prompt received` |
| `PostToolUse` | `postToolUse` | `tool` / `using <tool_name>` |
| `Stop` | `stop` | `idle` / 回复摘要 |

每条 action 调用：

```text
"<absolute-path-to-companion.exe>" --hook
```

安装器只管理名称以 `ak-companion-status-` 开头的条目；若同一文件存在其他 Hook，
安装和移除都会保留它们。

## 3. Handoff 与 Status Sink

GUI 和短生命周期 Hook 进程通过 handoff 文件交换本次 Sink 的端口和临时 token：

- Windows：`C:\Users\<user>\AppData\Roaming\ak-companion\hook.json`
- 其他平台：`~/.config/ak-companion/hook.json`

点击 **Start sink** 创建 handoff；点击 **Stop sink** 或关闭 Companion 会删除它。
Agent JSON 和全局 Hook 文件中都不保存 token。

## 4. Windows 真实验收

1. 启动 Companion，点击 **Install globally**，状态应为 `INSTALLED · 4/4`。
2. 点击 **Open hooks folder**，确认存在
   `C:\Users\<user>\.kiro\crew\hooks\ak-companion-status.json`。
3. 保持 Sink 为 `LISTENING · 127.0.0.1:5477`。
4. 在现有或新建 Kiro Crew 会话发送消息；不需要重启 Kiro Crew。
5. `/hooks` 应显示四条 `ak-companion-status-*` Hook，原审计 Hook仍保留。
6. Companion 日志应依次出现 `[KC-STATUS]`，Watched Chat 应出现 session。
7. 连接 AK 后确认 `display` 帧经 USB/BLE 更新 LCD。

若 Hook 已安装但列表仍为空，先验证 handoff：

```powershell
Get-Content "$env:APPDATA\ak-companion\hook.json"
```

再使用其中的端口和 token 手动 POST，以区分 Sink 故障和 Hook 子进程故障。

## 5. 验收清单

- [ ] 全局独立 Hook 文件安装后显示 `4/4`。
- [ ] Kiro Crew 重启后 Hook 文件不被恢复或删除。
- [ ] 四类生命周期事件均到达 Sink。
- [ ] Watched Chat 显示 session、state 和 text。
- [ ] pin session 后其他会话不覆盖 LCD。
- [ ] USB 与 BLE 均能把状态显示到 AK LCD。
- [ ] Companion/Sink/板端断开并恢复后链路重新工作。
