# Agent Container（多 Agent 第三阶段执行容器）

一个面向 **AI Coding Agent 并发研发（第三阶段：Leader + 持久化 Worker）** 的开箱即用容器环境。基于 `debian:trixie-slim` 与 Rootless Podman 构建，将所有并发 Agent 隔离在独立沙箱中运行，彻底与本地开发环境脱钩。

---

## 环境概览

| 项目 | 配置 |
| --- | --- |
| 基础镜像 | `debian:trixie-slim` |
| 默认用户 | `agent`（UID `1000`，支持免密 `sudo`） |
| 工作目录 | `/home/agent/workspace` |
| Coding Agent CLIs | **Codex CLI**、**Antigravity CLI (`agy`)**、**CodeBuddy Code (`codebuddy`)**、**Pi Coding Agent**、**Claude Code** |
| 轻量编排层（默认推荐） | **`aw`**（零依赖持久化 Worker 编排 + 角色路由 + 同分支接力 + 异构审查 CLI）+ **`bd`（Beads 任务账本）** + `leader-orchestrator` Skill |
| 重型编排层（大并发备用） | **Gas Town (`gt`)** + **Dolt** + **tmux** |
| 基础开发工具 | Git、ripgrep、jq、tmux、sqlite3、Python 3、fnm、Node.js、pnpm、Go、bubblewrap、build-essential |
| 远程访问 | OpenSSH Server，默认宿主机端口 **`6666`** 映射到容器 `22` |
| 国内镜像优化 | APT 清华源、DaoCloud 基础镜像、npmmirror（Node 二进制 + npm/pnpm）、阿里云 Go 镜像 + `goproxy.cn`（构建期尽量不消耗代理流量） |

---

## 前置要求（Linux / Debian 推荐）

推荐使用 **Rootless Podman** + **`podman-compose`**：

```bash
# Debian 安装示例
sudo apt-get update
sudo apt-get install -y podman podman-compose uidmap slirp4netns fuse-overlayfs

# 开启 systemd linger，确保断开 SSH 后 Rootless 容器 7×24 持续保活
sudo loginctl enable-linger "$USER"
```

---

## 快速开始

### 1. 克隆项目并拉取基础镜像

```bash
git clone -b feat/gastown https://github.com/aoyamaw/agent-container.git
cd agent-container

# 使用国内镜像拉取 debian:trixie-slim（如海外直连可跳过）
chmod +x ./pull.sh && ./pull.sh
```

### 2. 配置宿主机目录与代理（按需修改）

默认代理配置在 `compose.yaml` 中为 `192.168.3.110:7890`（仅用于构建期少量外网资源及容器运行时访问 AI 服务，APT / Node / npm / Go 均优先走国内直连镜像）。

使用前请先在宿主机创建工作目录，并按你自己的网络环境调整 `compose.yaml` 里的 `PROXY_IP` / `PROXY_PORT`（如果服务器可直连外网，可将 `USE_PROXY` 与 `RUNTIME_PROXY` 设为 `"false"`）：

```bash
mkdir -p ./workspace
```

### 3. 构建并后台启动容器

> **注意**：`podman-compose` 默认会创建 pod，与 `userns_mode: "keep-id"` 冲突，启动时请加上 `--in-pod=0`：

```bash
# 使用默认 ./workspace 目录启动
podman-compose --in-pod=0 up --build -d

# 或挂载宿主机任意指定代码目录
WORKSPACE_HOST_DIR=/path/to/your/workspace podman-compose --in-pod=0 up --build -d
```

### 4. 一键自检工具链与订阅隔离状态

```bash
podman exec -it agent-container-0.2.0-gastown bash -lc "gt-check"
```

`gt-check` 会检查所有核心工具链、各 Agent CLI 版本，并确认 `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `GEMINI_API_KEY` 均未设置（避免意外走按量付费 API 覆盖订阅登录态）。

### 5. SSH 登录与首次订阅认证

默认凭据：用户名 `agent`，密码 `agent123`（**对外或公网环境请务必修改密码或改用 SSH 公钥**）。

```bash
# 本地连接容器（如需浏览器 OAuth 本地回调，按需加上 -L 端口转发）
ssh -p 6666 -L 1455:127.0.0.1:1455 agent@<服务器IP>

# 在容器内完成各 CLI 订阅登录（凭证保存在 Named Volume 中，重建镜像免重登）
codex login
agy          # 无头 SSH 下会打印 Google 授权链接，浏览器打开后粘贴授权码即可
codebuddy
```

---

## 推荐工作流：个人 / 小团队“轻第三阶段”架构

本容器同时内置了**零编排税的轻量组合（默认推荐，适合 2~5 个并发）**与**重型工厂 Gas Town（8~20 个并发备用）**。

核心哲学：**人看不过来海量并发代码，只把控「事前技术路线与契约」+「事后例外简报」。**

### 三驾马车任务路由（Cost per Solved Task & 5 小时额度分流）

`aw` 内置了按任务角色自动路由的默认映射（可通过 `aw routes` 查看，或在 `~/.config/aw/routes.json` 随时覆盖）：

| 任务角色 (`--role`) | 默认主力 (`backend / model`) | 适用场景 | 限频/卡死一键接力链 (`aw handoff`) |
| --- | --- | --- | --- |
| `core` | `codex` / `gpt-6.2-sol` | 核心业务、强类型后端/算法、疑难 Debug | `agy/claude-sonnet-5-5-medium` → `agy/claude-opus-5-5-medium` → `codebuddy/deepseek-v4-pro` |
| `ui` | `agy` / `gemini-4-neon-medium` | 前端交互、跨多文件大上下文整合、文档 | `agy/claude-sonnet-5-5-medium` → `codebuddy/kimi-k3.1-pro` |
| `crud` | `codebuddy` / `glm-5.3` (自动降级 `kimi-k3.1-pro`) | 常规接口/表单/体力活（帮 Codex & AGY 省 5h 额度） | `codebuddy/kimi-k3.1-pro` → `agy/gemini-3.8-flash-high` |
| `test` | `agy` / `gemini-3.8-flash-high` | 单元测试、边界用例、辅助脚本（极速低耗） | `codebuddy/glm-5.3` → `codex/gpt-6-luna` |

- **异构交叉初筛（`aw review <name>`）**：绝不自己审自己——`codex` 写的代码由 `agy/gemini-3.8-flash-high` 初筛；`agy` / `codebuddy` 写的代码由 `codex/codex-auto-review` 初筛。

### 双模式设计（已内置为 `leader-orchestrator` Skill）

1. **冷启动 / 大型重构（完整打磨模式）**
   - 用反重力（`-1`）Remote-SSH 连进容器（`agent@<服务器IP>:6666`），打开 `/home/agent/workspace/<项目>`。
   - 结合 `/grill-me`（深度拷问边界与假设）或 BMAD `/pm` + `/architect`（工程蓝图防漏项），共同打磨并冻结 **`docs/architecture.md`**（目录树、模块边界、数据模型、公共契约、红线、验收命令）。
   - **冻结后停掉重型规划流程**，把 `docs/architecture.md` 和公共接口定义提交到主分支。

2. **日常功能迭代（轻量增量模式）**
   - `-1` 直接读取 `docs/architecture.md` 作为项目宪法，花 2 分钟给出本次 2~4 个 Worker 的任务切分表（每个任务明确 `--role`、`--allow` 允许改动路径和 `--verify` 验收命令）。
   - 用 `bd`（Beads）记录任务依赖，`-1` 通过内置 **`aw`** CLI 并发拉起持久化 `-2`。
   - `-2` 跑完后自动跑 **0 Token 硬门禁（`aw check`）**——越界改文件或测试失败时，`-1` 直接 `aw send` 原地返工；遇 5 小时限频或卡死时直接 `aw handoff` 同分支跨池接力。
   - 全部通过后运行 **`aw report --run-check`** 生成一屏**架构师例外简报**（合规全绿项折叠，只高亮越界、改依赖/契约、审查不通过、失败或限频项），你确认后一键 `aw merge`。

### 轻量编排工具 `aw` 常用命令速查

```bash
# 0. 查看当前生效的角色路由表与接力链
aw routes

# 1. 按角色自动路由创建独立 git worktree 并后台拉起持久化 Worker
aw spawn core-impl --role core \
  --allow "src/core/" \
  --verify "pnpm test -- core" \
  -p "严格遵守 docs/architecture.md，实现核心模块并提交代码。"

# 2. 查看所有并发 Worker 状态、角色、模型、轮次、改动文件与越界数
aw ls

# 3. 等待任意一个（或全部）Worker 完成本轮
aw wait --any

# 4. 查看 Worker 最新回复摘要或原始日志
aw logs core-impl --last
aw logs core-impl --tail 80

# 5. 运行 0 Token 硬门禁（路径越界检测 + 敏感/契约文件告警 + verify 命令）
aw check core-impl

# 6. 原地续聊纠偏（保留完整会话上下文，不重建）
aw send core-impl "测试报错 xxx，请只在 src/core/ 内修复后重跑验证。"

# 7. 撞 5 小时限频或同模型卡死时，同分支一键交接给备选池下一模型
aw handoff core-impl

# 8. 触发异构只读代码初筛（对照 docs/architecture.md 查 diff）
aw review core-impl

# 9. 生成一屏架构师例外简报
aw report --run-check

# 10. 终审通过后合并回当前主分支并清理 worktree/分支
aw merge core-impl --auto-commit --delete

# 11. 放弃并清理某个 Worker
aw rm core-impl --force
```

### 未来升级到大并发（8~20 个 Agent）

当项目并发规模扩大到需要自动看门狗与合并队列时，容器内已预装 `dolt`、`bd` 与 `gt`（Gas Town），可直接在已有 Beads 账本上平滑启用：

```bash
bd init
gt up
```

---

## 持久化卷与容器数据说明

`compose.yaml` 将**业务代码**与**状态/缓存**解耦：
- **业务代码（Bind Mount）**：`${WORKSPACE_HOST_DIR:-./workspace}` → `/home/agent/workspace`
- **持久化 Named Volumes**（重建/升级镜像不丢失）：
  - `agent-codex` → `/home/agent/.codex`
  - `agent-claude` → `/home/agent/.claude`
  - `agent-gemini` → `/home/agent/.gemini`（同时持久化 `agy` 配置与登录态）
  - `agent-pi` → `/home/agent/.pi`
  - `agent-codebuddy` → `/home/agent/.codebuddy`
  - `agent-gastown` → `/home/agent/gt`
  - `agent-pnpm-store` → `/home/agent/.local/share/pnpm/store`（并发 worktree 共享依赖缓存）

---

## 主要配置项

| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `WORKSPACE_HOST_DIR` | `./workspace` | 宿主机挂载到容器 `/home/agent/workspace` 的代码目录 |
| `PROXY_IP` / `PROXY_PORT` | `192.168.3.110` / `7890` | 代理地址（可在 `compose.yaml` 中按自身环境修改） |
| `USE_PROXY` / `RUNTIME_PROXY` | `true` / `true` | 构建期 / 运行期是否启用代理（`NO_PROXY` 自动放行本地与私有网段） |
| `USE_CHINA_APT_MIRROR` | `true` | 使用清华大学 Debian APT 源 |
| `USE_CHINA_NPM_MIRROR` | `true` | Node 二进制、npm、Corepack、pnpm 走 `npmmirror` |
| `USE_CHINA_GO_PROXY` | `true` | Go 二进制走阿里云镜像，Go 模块走 `goproxy.cn` |
| 宿主机 SSH 端口 | `6666` | 在 `compose.yaml` 的 `ports` 中修改 |
| 资源限制 | `12g` 内存 / `6` CPU | 防止并发编译或 Agent 失控拖垮宿主机 |

---

## 项目结构

```text
.
├── Containerfile                                   # 镜像构建定义
├── compose.yaml                                    # Podman Compose 编排与持久化卷配置
├── pull.sh                                         # 国内镜像拉取基础镜像脚本
├── bashrc.sh                                       # 容器 Shell 环境、自动代理与 gt-check 自检
└── home/                                           # 构建期复制到 /home/agent/
    ├── set-proxy.sh / unset-proxy.sh               # 代理开关脚本
    ├── .local/bin/w                                # 零依赖持久化 Worker 编排 CLI（软链为 /usr/local/bin/aw）
    ├── .local/share/templates/DESIGN.md            # 增量任务切分模板
    └── .agents/skills/leader-orchestrator/SKILL.md # 反重力 -1 Leader 工作流 Skill
```
