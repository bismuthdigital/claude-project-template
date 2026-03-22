---
name: sprint
description: >
  Sprint execution — thin wrapper over /claim-tasks. Checks for existing
  claims and delegates to the merge-queue execution pipeline.
argument-hint: "[plan|execute|status]"
allowed-tools: Read, Bash(*/work-queue.sh *), Bash(.venv/bin/python scripts/task-board.py *), Bash(git *), Skill, AskUserQuestion
---

# Sprint

Thin wrapper over `/claim-tasks` that checks for existing claims and delegates.

## Commands

### `/sprint execute` (default)

1. **Check for existing claims**:
   ```bash
   scripts/work-queue.sh claimed-by-me
   ```

2. **If this worktree has claimed tasks**: Check if a handoff file exists at
   `/tmp/claim-tasks-<worktree>.json` (where `<worktree>` is from
   `scripts/work-queue.sh` output or the worktree directory name).

   - If the handoff file exists and has tasks with status `pending`:
     Resume Phase 2 of `/claim-tasks` — invoke the Skill tool with
     `/claim-tasks execute-pending` (the claim-tasks skill will detect
     the existing handoff file and skip Phase 1).
   - If no handoff file: Invoke `/claim-tasks` with the number of already-
     claimed tasks. Phase 1 will detect the existing claims via
     `ALREADY_OWNED` and proceed to execution.

3. **If no claims exist**: Invoke `/claim-tasks 1` to claim one task and
   execute it.

### `/sprint plan`

Show what would be claimed without executing:

1. **Load the unified task board**:
   ```bash
   .venv/bin/python scripts/task-board.py
   ```
   Use `--clusters` to see file-overlap groupings.
   Use `--available-only` to show only claimable tasks.

2. Present the top candidates with priority, files, and review status.
3. Ask the user to confirm, then invoke `/claim-tasks` with the selected
   count or task names.

### `/sprint status`

Equivalent to `/claim-tasks status`. Shows this worktree's claims.

```bash
scripts/work-queue.sh claimed-by-me
```

If a handoff file exists at `/tmp/claim-tasks-<worktree>.json`, also show
the current phase and per-task status from the file.
