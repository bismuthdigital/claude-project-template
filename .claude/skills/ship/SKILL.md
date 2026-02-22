---
name: ship
version: 1.2.0
description: >
  Commits changes, creates a PR, merges it, and syncs the local repo.
  Complete workflow from worktree changes to running code in one command.
argument-hint: "[commit message or empty for auto-generated]"
allowed-tools: Read, Glob, Grep, Edit, Bash(git *), Bash(gh *), Bash(cd * && git *), Bash(*/work-queue.sh *), Bash(source *), Bash(ruff *), Bash(mypy *), Skill
---

# Ship Changes to Main

Complete workflow to ship changes from a worktree to the main branch and sync the local repository.

## What This Skill Does

1. **Commit** - Stage and commit all changes with a descriptive message
2. **Version** - Bump the semantic version by invoking the `/version` skill
3. **Push** - Push the branch to GitHub
4. **Create PR** - Open a pull request with summary and test plan
5. **Merge** - Squash merge the PR into main
6. **Sync Local** - Fetch and pull changes in the local (non-worktree) directory

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

### Step 6: Push to Remote

```bash
# Push branch, setting upstream if needed
git push -u origin HEAD
```

If a version tag was created in Step 5, also push the tag:

```bash
# Push the version tag
git push origin <tag>
```

### Step 7: Create Pull Request

```bash
# Check if PR already exists for this branch
gh pr view --json number 2>/dev/null
```

If no PR exists, create one:

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
<bullet points of changes>

## Test plan
- [ ] <testing checklist>

🤖 Generated with [Claude Code](https://claude.ai/claude-code)
EOF
)"
```

If PR already exists, update it if there are new commits.

### Step 8: Merge the PR

**For docs-only commits** (commit message contains `[skip ci]`): merge immediately with `--admin` since no CI checks will run.

```bash
gh pr merge --squash --delete-branch --admin
```

**For code commits**: wait for CI checks to complete, then merge.

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

### Step 9: Sync Local Repository

Navigate to the local path and pull changes:

```bash
# Sync the local (non-worktree) repository
cd "<localPath>" && git fetch origin && git pull origin main
```

Verify the sync succeeded:

```bash
cd "<localPath>" && git log -1 --oneline
```

### Step 10: Release Work Queue Claims

If the work queue has claims for this worktree, release them after shipping:

```bash
# Release all claims held by this worktree
scripts/work-queue.sh release-all
```

This frees the tasks for other agents. If the script is not found or the queue directory doesn't exist, skip silently — the work queue is optional.

### Step 11: Cleanup

If the worktree branch was deleted remotely, clean up locally:

```bash
# Prune deleted remote branches
git fetch --prune
```

Since worktrees are automatically created by `/claim-tasks`, offer to remove the worktree after a successful merge:

> "Changes merged to main. Remove this worktree? The session will end. [Y/n]"

If the user accepts (or presses Enter), remove the worktree. If the user declines, the worktree remains for further work.

## Output Format

```
═══════════════════════════════════════════════════
              SHIPPING CHANGES
═══════════════════════════════════════════════════

Branch: inspiring-antonelli → main

───────────────────────────────────────────────────
CI PARITY
───────────────────────────────────────────────────
✓ ruff format clean                    # or: ⊘ Skipped (docs-only)
✓ ruff check clean                     # or: ⊘ Skipped (docs-only)
✓ mypy clean                           # or: ⊘ Skipped (docs-only)

───────────────────────────────────────────────────
COMMIT
───────────────────────────────────────────────────
✓ Staged 5 files
✓ Docs-only detected — added [skip ci]  # only if docs-only
✓ Committed: "Add /ship skill for streamlined deployment"

───────────────────────────────────────────────────
VERSION
───────────────────────────────────────────────────
✓ Analyzed commits → MINOR increment
✓ Bumped version: 0.1.0 → 0.2.0
✓ Updated pyproject.toml
✓ Updated src/your_package/__init__.py
✓ Committed: "Bump version to 0.2.0"
✓ Created tag: v0.2.0

───────────────────────────────────────────────────
PUSH
───────────────────────────────────────────────────
✓ Pushed to origin/inspiring-antonelli
✓ Pushed tag v0.2.0

───────────────────────────────────────────────────
PULL REQUEST
───────────────────────────────────────────────────
✓ Created PR #42: Add /ship skill for streamlined deployment
  https://github.com/user/repo/pull/42

───────────────────────────────────────────────────
MERGE
───────────────────────────────────────────────────
✓ CI checks passed                      # or: ⊘ CI skipped (docs-only)
✓ Squash merged into main               # uses --admin when docs-only
✓ Branch deleted

───────────────────────────────────────────────────
SYNC LOCAL
───────────────────────────────────────────────────
✓ Fetched latest from origin
✓ Pulled into /Users/jwilkin/code/claude/project
✓ Local repo now at: abc1234 Add /ship skill...

═══════════════════════════════════════════════════
                  SHIPPED!
═══════════════════════════════════════════════════
```

## Error Handling

| Error | Resolution |
|-------|------------|
| No changes to commit | Exit early with message |
| Version bump fails | Show error, ask user whether to continue shipping without a version bump |
| Push rejected | Pull and retry, or ask user |
| PR creation fails | Show error, offer to open manually |
| CI checks failing | Ask user: wait, merge anyway, or abort |
| Merge conflicts | Abort and instruct user to resolve |
| Local path invalid | Prompt user to configure `.claude/ship.json` |
| Local pull fails | Show error, suggest manual intervention |

## Worktree Safety

This skill is designed for git worktree workflows. Key safety considerations:

- **Never use `git stash`** — stashes are shared across all worktrees and can be lost if popped in the wrong one
- **Branch deletion is remote-only** — the `--delete-branch` flag on merge only deletes the remote branch; the local worktree branch remains intact until the worktree itself is removed
- **Local sync is isolated** — syncing the main repo (`cd "<localPath>" && git pull`) does not affect this worktree's state
- **Worktree cleanup** — after shipping, the worktree can be removed with `git worktree remove <path>` from the main repo

## Notes

- This skill is designed for the `/claim-tasks` → develop → `/ship` workflow
- Worktrees are automatically created by `/claim-tasks`; this skill ships from them
- The PR is squash-merged by default to keep history clean
- The worktree branch is deleted on remote after merge
- Local sync only pulls; it won't auto-resolve conflicts
- If `gh` CLI is not authenticated, the skill will prompt for setup
