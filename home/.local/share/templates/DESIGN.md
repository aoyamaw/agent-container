# DESIGN.md — <功能/需求名称>

## 1. 目标（最多 3 句话）
- 交付物：
- 核心指标 / 验收标准：

## 2. 技术路线与红线
- **采用方案**：
- **明确禁止（红线）**：
  - 禁止擅自新增第三方重依赖
  - 禁止修改白名单以外的核心模块 / 公共契约

## 3. 公共契约（并发前先在主分支写死提交）
- 关键类型 / 接口签名 / 数据结构：
  - `path/to/types.ts`（或 `.rs` / `.py`）

## 4. 并发子任务切分（建议 2~4 个）

| Worker 名称 | 后端 CLI | 允许改动路径 (`--allow`) | 验收命令 (`--verify`) | 任务摘要 |
| --- | --- | --- | --- | --- |
| `core-impl` | `codex` | `src/core/` | `pnpm test -- core` | 实现核心逻辑 |
| `api-layer` | `pi` | `src/api/` | `pnpm typecheck` | 对接接口层 |
| `unit-tests` | `gemini` | `tests/` | `pnpm test` | 补齐边界单测 |
