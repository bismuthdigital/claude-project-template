---
name: cleanup
version: 1.0.0
description: >
  Pre-exit safety check for worktrees. Detects unshipped work, uncommitted changes,
  uncaptured knowledge artifacts, and active claims before you exit and remove a worktree.
  Defends against accidental data loss from premature worktree removal.
argument-hint: "[--force]"
allowed-tools: Read, Glob, Grep, Bash(git status *), Bash(git status), Bash(git diff *), Bash(git log *), Bash(git rev-list *), Bash(git rev-parse *), Bash(git branch *), Bash(gh pr *), Bash(./bin/pr *), Bash(./bin/worktree-info *), Bash(scripts/work-queue.sh *), Bash(ls *), AskUserQuestion
---

# Pre-Exit Cleanup Check

Safety net before exiting a worktree session. Checks for work that would be lost if the worktree were removed, and guides you through preserving it.

**Run this instead of immediately exiting.** The goal is to ensure that every artifact from the conversation — code, plans, knowledge — has been captured somewhere recoverable.

## When to Use

- Before ending a conversation in a worktree
- Before running `ExitWorktree` with `action: "remove"`
- When the user says "done", "exit", "wrap up", or similar
- When you're about to suggest the user can safely remove the worktree

## Checks

Run all checks in parallel where possible, then present a consolidated report.

### Check 1: Uncommitted Changes

```bash
git status --porcelain
```

**If output is non-empty:** There are uncommitted changes. List them and flag as `UNCOMMITTED CHANGES`.

### Check 2: Unpushed Commits

```bash
# Check if branch has a remote tracking branch
git rev-parse --abbrev-ref @{upstream} 2>/dev/null

# Count commits ahead of remote (if tracking branch exists)
git rev-list --count @{upstream}..HEAD 2>/dev/null
```

**If ahead > 0 or no upstream:** There are local commits that haven't been pushed. Flag as `UNPUSHED COMMITS`.

### Check 3: Ship Status

Check whether `/ship` has been run for this worktree's work:

```bash
# Check for a PR from this branch
gh pr list --head "$(git branch --show-current)" --state all --json number,state,title,url
```

**If no PR exists:** Flag as `NO PR CREATED` — `/ship` has not been run.
**If PR exists but is open (not merged):** Note the PR URL and state. This is normal for merge-queue mode.
**If PR is merged:** Work has been shipped successfully.

### Check 4: Work Queue Claims

```bash
scripts/work-queue.sh claimed-by-me
```

**If claims exist with `state: "claimed"`:** These tasks are still claimed but not shipped. Flag as `ACTIVE CLAIMS`.
**If claims exist with `state: "shipped"`:** Normal — waiting for merge queue. Note for awareness.

### Check 5: Knowledge Artifacts

Check for planning work in this conversation that may not have been preserved:

```bash
# Check if any plan files were modified in this worktree's branch
git diff origin/main --name-only -- .claude/plans/ docs/

# Check for review artifacts that haven't been embedded in a PR
ls .claude/reviews/ 2>/dev/null
```

Also check the conversation context (not via tools — assess from your own memory of the conversation):
- Was there significant planning discussion?
- Were strategic decisions made that aren't captured in a plan file?
- Did the user share context (contacts, research, strategy) that should be preserved?
- Were there multi-iteration design discussions whose conclusions should be written down?

**If conversation had significant planning that produced no plan file:** Flag as `UNCAPTURED KNOWLEDGE` and suggest running `/capture` before exit.

### Check 6: Temporary Files

```bash
# Check for PR body drafts that weren't consumed
ls /tmp/*-pr-body-*.md 2>/dev/null

# Check for test output that might be relevant
ls /tmp/pytest-output-*.txt 2>/dev/null
```

These are informational only — not blockers.

## Report Format

Present findings as a structured report:

```
===============================================
          PRE-EXIT CLEANUP CHECK
===============================================

Worktree: <worktree-name>
Branch:   <branch-name>

-----------------------------------------------
CODE STATUS
-----------------------------------------------
  Uncommitted changes:  NONE / <count> files
  Unpushed commits:     NONE / <count> commits
  Pull request:         NONE / #<number> (<state>)
  Ship status:          NOT RUN / SHIPPED / QUEUED

-----------------------------------------------
WORK QUEUE
-----------------------------------------------
  Active claims:        NONE / <count> tasks
  Shipped claims:       NONE / <count> tasks (in merge queue)

-----------------------------------------------
KNOWLEDGE
-----------------------------------------------
  Plan files changed:   NONE / <list>
  Uncaptured context:   NONE / YES — suggest /capture
  Review artifacts:     NONE / <count> files

-----------------------------------------------
VERDICT
-----------------------------------------------
  SAFE TO EXIT        — all work preserved
  # or:
  ACTION NEEDED       — <N> items require attention
    1. <action needed>
    2. <action needed>

===============================================
```

## Verdicts

### SAFE TO EXIT

All of these must be true:
- No uncommitted changes
- No unpushed commits (or branch has been pushed)
- A PR exists (open or merged)
- No active (unshipped) claims
- No significant uncaptured knowledge from the conversation

Report the verdict and confirm the user can safely exit/remove the worktree.

### ACTION NEEDED

One or more checks failed. For each issue, suggest the resolution:

| Issue | Resolution |
|-------|------------|
| Uncommitted changes | Run `/ship` to commit, PR, and merge |
| Unpushed commits | Run `git push` or `/ship` |
| No PR created | Run `/ship` |
| Active claims not shipped | Run `/ship` or `/release-tasks` |
| Uncaptured knowledge | Run `/capture` to preserve planning artifacts |

**Do not block the user.** Present the report and let them decide. If they pass `--force`, acknowledge the risks and proceed without objection.

### Edge Cases

**Conversation was purely exploratory (no code changes):**
- Code checks will all pass (nothing to commit/push/ship)
- Focus on knowledge check — did the conversation produce insights worth capturing?

**User already ran /ship:**
- PR and claims checks will pass
- Still check for uncaptured knowledge — `/ship` ships code, not plans

**Worktree has changes from a previous session:**
- Check `git log` to see if commits predate this conversation
- Flag any pre-existing uncommitted changes separately

## Arguments

| Argument | Effect |
|----------|--------|
| (none) | Run all checks and present report |
| `--force` | Run checks, present report, but don't suggest actions — just confirm exit |
