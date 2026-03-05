---
name: claim-tasks
description: >
  Claim tasks from NEXT-STEPS.md. Automatically creates an isolated git
  worktree before claiming, so development happens on a clean branch.
  Prevents concurrent agents from picking the same work via file-based locks.
argument-hint: "[N | list | status]"
allowed-tools: Read, Glob, Grep, Bash(*/work-queue.sh *), Bash(git worktree list*), Bash(git tag *), Bash(git log *), Bash(grep *version* pyproject.toml), Bash(git rev-parse *), Bash(*/task-format.py *), EnterWorktree, AskUserQuestion
---

# Claim Tasks

You are claiming tasks from NEXT-STEPS.md. When claiming tasks (not listing or checking status), this skill first ensures the session is in an isolated git worktree, creating one automatically if needed. This prevents other concurrent Claude Code agents from duplicating the same work.

**Assumption:** All agents work within worktrees off the same repository. The work queue relies on a shared filesystem directory visible to all worktrees.

## How It Works

Tasks are claimed by writing lock files to a shared directory that all worktrees can see. The lock directory lives in the **main repo's** `.claude/work-queue/claims/`. Since all worktrees are children of the main repo, they can all read and write this directory.

The helper script `scripts/work-queue.sh` manages all claim operations.

## Task Storage Modes

Tasks may be stored in two formats:

1. **Per-task files** (preferred): Individual `.md` files in `next-steps/active/` with YAML frontmatter. Detected when the `next-steps/` directory exists. Use `scripts/task-format.py render` to generate `NEXT-STEPS.md` from these files.
2. **Monolithic** (legacy): Tasks stored directly in `NEXT-STEPS.md`.

The claiming process works the same regardless of storage mode — it reads from `NEXT-STEPS.md` (rendered or committed).

## Commands

### `/claim-tasks N` (default: 3)

Claim N unclaimed tasks from NEXT-STEPS.md.

1. **Ensure worktree isolation**:
   ```bash
   git rev-parse --git-dir
   ```
   - If the output contains `/worktrees/`, you are already in a worktree — proceed to step 2.
   - If the output ends with `.git`, you are on main — use the **EnterWorktree** tool with no `name` argument (it will auto-generate a name), then verify:
     ```bash
     git rev-parse --git-dir
     ```
   - **Important:** Do NOT ask the user for confirmation. Worktree creation is automatic and silent. Note the worktree name for the final output.

2. **Initialize** the work queue:
   ```bash
   scripts/work-queue.sh init
   ```

3. **Auto-release merged PRs**: Clean up claims for PRs that have already been merged:
   ```bash
   scripts/work-queue.sh auto-release-merged
   ```

4. **Expire stale claims**: Remove claims that exceeded their TTL (skips shipped claims):
   ```bash
   scripts/work-queue.sh expire
   ```

5. **Render task files** (if per-task mode):
   ```bash
   # Check if per-task mode is active
   ls next-steps/active/ 2>/dev/null
   ```
   If the directory exists, render NEXT-STEPS.md from task files:
   ```bash
   scripts/task-format.py render
   ```

6. **Read** NEXT-STEPS.md to get the full task list

7. **List** current claims to see what's already taken:
   ```bash
   scripts/work-queue.sh list
   ```

8. **Check in-flight PRs** for tasks already completed in unmerged PRs:
   ```bash
   scripts/work-queue.sh inflight-tasks
   ```
   This returns a JSON array of task titles that are marked `[x]` in open PRs. These tasks are being shipped by another agent and should be excluded from claiming, even though they still appear as `[ ]` in the local NEXT-STEPS.md.

9. **Parse tasks** from the High Priority and Medium Priority sections. Each task looks like:
   ```markdown
   - [ ] **[role] Task title** — Description
   ```
   Extract: the checkbox state, role tag, title, and description.

10. **Filter** out:
    - Tasks already completed (`[x]`)
    - Tasks already claimed by another worktree (check the `list` output)
    - Tasks whose dependencies are not yet complete
    - Tasks completed in open PRs (from the `inflight-tasks` output)

11. **Select** up to N unclaimed tasks. Prefer:
    - Higher priority first (High > Medium > Low)
    - Tasks with fewer dependencies
    - Tasks that are coherent together (same area of the codebase)

12. **Speculate version** for this batch of tasks (see Version Speculation below). This determines a `speculated_version` string to include in each claim.

13. **Batch claim** using try-claim for atomic, race-safe claiming:

    Write a candidates file at `/tmp/wq-candidates-<worktree_name>.json`:
    ```json
    [
      {"title": "Task title one", "section": "High Priority", "role_tag": "dev"},
      {"title": "Task title two", "section": "Medium Priority", "role_tag": "test"}
    ]
    ```

    ```bash
    scripts/work-queue.sh try-claim <N> /tmp/wq-candidates-<worktree_name>.json
    ```

    Parse the JSON output — `got` tells you how many were claimed, `claims` contains the details. If `got` is 0, all candidates were already taken.

    After try-claim, update each claim with the speculated version:
    ```bash
    scripts/work-queue.sh claim "<slug>" "<title>" "<section>" "<role_tag>" "<speculated_version>"
    ```

14. **Present** the claim results:

```
═══════════════════════════════════════════════════
            TASKS CLAIMED
═══════════════════════════════════════════════════

Worktree: festive-mendel (auto-created)
Branch: claude-worktree-festive-mendel
Claimed: 3 tasks | Skipped: 2 (claimed) | In-flight: 3 (open PRs)
Speculated version: 0.18.0 (minor)

───────────────────────────────────────────────────
YOUR TASKS
───────────────────────────────────────────────────

1. [dev] Fix config validation edge case
   Section: High Priority
   Files: src/your_package/config.py

2. [dev] Add retry logic to publisher
   Section: High Priority
   Files: src/your_package/publish.py

3. [design] Improve mobile nav breadcrumbs
   Section: Medium Priority
   Files: src/your_package/templates/

───────────────────────────────────────────────────
CLAIMED BY OTHERS
───────────────────────────────────────────────────

exciting-shtern (v0.19.0):
  - [docs] Rewrite getting started guide (42 min ago)
  - [test] Add integration test coverage (42 min ago)

───────────────────────────────────────────────────
IN-FLIGHT (OPEN PRs)
───────────────────────────────────────────────────

  - Add content hash dedup for submissions (PR #145)
  - Improve error messages in validation (PR #145)
  - Add batch-process CLI command (PR #145)

───────────────────────────────────────────────────

Ready to start working, or **/ship** when done
to merge back to main.
═══════════════════════════════════════════════════
```

Note: Include `(auto-created)` after the worktree name only if the worktree was created in step 1. Omit it if the worktree pre-existed.

### `/claim-tasks list`

Show all current claims across all worktrees without claiming anything new.

> This command does NOT create a worktree. It runs wherever the session currently is.

1. Run `scripts/work-queue.sh list` to get the JSON claim data
2. Present a formatted summary grouped by worktree, including speculated versions and shipped state

### `/claim-tasks status`

Show only this worktree's claimed tasks.

> This command does NOT create a worktree. It runs wherever the session currently is.

1. Run `scripts/work-queue.sh claimed-by-me`
2. Present a formatted list including speculated version and shipped state

## Version Speculation

When claiming tasks, speculate on the next appropriate semver version. This helps concurrent agents avoid version collisions when they independently ship and version their work.

### How It Works

1. **Get the current project version** from `pyproject.toml`:
   ```bash
   grep -E "^version" pyproject.toml
   ```

2. **Check for the highest claimed version** across all active and shipped claims:
   ```bash
   scripts/work-queue.sh max-claimed-version
   ```
   This returns a version string (e.g., `0.18.0`) or `NONE` if no claims have versions.

3. **Determine the base version** for incrementing:
   - If `max-claimed-version` returns `NONE`, use the project version from `pyproject.toml` as the base
   - If `max-claimed-version` returns a version, use whichever is higher: the project version or the max claimed version

4. **Determine the increment level** from the selected tasks:

   | Task Pattern | Increment | Examples |
   |-------------|-----------|---------|
   | New feature, new page, new command, new capability | **MINOR** | "Add dark mode", "Create user dashboard", "Add export command" |
   | Bug fix, typo, docs update, test addition, refactor, chore | **PATCH** | "Fix config validation", "Update README", "Add missing tests" |
   | Breaking change, remove feature, change public API | **MAJOR** | "Remove legacy API", "Redesign data schema" |

   Use the **highest** applicable level across all selected tasks. When in doubt, default to PATCH.

5. **Calculate the speculated version** by applying the increment to the base:
   ```
   Base: 0.17.1
     + PATCH → 0.17.2
     + MINOR → 0.18.0
     + MAJOR → 1.0.0
   ```

6. **Pass the version** to each claim command as the 5th argument.

### Examples

**No other claims, project at 0.17.1, claiming bug fixes:**
- Base: 0.17.1 (from pyproject.toml)
- Increment: PATCH (bug fixes only)
- Speculated: `0.17.2`

**Another agent claimed 0.18.0, project at 0.17.1, claiming a new feature:**
- Base: 0.18.0 (highest claimed version)
- Increment: MINOR (new feature)
- Speculated: `0.19.0`

**Another agent claimed 0.17.2, project at 0.17.1, claiming a bug fix:**
- Base: 0.17.2 (highest claimed version)
- Increment: PATCH
- Speculated: `0.17.3`

### Important Notes

- The speculated version is a **best guess** — the actual version will be determined at `/version` time based on real commit analysis
- If the `/version` skill detects a different increment level from actual commits, the actual version takes precedence
- This coordination is advisory, not enforced — it prevents the common case where two agents both target the same version number
- Expired claims (past TTL) are excluded from version calculations — crashed agents don't inflate version speculation for active agents
- Shipped claims ARE included in version calculations — they represent in-flight versions waiting to merge

## Task Slug Generation

Slugs are **auto-generated by the script** from the task title. Do NOT manually compute slugs — just pass the exact title and a placeholder slug. The script's `slug_from_title()` function is the single source of truth.

## Safety Rules

1. **Never `rm -f` claim files directly.** Always use `scripts/work-queue.sh release` or `release-all`. Direct deletion bypasses ownership checks and can delete another agent's claims.
2. **Never `cd` to the main repo before running the script.** The script resolves the main repo path internally. Changing CWD to the main repo before running causes worktree detection to misidentify as "main".
3. **Never edit claim JSON files directly.** Use the script's subcommands. Direct edits bypass validation.
4. **Run `scripts/work-queue.sh validate`** if you suspect claim issues (duplicates, mismatches, orphans).

## Conflict Handling

If a claim attempt returns `CLAIMED_BY:<worktree>`:
- Skip that task and try the next unclaimed one
- Report the skip in the output

If a claim attempt returns `EXPIRED_RECLAIMED`:
- Note in the output that a stale claim was reclaimed
- Proceed with the task

If a claim attempt returns `ALREADY_OWNED`:
- This worktree already has this task; skip re-claiming
- Include it in the "your tasks" list

If a claim attempt returns `LOCK_FAILED`:
- Another agent is actively claiming this exact task right now
- Skip it and try the next unclaimed task
- Report the skip in the output (this is rare and transient)

### Lock Directories

The work queue uses `.lock/` directories inside `claims/` for atomic mutual exclusion. These are ephemeral — they exist only during the brief window while a claim is being written. Lock dirs older than 30 seconds are automatically cleaned as stale. You should never need to manually manage `.lock/` directories; they are created and removed by `work-queue.sh` internally.

## Integration

- **Start work**: Run `/claim-tasks` to create a worktree and reserve tasks
- **After `/ship`**: Claims are marked as shipped (not released) for merge queue tracking
- **Manual release**: Run `/release-tasks` to give back unclaimed work
- **Auto-cleanup**: `auto-release-merged` frees claims for PRs that have merged

## Expiration

Claims have a TTL (default: 120 minutes). After the TTL, other agents can reclaim the task. Shipped claims are exempt from TTL expiration — they represent work waiting in the merge queue. To clean up expired claims:

```bash
scripts/work-queue.sh expire
```
