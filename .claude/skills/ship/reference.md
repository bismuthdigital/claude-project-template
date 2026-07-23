# Ship — Reference

On-demand reference for `/ship`. Each section is loaded when the
corresponding step of SKILL.md points here.

## PR Body Templates

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

## Embedding Technical Reviews in the PR Body (Step 7a.1)

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
