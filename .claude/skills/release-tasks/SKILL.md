---
name: release-tasks
description: >
  Release claimed tasks back to the work queue. Use when abandoning work,
  when tasks are blocked, or for manual cleanup of stale claims.
argument-hint: "[all | <slug> | expire]"
allowed-tools: Read, Bash(*/work-queue.sh *), AskUserQuestion
---

# Release Tasks

Release task claims back to the shared work queue so other agents can pick them up.

## Commands

### `/release-tasks` (no args)

Release all tasks claimed by this worktree.

1. **List** current claims for this worktree:
   ```bash
   scripts/work-queue.sh claimed-by-me
   ```

2. **Confirm** with the user before releasing:
   > "You have N claimed tasks. Release all of them back to the queue?"

3. **Release** all claims:
   ```bash
   scripts/work-queue.sh release-all
   ```

4. **Report**:
```
═══════════════════════════════════════════════════
            TASKS RELEASED
═══════════════════════════════════════════════════

Released 3 tasks back to the work queue:
  1. fix-config-validation-edge-case
  2. add-retry-logic-to-publisher
  3. improve-mobile-nav-breadcrumbs

These tasks are now available for other agents.
═══════════════════════════════════════════════════
```

### `/release-tasks <slug>`

Release a single task by its slug.

```bash
scripts/work-queue.sh release "<slug>"
```

### `/release-tasks expire`

Remove all claims that have exceeded their TTL, from any worktree. Shipped claims are exempt from expiration — they represent work waiting in the merge queue.

```bash
scripts/work-queue.sh expire
```

Also runs auto-release for merged PRs:

```bash
scripts/work-queue.sh auto-release-merged
```

Report which claims were expired, which were auto-released (merged), and from which worktrees.

## When to Use

- **Abandoning work**: If you realize a task is too complex or blocked
- **Rebalancing**: If one agent has too many tasks and another has none
- **Cleanup**: After a crash or when a worktree is removed without shipping
- **Sprint complete**: `/ship` marks claims as shipped, but use this for manual release
- **Post-merge cleanup**: `auto-release-merged` handles this automatically

## Claim States

| State | Meaning | Released by |
|-------|---------|-------------|
| `claimed` | Active work in progress | `release`, `release-all`, or `expire` (TTL) |
| `shipped` | PR created, waiting to merge | `auto-release-merged` (after PR merges) |

Shipped claims are exempt from TTL expiration. They are only released when their associated PR merges (detected by `auto-release-merged`).

## Error Handling

| Result | Meaning |
|--------|---------|
| `RELEASED` | Claim successfully removed |
| `NOT_FOUND` | No claim exists for this slug (already released or never claimed) |
| `NOT_OWNER:<worktree>` | Claim belongs to another worktree; use `--force` to override |

## Handling Duplicate Claim Files

If you see duplicate claim files (same task, different slugs), run `validate` first:
```bash
scripts/work-queue.sh validate
```
This reports all issues. Then release only your own claims using the script — never delete files directly.

## Safety Rules

1. **Never `rm -f` claim files directly.** Always use `scripts/work-queue.sh release` or `release-all`. Direct deletion bypasses ownership checks and can delete another agent's claims.
2. **Never `cd` to the main repo before running the script.** The script resolves the main repo path internally. Changing CWD causes worktree misidentification.
3. **Never edit claim JSON files directly.** Use the script's subcommands.
