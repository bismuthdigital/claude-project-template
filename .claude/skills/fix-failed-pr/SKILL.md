---
name: fix-failed-pr
description: >
  Find PRs that failed in CI, have merge conflicts (DIRTY), or both.
  Claims one for repair, resolves conflicts and/or fixes CI failures,
  and re-submits. Safe for concurrent invocation — each agent claims
  a different PR.
argument-hint: "[PR number or empty for auto-detect]"
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(gh *), Bash(git *), Bash(cd * && git *), Bash(*/work-queue.sh *), Bash(source *), Bash(ruff *), Bash(mypy *), Bash(.venv/bin/pytest *)
---

# Fix Failed PR

Find PRs that failed in CI, have merge conflicts (DIRTY), or both. Claims one for repair, resolves conflicts and/or fixes CI failures, and re-submits. Safe for concurrent invocation — each agent claims a different PR.

## Process

### Step 1: Find PRs Needing Repair

Run two separate queries to find PRs that need repair. A PR may appear in both lists.

**Query A — CI Failures:**

```bash
# PRs with at least one failed CI check
gh pr list --state open --json number,title,headRefName,statusCheckRollup \
  --jq '[.[] | select(.statusCheckRollup != null) |
    select([.statusCheckRollup[] | select(.conclusion == "FAILURE")] | length > 0) |
    {number, title, branch: .headRefName, problem: "ci_failure"}]'
```

**Query B — Merge Conflicts (DIRTY):**

```bash
# PRs with merge conflicts against main
gh pr list --state open --json number,title,headRefName,mergeStateStatus \
  --jq '[.[] | select(.mergeStateStatus == "DIRTY") |
    {number, title, branch: .headRefName, problem: "dirty"}]'
```

Merge both lists by PR number. A PR can have both problems — tag it accordingly:

| Tags | Meaning | Action |
|------|---------|--------|
| `dirty` only | Merge conflicts, CI may be stale | Rebase first, then re-check CI |
| `ci_failure` only | Clean merge state, but CI failing | Diagnose and fix CI |
| `dirty` + `ci_failure` | Both problems | Rebase first (may resolve CI), then re-check |

**Priority**: Prefer DIRTY-only PRs first (fastest to fix — often just a rebase), then DIRTY+CI, then CI-only.

If a specific PR number was passed as argument, skip detection and use that PR directly (still claim it in Step 2).

If no PRs need repair, exit gracefully:

```
All PRs are clean. Nothing to fix.
```

### Step 2: Claim a PR for Repair

Write a candidates file at `/tmp/wq-candidates-<worktree_name>.json` with all PRs needing repair (ordered by priority), then try-claim one.

**CRITICAL: Use deterministic titles.** The title MUST be exactly `"Repair PR #<number>"` with no description, suffix, or context appended. The slug is derived from the title, so varying descriptions produce different slugs, allowing multiple agents to claim the same PR. Keep titles identical across agents:

```json
[
  {"title": "Repair PR #123", "section": "Repairs", "role_tag": "repair"},
  {"title": "Repair PR #125", "section": "Repairs", "role_tag": "repair"}
]
```

```bash
scripts/work-queue.sh try-claim 1 /tmp/wq-candidates-<worktree_name>.json
```

Parse the JSON output — if `got` is 0, no unclaimed PRs remain. Exit gracefully.

### Step 3: Check Out the PR's Branch

```bash
# Verify worktree is clean
git status --porcelain
```

If the worktree has uncommitted changes, warn the user and ask before proceeding.

```bash
# Fetch and check out the PR's branch
git fetch origin <branch>
git checkout <branch>
```

### Step 3a: Understand the PR's Intent

Before making any changes, build context about what this PR does. Unlike `/ship` where you wrote the code, here you are working on another agent's code.

**Read the PR description:**

```bash
gh pr view <number> --json title,body --jq '{title, body}'
```

**Read the PR diff against main:**

```bash
gh pr diff <number>
```

**Summarize mentally:**
- What feature or fix does this PR implement?
- Which files were changed and what was the intent of each change?
- Are there any test files that reveal expected behavior?

This context is essential for Step 3b (conflict resolution).

### Step 3b: Rebase onto Main (if DIRTY)

**Skip this step if the PR is tagged `ci_failure` only (not `dirty`).**

```bash
# Fetch latest main
git fetch origin main

# Attempt rebase
git rebase origin/main
```

#### 3b-i: Clean Rebase (no conflicts)

If the rebase succeeds cleanly, the PR just needed to catch up with main. Proceed to Step 4.

#### 3b-ii: Conflict Resolution

If the rebase stops with conflicts, resolve each conflicted file using the strategy below.

**Read the conflicted file** to see the conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`). Understand what the PR branch changed versus what main changed.

**IMPORTANT:** During a `git rebase`, the sides are swapped from what you might expect:
- `<<<<<<< HEAD` = the **main branch** (the base you're rebasing onto)
- `>>>>>>> <commit>` = **the PR's changes** (the commits being replayed)

##### Strategy by File Type

| File Pattern | Strategy | Details |
|-------------|----------|---------|
| `pyproject.toml` (version only) | **Take higher** | If the conflict is only in the `version = "..."` line, take whichever version is higher. |
| `pyproject.toml` (other fields) | **Analyze** | Read both sides, understand what each changed, combine. Usually one side added a dependency and the other changed something else — both changes apply. |
| `*.py` (source code) | **Analyze intent** | See "Code Conflict Resolution" below. |
| `tests/**/*.py` | **Analyze intent** | Same as code. Be especially careful about fixture changes that both sides depend on. |

##### Code Conflict Resolution

For Python source files and other code, you must rely on the context gathered in Step 3a (PR description and diff). You did not write this code, so take extra care:

1. **Read the full conflicted file** — understand the surrounding context, not just the conflict markers.
2. **Identify what main changed** — was it a refactor, bug fix, new feature, or formatting change? Check `git log origin/main --oneline -10` if needed.
3. **Identify what the PR changed** — use the PR description and diff from Step 3a.
4. **Determine compatibility:**
   - **Disjoint changes**: Both sides changed different things in the same region. Keep both changes.
   - **Overlapping changes**: Both sides modified the same logic. Understand the intent of each and write a version that satisfies both.
   - **Contradictory changes**: Main changed behavior in a way that conflicts with the PR's feature. This requires careful judgment — see "When NOT to Auto-Resolve" below.
5. **Edit the file** to remove conflict markers and produce the correct merged result. Do not leave any `<<<<<<<`, `=======`, or `>>>>>>>` markers.
6. **Stage the resolved file:**
   ```bash
   git add <resolved-file>
   ```

After resolving **all** conflicts for the current rebase step:

```bash
git rebase --continue
```

##### When NOT to Auto-Resolve

Abort the rebase and escalate to the user if:

- A code conflict involves **behavioral changes on both sides** where the correct merge is not obvious
- More than **5 files** are conflicted (suggests the branches diverged significantly)
- A conflict touches **security-sensitive code** (auth, input validation, sanitization)
- You are uncertain about the intent of either side's changes

To abort:
```bash
git rebase --abort
```

Then inform the user of the situation and ask how to proceed.

#### 3b-iii: Post-Rebase Verification

After resolving conflicts, re-run CI parity checks:

```bash
source .venv/bin/activate 2>/dev/null || true

# Lint and format
ruff check --fix .
ruff format .
ruff format --check .
ruff check .

# Type check
mypy src/

# Run tests
.venv/bin/pytest --tb=short -q
```

If linting or formatting was auto-fixed, stage and amend:
```bash
git add -A
git commit --amend --no-edit
```

### Step 4: Diagnose CI Failure

**If the PR was `dirty`-only and the rebase was clean**: Skip diagnosis. CI will re-run after push. Proceed to Step 6.

**If the PR was `dirty` and conflicts were resolved**: CI status is stale. If post-rebase verification passed, proceed to Step 6.

**If the PR has `ci_failure` tag**: diagnose the CI failure using the same approach as `/ci-review`.

### Step 5: Fix CI Issue (if applicable)

**Skip if the only problem was `dirty` and it was resolved by rebase.**

Apply the fix based on diagnosis and run local CI parity checks.

### Step 6: Push and Re-Queue

**If only a rebase was performed (no code fix):**

```bash
git push --force-with-lease origin HEAD
```

No new commit is needed. After pushing, enable auto-merge:

```bash
gh pr merge <number> --squash --delete-branch --auto
```

**If a CI fix was applied:**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Fix CI failure in PR #<number>

<description of what was fixed>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

git push --force-with-lease origin HEAD
gh pr merge <number> --squash --delete-branch --auto
```

### Step 7: Mark Repair Claim as Shipped

```bash
scripts/work-queue.sh mark-shipped "<pr_number>" "<pr_url>"
```

### Step 8: Report

```
===============================================
           PR #42 REPAIRED
===============================================

Branch: worktree-exciting-shtern
PR:     https://github.com/org/repo/pull/42
Tags:   dirty, ci_failure

-----------------------------------------------
PR INTENT
-----------------------------------------------
-> <what the PR does>

-----------------------------------------------
REBASE
-----------------------------------------------
Rebased onto main (5 commits behind)
No conflicts
  # or:
Rebased onto main (5 commits behind)
Resolved conflicts in 1 file:
  - src/your_package/models.py — disjoint changes, kept both
Post-rebase verification passed

-----------------------------------------------
DIAGNOSIS                           # only if ci_failure
-----------------------------------------------
Job:    Test
Cause:  test assertion failure — stale fixture

-----------------------------------------------
FIX                                 # only if ci_failure
-----------------------------------------------
  - Updated tests/conftest.py:45 — refresh fixture
  - 1 file changed, 3 insertions, 1 deletion

-----------------------------------------------
STATUS
-----------------------------------------------
Local CI parity passed
Pushed (force-with-lease)
Re-added to merge queue
Repair claim marked as shipped

===============================================
```

## Error Handling

| Scenario | Action |
|----------|--------|
| No failed or dirty PRs found | Exit: "All PRs are clean" |
| All broken PRs claimed | Exit: "All broken PRs being repaired by other agents" |
| Worktree has uncommitted changes | Ask user before switching branches |
| Rebase: clean (no conflicts) | Proceed — push rebased branch |
| Rebase: predictable file conflicts | Auto-resolve using strategy table |
| Rebase: code conflicts (intent clear) | Analyze both sides using PR context, resolve |
| Rebase: code conflicts (intent unclear) | Abort rebase, escalate to user |
| Rebase: >5 conflicted files | Abort rebase, escalate to user |
| Rebase: security-sensitive conflicts | Abort rebase, escalate to user |
| Post-rebase tests fail from resolution | Fix resolution and amend |
| Post-rebase tests fail from main | Note in commit, proceed |
| Fix doesn't resolve all CI failures | Report remaining failures, keep claim active |
| PR was closed/merged while repairing | Release claim, report: "PR resolved externally" |

## Concurrent Safety

The work queue claim mechanism provides mutual exclusion:
- Title `"Repair PR #42"` -> slug `repair-pr-42` is unique per PR number
- Titles MUST be exactly `"Repair PR #<number>"` — any variation in wording produces a different slug, defeating mutual exclusion
- `mkdir`-based atomic locking prevents races between agents
- TTL handles crashed repair agents (claim expires, another agent can pick up)
- Agents that find all failed PRs claimed exit immediately (no wasted work)

## Safety Rules

1. **Never `rm -f` claim files directly.** Always use `scripts/work-queue.sh release` or `release-all`.
2. **Never `cd` to the main repo before running the script.** The script resolves the main repo path internally.
3. **Never edit claim JSON files directly.** Use the script's subcommands.
4. **Always verify local CI parity** before pushing — don't push a fix that introduces new failures.
5. **Always use `--force-with-lease` when pushing after rebase** — never bare `--force`.
6. **Never resolve conflicts in security-sensitive code automatically** — abort the rebase and escalate.
