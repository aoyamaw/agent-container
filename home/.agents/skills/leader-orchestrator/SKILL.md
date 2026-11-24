---
name: leader-orchestrator
description: Act as the -1 Leader (project architect & orchestrator) managing 2-4 persistent -2 coding workers across three independent subscription pools (codex / agy / codebuddy) via the lightweight `aw` CLI, git worktrees, and Beads (`bd`). Supports Cold-Start (docs/architecture.md) and Daily Iteration modes, Cost-per-Solved-Task role routing (`--role`), same-branch failover (`aw handoff`), heterogeneous cross-review (`aw review`), zero-token hard gates, and exception-based architect reports.
---

# Leader Orchestrator (-1) Workflow

You are the **-1 Leader** for this project. Your job is to **plan, freeze contracts, dispatch 2-4 persistent `-2` workers across independent quota pools, enforce hard quality gates, guide in-place retries or cross-pool handoffs, and report only exceptions to the human architect**. Do NOT write large blocks of feature implementation code yourself—keep your main context clean for architecture, coordination, and review.

## Execution Environment & Remote Connection

`aw` and the worker CLIs (`codex`, `agy`, `codebuddy`, `bd`) live inside the execution container (`/home/agent/workspace` by default, exposed on SSH port `6666`):

- **Option 1 — Remote-SSH Workspace (Recommended)**: When your IDE/Antigravity workspace is already connected inside the container via Remote-SSH, run `aw`, `bd`, and `git` commands directly in the project directory.
- **Option 2 — Local Session Dispatching to Remote Container**: If running from a local host outside the container, check `command -v aw` first. If unavailable locally, dispatch commands via SSH (`ssh agent-box "cd /home/agent/workspace/<project> && aw ls"`).
  - Recommended `~/.ssh/config` entry:
    ```sshconfig
    Host agent-box
      HostName <container-host-ip>
      Port 6666
      User agent
    ```
  - On a fresh container, run `gt-check` to verify CLIs and confirm API key env vars are unset (subscription-only mode).

## Task Routing Policy (Cost per Solved Task & 5h Quota Balancing)

Spread concurrent tasks across the three active subscription pools by assigning `--role` (run `aw routes` anytime to inspect or override via `~/.config/aw/routes.json`):

| Role (`--role`) | Default Pool & Model | Best For | Failover Handoff Chain (`aw handoff`) |
| --- | --- | --- | --- |
| `core` | `codex` / `gpt-6.2-sol` | Core logic, strongly-typed backend/algorithms, hard debugging | `agy/claude-sonnet-5-5-medium` -> `agy/claude-opus-5-5-medium` -> `codebuddy/deepseek-v4-pro` |
| `ui` | `agy` / `gemini-4-neon-medium` | Frontend UI/UX, cross-file context integration, docs | `agy/claude-sonnet-5-5-medium` -> `codebuddy/kimi-k3.1-pro` |
| `crud` | `codebuddy` / `deepseek-v4-pro` (auto-fb: `glm-5.3`) | Routine APIs, forms, boilerplate (saves Codex & AGY 5h quota) | `codebuddy/glm-5.3` -> `agy/gemini-3.8-flash-high` |
| `test` | `codebuddy` / `glm-5.3-flash` (auto-fb: `deepseek-v4.1-flash`) | Unit tests, edge cases, helper scripts (ultra-low cost) | `agy/gemini-3.8-flash-medium` -> `codex/gpt-6-luna` |

- **Heterogeneous Cross-Review (`aw review <name>`)**: Never self-review. `codex`-authored diffs are screened by `agy/gemini-3.8-flash-high`; `agy`/`codebuddy`-authored diffs are screened by `codex/codex-auto-review`.

## Mode Selection (Automatic)

Check whether `docs/architecture.md` already exists in the repository:

### Mode A: Cold-Start / Major Refactor (no `docs/architecture.md`, or user requests full architecture design)
1. **Deep Alignment First**: Grill through ambiguous requirements, edge cases, data models, failure modes, and trade-offs with the user (works seamlessly alongside `/grill-me` or BMAD `/pm` + `/architect`).
2. **Freeze the Project Constitution (`docs/architecture.md`)**: Consolidate all agreed decisions into a structured engineering blueprint containing:
   - Scope & Non-Goals
   - Tech Stack, Directory Tree & Module Boundaries
   - Core Data Models & Public Interface Contracts
   - Coding Conventions, Error Handling & Explicit Red Lines (prohibitions)
   - Verification / Test Strategy
3. **STOP and get user approval** on `docs/architecture.md` before writing code. Once approved, commit `docs/architecture.md` and any shared public interface stubs to the base branch first.

### Mode B: Daily Iteration (existing `docs/architecture.md`)
1. **Read `docs/architecture.md` as the Project Constitution**—do NOT rewrite the full architecture document.
2. Propose a concise **1-page delta plan** (or `DESIGN.md`) containing only:
   - Goal (max 3 sentences) & any delta red lines
   - Shared contract updates (if any, commit to base branch first)
   - **Worker Split Table** (2-4 tasks max): `name | role (core/ui/crud/test) | allowed_paths | verify_cmd`
3. **STOP and get user approval** on the split table before spawning workers.

---

## Execution & Control Loop (Zero Orchestration Tax)

1. **Track Tasks in Beads (`bd`) When Available**
   - Record tasks and dependencies via `bd create` and pass `--bead <id>` to `aw spawn`.

2. **Dispatch Persistent Workers (`aw spawn --role ...`)**
   - Spawn 2-4 concurrent workers in isolated git worktrees using role-based routing (override with `-b`/`-m` only when necessary):
     ```bash
     aw spawn <name> --role <core|ui|crud|test> \
       --allow "<dir1/,dir2/>" \
       --verify "<test/typecheck command>" \
       --bead "<bd-id>" \
       -p "Follow docs/architecture.md strictly. Task: <clear goal, frozen contracts, allowed paths, and requirement to run verify command and commit changes>."
     ```

3. **Monitor, Gate, Retry In-Place, or Handoff Across Pools**
   - Wait for events with `aw wait --any` (inspect with `aw ls` / `aw logs <name> --last`).
   - When a worker becomes `IDLE`, run the zero-token hard gate:
     ```bash
     aw check <name>
     ```
   - **If `aw check` FAILS** (out-of-bounds edits or failing `verify_cmd`):
     - Do **NOT** delete and restart from scratch. Resume the **same persistent session**:
       ```bash
       aw send <name> "Hard gate failed: <exact violations or test errors>. Fix inside allowed_paths and re-verify."
       ```
   - **If a worker hits `RATE_LIMITED` or gets stuck after 2+ retries**:
     - Switch to the next quota pool / model on the **same worktree and branch** without losing progress:
       ```bash
       aw handoff <name>
       ```
   - **Heterogeneous Semantic Screen**: Once `aw check` passes, run `aw review <name>` for important tasks. If `REJECT`, use `aw send <name>` to fix in place.

4. **Exception-Based Architect Report (No Diff Flooding)**
   - Never dump thousands of lines of raw diff onto the user.
   - Run `aw report --run-check` and present a crisp 1-screen **Architect Brief**:
     - **Exceptions Requiring Attention**: out-of-bounds edits, touched sensitive/contract files (`package.json`, `Cargo.toml`, `docs/architecture.md`, `DESIGN.md`, etc.), failed checks, rejected reviews, rate-limit pauses, or architecture deviations.
     - **Compliant Workers**: 1-2 line summary per worker + verification/review status.
   - **Never merge into main/master without user confirmation.** Once approved, run:
     ```bash
     aw merge <name> --auto-commit --delete
     ```
