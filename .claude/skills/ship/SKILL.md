---
name: ship
description: >
  Commits changes, creates a PR, merges it, and syncs the local repo.
  Complete workflow from worktree changes to running code in one command.
argument-hint: "[commit message or empty for auto-generated]"
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(git *), Bash(gh *), Bash(cd * && git *), Bash(*/work-queue.sh *), Bash(./bin/pr *), Bash(./bin/test *), Bash(./bin/worktree-info *), Bash(source *), Bash(ruff *), Bash(mypy *), Bash(pytest *), Skill
---

# Ship Changes to Main

Complete workflow to ship changes from a worktree to the main branch and sync the local repository.

## What This Skill Does

1. **Detect** — Find claimed tasks and build context
2. **Commit** — Stage and commit all changes with a descriptive message
3. **Rebase** — Rebase onto latest main, resolving conflicts intelligently
4. **Push** — Push the branch to GitHub
5. **Create PR** — Open a pull request with summary, test plan, and technical reviews
6. **Merge** — Squash merge the PR (or enable auto-merge for merge queues)
7. **Sync Local** — Fetch and pull changes in the local (non-worktree) directory

## Configuration

This skill reads from `.claude/ship.json` for project-specific settings:

```json
{
  "localPath": "/Users/yourname/code/project-name",
  "defaultBase": "main",
  "mergeMethod": "squash"
}
```

| Setting | Description | Default |
|---------|-------------|---------|
| `localPath` | Path to local repo (where code runs) | Auto-detect from worktree |
| `defaultBase` | Base branch for PRs | `main` |
| `mergeMethod` | PR merge method: `squash`, `merge`, `rebase` | `squash` |
| `mergeQueue` | Use GitHub merge queue instead of direct merge | `false` |

If `localPath` is not configured, the skill auto-detects it from `git worktree list` (uses the main worktree path).

## Process

### Step 1: Pre-flight Checks

Before starting, verify:

```bash
# Check we're in a worktree (not the main repo)
./bin/worktree-info is-worktree
```

If the command prints `true`, you are in a worktree (expected). If it prints `false`, you're in the main repository — warn the user:
> "You're already in the main repository. This skill is designed for worktree -> main workflows. Continue anyway?"

```bash
# Check for uncommitted changes
git status --porcelain
```

If no changes exist, inform the user and exit.

**Worktree safety:** If the user has uncommitted changes they want to set aside temporarily, never suggest `git stash` — stashes are shared across all worktrees and can be accidentally popped in the wrong worktree. Recommend committing as a WIP commit instead.

### Step 1a: Detect Claimed Tasks

Query the work queue to find what task(s) this worktree is shipping:

```bash
scripts/work-queue.sh claimed-by-me
```

This returns a JSON array of claim objects. Extract the `task_title` from each. If the array is non-empty, these are the tasks being shipped — display them prominently in the output header (see Output Format) and include them in the PR description.

If the work queue script is not found or returns `[]`, that's fine — the agent may be shipping ad-hoc work without a claimed task. In that case, analyze the diff to infer the task description for the output header.

### Step 2: Determine Local Path

Read configuration and determine the local sync path:

```bash
# Try to read config
cat .claude/ship.json 2>/dev/null
```

Also read the `mergeQueue` flag (default: `false`). When `true`, Steps 8-10 use merge queue behavior instead of direct merge.

If `localPath` is not configured, auto-detect:

```bash
# Get main worktree path
./bin/worktree-info main-repo
```

Verify the path exists and is a git repository before proceeding.

### Step 3: Detect Docs-Only Changes

Before running CI checks, determine whether the changeset is docs-only. Stage the files first, then **unstage rendered task files** (these are maintained by CI, not by PRs):

```bash
git add -A

# Unstage rendered task files — CI auto-commits these after merge
git reset HEAD -- NEXT-STEPS.md NEXT-STEPS-COMPLETED.md .tasks.json 2>/dev/null || true

git diff --cached --name-only
```

A commit is **docs-only** if every changed file matches one of these patterns:
- `*.md` (Markdown files)
- `*.txt` (text files, but NOT `requirements*.txt`)
- `*.toml` (config files, but NOT `pyproject.toml`)
- `docs/**` (documentation directory)
- `.claude/**` (Claude config/skills)
- `LICENSE*`, `NOTICE*`, `.gitignore`, `.github/CODEOWNERS`

If **any** file falls outside these patterns (e.g. `.py`, `.yml`, `pyproject.toml`, `requirements*.txt`), the commit is **not** docs-only and requires full CI.

### Step 3a: CI Parity Checks (code changes only)

**Skip this step entirely for docs-only commits.**

Run the same lint and type checks that CI runs. This prevents shipping code that will fail the PR checks.

```bash
# Activate venv
source .venv/bin/activate 2>/dev/null || true

# Auto-fix first
ruff check --fix .
ruff format .

# Then verify CI checks pass
ruff format --check .
ruff check .
mypy src/
```

If any check fails, **stop and fix the issues before continuing**. Do not skip this step — CI will catch the same errors and block the merge.

### Step 4: Commit Changes

Generate or use provided commit message:

```bash
# Show what will be committed
git status
git diff --cached --stat
```

If no commit message argument provided, generate one by:
1. Analyzing the diff to understand the changes
2. Writing a concise commit message (1-2 sentences)
3. Including Co-Authored-By line

**Docs-only**: append `[skip ci]` to first line.

```bash
git commit -m "$(cat <<'EOF'
<commit message here>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Step 5: Rebase onto Latest Main

**This step prevents merge conflicts at PR merge time.** When multiple agents work concurrently, main moves forward as other agents merge. Rebasing now — while you still have full context of your changes — is far better than failing at merge time.

```bash
# Fetch latest main
git fetch origin main
```

Check if main has moved since you branched:

```bash
# Count commits on main that aren't in this branch
git rev-list --count HEAD..origin/main
```

If the count is 0, main hasn't moved — **skip the rebase** and proceed to Step 6.

If main has moved, rebase:

```bash
git rebase origin/main
```

#### 5a: Clean Rebase (no conflicts)

If the rebase succeeds cleanly, proceed to Step 6.

#### 5b: Conflict Resolution

If the rebase stops with conflicts, `git status` will show unmerged paths. For **each** conflicted file, apply the appropriate strategy:

**Read the conflicted file** to see the conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`). Understand what your branch changed versus what main changed.

**IMPORTANT:** During a `git rebase`, the sides are swapped from what you might expect:
- `<<<<<<< HEAD` = the **main branch** (the base you're rebasing onto)
- `>>>>>>> <commit>` = **your changes** (the commits being replayed)

##### Strategy by File Type

| File Pattern | Strategy | Details |
|-------------|----------|---------|
| `next-steps/**/*.md` | **Rarely conflicts** | Each PR touches different task files. If a conflict does occur, read both sides and combine (standard merge). |
| `next-steps/_sections.toml` | **Take theirs + re-add** | If your branch added a section, take theirs and re-add your section entry. |
| `pyproject.toml` (version only) | **Take main's** | Feature PRs don't touch version files. If a version conflict appears, take main's version. |
| `pyproject.toml` (other fields) | **Analyze** | Read both sides, understand what each changed, combine. Usually one side added a dependency and the other changed something else. |
| `reports/**`, `sprints/**` | **Keep both** | These are append-only. Both sides' additions are valid. |
| `*.py` (source code) | **Analyze intent** | See "Code Conflict Resolution" below. |
| `*.html`, `*.css` | **Analyze intent** | Same as code — understand what each side changed and combine. |
| `tests/**/*.py` | **Analyze intent** | Same as code. Be especially careful about fixture changes that both sides depend on. |

##### Code Conflict Resolution

For Python source files and other code, you have a significant advantage: you understand the intent of your changes because you just wrote them. Use this to resolve intelligently:

1. **Read the full conflicted file** — understand the surrounding context, not just the conflict markers.
2. **Identify what main changed** — was it a refactor, bug fix, new feature, or formatting change?
3. **Identify what your branch changed** — you already know this from the work you just did.
4. **Determine compatibility:**
   - **Disjoint changes**: Both sides changed different things in the same region. Keep both changes.
   - **Overlapping changes**: Both sides modified the same logic. Understand the intent of each and write a version that satisfies both.
   - **Contradictory changes**: Main changed behavior in a way that conflicts with your feature. Flag this to the user — automated resolution risks losing important semantics.

5. **Edit the file** to remove conflict markers and produce the correct merged result. Use the Edit tool — do not leave any `<<<<<<<`, `=======`, or `>>>>>>>` markers.

6. **Stage the resolved file:**
   ```bash
   git add <resolved-file>
   ```

After resolving **all** conflicts for the current rebase step:

```bash
git rebase --continue
```

If the rebase has multiple conflicting commits, you may need to resolve conflicts and `--continue` multiple times.

##### When NOT to Auto-Resolve

Abort the rebase and escalate to the user if:

- A code conflict involves **behavioral changes on both sides** where the correct merge isn't obvious
- More than **5 files** are conflicted (suggests the branches diverged significantly)
- A conflict touches **security-sensitive code** (auth, input validation, sanitization)
- You're uncertain about the intent of main's changes

To abort:
```bash
git rebase --abort
```

Then inform the user of the situation and ask how to proceed.

#### 5c: Post-Rebase Verification (code changes only)

**Skip this step for docs-only commits or if the rebase was clean (no conflicts resolved).**

After resolving conflicts, re-run CI parity checks to ensure the resolution didn't break anything:

```bash
source .venv/bin/activate 2>/dev/null || true

# Lint and format check
ruff check --fix .
ruff format .
ruff format --check .
ruff check .

# Type check
mypy src/

# Run scoped tests
./bin/test
```

If any linting or formatting was auto-fixed, stage and amend:
```bash
git add -A
git commit --amend --no-edit
```

If tests fail after conflict resolution:
1. **Analyze the failure** — is it caused by the merge resolution or a pre-existing issue on main?
2. **Fix the resolution** if it's your merge that broke things. Stage and amend.
3. **If main itself has failing tests**, note this in the PR description and proceed.

### Step 6: Push to Remote

```bash
# force-with-lease is always safe for worktree branches (single-owner)
git push --force-with-lease -u origin HEAD
```

Use `--force-with-lease` unconditionally. When a rebase occurred, it's required (rebase rewrites commit hashes). When no rebase occurred, it's harmless and equivalent to a regular push. This is safe because worktree branches are owned by a single agent; no one else pushes to them.

### Step 6a: Detect Competing PRs

Before creating a PR, check if another PR already implements the same task(s). This prevents duplicate work when multiple agents implement the same task concurrently.

**Skip this step if no claimed tasks were found in Step 1a** (ad-hoc work has no task slug to match).

For each claimed task, run:

```bash
scripts/work-queue.sh reconcile <task-slug>
```

This returns a JSON object with a `competing_prs` array. If the array is non-empty, **stop and alert the user**:

```
---------------------------------------------------
COMPETING PR DETECTED
---------------------------------------------------
Task: <task title>

Another PR already implements this task:
  PR #<number>: <title>
  Branch: <branch>
  Author: <author>
  URL: <url>
  Files changed: <file list>

Options:
  1. Proceed anyway — create a second PR (reviewer decides which to merge)
  2. Abort — discard this implementation
  3. Reconcile — compare both implementations side by side

Choose [1/2/3]:
```

If the user chooses **1 (Proceed)**, continue to Step 7 normally. The PR description should note that a competing implementation exists.

If the user chooses **2 (Abort)**, stop the ship process. Do not create a PR.

If the user chooses **3 (Reconcile)**, show the diff stats from the reconcile output for both the current branch and the competing PR, then ask the user which implementation to keep or how to combine them.

### Step 7: Create or Update Pull Request

#### Step 7a: Write PR body to temp file

Derive a slug for the temp file to avoid collisions with concurrent agents:
- **If claimed tasks exist**: slugify the first task title (lowercase, replace non-alphanumeric with hyphens, truncate to 60 chars)
- **If no claimed tasks**: use the worktree branch name as the slug

Use the **Write tool** (not Bash) to write the PR body to `/tmp/pr-body-<slug>.md`. This avoids backtick security prompts that occur when markdown content with inline code is passed through bash heredoc or command substitution.

**If claimed tasks were found in Step 1a**, include a "Task" section:

```markdown
## Task
- **<task title from claim>** (from task backlog)

## Summary
<bullet points of changes>

## Test plan
- [ ] <testing checklist>

Generated with [Claude Code](https://claude.ai/claude-code)
```

**Without claimed tasks (ad-hoc work):**

```markdown
## Summary
<bullet points of changes>

## Test plan
- [ ] <testing checklist>

Generated with [Claude Code](https://claude.ai/claude-code)
```

**If conflicts were resolved during rebase**, add a "Conflict Resolution" section:

```markdown
## Conflict Resolution
- Rebased onto main (N commits behind)
- Resolved conflicts in: <list of files>
- <brief description of resolution strategy per file>
- Post-rebase verification: tests passing
```

#### Step 7a.1: Embed Technical Reviews in PR Body

If claimed tasks were found in Step 1a, check for technical review files and embed them in the PR body as collapsible sections. This preserves the audit trail after reviews are cleaned up.

For each claimed task:

1. Derive the slug from the task title
2. Resolve the main repo: `MAIN_REPO=$(./bin/worktree-info main-repo)`
3. Check if `${MAIN_REPO}/.claude/reviews/<slug>.md` exists
4. If found, read the content, strip the YAML frontmatter (everything between the opening and closing `---` lines), and append a collapsible `<details>` block before the footer line in the PR body:

```markdown
<details>
<summary>Technical Review: <task title></summary>

<review markdown content, frontmatter stripped>

</details>
```

If no review file exists for a task, skip silently — reviews are optional.

#### Step 7b: Create or update PR from body file

```bash
./bin/pr create --title "<title>" --body-file /tmp/pr-body-<slug>.md
```

**IMPORTANT:** Always use `./bin/pr` for PR operations — never call `gh pr` directly. The `./bin/pr` wrapper is pre-approved in permissions, so it will never trigger approval prompts. Direct `gh` calls with heredocs, env vars, or command substitutions will require manual approval each time.

The `create` command automatically detects whether a PR already exists for the branch. If one exists, it updates the title and body; if not, it creates a new PR.

### Step 8: Merge the PR

**With `mergeQueue: true`**: enable auto-merge and return immediately. Do NOT wait for CI checks — the queue handles that. Do NOT use `--delete-branch` — it is incompatible with merge queue.

```bash
# Enable auto-merge — PR enters the merge queue once CI passes
./bin/pr merge --auto
```

The `--auto` flag is preferred over a direct `gh pr merge` (without `--auto`) because it is resilient to timing: if CI hasn't finished yet, auto-merge queues the PR to merge as soon as checks pass.

**With `mergeQueue: false`** (default): wait for CI checks to complete, then merge.

Docs-only:
```bash
./bin/pr merge --admin
```

Code:
```bash
# Watch CI checks
./bin/pr checks

# Merge using configured method (default: squash)
./bin/pr merge
```

If checks are failing, ask user whether to:
- Wait for checks to complete
- Merge anyway (with `--admin`)
- Abort and fix issues

### Step 9: Sync Local Repository

**With `mergeQueue: true`**: Skip this step entirely. The PR hasn't merged yet — it's queued for auto-merge.

**With `mergeQueue: false`** (default): Navigate to the local path and pull changes:

```bash
# Sync the local (non-worktree) repository
cd "<localPath>" && git fetch origin && git pull origin main
```

Verify the sync succeeded:

```bash
cd "<localPath>" && git log -1 --oneline
```

### Step 10: Release Work Queue Claims

**With `mergeQueue: true`**: Mark claims as shipped instead of releasing.

```bash
# Transition claims to shipped state
./bin/pr mark-shipped
```

If `mark-shipped` fails, fall back to `./bin/pr release-claims` to avoid orphaned claims.

**With `mergeQueue: false`** (default): Release claims immediately:

```bash
# Release all claims held by this worktree
./bin/pr release-claims
```

This frees the tasks for other agents. If the script is not found or the queue directory doesn't exist, skip silently — the work queue is optional.

### Step 10a: Clean Up Review Artifacts

If claimed tasks were found in Step 1a, clean up their review files and reviewed markers. Reviews are ephemeral — the audit trail now lives in the PR body (embedded in Step 7a.1).

For each claimed task slug:

```bash
./bin/pr clean-review "<slug>"
```

Skip this step for ad-hoc (non-claimed) work. If the script or review files don't exist, skip silently.

### Step 11: Cleanup (Optional)

Offer to remove worktree after successful merge (not with mergeQueue).

```bash
# Prune deleted remote branches
git fetch --prune
```

## Output Format

```
===================================================
              SHIPPING CHANGES
===================================================

Branch: <branch> -> main

---------------------------------------------------
TASK
---------------------------------------------------
-> <task title>
  (claimed from task backlog)
  # or, if multiple tasks:
-> Task 1 title
-> Task 2 title
  (2 tasks claimed from task backlog)
  # or, if no claimed task:
-> (no claimed task -- ad-hoc work)
  <description inferred from diff>

---------------------------------------------------
CI PARITY
---------------------------------------------------
  ruff format clean                     # or: Skipped (docs-only)
  ruff check clean                      # or: Skipped (docs-only)
  mypy clean                            # or: Skipped (docs-only)

---------------------------------------------------
COMMIT
---------------------------------------------------
  Staged N files
  Docs-only detected -- CI will fast-pass  # only if docs-only
  Committed: "<message>"

---------------------------------------------------
REBASE
---------------------------------------------------
  Main is up to date -- no rebase needed
  # or:
  Rebased onto main (N commits behind)
  No conflicts
  # or:
  Rebased onto main (N commits behind)
  Resolved conflicts in M file(s):
    src/package/models.py -- combined field additions
  Post-rebase CI parity passed
  Post-rebase tests passed
  # or (escalation):
  Rebase aborted -- N conflicted files
    -> Ask user for guidance

---------------------------------------------------
PUSH
---------------------------------------------------
  Pushed to origin/<branch> (force-with-lease)

---------------------------------------------------
PULL REQUEST
---------------------------------------------------
  Created PR #N: <title>
  <url>

---------------------------------------------------
MERGE
---------------------------------------------------
  CI checks passed                       # or: CI fast-passed (docs-only)
  Squash merged into main                # mergeQueue=false
  Branch deleted
  # or (mergeQueue=true):
  Added to merge queue
  Claims marked as shipped

---------------------------------------------------
SYNC LOCAL
---------------------------------------------------
  Fetched latest from origin             # mergeQueue=false
  Pulled into /path/to/project
  Local repo now at: abc1234 <message>
  # or (mergeQueue=true):
  Skipped (merge queue mode)

===================================================
        SHIPPED! / QUEUED FOR MERGE!
===================================================
Task: <task title>
  # or, if multiple:
Tasks: N completed
  - Task 1
  - Task 2
  # or, if ad-hoc:
Shipped: <description>
```

## Error Handling

| Error | Resolution |
|-------|------------|
| No changes to commit | Exit early with message |
| Rebase: clean (no conflicts) | Proceed normally |
| Rebase: predictable file conflicts | Auto-resolve using strategy table, then `--continue` |
| Rebase: code conflicts (intent clear) | Analyze both sides, resolve, verify with tests |
| Rebase: code conflicts (intent unclear) | Abort rebase, escalate to user |
| Rebase: >5 conflicted files | Abort rebase, escalate to user |
| Rebase: security-sensitive conflicts | Abort rebase, escalate to user |
| Post-rebase tests fail from resolution | Fix resolution and amend |
| Post-rebase tests fail from main | Note in PR, proceed |
| Push rejected (force-with-lease) | Investigate — shouldn't happen for worktree branches |
| Competing PR detected | Alert user, offer proceed/abort/reconcile |
| PR creation fails | Show error, offer to open manually |
| CI checks failing | Ask user: wait, merge anyway, or abort |
| Merge conflicts at PR merge | Re-fetch and re-rebase (shouldn't happen if Step 5 succeeded) |
| Local path invalid | Prompt user to configure `.claude/ship.json` |
| Local pull fails | Show error, suggest manual intervention |
| `mark-shipped` fails | Log warning, fall back to `release-claims` |
| Merge queue unavailable (plan limitation) | Fall back to `--auto` merge |
| Merge queue rejects PR (conflicts) | Offer to re-rebase and retry |

## Worktree Safety

This skill is designed for git worktree workflows. Key safety considerations:

- **Never use `git stash`** — stashes are shared across all worktrees and can be lost if popped in the wrong one
- **`--force-with-lease` is safe for worktree branches** — worktree branches are single-owner; no one else pushes to them. This flag still protects against unexpected state by verifying the remote ref matches what you expect.
- **Never force-push to main** — the rebase and force-push only apply to the worktree's feature branch
- **Branch deletion is remote-only** — the `--delete-branch` flag on merge only deletes the remote branch; the local worktree branch remains intact until the worktree itself is removed
- **Local sync is isolated** — syncing the main repo (`cd "<localPath>" && git pull`) does not affect this worktree's state
- **Worktree cleanup** — after shipping, the worktree can be removed with `git worktree remove <path>` from the main repo

## Notes

- This skill assumes you're working in a git worktree
- The PR is squash-merged by default to keep history clean
- The worktree branch is deleted on remote after merge
- If `gh` CLI is not authenticated, the skill will prompt for setup
- Rebase uses `--force-with-lease` (not `--force`) for safety
- Post-rebase verification catches issues before they reach CI
