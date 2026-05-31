---
id: T002
role: dev
section: medium-priority
priority: medium
status: pending
sprint:
completed_date:
completed_summary:
created: 2026-05-31
---

# Make bin/pr merge worktree-safe (avoid local main checkout)

bin/pr line ~89 runs 'gh pr merge --squash --delete-branch'. The --delete-branch flag also deletes the LOCAL branch, so gh tries to switch the local checkout to the default branch (main). In a worktree workflow the main repo already owns 'main', so this fails: 'fatal: main is already used by worktree at <main-repo>'. The GitHub merge has already completed at that point — only the local cleanup fails. Fix: make merge worktree-aware — merge remotely without local branch deletion (e.g. 'gh pr merge --squash'), then delete only the REMOTE branch explicitly ('git push origin --delete <branch>'), and leave local branch/worktree removal to /worktree-cleanup. Verify the merged state with 'gh pr view <N> --json state' afterward. Acceptance: shipping from a worktree exits 0 and prints a clean merge result; the remote branch is deleted; the local worktree/branch are untouched.

## Context

Surfaced while shipping PR #27/#28 from a worktree; see .claude/plans/template-modernization-2026-05.md. The merge succeeds remotely but the wrapper exits non-zero, which reads as a failed ship.

## Files

- `bin/pr`
