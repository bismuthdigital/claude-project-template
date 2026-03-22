---
name: worktree-cleanup
description: >
  Clean up stale git worktrees. Removes orphaned directories, merged worktrees,
  and optionally dirty worktrees (with diff preservation). Frees disk space and
  releases stale work-queue claims.
argument-hint: "[--dry-run] [--save-diffs] [--force]"
allowed-tools: Bash(*/worktree-cleanup.sh *), Bash(git worktree *), Bash(du -sh *), Bash(git -C *), AskUserQuestion
---

# Worktree Cleanup

Clean up stale git worktrees to reclaim disk space and reduce clutter.

## Execution

### Step 1: Dry run first (always)

Always start with a dry run to show what would be removed:

```bash
scripts/worktree-cleanup.sh --dry-run
```

### Step 2: Present the plan

Show the user the dry-run output and ask for confirmation. Highlight:
- Total disk space to be freed
- Any dirty worktrees that would be skipped (and their uncommitted changes)
- Any worktrees with active work-queue claims

### Step 3: Execute cleanup

Based on user preference:

**Default** (safe — skip dirty worktrees):
```bash
scripts/worktree-cleanup.sh
```

**Save diffs before removing dirty worktrees**:
```bash
scripts/worktree-cleanup.sh --save-diffs /tmp/worktree-diffs
```

**Force remove everything** (including dirty):
```bash
scripts/worktree-cleanup.sh --force
```

### Step 4: Report results

Relay the key numbers:
- How many worktrees removed
- How much disk space freed
- Any remaining worktrees and why they were kept

## What gets removed

1. **Orphaned directories** — exist in `.claude/worktrees/` but have no git worktree registration
2. **Merged worktrees** — branch fully merged to main, no dirty changes
3. **Dirty worktrees without active claims** — only with `--force` or `--save-diffs`
4. **Dirty worktrees with active claims** — only with `--force`

## What is always kept

- The **current worktree** (the one this session is running in)
- Worktrees with **unmerged branches** and no dirty state
- Worktrees with **dirty changes + active claims** (unless `--force`)

## Side effects

- Releases stale work-queue claims for removed worktrees
- Deletes remote branches (`worktree-*`) for removed worktrees
- Runs `git worktree prune` to clean up stale metadata
