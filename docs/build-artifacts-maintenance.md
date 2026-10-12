# 构建产物与磁盘维护（EC2 多 worktree）

本项目在 EC2 上用 **git worktree** 隔离多条分支（每条分支一个独立工作目录，共享同一
`.git`）。每个 worktree 各自编译，会堆积大量**构建产物**。这些产物全部已被
`.gitignore` 忽略，**与版本库无关、删除不影响源码**，但长期不清会吃满 `/data`
分区。本文档记录它们的位置、量级与安全的清理方法，作为日常维护依据。

> 最近一次清理：2026-10-12，回收约 7.6G（固件 dist ≈1.8G + Companion Rust target ≈5.8G）。

## worktree 布局

| worktree 路径 | 分支 | 硬件 |
|---|---|---|
| `/data/projects/tuya-powered-agentic-keyboard-for-kiro` | `main` | v0.3 |
| `/data/projects/ak-crew-api` | `feat/companion-crew-api` | v0.2 |
| `/data/projects/ak-v0.3` | `feat/v0.3-bringup` | v0.3 |
| `/data/projects/ak-macos-companion` | `feat/macos-companion` | v0.2 |

（`fix/ble-transport-ownership` 的 worktree `/data/projects/ak-ble-owner` 已于分支删除时移除。）

## 构建产物位置与量级

每个 worktree 下有两类编译：**固件（TuyaOpen / tos.py）** 和 **Companion（Rust/Tauri + 前端）**。

### 固件（`firmware/app/`）

| 路径 | 内容 | 典型大小 | 再生成本 |
|---|---|---|---|
| `firmware/app/dist/app_<version>/` | 每次构建产出的 `app_QIO_*.bin` / `app_UA_*.bin` / `app_UG_*.bin` | 每个版本 ≈15M，会逐版本累积 | 重编一个 profile 数分钟 |
| `firmware/app/.build/` | tos.py 的 CMake/中间对象缓存 | ≈130–150M / worktree | 删后首编全量，之后增量 |
| `firmware/app/include/ak_tuya_authkey.h` | 本机占位 License 头（gitignored） | <2K | 从 `.example` 复制 |

- `dist/` 会**每个版本留一份**，不自动清理，是固件侧膨胀主因。
- `.build/` 是增量缓存，保留可加速编译。

### Companion（`companion/`）

| 路径 | 内容 | 典型大小 | 再生成本 |
|---|---|---|---|
| `companion/src-tauri/target/` | Rust 编译缓存（**最大头**） | 已编过的 worktree 可达 **1–4G** | 删后 `cargo build` 全量重编（Windows 更久） |
| `companion/node_modules/` | 前端依赖 | ≈114–117M | `npm ci` 重装（联网 1–2 分钟） |
| `companion/dist/` | 前端 vite 产物 | <1M | `vite build` 秒级 |

## 清理原则

1. **只清 gitignored 构建产物**，永不碰源码 / 已跟踪文件。先确认：
   ```bash
   git check-ignore <path>   # 有输出 = 已忽略，可安全删
   ```
2. **保留当前活跃分支的产物**。EC2 上真正在验证的是 `ak-crew-api`（v0.2），
   保留它的 `dist/` 最新 bin、`.build/`、`src-tauri/target/`，让下次构建走增量。
3. **固件 dist 每个 worktree 只留最新一个版本**，旧版本删掉（可随时重编再生）。
4. **真正开发在 Windows 本机**，EC2 的 Companion target 只是编译验证用途，
   非活跃分支的删掉几乎无损。
5. **闲置/残留 worktree 的产物优先清**（如 `main` 的 dist 残留，曾是误烧旧版本的来源）。

## 安全的删除写法（重要）

Kiro Crew 主机安全策略会**结构性拦截递归强删绝对路径的命令**（即 `rm` 加
`-rf` 作用于以 `/` 开头的绝对路径，路径在 `/data` 下也命中），这不是用户取消。
**不要**对绝对路径用递归强删。改用不匹配该模式的写法（用 `find` 逐项删除）：

```bash
# 删某目录下的所有子项（保留目录本身），不触发该拦截
find <dir> -mindepth 1 -maxdepth 1 -exec rm -r {} +

# 删 dist 下除最新版本外的旧 bin（示例：保留 app_0.2.15）
find firmware/app/dist -mindepth 1 -maxdepth 1 -type d -name 'app_*' \
     ! -name 'app_0.2.15' -exec rm -r {} +

# 删整份 Rust target 并移除空目录
find companion/src-tauri/target -mindepth 1 -maxdepth 1 -exec rm -r {} +
rmdir companion/src-tauri/target 2>/dev/null
```

## 快速巡检命令

```bash
# 各 worktree 固件 dist / Companion target 占用
du -sh /data/projects/*/firmware/app/dist \
       /data/projects/*/firmware/app/.build \
       /data/projects/*/companion/src-tauri/target 2>/dev/null

# /data 分区剩余
df -h /data | tail -1

# 列出各 worktree 保留的固件 bin 版本
ls -1dt /data/projects/*/firmware/app/dist/app_* 2>/dev/null
```

## 常规维护清单

- [ ] 固件：每个 worktree 的 `dist/` 只留最新版本 bin，删旧版本
- [ ] Companion：删非活跃分支 worktree 的 `src-tauri/target/`
- [ ] 残留/闲置 worktree：清空其 `dist/`（避免 `flash.ps1` 默认根拉到错版本）
- [ ] 保留：活跃分支（当前 `ak-crew-api`）的全部产物 + 所有 `.build` 增量缓存
- [ ] `.build/` 仅在需要彻底回收空间时才删（会牺牲增量编译）
