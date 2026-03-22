---
name: claim-tasks
description: >
  Claim tasks from the task backlog (`next-steps/active/`), then implement
  them using a merge-queue strategy: implement each with tests, then
  verify test quality for the batch. Accepts a number (claim N tasks),
  text (fuzzy match), or "list"/"status" for inspection.
argument-hint: "[N | task description | slug | list | status]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Bash(./bin/fuzzy-match *), Bash(./bin/worktree-info *), Bash(./bin/complete-tasks *), Bash(.venv/bin/python scripts/task-board.py *), Agent, AskUserQuestion, Skill
---

# Claim Tasks — Merge Queue Execution

Claim tasks from the task backlog and implement them end-to-end using a
merge-queue strategy. Multiple features are implemented with proper tests
between each, then test quality is verified for the batch.
Auto-invokes `/ship` when complete.

## Task System Reference

Tasks are stored as per-task markdown files with YAML frontmatter:

- **Pending tasks**: `next-steps/active/*.md`
- **Completed tasks**: `next-steps/completed/*.md`
- **Section ordering**: `next-steps/_sections.toml`
- **Full format spec**: `docs/TASK-FORMAT.md`

`NEXT-STEPS.md` is a **generated artifact** — rendered by CI via `scripts/task-format.py render`. Never read or edit it directly.

**Key commands** (always use these — never manually create/edit task files):

| Command | Purpose |
|---------|---------|
| `scripts/task-format.py parse` | Parse all pending tasks to JSON |
| `scripts/task-format.py create-task --role X --section Y --priority Z --title "..."` | Create a new task file |
| `./bin/complete-tasks --summary "..." slug1 slug2 ...` | Mark tasks complete (batch), move to `completed/` |
| `scripts/task-format.py validate` | Check task format compliance |
| `scripts/task-format.py lookup "<title or ID>"` | Find a task by title or ID |
| `scripts/task-format.py list-unreviewed` | List tasks without technical reviews |
| `scripts/task-format.py render` | Regenerate NEXT-STEPS.md locally (CI does this after merge) |

## Input Parsing

Determine the mode from the user's argument:

| Input | Mode |
|-------|------|
| (empty) or `1` | **count** — claim 1 task |
| Any positive integer N | **count** — claim N tasks |
| `list` | **list** — show all claims, no execution |
| `status` | **status** — show this worktree's claims, no execution |
| Any other text | **fuzzy** — match against task titles/slugs |

### Fuzzy Matching

When the input is text (not a number, not `list`/`status`):

1. Load pending tasks via `task-board.py --json` (or reuse if already loaded)
2. Run multi-match:
   ```bash
   ./bin/fuzzy-match --multi "<search_term>" < /tmp/claim-tasks-pending.json
   ```
3. Filter matches to only `status: "available"` tasks
4. Batch size limits: 0 matches = stop, 1-5 = claim all, 6+ = claim top 5 (ask to claim all)

## Inspection Commands

### `/claim-tasks list`

Show all current claims across all worktrees:
```bash
.venv/bin/python scripts/task-board.py
```

### `/claim-tasks status`

Show this worktree's claims:
```bash
scripts/work-queue.sh claimed-by-me
```

**For both inspection commands, stop — do not proceed to execution.**

---

## Test Execution Discipline

These rules apply to ALL phases:

1. **Commit before test.** Always `git add -A && git commit && git push` BEFORE running tests.
2. **One foreground test run.** Run `pytest` with `timeout: 300000` (5 minutes).
3. **Never pipe test output.** Run directly and read output.
4. **Never run tests in background.** No `run_in_background` for test runs.
5. **Maximum 3 fix-rerun cycles per phase.** If still failing, move on — CI is the gate.
6. **Never blame the user for interruptions.** Check committed state and continue.

## Interruption Handling

When the user interrupts, **stop and assess**:
1. Run `git log --oneline -5` and `git diff --stat` to show saved state
2. Offer options: continue from last commit, skip task, stop batch and ship
3. Never re-launch the same prompt unchanged

---

## Four-Phase Execution

### Phase 1 — Claim & Orient

**Runs in the main context. Writes a handoff file for Phase 2.**

0. **Ensure venv exists**:
   ```bash
   test -x .venv/bin/python || (python3 -m venv .venv && .venv/bin/pip install -e ".[dev]" 2>&1 | tail -5)
   ```

1. **Initialize work queue and load task board**:
   ```bash
   scripts/work-queue.sh init
   scripts/work-queue.sh auto-release-merged
   .venv/bin/python scripts/task-board.py --json > /tmp/claim-tasks-board.json
   ```

2. **Select tasks** — by count (highest priority) or fuzzy match. Only `status: "available"`.
   Use pre-computed `clusters` from board JSON for count mode.

   **PR conflict detection** after selecting candidates:
   ```bash
   scripts/work-queue.sh check-pr-overlap '["src/foo.py", ...]'
   ```

3. **Already-implemented check** — verify each candidate hasn't been implemented on main.
   If found, complete immediately:
   ```bash
   ./bin/complete-tasks --summary "Already implemented in main" <slug>
   ```

4. **Claim** using `try-claim`:
   ```bash
   scripts/work-queue.sh try-claim <N> /tmp/wq-candidates-<worktree>.json
   ```

5. **Generate missing technical reviews** for claimed tasks. Write to `${MAIN_REPO}/.claude/reviews/<slug>.md`.

6. **Write handoff file** at `/tmp/claim-tasks-<worktree>.json`.

7. **Present** the claim summary.

---

### Phase 2 — Implement with Tests

**Each task runs in its own subagent (Agent tool) for fresh context.**

For each task, spawn an Agent that:
1. Reads the handoff file and technical review
2. Reads source files and understands existing code
3. Implements the feature/fix with incremental commits
4. Writes tests (5-10 per task, add to existing files first)
5. Runs scoped `pytest` with timeout
6. Updates handoff file status to "implemented"

**Test efficiency rules:**
- Add to existing test files first — no duplicate scope files
- Share fixtures via conftest.py
- 5-10 tests per task, not more
- Never assert exact counts of dynamic data
- Never assert specific prose phrases

---

### Phase 2.5 — Code Health Review

**Single subagent reviewing all changed files.**

Review checklist:
1. **Simplification** — early returns, dead code removal, idiomatic Python
2. **Assumption checking** — type annotations match runtime, callers match callees
3. **Anti-patterns** — mutable defaults, bare except, god functions
4. **Consistency** — module patterns, naming conventions, error handling

Commit fixes per file, run lint and tests after all fixes.

---

### Phase 3 — Verify and Harden

**Single subagent. Does NOT write new test files.**

1. Review test fixture efficiency and duplication
2. Merge duplicate test files, delete trivial tests
3. Run `mypy src/`
4. Complete tasks:
   ```bash
   ./bin/complete-tasks --summary "<what>" slug1 slug2
   ```
5. Auto-invoke `/ship`

---

## Handoff File

Path: `/tmp/claim-tasks-<worktree>.json`

| Field | Set By | Description |
|-------|--------|-------------|
| `worktree` | Phase 1 | Worktree name |
| `main_repo` | Phase 1 | Absolute path to main repo |
| `tasks[].index` | Phase 1 | 1-based task number |
| `tasks[].title` | Phase 1 | Exact title from task file |
| `tasks[].slug` | Phase 1 | Task slug |
| `tasks[].status` | All | `pending` → `implemented` → `health-checked` → `verified` |
| `tasks[].files_changed` | Phase 2 | Source files modified |
| `tasks[].tests_written` | Phase 2 | Test file paths |
| `tasks[].health_notes` | Phase 2.5 | Code health changes |

## Conflict Handling

Status codes from `try-claim`:
- `CLAIMED` — success
- `ALREADY_OWNED` — this worktree already owns it
- `EXPIRED_RECLAIMED` — reclaimed from expired agent
- `CLAIMED_BY:<wt>` — another active agent owns it (skip)
- `SHIPPED_BY:<wt>` — in merge queue (skip)

## Safety Rules

1. Never `rm -f` claim files — use `scripts/work-queue.sh release`
2. Never edit claim JSON files directly
3. Claims expire after 10 hours (TTL default)
