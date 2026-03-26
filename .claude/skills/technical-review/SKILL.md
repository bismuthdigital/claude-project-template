---
name: technical-review
description: >
  Technical review of backlog tasks — finds unreviewed tasks in
  `next-steps/active/`, produces codebase orientation artifacts (patterns,
  risks, test strategy), and writes them to a shared directory. Designed to
  run as a standalone review agent.
argument-hint: "[N | <task-id> | check [--all]]"
allowed-tools: Read, Glob, Grep, Bash(git *), Bash(scripts/task-format.py *), Bash(.venv/bin/python scripts/task-format.py *), Bash(.venv/bin/python scripts/task-board.py *), Bash(scripts/work-queue.sh *), Bash(./bin/worktree-info *), Write, Task
---

# Technical Review

Produce codebase orientation artifacts for backlog tasks. Reviews give
implementation agents a head start by mapping relevant files, existing patterns,
risks, and test strategy — without prescribing implementation details.

This skill is designed to run as a **standalone review agent** in its own
worktree. The review agent finds unreviewed tasks, generates review artifacts,
and writes them to a shared directory. Implementation agents then consume the
reviews during `/claim-tasks`. The audit trail lives in PR bodies (embedded
by `/ship`), and reviews are cleaned up after shipping.

## Workflows

### Single-Agent (recommended)

```
/claim-tasks 1
  -> claims task for work
  -> detects missing review
  -> generates .claude/reviews/*.md inline
  -> implements, tests, verifies
  -> /ship
```

When `/claim-tasks` detects a claimed task without a review, it generates
one inline and transitions directly to implementation. This is the
recommended workflow — no separate review agent needed.

### Two-Agent (batch review)

```
Review agent (this skill):         Implementation agent:
  /technical-review 3                /claim-tasks 1
  -> finds unreviewed tasks          -> claims task for work
  -> generates .claude/reviews/*.md  -> reads review as orientation
  -> commits reviews to repo         -> implements, tests, verifies
                                     -> /ship
```

Use the two-agent workflow when batch-reviewing multiple tasks ahead of
time (e.g., a review agent prepares 3-5 reviews, then multiple
implementation agents consume them). This skill remains useful for
advance preparation and review auditing (`check --all`).

## Arguments

- **`N`** (number, default 1): Find and review N unreviewed tasks from `next-steps/active/`
- **`T###` or title substring**: Review a specific task by ID or title
- **`check T###`**: Check freshness of a specific review
- **`check --all`**: Check freshness of all reviews

## Process

### When Argument is a Number (or omitted)

#### 1. Coordination Check

Before selecting tasks to review, load the unified task board:

```bash
.venv/bin/python scripts/task-board.py --json
```

The task board shows each task's status (available, claimed, shipped,
in-flight, blocked) and claim ownership. Note which tasks are claimed by
other worktrees (especially those with `purpose: reviewing`) to avoid
double-reviewing. Also note tasks that are already being implemented —
reviewing them is lower priority since the implementation agent is already
reading the code.

#### 2. Find Unreviewed Tasks

```bash
.venv/bin/python scripts/task-format.py list-unreviewed --limit N
```

This returns a JSON array of pending tasks that have no corresponding review
file in `.claude/reviews/`. Tasks are ordered by priority (High > Medium > Low).

If no unreviewed tasks are found, report that and stop.

#### 3. Claim for Review

Write a JSON candidates file at `/tmp/wq-candidates-<worktree_name>.json` with
all unreviewed tasks in priority order, then claim them in one call:

```json
[
  {"title": "Task title", "section": "High Priority", "roles": ["steward"], "purpose": "reviewing"},
  ...
]
```

```bash
scripts/work-queue.sh try-claim <count> /tmp/wq-candidates-<worktree_name>.json
```

The script tries each candidate in order and skips tasks that are already
claimed. The goal is to avoid double-reviewing, not to block implementation
agents — implementation agents use their own claims.

If no tasks can be claimed (all skipped), report that and stop.

#### 4. Generate Reviews

For each claimed task, follow the [Explore and Write](#explore-the-codebase)
process below.

#### 5. Verify Reviews Written

After all reviews are generated, confirm the files exist in the shared directory:

```bash
MAIN_REPO=$(./bin/worktree-info main-repo)
ls -la "${MAIN_REPO}/.claude/reviews/"
```

Reviews are **not committed** — they are shared ephemeral files (gitignored).
The audit trail lives in PR bodies, where `/ship` embeds reviews as collapsible
`<details>` sections. Cleanup happens automatically at ship time.

#### 6. Mark Reviewed and Release Claims

For each reviewed task, write a persistent marker visible to all worktrees, then
release the claim so implementation agents can claim it:

```bash
scripts/work-queue.sh mark-reviewed "<slug>"
scripts/work-queue.sh release "<slug>"
```

The `mark-reviewed` marker persists in `.claude/work-queue/reviewed/` (shared
across all worktrees). This prevents other review agents from re-reviewing the
task.

### When Argument is a Task ID or Title

#### Resolve the Task

```bash
.venv/bin/python scripts/task-format.py lookup "<argument>"
```

If the lookup returns no result, report the error and stop. If multiple matches,
use the first match and note the ambiguity.

Then proceed directly to [Explore and Write](#explore-the-codebase).

### Explore the Codebase

Starting from the task's `files` sub-field (if present) and keywords from the
title and description:

1. **Read referenced files** — understand current implementation
2. **Find test files** — check existing coverage
3. **Grep for related patterns** — find similar implementations, constants, or
   helper functions that the task might use
4. **Check `next-steps/completed/`** — look for similar completed tasks that
   establish patterns
5. **Review recent git history** — check if any recent commits touch the same
   files or area

### Write the Review

Output to `.claude/reviews/<slug>.md` where `<slug>` comes from the task-format
lookup output.

#### Review Artifact Format

```markdown
---
task_id: T047
task_title: "Task title from task file"
reviewed_at: "2026-02-26T14:30:00Z"
reviewed_sha: "<current HEAD short sha>"
referenced_files_sha:
  src/package/models.py: "<git hash-object output>"
  tests/test_scoring.py: "<git hash-object output>"
---

# Technical Review: Task title

## Task Context
[1-2 paragraphs — what this task is about, why it matters]

## Scope
- Estimated complexity: Low / Medium / High
- Files affected: N
- New files: Y/N

## Files Involved
- `path/to/file.py` — What it does, what's relevant, key line numbers

## Patterns to Follow
- [Existing patterns the implementer should match]

## Dependencies
- [Other tasks that must complete first, or "none"]

## Risks
- [Things that could go wrong, gotchas, edge cases]

## Test Strategy
- [Existing test coverage, suggested new tests, test file locations]

## Open Questions
- [Decisions the implementer should make at implementation time]
```

### Scope Rules

The review produces **orientation, not instructions**:

| DO | DO NOT |
|----|--------|
| List files and their purpose | Write pseudocode |
| Show existing patterns | Specify function signatures |
| Flag risks and gotchas | Dictate variable names |
| Suggest test approaches | Prescribe implementation order |
| Note dependencies | Write code snippets to copy |

### Staleness Detection

Reviews include `referenced_files_sha` in the YAML frontmatter — the git
hash-object of each file at the time of review.

#### Check Freshness

```bash
# All reviews
.venv/bin/python scripts/task-format.py review-freshness

# Single review
/technical-review check T047
```

Reports each review as:
- **fresh**: All referenced files unchanged since review
- **stale**: One or more referenced files have been modified (lists which ones)
- **orphaned**: The task no longer exists in `next-steps/active/`

### Check Subcommand

When invoked with `check`:

```
/technical-review check T047     # Freshness of one review
/technical-review check --all    # Freshness of all reviews
```

For `check T047`: resolve the task, find its review file, compare stored SHAs
against current file hashes. Report fresh/stale/missing.

For `check --all`: run `scripts/task-format.py review-freshness` and present
the summary.

## Lifecycle

- Reviews are **shared ephemeral files** in `.claude/reviews/` (gitignored) —
  visible to all worktrees via the main repo's shared directory
- The **audit trail** lives in PR bodies — `/ship` embeds reviews as collapsible
  `<details>` sections before creating the PR
- **Cleanup** happens at ship time — `/ship` calls
  `scripts/work-queue.sh clean-review "<slug>"` after releasing claims
- Stale reviews are still useful as starting points — they just need the
  implementer to note what changed
- Orphaned reviews (task no longer in `next-steps/active/`) are cleaned up during
  `/next-steps clean`
- Review claims are temporary (released after writing) — they only prevent
  concurrent review agents from double-reviewing
- **Reviewed markers** in `.claude/work-queue/reviewed/` persist across worktrees
  and prevent re-reviews

## Examples

```
/technical-review               # Review 1 unreviewed task (default)
/technical-review 3             # Review up to 3 unreviewed tasks
/technical-review T047          # Review a specific task by ID
/technical-review config        # Review by title substring
/technical-review check T047    # Check if review is fresh
/technical-review check --all   # Check all reviews
```
