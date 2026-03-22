---
name: next-steps
description: >
  Identifies and maintains project next steps. Reviews existing task backlog
  (`next-steps/active/`), consolidates scattered TODOs, analyzes code and
  commits for opportunities, or asks the user for goals when none are found.
argument-hint: "[refresh|clean]"
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(git log *), Bash(git diff *), Bash(scripts/work-queue.sh *), Bash(*/task-format.py *), Bash(*/task-board.py *), Bash(./bin/complete-tasks *), Bash(ls *), AskUserQuestion
---

# Next Steps

Identify, consolidate, and maintain actionable next steps for the project.

## Task Storage Modes

### Per-Task Files (preferred)

Tasks in `next-steps/active/` with YAML frontmatter. Use `scripts/task-format.py` to manage.

### Monolithic (legacy)

Tasks in `NEXT-STEPS.md`. Auto-detected when `next-steps/` doesn't exist.

## Arguments

- **(none)**: Full cascade — check backlog, scan TODOs, analyze, ask if needed
- **refresh**: Force re-analysis even if tasks exist
- **clean**: Remove completed items and re-prioritize

## Process

### Phase 0: Load the Task Board

```bash
scripts/task-board.py
```

Shows all pending tasks with status indicators: `[ ]` available, `[C]` claimed,
`[S]` shipped, `[P]` in-flight, `[B]` blocked. Use `--json` for machine-readable,
`--available-only` for claimable tasks. Skip if script doesn't exist.

### Phase 1: Check for Existing Task Backlog

```bash
ls next-steps/active/ 2>/dev/null
```

If per-task files exist:
1. Parse: `scripts/task-format.py parse`
2. Stats: `scripts/task-format.py stats`
3. Validate: `scripts/task-format.py validate`
4. Freshness: `scripts/task-format.py review-freshness`

If monolithic files found, read and review for staleness.

If `clean` argument: `scripts/task-format.py render`

### Phase 2: Scan for Scattered TODOs

Search for `TODO`, `FIXME`, `HACK`, `XXX`, `OPTIMIZE`, `REFACTOR` across source files.
Group by theme, assess priority by marker type.

### Phase 3: Analyze Code, Docs, and Commits

- Recent commits: `git log --oneline -20`
- Missing tests, docs, type hints
- Configuration gaps
- Dependency health

### Phase 4: Ask the User

If <3 actionable items found, ask using AskUserQuestion.

## Creating Tasks

**Always use helper scripts — never manually create task files.**

```bash
scripts/task-format.py create-task \
  --role <role> --section "<section-id>" --priority "<high|medium|low>" \
  --title "Task title" --body "What needs to be done"
```

**Completing tasks:**
```bash
./bin/complete-tasks --summary "What was done" slug1 slug2
```

Role tags: `[dev]`, `[design]`, `[docs]`, `[test]`, `[ops]`, `[security]`

## Output Format

### When existing tasks found

```
═══════════════════════════════════════════════════
            NEXT STEPS REVIEW
═══════════════════════════════════════════════════

Task backlog: next-steps/active/ (N pending tasks)

STATUS:
  OK    Item 1 — Still relevant
  DONE  Item 2 — Completed (see commit abc1234)
  STALE Item 3 — References removed file

INLINE TODOs FOUND:
  src/module.py:42  — TODO: Add retry logic
  src/utils.py:18   — FIXME: Handle empty input

RECOMMENDATION:
  - Remove 1 completed item
  - Add 2 inline TODOs to task list
═══════════════════════════════════════════════════
```

### When no tasks exist

```
═══════════════════════════════════════════════════
            NEXT STEPS ANALYSIS
═══════════════════════════════════════════════════

INLINE TODOs (X found):
  HIGH: ...
  MEDIUM: ...

CODE ANALYSIS:
  - 3 source files without tests
  - README contains template text

PROPOSED TASKS:
  [Preview of tasks to create]

Say **create** to write tasks.
═══════════════════════════════════════════════════
```
