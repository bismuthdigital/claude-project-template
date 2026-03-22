---
name: ship
description: >
  Commits changes, creates a PR, merges it, and syncs the local repo.
  Complete workflow from worktree changes to running code in one command.
argument-hint: "[commit message or empty for auto-generated]"
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(git *), Bash(gh *), Bash(cd * && git *), Bash(*/work-queue.sh *), Bash(./bin/pr *), Bash(./bin/worktree-info *), Bash(source *), Bash(ruff *), Bash(mypy *), Bash(pytest *), Skill
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

Reads from `.claude/ship.json`:

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
| `localPath` | Path to local repo | Auto-detect from worktree |
| `defaultBase` | Base branch for PRs | `main` |
| `mergeMethod` | `squash`, `merge`, `rebase` | `squash` |
| `mergeQueue` | Use GitHub merge queue | `false` |

## Process

### Step 1: Pre-flight Checks

```bash
./bin/worktree-info is-worktree
git status --porcelain
```

If no changes, exit. **Never use `git stash`** — stashes are shared across worktrees.

### Step 1a: Detect Claimed Tasks

```bash
scripts/work-queue.sh claimed-by-me
```

Extract `task_title` from each claim. If empty, analyze diff to infer task description.

### Step 2: Determine Local Path

```bash
cat .claude/ship.json 2>/dev/null
./bin/worktree-info main-repo
```

### Step 3: Detect Docs-Only Changes

```bash
git add -A
# Unstage rendered task files — CI auto-commits these after merge
git reset HEAD -- NEXT-STEPS.md NEXT-STEPS-COMPLETED.md .tasks.json 2>/dev/null || true
git diff --cached --name-only
```

Docs-only if every file matches: `*.md`, `*.txt` (not requirements), `*.toml` (not pyproject), `docs/**`, `.claude/**`, `LICENSE*`, `.gitignore`, `.github/CODEOWNERS`.

### Step 3a: CI Parity Checks (code changes only)

**Skip for docs-only commits.**

```bash
source .venv/bin/activate 2>/dev/null || true
ruff check --fix .
ruff format .
ruff format --check .
ruff check .
mypy src/
```

### Step 4: Commit Changes

Generate or use provided commit message.

**Docs-only**: append `[skip ci]` to first line.

```bash
git commit -m "$(cat <<'EOF'
<message> [skip ci]

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Step 5: Rebase onto Latest Main

```bash
git fetch origin main
git rev-list --count HEAD..origin/main
```

If count > 0:
```bash
git rebase origin/main
```

#### Conflict Resolution Strategy

| File Pattern | Strategy |
|-------------|----------|
| `next-steps/**/*.md` | Read both sides, combine |
| `NEXT-STEPS.md` | Skip (generated file) |
| `pyproject.toml` (version only) | Take main's |
| `pyproject.toml` (other) | Analyze and combine |
| `*.py` (source) | Analyze intent, combine |
| `tests/**/*.py` | Analyze intent, watch fixtures |
| `reports/**` | Keep both (append-only) |

**During rebase**: `<<<<<<< HEAD` = main, `>>>>>>> <commit>` = your changes.

**Abort and escalate** if: >5 conflicted files, security-sensitive code, or unclear intent.

#### Post-Rebase Verification (code changes only)

Re-run CI parity checks after conflict resolution:
```bash
ruff check --fix . && ruff format .
mypy src/
pytest --tb=short -q
```

### Step 6: Push to Remote

```bash
git push --force-with-lease -u origin HEAD
```

### Step 6a: Detect Competing PRs

For each claimed task:
```bash
scripts/work-queue.sh reconcile <task-slug>
```

If competing PRs found, alert user with options: proceed / abort / reconcile.

### Step 7: Create or Update Pull Request

#### Step 7a: Write PR body to temp file

Use the **Write tool** to write PR body to `/tmp/pr-body-<slug>.md`.

Include: Task section (if claimed), Summary, Test plan, Conflict Resolution (if any).

#### Step 7a.1: Embed Technical Reviews

For each claimed task, check `${MAIN_REPO}/.claude/reviews/<slug>.md`. If found, strip YAML frontmatter and append as collapsible `<details>` block.

#### Step 7b: Create/update PR

```bash
./bin/pr create --title "<title>" --body-file /tmp/pr-body-<slug>.md
```

**Always use `./bin/pr`** — never `gh pr` directly.

### Step 8: Merge the PR

**With `mergeQueue: true`**:
```bash
./bin/pr merge --auto
```
Do NOT wait for CI. Do NOT use `--delete-branch`.

**With `mergeQueue: false`** (default):

Docs-only:
```bash
./bin/pr merge --admin
```

Code:
```bash
./bin/pr checks
./bin/pr merge
```

### Step 9: Sync Local Repository

**With `mergeQueue: true`**: Skip (PR hasn't merged yet).

**With `mergeQueue: false`**:
```bash
cd "<localPath>" && git fetch origin && git pull origin main
```

### Step 10: Release Work Queue Claims

**With `mergeQueue: true`**:
```bash
./bin/pr mark-shipped
```

**With `mergeQueue: false`**:
```bash
./bin/pr release-claims
```

### Step 10a: Clean Up Review Artifacts

```bash
./bin/pr clean-review "<slug>"
```

### Step 11: Cleanup (Optional)

Offer to remove worktree after successful merge (not with mergeQueue).

## Output Format

```
═══════════════════════════════════════════════════
              SHIPPING CHANGES
═══════════════════════════════════════════════════

Branch: <branch> → main

───────────────────────────────────────────────────
TASK
───────────────────────────────────────────────────
→ <task title> (from task backlog)

───────────────────────────────────────────────────
CI PARITY
───────────────────────────────────────────────────
✓ ruff format clean
✓ ruff check clean
✓ mypy clean

───────────────────────────────────────────────────
COMMIT
───────────────────────────────────────────────────
✓ Staged N files
✓ Committed: "<message>"

───────────────────────────────────────────────────
REBASE
───────────────────────────────────────────────────
✓ Rebased onto main (N commits behind)
✓ No conflicts

───────────────────────────────────────────────────
PUSH
───────────────────────────────────────────────────
✓ Pushed to origin/<branch> (force-with-lease)

───────────────────────────────────────────────────
PULL REQUEST
───────────────────────────────────────────────────
✓ Created PR #N: <title>
  <url>

───────────────────────────────────────────────────
MERGE
───────────────────────────────────────────────────
✓ Squash merged into main

───────────────────────────────────────────────────
SYNC LOCAL
───────────────────────────────────────────────────
✓ Pulled into <localPath>

═══════════════════════════════════════════════════
        SHIPPED!
═══════════════════════════════════════════════════
```

## Error Handling

| Error | Resolution |
|-------|------------|
| No changes | Exit early |
| Rebase conflicts (≤5 files) | Auto-resolve using strategy table |
| Rebase conflicts (>5 files) | Abort, escalate |
| Security-sensitive conflicts | Abort, escalate |
| Competing PR detected | Alert user |
| CI checks failing | Ask: wait, merge anyway, abort |
| `mark-shipped` fails | Fall back to `release-claims` |

## Worktree Safety

- Never use `git stash` — stashes shared across worktrees
- `--force-with-lease` is safe for single-owner worktree branches
- Never force-push to main
- Local sync is isolated from worktree state
