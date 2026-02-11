---
name: ship
description: >
  Commits changes, creates a PR, merges it, and syncs the local repo.
  Complete workflow from worktree changes to running code in one command.
argument-hint: "[commit message or empty for auto-generated]"
allowed-tools: Read, Glob, Grep, Bash(git *), Bash(gh *), Bash(cd * && git *)
---

# Ship Changes to Main

Complete workflow to ship changes from a worktree to the main branch and sync the local repository.

## What This Skill Does

1. **Commit** - Stage and commit all changes with a descriptive message
2. **Push** - Push the branch to GitHub
3. **Create PR** - Open a pull request with summary and test plan
4. **Merge** - Squash merge the PR into main
5. **Sync Local** - Fetch and pull changes in the local (non-worktree) directory

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

If the `--git-dir` output contains `/worktrees/`, you are in a worktree (expected). If it ends with just `.git`, you're in the main repository — warn the user:
> "You're already in the main repository. This skill is designed for worktree → main workflows. Continue anyway?"

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

### Step 3: Commit Changes

Generate or use provided commit message:

```bash
# Show what will be committed
git status
git diff --stat
```

If no commit message argument provided, generate one by:
1. Analyzing the diff to understand the changes
2. Writing a concise commit message (1-2 sentences)
3. Including Co-Authored-By line

```bash
# Stage and commit
git add -A
git commit -m "$(cat <<'EOF'
<commit message here>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Step 4: Push to Remote

```bash
# Push branch, setting upstream if needed
git push -u origin HEAD
```

### Step 5: Create Pull Request

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

### Step 6: Merge the PR

Wait briefly for any CI checks to start, then:

```bash
# Check PR status
gh pr checks

# Merge using configured method (default: squash)
gh pr merge --squash --delete-branch
```

If checks are failing, ask user whether to:
- Wait for checks to complete
- Merge anyway (if allowed)
- Abort and fix issues

### Step 7: Sync Local Repository

Navigate to the local path and pull changes:

```bash
# Sync the local (non-worktree) repository
cd "<localPath>" && git fetch origin && git pull origin main
```

Verify the sync succeeded:

```bash
cd "<localPath>" && git log -1 --oneline
```

### Step 8: Cleanup (Optional)

If the worktree branch was deleted remotely, offer to clean up locally:

```bash
# Prune deleted remote branches
git fetch --prune
```

## Output Format

```
═══════════════════════════════════════════════════
              SHIPPING CHANGES
═══════════════════════════════════════════════════

Branch: inspiring-antonelli → main

───────────────────────────────────────────────────
COMMIT
───────────────────────────────────────────────────
✓ Staged 5 files
✓ Committed: "Add /ship skill for streamlined deployment"

───────────────────────────────────────────────────
PUSH
───────────────────────────────────────────────────
✓ Pushed to origin/inspiring-antonelli

───────────────────────────────────────────────────
PULL REQUEST
───────────────────────────────────────────────────
✓ Created PR #42: Add /ship skill for streamlined deployment
  https://github.com/user/repo/pull/42

───────────────────────────────────────────────────
MERGE
───────────────────────────────────────────────────
✓ CI checks passed
✓ Squash merged into main
✓ Branch deleted

───────────────────────────────────────────────────
SYNC LOCAL
───────────────────────────────────────────────────
✓ Fetched latest from origin
✓ Pulled into /Users/jwilkin/code/claude/project
✓ Local repo now at: abc1234 Add /ship skill...

═══════════════════════════════════════════════════
                  SHIPPED! 🚀
═══════════════════════════════════════════════════
```

## Error Handling

| Error | Resolution |
|-------|------------|
| No changes to commit | Exit early with message |
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

- This skill assumes you're working in a git worktree
- The PR is squash-merged by default to keep history clean
- The worktree branch is deleted on remote after merge
- Local sync only pulls; it won't auto-resolve conflicts
- If `gh` CLI is not authenticated, the skill will prompt for setup
