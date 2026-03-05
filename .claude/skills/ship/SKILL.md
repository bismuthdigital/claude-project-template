---
name: ship
description: >
  Commits changes, creates a PR, merges it, and syncs the local repo.
  Complete workflow from worktree changes to running code in one command.
argument-hint: "[commit message or empty for auto-generated]"
allowed-tools: Read, Glob, Grep, Edit, Bash(git *), Bash(gh *), Bash(cd * && git *), Bash(*/work-queue.sh *), Bash(*/task-format.py *), Bash(source *), Bash(ruff *), Bash(mypy *), Bash(pytest *), Skill
---

# Ship Changes to Main

Complete workflow to ship changes from a worktree to the main branch and sync the local repository.

## What This Skill Does

1. **Detect** - Find claimed tasks and build context
2. **Commit** - Stage and commit all changes with a descriptive message
3. **Version** - Bump the semantic version by invoking the `/version` skill
4. **Rebase** - Rebase onto latest main, resolving conflicts intelligently
5. **Push** - Push the branch to GitHub
6. **Create PR** - Open a pull request with summary, test plan, and technical reviews
7. **Merge** - Squash merge the PR into main (or enable auto-merge for merge queues)
8. **Sync Local** - Fetch and pull changes in the local (non-worktree) directory

## Configuration

This skill reads from `.claude/ship.json` for project-specific settings:

```json
{
  "localPath": "/path/to/your/repo",
  "defaultBase": "main",
  "mergeMethod": "squash",
  "mergeQueue": false
}
```

| Setting | Description | Default |
|---------|-------------|---------|
| `localPath` | Path to local repo (where code runs) | Auto-detect from worktree |
| `defaultBase` | Base branch for PRs | `main` |
| `mergeMethod` | PR merge method: `squash`, `merge`, `rebase` | `squash` |
| `mergeQueue` | If `true`, use `gh pr merge --auto` instead of waiting for checks | `false` |

If `localPath` is not configured, the skill auto-detects it from `git worktree list` (uses the main worktree path).

## Process

### Step 1: Pre-flight Checks

Before starting, verify:

```bash
# Check we're in a worktree (not the main repo)
git rev-parse --git-dir
```

If the `--git-dir` output contains `/worktrees/`, you are in a worktree — this is the normal case when using `/claim-tasks` followed by `/ship`. If it ends with just `.git`, you're in the main repository — ask the user:
> "You're in the main repository, not a worktree. This typically means changes weren't made through /claim-tasks. Would you like to commit directly to main instead?"

```bash
# Check for uncommitted changes
git status --porcelain
```

If no changes exist, inform the user and exit.

**Worktree safety:** If the user has uncommitted changes they want to set aside temporarily, never suggest `git stash` — stashes are shared across all worktrees and can be accidentally popped in the wrong worktree. Recommend committing as a WIP commit instead.

### Step 1a: Detect Claimed Tasks

Check if the work queue has claims for this worktree:

```bash
scripts/work-queue.sh claimed-by-me
```

If claims exist, use them to:
- Build context for the commit message and PR description
- Determine which task checkboxes to mark as complete
- Include task metadata in the PR body

### Step 2: Determine Local Path

Read configuration and determine the local sync path:

```bash
# Try to read config
cat .claude/ship.json 2>/dev/null
```

If `localPath` is not configured, auto-detect:

```bash
# Get main worktree path (first line is always the main repo)
git worktree list --porcelain | grep -m1 "^worktree " | cut -d' ' -f2
```

Verify the path exists and is a git repository before proceeding.

### Step 3: Detect Docs-Only Changes

Before running CI checks, determine whether the changeset is docs-only. Stage the files first so we can inspect what will be committed:

```bash
git add -A
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

**Unstage generated files**: If per-task file mode is active, unstage rendered files that shouldn't be committed:

```bash
git reset HEAD NEXT-STEPS.md NEXT-STEPS-COMPLETED.md .tasks.json 2>/dev/null || true
```

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

**For docs-only commits**, append `[skip ci]` to the commit message (on the first line, after the message text). This tells GitHub Actions to skip all workflows for this push, saving CI minutes on changes that cannot break the build.

```bash
# Docs-only commit (with [skip ci])
git commit -m "$(cat <<'EOF'
<commit message here> [skip ci]

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

# Code commit (without [skip ci])
git commit -m "$(cat <<'EOF'
<commit message here>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Step 5: Bump Version

After committing changes, invoke the `/version` skill to bump the semantic version. The version skill will:
1. Analyze the commits since the last tag to determine the increment level (major/minor/patch)
2. Update version files (`pyproject.toml` and `src/your_package/__init__.py`)
3. Commit the version bump
4. Create an annotated git tag

Invoke the skill:

```
/version
```

The version skill will ask the user for confirmation before applying the bump. If the user declines, continue with the ship process without a version bump.

**Important:** Do NOT let the version skill push the tag or commit — the ship skill handles all pushing in the next step. When the version skill asks whether to push the tag, decline and proceed to Step 6.

### Step 6: Rebase onto Latest Main

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

If the count is 0, main hasn't moved — **skip the rebase** and proceed to Step 7.

If main has moved, rebase:

```bash
git rebase origin/main
```

#### 6a: Clean Rebase (no conflicts)

If the rebase succeeds cleanly, proceed to Step 7.

#### 6b: Conflict Resolution

If the rebase stops with conflicts, `git status` will show unmerged paths. For **each** conflicted file, apply the appropriate strategy:

**Read the conflicted file** to see the conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`). Understand what your branch changed versus what main changed.

**IMPORTANT:** During a `git rebase`, the sides are swapped from what you might expect:
- `<<<<<<< HEAD` = the **main branch** (the base you're rebasing onto)
- `>>>>>>> <commit>` = **your changes** (the commits being replayed)

##### Strategy by File Type

| File Pattern | Strategy | Details |
|-------------|----------|---------|
| `NEXT-STEPS.md` | **Skip** | This is a generated file in per-task mode. If monolithic, union merge checkbox states. |
| `pyproject.toml` (version only) | **Take higher** | If the conflict is only in the `version = "..."` line, take whichever version is higher. |
| `pyproject.toml` (other fields) | **Analyze** | Read both sides, understand what each changed, combine. Usually one side added a dependency and the other changed something else — both changes apply. |
| `*.py` (source code) | **Analyze intent** | See "Code Conflict Resolution" below. |
| `tests/**/*.py` | **Analyze intent** | Same as code. Be especially careful about fixture changes that both sides depend on. |

##### Code Conflict Resolution

For Python source files and other code, you have a significant advantage: you understand the intent of your changes because you just wrote them. Use this to resolve intelligently:

1. **Read the full conflicted file** — understand the surrounding context, not just the conflict markers.
2. **Identify what main changed** — was it a refactor, bug fix, new feature, or formatting change?
3. **Identify what your branch changed** — you already know this from the work you just did.
4. **Determine compatibility:**
   - **Disjoint changes**: Both sides changed different things in the same region (e.g., main fixed a typo on line 45, you added a parameter on line 47). Keep both changes.
   - **Overlapping changes**: Both sides modified the same logic. Understand the intent of each and write a version that satisfies both. This is where your understanding of the code matters most.
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

If the rebase has multiple conflicting commits, you may need to resolve conflicts and `--continue` multiple times. Each time, apply the same strategies above.

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

#### 6c: Post-Rebase Verification (code changes only)

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

# Run tests
pytest --tb=short -q
```

If any linting or formatting was auto-fixed, stage and amend:
```bash
git add -A
git commit --amend --no-edit
```

If tests fail after conflict resolution:
1. **Analyze the failure** — is it caused by the merge resolution or a pre-existing issue on main?
2. **Fix the resolution** if it's your merge that broke things. Stage and amend:
   ```bash
   git add <fixed-files>
   git commit --amend --no-edit
   ```
3. **If main itself has failing tests**, note this in the PR description and proceed.

### Step 7: Push to Remote

```bash
# force-with-lease is always safe for worktree branches (single-owner)
git push --force-with-lease -u origin HEAD
```

Use `--force-with-lease` unconditionally. When a rebase occurred, it's required (rebase rewrites commit hashes). When no rebase occurred, it's harmless and equivalent to a regular push. This is safe because worktree branches are owned by a single agent; no one else pushes to them.

If a version tag was created in Step 5, also push the tag:

```bash
# Push the version tag
git push origin <tag>
```

### Step 7a: Generate Technical Reviews (if claimed tasks exist)

If tasks were detected in Step 1a, check for and embed technical review artifacts:

```bash
scripts/work-queue.sh is-reviewed
```

If reviews exist in `.claude/reviews/`, read each review file and embed them in the PR body (Step 8). Reviews provide context for PR reviewers about what was checked and any concerns.

```bash
scripts/work-queue.sh list-reviewed
```

### Step 8: Create Pull Request

```bash
# Check if PR already exists for this branch
gh pr view --json number 2>/dev/null
```

If no PR exists, create one:

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
<bullet points of changes>

## Tasks Completed
- [x] Task 1 title
- [x] Task 2 title

## Test plan
- [ ] <testing checklist>

## Technical Review
<embedded review content, if available>

Generated with [Claude Code](https://claude.ai/claude-code)
EOF
)"
```

**If conflicts were resolved during rebase**, add a "Conflict Resolution" section to the PR body:

```markdown
## Conflict Resolution
- Rebased onto main (N commits behind)
- Resolved conflicts in: <list of files>
- <brief description of resolution strategy per file>
- Post-rebase verification: tests passing
```

If PR already exists, update it if there are new commits.

### Step 9: Merge the PR

Read merge strategy from `.claude/ship.json`:

**If `mergeQueue` is `true`**: Enable auto-merge and exit. The merge queue handles the rest:

```bash
gh pr merge --squash --delete-branch --auto
```

**For docs-only commits** (commit message contains `[skip ci]`): merge immediately with `--admin` since no CI checks will run.

```bash
gh pr merge --squash --delete-branch --admin
```

**For code commits (no merge queue)**: wait for CI checks to complete, then merge.

```bash
# Check PR status
gh pr checks --watch --fail-fast

# Merge using configured method (default: squash)
gh pr merge --squash --delete-branch
```

If checks are failing, ask user whether to:
- Wait for checks to complete
- Merge anyway (with `--admin`)
- Abort and fix issues

### Step 10: Mark Claims as Shipped / Release

If the work queue has claims for this worktree:

**If `mergeQueue` is `true`** (PR enters merge queue, not immediately merged):

```bash
# Mark claims as shipped — exempt from TTL, released when PR merges
scripts/work-queue.sh mark-shipped "<pr_number>" "<pr_url>"
```

**If `mergeQueue` is `false`** (PR merged directly):

```bash
# Release all claims held by this worktree
scripts/work-queue.sh release-all
```

This frees the tasks for other agents. If the script is not found or the queue directory doesn't exist, skip silently — the work queue is optional.

### Step 10a: Clean Review Artifacts

If technical reviews were embedded in the PR body, clean up the local review files:

```bash
scripts/work-queue.sh clean-review
```

### Step 11: Sync Local Repository

**Skip if `mergeQueue` is `true`** — the PR hasn't merged yet, so there's nothing to sync.

Navigate to the local path and pull changes:

```bash
# Sync the local (non-worktree) repository
cd "<localPath>" && git fetch origin && git pull origin main
```

Verify the sync succeeded:

```bash
cd "<localPath>" && git log -1 --oneline
```

### Step 12: Cleanup

If the worktree branch was deleted remotely, clean up locally:

```bash
# Prune deleted remote branches
git fetch --prune
```

Since worktrees are automatically created by `/claim-tasks`, offer to remove the worktree after a successful merge:

> "Changes merged to main. Remove this worktree? The session will end. [Y/n]"

If the user accepts (or presses Enter), remove the worktree. If the user declines, the worktree remains for further work.

**If `mergeQueue` is `true`**: Do NOT offer worktree removal. The PR is queued but not merged yet. Instead:

> "PR queued for merge. Claims marked as shipped. This worktree can be removed after the PR merges."

## Output Format

```
═══════════════════════════════════════════════════
              SHIPPING CHANGES
═══════════════════════════════════════════════════

Branch: inspiring-antonelli → main

───────────────────────────────────────────────────
CI PARITY
───────────────────────────────────────────────────
OK  ruff format clean                    # or: SKIP (docs-only)
OK  ruff check clean                     # or: SKIP (docs-only)
OK  mypy clean                           # or: SKIP (docs-only)

───────────────────────────────────────────────────
COMMIT
───────────────────────────────────────────────────
OK  Staged 5 files
OK  Docs-only detected — added [skip ci]  # only if docs-only
OK  Committed: "Add /ship skill for streamlined deployment"

───────────────────────────────────────────────────
VERSION
───────────────────────────────────────────────────
OK  Analyzed commits → MINOR increment
OK  Bumped version: 0.1.0 → 0.2.0
OK  Updated pyproject.toml
OK  Updated src/your_package/__init__.py
OK  Committed: "Bump version to 0.2.0"
OK  Created tag: v0.2.0

───────────────────────────────────────────────────
REBASE
───────────────────────────────────────────────────
OK  Main is up to date — no rebase needed
  # or:
OK  Rebased onto main (3 commits behind)
OK  No conflicts
  # or:
OK  Rebased onto main (7 commits behind)
!!  Resolved conflicts in 2 files:
    - pyproject.toml — took higher version
    - src/your_package/models.py — combined field additions
OK  Post-rebase CI parity passed
OK  Post-rebase tests passed
  # or (escalation):
FAIL  Rebase aborted — 8 conflicted files
      → Ask user for guidance

───────────────────────────────────────────────────
PUSH
───────────────────────────────────────────────────
OK  Pushed to origin/inspiring-antonelli (force-with-lease)
OK  Pushed tag v0.2.0

───────────────────────────────────────────────────
PULL REQUEST
───────────────────────────────────────────────────
OK  Created PR #42: Add /ship skill for streamlined deployment
    https://github.com/user/repo/pull/42

───────────────────────────────────────────────────
MERGE
───────────────────────────────────────────────────
OK  CI checks passed                      # or: SKIP (docs-only)
OK  Squash merged into main               # uses --admin when docs-only
OK  Branch deleted                        # or: Queued for merge (auto-merge)

───────────────────────────────────────────────────
CLAIMS
───────────────────────────────────────────────────
OK  Released 3 task claims                # or: Marked 3 claims as shipped
OK  Review artifacts cleaned

───────────────────────────────────────────────────
SYNC LOCAL
───────────────────────────────────────────────────
OK  Fetched latest from origin            # or: SKIP (merge queue)
OK  Pulled into <localPath>
OK  Local repo now at: abc1234 Add /ship skill...

═══════════════════════════════════════════════════
                  SHIPPED!
═══════════════════════════════════════════════════
```

## Error Handling

| Error | Resolution |
|-------|------------|
| No changes to commit | Exit early with message |
| Version bump fails | Show error, ask user whether to continue shipping without a version bump |
| Rebase: clean (no conflicts) | Proceed normally |
| Rebase: predictable file conflicts | Auto-resolve using strategy table, then `--continue` |
| Rebase: code conflicts (intent clear) | Analyze both sides, resolve, verify with tests |
| Rebase: code conflicts (intent unclear) | Abort rebase, escalate to user |
| Rebase: >5 conflicted files | Abort rebase, escalate to user |
| Rebase: security-sensitive conflicts | Abort rebase, escalate to user |
| Post-rebase tests fail from resolution | Fix resolution and amend |
| Post-rebase tests fail from main | Note in PR, proceed |
| Push rejected (force-with-lease) | Investigate — shouldn't happen for worktree branches |
| PR creation fails | Show error, offer to open manually |
| CI checks failing | Ask user: wait, merge anyway, or abort |
| Merge conflicts at PR merge | Re-fetch and re-rebase (shouldn't happen if Step 6 succeeded) |
| Local path invalid | Prompt user to configure `.claude/ship.json` |
| Local pull fails | Show error, suggest manual intervention |

## Worktree Safety

This skill is designed for git worktree workflows where all agents work within worktrees off the same repository. Key safety considerations:

- **Never use `git stash`** — stashes are shared across all worktrees and can be lost if popped in the wrong one
- **`--force-with-lease` is safe for worktree branches** — worktree branches are single-owner; no one else pushes to them. This flag still protects against unexpected state by verifying the remote ref matches what you expect.
- **Never force-push to main** — the rebase and force-push only apply to the worktree's feature branch
- **Branch deletion is remote-only** — the `--delete-branch` flag on merge only deletes the remote branch; the local worktree branch remains intact until the worktree itself is removed
- **Local sync is isolated** — syncing the main repo (`cd "<localPath>" && git pull`) does not affect this worktree's state
- **Worktree cleanup** — after shipping, the worktree can be removed with `git worktree remove <path>` from the main repo

## Notes

- This skill is designed for the `/claim-tasks` → develop → `/ship` workflow
- Worktrees are automatically created by `/claim-tasks`; this skill ships from them
- The PR is squash-merged by default to keep history clean
- The worktree branch is deleted on remote after merge
- If `gh` CLI is not authenticated, the skill will prompt for setup
- Rebase uses `--force-with-lease` (not `--force`) for safety
- Post-rebase verification catches issues before they reach CI
- When `mergeQueue` is enabled, claims are marked shipped (not released) and local sync is deferred
