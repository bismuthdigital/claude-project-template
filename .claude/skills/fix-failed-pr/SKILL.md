---
name: fix-failed-pr
description: >
  Batch-fix broken PRs. Queue PRs (auto-merge enabled) with merge conflicts
  are fixed individually and re-queued. Non-queue PRs with CI failures are
  combined into a single new PR, originals closed with traceability comments.
  Safe for concurrent invocation via work-queue claims.
argument-hint: "[PR number for single-PR mode, or empty for batch auto-detect]"
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(./bin/broken-prs *), Bash(./bin/ci-status *), Bash(gh *), Bash(git *), Bash(cd * && git *), Bash(*/work-queue.sh *), Bash(source *), Bash(ruff *), Bash(mypy *), Bash(pytest *), Bash(.venv/bin/pytest *), Agent, Skill
---

# Fix Failed PR — Batch Mode

Find all broken PRs, categorize them, and fix them. Queue PRs (auto-merge
enabled) with issues are fixed individually and re-added to the merge queue.
Non-queue PRs with CI failures are combined into a single new PR that merges
all their features, with originals closed and linked for traceability.

## Single-PR Override

If a specific PR number is passed, skip batch detection and fix only that PR
using the **Individual PR Fix** flow (Step 4):
```bash
./bin/broken-prs pr-state <number>
```

## Step 1: Discover All Broken PRs

```bash
./bin/broken-prs
```

Returns JSON array with each PR tagged: `problem` ("ci_failure", "dirty", or "ci_failure+dirty") and `inQueue` (boolean).

### Step 1a: Loop Prevention

Filter out PRs already combined:
```bash
./bin/broken-prs combined-check <number>
```

Also filter PRs whose title starts with "Combined:" — these are PRs created by this skill.

### Step 1b: Categorize

| Bucket | Criteria | Action |
|--------|----------|--------|
| **Queue PRs** | auto-merge enabled | Fix individually, re-queue |
| **Non-queue PRs** | no auto-merge | Batch-combine (or solo if only 1) |

## Step 2: Claim PRs for Repair

**CRITICAL: Use deterministic titles.** Title MUST be exactly `"Repair PR #<number>"`.

```bash
scripts/work-queue.sh try-claim <count> /tmp/wq-candidates-<worktree>.json
```

## Step 3: Process Queue PRs (Individual Fix)

For each, run Step 4 below. After each fix:
```bash
scripts/work-queue.sh mark-shipped "<pr_number>" "<pr_url>"
```

## Step 4: Individual PR Fix

### 4a: Check out branch
```bash
git fetch origin <branch>
git checkout <branch>
```

### 4b: Understand intent
```bash
gh pr view <number> --json title,body --jq '{title, body}'
gh pr diff <number>
```

### 4c: Rebase onto main (if DIRTY)

```bash
git fetch origin main
git rebase origin/main
```

**Version-only fast path**: If only `pyproject.toml` version conflicts, take main's version and skip tests.

**Conflict resolution**: Same strategy table as `/ship`.

**Post-rebase verification**:
```bash
ruff check --fix . && ruff format .
mypy src/
pytest --tb=short -q
```

### 4d: Diagnose CI failure
```bash
./bin/ci-status checks <number>
./bin/ci-status run-id <branch>
./bin/ci-status log-failed <RUN_ID>
```

### 4e: Fix CI issue

### 4f: Commit fix
```bash
git add -A
git commit -m "$(cat <<'EOF'
Fix CI failure in PR #<number>

<description>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### 4g: Push and re-queue
```bash
git push --force-with-lease origin HEAD
gh pr merge <number> --squash --delete-branch --auto
```

### 4h: Report

## Step 5: Process Non-Queue PRs (Batch Combine)

### 5a: Count check
- 0: skip
- 1: Individual fix (Step 4)
- 2+: Batch combine

### 5b: Gather PR context

### 5c: Create combined branch
```bash
git checkout -b combined-fix-<timestamp> origin/main
```

### 5d: Merge each PR's changes
```bash
git fetch origin <pr_branch>
git merge origin/<pr_branch> --no-edit
```

Resolve inter-PR conflicts (both features must coexist). **Abort if >5 files conflicted.**

### 5e: Validate combined code
```bash
ruff check --fix . && ruff format .
mypy src/
pytest --tb=short -q
```

### 5f: Code health review (subagent)

### 5g: Create combined PR
```bash
gh pr create --title "Combined: <features>" --body-file /tmp/pr-body-<slug>.md
```

### 5h: Close original PRs with traceability
```bash
gh pr comment <number> --body "Combined into PR #<combined> by \`/fix-failed-pr\`."
gh pr close <number>
```

### 5i: Queue combined PR
```bash
gh pr merge <combined_number> --squash --delete-branch --auto
```

### 5j: Mark repair claims as shipped

## Step 6: Final Report

```
===============================================
        FIX-FAILED-PR BATCH COMPLETE
===============================================

QUEUE PRs (fixed individually):
  PR #123 (dirty)      -> Rebased, re-queued
  PR #125 (ci_failure) -> Fixed test, re-queued

NON-QUEUE PRs (combined):
  PR #42 (ci_failure)  -> Combined into PR #200
  PR #45 (ci_failure)  -> Combined into PR #200

Combined PR: <url>

SKIPPED:
  PR #50 -> Claimed by other agent
  PR #52 -> Previously combined
===============================================
```

## Concurrent Safety

- Title `"Repair PR #42"` → slug `repair-pr-42` is unique per PR number
- `mkdir`-based atomic locking prevents races
- TTL handles crashed agents

## Safety Rules

1. Never `rm -f` claim files — use `scripts/work-queue.sh release`
2. Always verify local CI parity before pushing
3. Always use `--force-with-lease` after rebase
4. Never auto-resolve security-sensitive conflicts
5. Close originals immediately after creating combined PR
6. Never re-combine a "Combined:" PR
