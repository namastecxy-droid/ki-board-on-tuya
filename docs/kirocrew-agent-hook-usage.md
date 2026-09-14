# Kiro Crew Agent 使用与 Companion Hook 配置建议

> 核实日期：2026-09-14
> 用途：为 FP-4 Kiro Crew Control 的 Agent Hook 安装与端到端验收提供目标清单。

## 1. 检查范围与口径

检查了 2026-08-10 至 2026-09-14 保存的 24 个会话、会话元数据、历史 `spawn_run` 调用、Kiro Crew Agent 映射，以及 `/data/kiro/.kiro/agents/` 下的 7 个 Agent 配置。

子 Agent 次数是保存记录中的**任务分配尝试次数**，包含失败和重试，不等同于成功完成次数。旧消息渠道会话中有 11 个未保存 Agent 元数据，因此只能结合当时的进程记录和当前默认映射判断。

## 2. 实际使用情况

| Agent | 使用记录 | 主要用途 | Hook 建议 |
|---|---:|---|---|
| `kirocrew` | 当前默认主 Agent；13 个会话明确记录为 `default`，另有 5 次显式子任务分配 | Dashboard、Slack、微信主会话；开发、运维、文档 | 必须安装 |
| `kirocrew-research` | 50 次子任务分配尝试 | 大规模代码调查、FP 实现、固件审查、行业资产分析 | 建议安装 |
| `kirocrew-lite` | 11 次子任务分配尝试；早期还承载过常驻会话 | 轻量审查、BLE/ASR 调查、Mascot 文档 | 第二阶段安装 |
| `kirocrew-knowledge` | 无普通会话或显式分配记录 | 知识库内部抽取 | 不建议安装 |
| `kirocrew-heartbeat` | 无普通会话记录 | 后台只读轮询与通知 | 不建议安装 |
| `kirocrew-conductor` | 无实际使用记录 | 长周期目标编排 | 暂不安装 |
| `kirocrew-pipeline-conductor` | 无实际使用记录 | 仓库流水线编排 | 暂不安装 |

当前 `/data/kiro/.kiro/crew/config.json` 将 `default` 映射到 `kirocrew`。2026-08-20 的进程检查曾显示部分旧会话使用 `kirocrew-lite`，所以继续使用旧会话时也应覆盖 `kirocrew-lite`。

### 子 Agent 分布

`kirocrew-research` 的 50 次分配尝试：

- Bringup-Feature Probe：17
- Industry assets model analysis inventory：16
- Optimization：10
- Industry Assets Analysis：7

`kirocrew-lite` 的 11 次分配尝试：

- Hook for Companion：4
- Ki-board Mascot：3
- 零碎改进：3
- Bringup-Feature Probe：1

`kirocrew-lite` 曾多次出现只输出 preamble、未实际调用工具的空转，因此不作为首轮 Hook 验证对象。

## 3. 当前 Hook 状态

检查时，7 个 Agent 配置均未包含 Companion 的 `--hook` 命令。

以下配置已有独立的 `postToolUse` 审计 Hook，安装器必须保留这些条目：

- `/data/kiro/.kiro/agents/kirocrew.json`
- `/data/kiro/.kiro/agents/kirocrew-research.json`
- `/data/kiro/.kiro/agents/kirocrew-conductor.json`
- `/data/kiro/.kiro/agents/kirocrew-pipeline-conductor.json`

Companion 安装器按命令中的 `--hook` 标记识别自身条目，安装幂等，移除时只删除自身条目。

## 4. Hook 事件集合

安装器应为每个选中的 Agent 安装以下四个事件：

| 事件 | LCD 状态含义 |
|---|---|
| `agentSpawn` | Agent 启动，映射为 `running` |
| `userPromptSubmit` | 收到用户输入，映射为 `received` |
| `postToolUse` | 工具执行完成，映射为 `tool` |
| `stop` | Agent 本轮结束，映射为 `idle` 并附回复摘要 |

`userPromptSubmit` 原先仅由 status sink 支持，但没有加入一键安装器；现已加入 `HOOK_EVENTS`。

## 5. 推荐安装顺序

### 第一阶段：主链路验证

只选择 `kirocrew`，走通：

```text
Kiro agent event
→ companion --hook
→ 127.0.0.1 status sink
→ display frame
→ USB/BLE
→ LCD
```

依次验证 `agentSpawn`、`userPromptSubmit`、`postToolUse`、`stop`。

### 第二阶段：覆盖实际开发工作流

主链路稳定后增加：

- `kirocrew-research`
- `kirocrew-lite`

最终推荐安装集合：

```text
kirocrew
kirocrew-research
kirocrew-lite
```

启用多个子 Agent 后，应在 Companion 中 pin 一个 watched session；否则并行子任务可能连续覆盖 LCD 状态。

## 6. FP-4 Hook 验收清单

- [ ] Companion 启动 status sink，并生成 handoff 文件及 token。
- [ ] 只给 `kirocrew` 安装四个 Hook 事件，现有审计 Hook 保持不变。
- [ ] 新建真实 Kiro Crew turn，四类事件均能到达 sink。
- [ ] Companion 状态列表显示正确的 session、agent、state 和 text。
- [ ] `display` 帧通过 USB 到达板端并更新 LCD。
- [ ] `display` 帧通过 BLE 到达板端并更新 LCD。
- [ ] pin session 后，其他并行 Agent 不再覆盖 LCD。
- [ ] Companion/sink/板端重启后可以恢复工作。
- [ ] 扩展安装到 `kirocrew-research` 和 `kirocrew-lite`。
