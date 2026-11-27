# Leader Orchestrator（`-1` 项目架构师与编排官）中文操作指南

> 本文件是同目录下英文 [SKILL.md](./SKILL.md) 的**人类阅读中文对照版**（英文 `SKILL.md` 供 AI Agent 自动加载执行，中文版供开发者查阅、评审与协作对齐，两者逐节保持同步）。

---

## 核心定位

**`-1` Leader** 是项目的架构师与编排官，负责：
- 与人类架构师对齐需求、冻结技术路线与公共契约；
- 通过轻量 CLI **`aw`** 将 2~4 个持久化 **`-2` Worker** 并发派发到三大独立订阅池（`codex` / `agy` / `codebuddy`）；
- 执行 0 Token 硬门禁、异构交叉审查与审查分歧仲裁；
- 在每波次合入后维护全局活文档 **`docs/progress.md`**；
- 只向人类架构师升级汇报**例外项**，避免海量 diff 淹没。

> **红线**：`-1` 不亲自编写大段业务功能代码，保持主上下文干净（仅允许合并后 ≤50 行的薄接线胶水，更大集成层必须派发给 Worker）。

---

## 一、执行环境与前置准备

在容器工作区终端直接运行 `aw`、`bd` 与 `git`（工具预装于 `/usr/local/bin/aw`；若从容器外本地会话调度且本地无 `aw`，则通过 `ssh agent-box` 远程执行，容器内绝不套娃 SSH）。

### 1. 启动前自检与精准探针
- **全新容器首次检查**：运行 `gt-check` 检查全部工具链、CLI 登录态，并确认无 `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `GEMINI_API_KEY` 泄露（纯吃订阅）。
- **Wave 1 前精准探活**：运行 `aw probe <roles>`（例如 `aw probe core ui crud`），并发执行与真实派活一致的 `stream-json` + **真实只读文件读取工具**校验，结果写入带文件锁的 `~/.cache/aw/health.json`（30 分钟 TTL）。
- **被动活体心跳 & 自动冷却**：
  - 正在活跃输出日志或刚顺利收工的 Worker 自动续期同模型健康缓存（运行顺畅时绝不重复探针）。
  - 发生 `STALLED` / `RATE_LIMITED` / 探针失败会自动触发 **30 分钟冷却**，`aw spawn --role` 与 `aw handoff` 自动绕开冷却中的模型。
- **零 I/O 懒加载路由查看**：`aw routes` 默认纯静态零 I/O；按需传 `aw routes --health`（`-H`）才只读展示健康徽章。

### 2. Worktree 依赖、软链与 `.env` 初始化（`.aw.json`）
- `aw spawn` 默认自动软链主仓库中被 `.gitignore` 忽略的 `node_modules` / `.venv` / `venv`，并自动将无斜杠路径幂等写入 `.git/info/exclude`（避免与 `.gitignore` 中 `node_modules/` 带斜杠规则冲突导致误报越界）。
- 对于 Monorepo、Prisma 或需要拷贝 `.env.local` 的全栈项目，在仓库根目录放置 `.aw.json`（或通过 `aw spawn --setup "<cmd>"` 临时覆盖）：
  ```json
  {
    "setup_cmd": "pnpm install --offline",
    "copy_files": [".env.local"],
    "auto_symlink_deps": false
  }
  ```

---

## 二、按复杂度与风险的任务路由策略（质量优先 + 5 小时额度分流）

按**技术复杂度与出错风险**（而非目录名）分配 `--role`（可通过 `aw routes` 查看，或在 `~/.config/aw/routes.json` 覆盖）。**不要为了硬摊配额把高风险并发/有状态模块丢给弱模型**，避免多轮审查返工。

| 角色 (`--role`) | 默认订阅池与模型 | 适用场景 | 限频/卡死接力链 (`aw handoff`) |
| :--- | :--- | :--- | :--- |
| **`core`** | `codex` / `gpt-6.2-sol` | 强类型核心逻辑、并发锁、资金/计费/安全状态机、复杂有状态适配器、疑难 Debug | `agy/claude-sonnet-5-5-medium` → `agy/claude-opus-5-5-medium` → `codebuddy/deepseek-v4.1-flash` |
| **`ui`** | `agy` / `gemini-4-neon-medium` | 前端 UI/UX、跨多文件集成网关/路由（如 MCP/HTTP 路由）、大上下文整合、文档 | `agy/claude-sonnet-5-5-medium` → `codebuddy/deepseek-v4.1-flash` → `codebuddy/kimi-k3.1-pro` |
| **`crud`** | `codebuddy` / `deepseek-v4.1-flash` *(过载自动降级 `kimi-k3.1-pro`)* | 常规 API、CLI 命令、薄契约适配器、表单、标准集成测试、模板代码 | `codebuddy/kimi-k3.1-pro` → `agy/gemini-3.8-flash-high` |
| **`test`** | `agy` / `gemini-3.8-flash-high` | 独立单元测试、边界用例、辅助脚本（快且低耗） | `codebuddy/deepseek-v4.1-flash` → `codex/gpt-6-luna` |

- **异构交叉审查（`aw review <name>`）**：绝不自己审自己。`codex` 写的代码由 `agy/gemini-3.8-flash-high` 初筛；`agy` / `codebuddy` 写的代码由 `codex/codex-auto-review` 初筛。

---

## 三、双模式自动切换（冷启动 vs 日常迭代）

`-1` 根据仓库是否存在 `docs/architecture.md` 自动选择模式：

### Mode A：冷启动 / 大型重构（无 `docs/architecture.md`，或明确要求完整架构设计）
1. **深度对齐**：配合 `/grill-me` 或 BMAD `/pm` + `/architect`，先拷问透模糊需求、边界条件、数据模型、失败模式与权衡取舍。
2. **双件套一次呈审**：在写任何业务代码前，同时拿出两份交付物等你拍板：
   - **`docs/architecture.md`**（项目宪法：范围与非目标、技术栈/目录树/模块边界、核心数据模型与公共接口契约、编码规范/错误处理/红线、验收测试策略）；
   - **Wave 任务切分表**（每波 2~4 个互不重叠任务：`wave | name | role | allowed_paths | verify_cmd`，并明确 `.aw.json` 与 `bd` 启用建议）。
3. **停机等你批准**双件套。
4. **Wave 0 基线提交（Leader 执行）**：把 `docs/architecture.md`、`.aw.json`、根配置、冻结的公共契约接口存根提交到 `main`，装好依赖并**确认 `main` 基线编译/类型检查全绿**，再启动 Wave 1。

### Mode B：日常功能迭代（已有 `docs/architecture.md`）
1. **直接以 `docs/architecture.md`（及 `docs/progress.md`）为宪法**，不再重写整份架构文档。
2. 只提交一份 1 页增量方案（目标 ≤3 句、增量红线、必要的公共契约更新 + Wave 任务切分表）。
3. **等你拍板切分表**后再派发 Worker。

### 契约修订协议（执行中发现缺口的逃生口）
Worker **严禁**修改冻结契约或 `--allow` 白名单外的文件。若执行中确实发现缺失字段或方法：
1. Worker 上报阻塞，不得绕路 hack 或越界修改；
2. Leader 评估是否真阻塞：
   - **可延后**：记入 `docs/progress.md` 的「延后技术债」，留待后续迭代；
   - **真阻塞**：**停机请示人类架构师批准** → Leader 在 `main` 修订契约、记录到 `docs/progress.md`，再让受影响 Worker 同步继续。

---

## 四、执行与质量控制闭环

### 1. Beads (`bd`) 按规模分层启用
- **单波次 / ≤4 个任务**：可跳过 `bd`，直接按拍板的任务切分表推进，省去嵌入式 Dolt 开销。
- **多波次 / ≥5 个任务 / 跨天项目**：
  - 静默初始化：`bd init --stealth --non-interactive >/dev/null`（保持 `.beads/` 不污染项目 Git）；
  - 建任务并显式加 `-t blocks` 依赖：`bd dep add <下游> <上游> -t blocks`；
  - 从 `bd ready` 派发并传 `--bead <id>` 给 `aw spawn`，`aw` 自动同步状态并在 `aw merge` 时自动 `bd close`。

### 2. 多波次并发派发（`aw spawn --role`）
- **默认按 Wave 推进**：Wave 1（基础模块）→ 门禁/审查/合并 → `main` 全量回归 + 更新 `docs/progress.md` → 从最新 `main` 拉起 Wave 2。
- **紧急叠分支逃生口**：仅当 Wave 1 已通过 `aw check` 且确有抢跑需求时，才用 `--base agent/<上游>` 叠分支。
- 每波并发 2~4 个 Worker，严格保证 `--allow` 路径互斥：
  ```bash
  aw spawn <name> --role <core|ui|crud|test> \
    --allow "<dir1/,dir2/>" \
    --verify "<测试/类型检查命令>" \
    [--bead "<bd-id>"] [--setup "<初始化命令>"] [--timeout <秒>] \
    -p "严格遵守 docs/architecture.md。任务：<目标、契约、白名单、跑验收并提交>。"
  ```

### 3. 监控、硬门禁、隔离防护与上下文保鲜
- **等待事件**：`aw wait --any`（仅盯启动时仍在 `RUNNING` 的 Worker，不会被旧 `IDLE` 短路；`aw wait --running` 等全部运行中 Worker），配合 `aw ls` / `aw logs <name> --last` 查看进度。
- **隔离与 6 层超时阶梯**：
  - 每个 Worker 自动挂载独立 `pre-commit` 钩子，禁止向主仓库与兄弟 worktree 提交（同时放行 `/tmp` 单测临时仓）；
  - 探针 `60s` < 空闲假死熔断 `AW_IDLE_TIMEOUT=240s`（标 `STALLED` 并强杀双进程组 + 触发 30m 冷却）< 验证/审查 `300s` < 按角色单轮总超时（`core=720s` / `ui,crud=600s` / `test=540s`）< `aw wait=900s`。
- **0 Token 硬门禁（`aw check <name>`）**：检查越界路径、主干漂移/脏状态、敏感契约文件与 `verify_cmd`。失败时**不销毁重建**，直接 `aw send <name>` 在原上下文内原地修复。
- **症状驱动的上下文保鲜（取代机械按轮次切）**：
  - **立即切换（不等第 6 轮）**：遇 `RATE_LIMITED` / `STALLED`、同一错误连卡 ≥2 轮、修 A 坏 B 振荡或明显失忆 → 直接 `aw handoff <name> [--force]` 同分支无缝换池。
  - **第 6 轮诊断门（非自动降级）**：到第 6 轮时由 Leader 诊断选择：
    1. 明显收敛仅剩 1 处小修 → 保留热会话再跑 1~2 轮收尾；
    2. 上下文臃肿但当前模型仍是最佳人选（如 `core` 在 `codex`）→ `aw handoff <name> --same-model`（同模型原地清空历史重生，不降级）；
    3. 模型吃力或需求不清 → 跨池 `aw handoff <name>` 或升级上报人类架构师。

### 4. 异构审查（`aw review`）与 2 轮熔断仲裁
- `aw check` 通过后对重要任务跑 `aw review <name>`（覆盖已提交、暂存、未跟踪新文件；内联 diff 上限 48KB；出错/超时/`UNKNOWN` 返回非零退出码）。
- **最多 2 轮审改闭环**：
  - 第 1 次 `REJECT`：属白名单内真实缺陷则 `aw send <name>` 原地修复；
  - 第 2 次仍 `REJECT`（或审稿人挑越界架构建议、代码风格吹毛求疵、疑似截断误判）：**Leader 必须亲自读源码仲裁**——真阻塞 Bug 继续修或 `handoff`；非阻塞/越界分歧立即停止空转，写明裁定理由上报架构师简报由人拍板。

### 5. 异常驱动合并、强制主干回归与活文档 `docs/progress.md`
- 每波次结束执行 `aw report --run-check`。
- **强制停机等人拍板（满足任一即停）**：
  - 存在任意异常（`FAILED`/`STALLED`/`RATE_LIMITED`、越界路径、改了敏感/契约文件、主仓库脏/漂移、`verify` 失败、`REJECT`/`UNKNOWN` 审查、审查分歧升级）；或
  - 当前是项目/迭代的**最终交付 Wave**。
  - 向你呈报一屏 **Architect Brief**（高亮例外 + 合规 Worker 1~2 行摘要，绝不倾倒原始 diff），等你批准后执行 `aw merge <name> --auto-commit --delete`。
- **中间 Wave 零异常自动推进**：若中间波次 **0 异常**（全部 `IDLE`、0 越界、0 敏感文件改动、`aw check PASS`、`aw review PASS`、主干干净），Leader 可直接 `aw merge` 合入（冲突会自动 `git merge --abort` 保护主工作区）。
- **强制主干全量回归**：每次合并进 `main` 后，Leader **必须立即在 `main` 跑全量构建/类型检查/测试**，不绿立刻停机上报。
- **维护全局活文档 `docs/progress.md`**：每波次合入并通过主干回归后，Leader 从**全项目架构视角**（绝非流水账 commit log）更新 `docs/progress.md` 并提交到 `main`，记录：整体波次里程碑、本波次落地模块与架构/数据流演进、已验证的核心不变量、延后技术债与审查备注、以及当前已验证的 `main` 基线数据。
