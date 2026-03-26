---
name: claim-tasks
description: >
  Claim tasks from the task backlog (`next-steps/active/`), then implement
  them using a merge-queue strategy: implement each with tests, then
  verify test quality for the batch. Accepts a number (claim N tasks),
  text (fuzzy match), or "list"/"status" for inspection.
argument-hint: "[N | task description | slug | list | status]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Bash(./bin/fuzzy-match *), Bash(./bin/worktree-info *), Bash(./bin/complete-tasks *), Bash(.venv/bin/python scripts/task-board.py *), Agent, AskUserQuestion, Skill
---

# Claim Tasks — Merge Queue Execution

Claim tasks from the task backlog and implement them end-to-end using a
merge-queue strategy. Multiple features are implemented with proper tests
between each, then test quality is verified for the batch.
Auto-invokes `/ship` when complete.

## Task System Reference

Tasks are stored as per-task markdown files with YAML frontmatter:

- **Pending tasks**: `next-steps/active/*.md`
- **Completed tasks**: `next-steps/completed/*.md`
- **Section ordering**: `next-steps/_sections.toml`
- **Full format spec**: `docs/TASK-FORMAT.md`

`NEXT-STEPS.md` is a **generated artifact** — rendered by CI via `scripts/task-format.py render`. Never read or edit it directly.

**Key commands** (always use these — never manually create/edit task files):

| Command | Purpose |
|---------|---------|
| `scripts/task-format.py parse` | Parse all pending tasks to JSON |
| `scripts/task-format.py create-task --role X --section Y --priority Z --title "..."` | Create a new task file |
| `./bin/complete-tasks --summary "..." slug1 slug2 ...` | Mark tasks complete (batch), move to `completed/` |
| `scripts/task-format.py validate` | Check task format compliance |
| `scripts/task-format.py lookup "<title or ID>"` | Find a task by title or ID |
| `scripts/task-format.py list-unreviewed` | List tasks without technical reviews |
| `scripts/task-format.py render` | Regenerate NEXT-STEPS.md locally (CI does this after merge) |

## Input Parsing

Determine the mode from the user's argument:

| Input | Mode |
|-------|------|
| (empty) or `1` | **count** — claim 1 task |
| Any positive integer N | **count** — claim N tasks |
| `list` | **list** — show all claims, no execution |
| `status` | **status** — show this worktree's claims, no execution |
| Any other text | **fuzzy** — match against task titles/slugs |

### Fuzzy Matching

When the input is text (not a number, not `list`/`status`):

1. Load pending tasks via `task-board.py --json` (or reuse if already loaded)
2. Run multi-match to find **all** tasks matching the search term:

```bash
./bin/fuzzy-match --multi "<search_term>" < /tmp/claim-tasks-pending.json
```

This returns `{"matches": [...], "count": N}` with all confident matches
sorted by score. A match is confident when the query appears as a substring
in the title, slug, or roles, or when the Levenshtein distance is within
the confidence threshold.

3. Filter the matches to only `status: "available"` tasks (skip claimed,
   shipped, in-flight, blocked).
4. Apply batch size limits:
   - **0 matches**: report no matches and stop.
   - **1-5 matches**: claim all of them automatically. Present: "Found N
     matching tasks. Claiming all N."
   - **6+ matches**: claim the top 5 (by score, then priority). Present:
     "Found N matching tasks. Claiming top 5. Approve claiming all N?"
     If the user approves, claim all. Otherwise proceed with 5.

## Inspection Commands

### `/claim-tasks list`

Show all current claims across all worktrees without claiming anything new.

1. Run `scripts/task-board.py` (human-readable, default output) to show the
   full task board: all pending tasks grouped by section with status indicators,
   role/priority summary, and claim annotations.
2. Present the output directly — it already includes claim info per task.

### `/claim-tasks status`

Show only this worktree's claimed tasks.

1. Run `scripts/work-queue.sh claimed-by-me`
2. Present a formatted list

**For both inspection commands, stop here — do not proceed to execution.**

---

## Test Execution Discipline

These rules apply to ALL phases. Violations cause lost work and wasted time.

1. **Commit before test.** Always `git add -A && git commit && git push`
   BEFORE running `./bin/test`. Tests can hang, time out, or be interrupted.
   Committed code is recoverable; uncommitted code is lost forever.

2. **One foreground test run.** Always run `./bin/test` as a single
   foreground Bash call with `timeout: 300000` (5 minutes). The script has
   its own internal timeout as a backstop, but always set the Bash tool
   timeout too.

3. **Never pipe test output.** Do NOT run `./bin/test 2>&1 | tail -5` or
   any piped variant. The script writes to an output file — read that file
   with the Read tool after the command finishes.

4. **Never run tests in the background.** Do NOT use `run_in_background`
   for `./bin/test`. Background test processes cannot be reliably monitored
   and create zombie processes that contend for CPU.

5. **Never retry endlessly.** Maximum 3 fix-rerun cycles per phase. If
   tests still fail, commit what works, note failures, and move on. CI is
   the comprehensive safety gate.

6. **Never blame the user for interruptions.** If a test run is interrupted
   or times out, that is a normal operational event. Your work is safe
   because you committed first (rule 1). Acknowledge the interruption
   neutrally, check what's committed, and continue from there.

## Interruption Handling

When the user presses ESC or interrupts a subagent, this is a **signal that
something is wrong** — the agent may be stuck, churning, or running too long
without visible progress. It is NOT an inconvenience to be dismissed.

**On any interruption, the orchestrator MUST:**

1. **Stop and assess.** Do NOT immediately re-launch the same subagent or
   say "let me continue." The user interrupted for a reason.

2. **Report saved state.** Run `git log --oneline -5` and `git diff --stat`
   to show the user exactly what work has been committed and what (if
   anything) is uncommitted. Be honest if work was lost.

3. **Acknowledge the gap.** If the subagent was running for a long time with
   no visible output, say so: "That agent ran for N tool calls without
   committing or reporting progress — that's not acceptable."

4. **Ask how to proceed.** Offer concrete options:
   - "Continue from the last commit?" (resume with a fresh subagent)
   - "Skip this task and move to the next?"
   - "Stop the batch here and ship what's done?"
   - "Something else?"

5. **Never re-launch the same prompt unchanged.** If a subagent was
   interrupted, the re-launch must include a note about what was already
   done (based on committed state) so it doesn't repeat work.

**Subagents also follow these rules.** If a subagent is interrupted during
a test run or long operation, it checks committed state, reports what's
saved, and asks how to proceed rather than silently retrying.

---

## Three-Phase Execution

After claiming (count or fuzzy mode), execute all three phases without pausing
for user input unless blocked.

### Phase 1 — Claim & Orient

**Runs in the main context. Writes a handoff file for Phase 2.**

0. **Ensure the worktree venv exists** before running any Python commands.
   This MUST complete before any subsequent steps — do NOT run it in parallel
   with other commands:
   ```bash
   test -x .venv/bin/python || (python3 -m venv .venv && .venv/bin/pip install -e ".[dev]" 2>&1 | tail -5)
   ```

1. **Initialize** the work queue and **load the unified task board**:
   ```bash
   scripts/work-queue.sh init
   scripts/work-queue.sh auto-release-merged
   .venv/bin/python scripts/task-board.py --json > /tmp/claim-tasks-board.json
   ```
   The task board aggregates three data sources into one JSON object:
   - **Task files** (`next-steps/active/*.md`) — all pending tasks with metadata
   - **Work queue claims** (`scripts/work-queue.sh list`) — active agent claims and shipped PRs
   - **In-flight PRs** (`scripts/work-queue.sh inflight-tasks`) — tasks completed in open PRs

   Each task has a pre-computed `status` field: `available`, `claimed`,
   `shipped`, `in-flight`, `blocked`, or `expired-claim`. Tasks also have
   pre-computed `blocked_by` (unresolved dependencies) and `cluster_id`
   (file-overlap grouping).

   **It is more costly to double-implement a feature than to spend tokens on
   coordination.** Always read the board carefully.

   Also write the tasks array to `/tmp/claim-tasks-pending.json` for fuzzy
   matching (extract `tasks` from the board JSON).

2. **Select tasks** from the board JSON — by count (highest priority first) or fuzzy match.
   Only consider tasks with `status: "available"`. Skip:
   - Tasks with `status: "claimed"` or `"shipped"` (another worktree owns them)
   - Tasks with `status: "in-flight"` (completed in an open PR)
   - Tasks with `status: "blocked"` (unresolved dependencies)
   - Tasks already implemented on main (see "Already-Implemented Check" below)

   For count mode, select using the pre-computed `clusters` array from
   the board JSON:

   a. **Use the clusters array directly.** Each cluster has `task_slugs`,
      `available_count`, `priority`, `dirs`, and `roles`. Clusters are
      pre-sorted by available count (descending), then priority. Pick the
      first cluster that satisfies the requested count N. When other
      concurrent agents have claimed tasks (check `summary.claimed > 0`),
      **actively avoid clusters whose `dirs` overlap with claimed tasks'
      file areas**.

   b. **Within a cluster, rank by priority** (High > Medium > Low).

   c. **Prefer tasks with fewer dependencies.**

   d. If no single cluster has N tasks, take the largest cluster and fill
      remaining slots from the next-closest cluster (fewest overlapping
      directories with the first cluster's files).

   **PR conflict detection.** After selecting candidate tasks (but before
   claiming), check for overlap with open PRs:

   ```bash
   # Collect all file paths from selected tasks into a JSON array
   scripts/work-queue.sh check-pr-overlap '["src/package/foo.py", ...]'
   ```

   If `overlap_count > 0`, review the overlapping PRs:
   - If a task's files overlap with an open PR that is **not** from this
     worktree, flag it as a conflict risk.
   - Try to swap the conflicting task for a non-overlapping alternative
     from the same priority tier.
   - If no alternative exists, proceed but include the warning in the
     presentation output (see "PR CONFLICT RISK" section below).

4. **Claim** using `try-claim`:

   Write a candidates file at `/tmp/wq-candidates-<worktree_name>.json`:
   ```json
   [
     {"title": "Task title 1", "section": "High Priority", "roles": ["steward"], "purpose": "implementing"},
     {"title": "Task title 2", "section": "High Priority", "roles": ["designer"], "purpose": "implementing"}
   ]
   ```
   The `title` field must be the **exact task title** from the task file's `# heading`.

   ```bash
   scripts/work-queue.sh try-claim <N> /tmp/wq-candidates-<worktree_name>.json
   ```

5. **Check for technical reviews** on each claimed task:
   ```bash
   .venv/bin/python scripts/task-format.py lookup "<task title>"
   ```
   Check if `${MAIN_REPO}/.claude/reviews/<slug>.md` exists (where `MAIN_REPO`
   is from `git worktree list --porcelain | head -1 | sed 's/^worktree //'`).

6. **Generate missing technical reviews**. For each claimed task without a
    review, perform inline exploration:

    a. Read referenced files from the task's `files` field
    b. Find test files for the area
    c. Grep for related patterns
    d. Check `next-steps/completed/` for similar completed tasks
    e. Check recent git history for the same files
    f. Write the review to `${MAIN_REPO}/.claude/reviews/<slug>.md`:

    ```markdown
    ---
    task_id: <id or null>
    task_title: "<exact task title>"
    reviewed_at: "<ISO 8601 timestamp>"
    reviewed_sha: "<current HEAD short sha>"
    referenced_files_sha:
      path/to/file.py: "<git hash-object output>"
    ---

    # Technical Review: <task title>

    ## Task Context
    ## Scope
    ## Files Involved
    ## Patterns to Follow
    ## Dependencies
    ## Risks
    ## Test Strategy
    ## Open Questions
    ```

7. **Write the handoff file** at `/tmp/claim-tasks-<worktree>.json`:

    ```json
    {
      "worktree": "<worktree_name>",
      "main_repo": "/path/to/main/repo",
      "tasks": [
        {
          "index": 1,
          "title": "Fix config validation edge case",
          "slug": "fix-config-validation-edge-case",
          "section": "High Priority",
          "roles": ["steward"],
          "review_path": ".claude/reviews/fix-config-validation-edge-case.md",
          "has_review": true,
          "status": "pending",
          "files_changed": [],
          "smoke_tests_written": [],
          "notes": ""
        }
      ]
    }
    ```

8. **Present** the claim summary (same format as current — see Presentation
    Format below).

**Phase 1 is complete. Proceed to Phase 2 using subagents.**

---

### Phase 2 — Implement with Tests

**Each task runs in its own subagent (Agent tool) for a fresh context window.**

For each task in the handoff file, in order, spawn an Agent with this prompt
structure:

```
You are implementing a single task from a merge-queue batch. Read the handoff
file at /tmp/claim-tasks-<worktree>.json for task context. You are implementing
task <N> of <total>: "<task title>".

CRITICAL RULES — read before doing anything:
- ALWAYS commit and push BEFORE running tests. Tests can hang or time out.
  Committed code is recoverable; uncommitted code is lost.
- NEVER pipe ./bin/test through tail, head, grep, or any other command.
  The script writes output to a file — read that file with the Read tool.
- NEVER run ./bin/test in the background. Always foreground with timeout.
- If you are interrupted or a test times out, your work is safe because you
  committed first. Check what's committed (`git log --oneline -3`), report
  status honestly, and ask how to proceed — do NOT silently retry.

Follow these steps:

1. Read the handoff file at /tmp/claim-tasks-<worktree>.json. Find your task
   (index <N>).

2. If the task has a review file (check has_review and review_path in the
   handoff), read it from ${MAIN_REPO}/<review_path>. Use "Files Involved",
   "Patterns to Follow", and "Risks" as orientation.

3. Read the source files involved. Understand the existing code before making
   changes.

4. Implement the feature/fix. Follow existing code patterns and project
   conventions from CLAUDE.md. **Commit incrementally** — after each
   meaningful unit of work (e.g., after modifying each source file, after
   writing each test file), commit and push:
   ```bash
   git add -A && git commit -m "<task title>: <what this commit does>"
   git push --force-with-lease -u origin HEAD
   ```
   This ensures work is never lost if the agent is interrupted. These are
   safety checkpoints — /ship squash-merges with a proper message later.

5. Write tests — proper coverage for the feature, following the test
   efficiency rules below. **This is the only testing phase.** There is no
   separate "comprehensive testing" phase later, so write complete tests now.

   **What to test:**
   - Happy path proving the feature works
   - 2-4 edge cases for obvious failure modes and boundary conditions
   - Error handling paths for invalid inputs (if applicable)

   **Test efficiency rules (MANDATORY):**
   - **Add to existing test files first.** Before creating a new file, check
     if the tests/ directory already has a file covering the same module or
     area. Add your tests there.
   - **Never create a file that duplicates an existing file's scope.** If
     test_config.py already tests config loading, do not create
     test_config_comprehensive.py — add tests to test_config.py.
   - **Share fixtures.** Use class-scoped or module-scoped fixtures, not
     per-test setup. Use conftest.py for shared fixtures.
   - **Aim for 5-10 tests per task, not more.** Each test should assert
     something meaningfully different. Do not write parametrized sweeps or
     exhaustive matrices.

   **Anti-patterns — NEVER do these:**
   - **Never assert exact counts** of dynamic data (files, records, items).
     These change over time. Use relative assertions (`>= N`) or check for
     specific entries by ID.
   - **Never assert specific prose phrases** from data content. Tests like
     `assert "specific text" in section["body"]` are brittle — editorial
     changes will break them. Instead, test structural properties: sections
     exist, bodies are non-empty.

   **Commit each test file immediately after writing it.**

6. Run scoped tests — foreground only, with timeout:
   ```bash
   ./bin/test
   ```
   Use the Bash tool's timeout parameter: 300000 (5 minutes).
   After the command completes, read the output file path printed at the
   start of the run for results. NEVER pipe this command. NEVER run it
   in the background.

7. If tests fail: read the output file, diagnose the root cause, fix the
   code, then commit and push FIRST, then re-run tests. Maximum 3 cycles.
   **"Pre-existing" is NOT a valid reason to skip failures.** If you suspect
   a failure is unrelated to your changes, verify by checking whether the
   failing test imports or exercises code you touched. If it genuinely has
   no connection to your changes, fix the test anyway (it's broken and you
   found it) or report it as a blocker — do NOT silently proceed.
   If tests TIME OUT (exit code 124): read the output file for partial
   results. If most tests passed, note the timeout and move on — CI is the
   comprehensive gate.

8. Update the handoff file: read /tmp/claim-tasks-<worktree>.json, set your
   task's status to "implemented", populate files_changed with the list of
   source files you modified, populate tests_written with the test file
   paths, and add a brief note about what you did. Write the updated JSON
   back.

Report what you implemented, what tests you wrote, and whether scoped tests
pass.
```

After each subagent completes:
- Read its output to verify success
- Read the handoff file to confirm status is "implemented"
- If the subagent reports a blocker it could not resolve, ask the user whether
  to continue with remaining tasks or stop
- Proceed to the next task

After all tasks are implemented, **proceed to Phase 2.5 (Code Health).**

---

### Phase 2.5 — Code Health Review

**Runs in a single subagent (Agent tool) for a fresh context window.**

This phase actively reviews and fixes code quality issues in all files changed
during Phase 2. It catches anti-patterns, unnecessary complexity, and assumption
errors before comprehensive testing locks things down.

Spawn an Agent with this prompt:

```
You are performing a code health review on recently implemented features.
All features have been implemented with passing smoke tests. Your job is to
review the changed code for quality issues and actively fix them — simplify,
remove anti-patterns, check assumptions, and improve consistency.

CRITICAL RULES — read before doing anything:
- ALWAYS commit and push BEFORE running tests. Tests can hang or time out.
  Committed code is recoverable; uncommitted code is lost.
- NEVER pipe ./bin/test through tail, head, grep, or any other command.
  The script writes output to a file — read that file with the Read tool.
- NEVER run ./bin/test in the background. Always foreground with timeout.
- If you are interrupted or a test times out, your work is safe because you
  committed first. Check what's committed (`git log --oneline -3`), report
  status honestly, and ask how to proceed — do NOT silently retry.

Follow these steps:

1. Read the handoff file at /tmp/claim-tasks-<worktree>.json. Collect all
   files_changed across all implemented tasks into a single deduplicated list.

2. For each changed source file (not test files):
   a. Read the file fully
   b. Read its immediate neighbors (files it imports from, files that import it)
      to verify assumptions at boundaries
   c. Review against this checklist:

   **Simplification:**
   - Collapse unnecessary nesting (early returns, guard clauses)
   - Remove dead code paths, unused variables, unreachable branches
   - Replace verbose patterns with idiomatic Python where clearer
   - Don't abstract unless 3+ call sites exist

   **Assumption checking:**
   - Verify type annotations match actual runtime values
   - Check callers pass arguments the callee expects
   - Confirm enum/constant values consistent across definition and usage
   - Validate string literals (dict keys, config keys) are consistent

   **Anti-patterns:**
   - Mutable default arguments
   - Bare or overly broad except clauses
   - God functions (>50 lines) that should be decomposed
   - Repeated attribute access in tight loops

   **Consistency:**
   - Follow patterns established in the same module/package
   - Match naming conventions (snake_case functions, PascalCase classes)
   - Use the same error handling style as surrounding code

3. Fix issues directly. Make focused, minimal edits. Every fix must be
   behavior-preserving. If unsure whether a change alters behavior, skip it
   and note it. **Commit after each file's fixes** — don't batch all fixes
   into one commit:
   ```bash
   git add -A && git commit -m "Code health: <file> — <what>"
   git push --force-with-lease origin HEAD
   ```

4. Do NOT add docstrings, comments, or type annotations to code you didn't
   otherwise change. Do NOT expand scope beyond the changed files and their
   immediate neighbors.

5. Run lint after all fixes:
   ```bash
   ruff check --fix .
   ruff format .
   ```

6. Run scoped tests — foreground only, with timeout:
   ```bash
   ./bin/test
   ```
   Use the Bash tool's timeout parameter: 300000 (5 minutes).
   After the command completes, read the output file for results.
   NEVER pipe this command. NEVER run it in the background.

7. If tests fail: read the output file, diagnose root cause, fix the code,
   then commit and push FIRST, then re-run. Maximum 3 cycles.
   **"Pre-existing" is NOT a valid reason to skip failures.** Fix the test
   or report it as a blocker — do NOT silently proceed.
   If tests TIME OUT (exit code 124): read the output file for partial
   results. Note the timeout and move on — CI is the safety gate.

8. Update the handoff file: set all task statuses to "health-checked".
   Add a "health_notes" field to each task listing changes made to its files.

Report: files reviewed, issues found and fixed, issues skipped (uncertain),
and test results.
```

After the subagent completes:
- Read its output to verify success
- Read the handoff file to confirm statuses are "health-checked"
- If the subagent reports test failures it could not resolve, ask the user
  whether to continue to Phase 3 or stop

**Phase 2.5 is complete. Proceed to Phase 3.**

---

### Phase 3 — Verify and Harden

**Runs in a single subagent (Agent tool) for a fresh context window.**

This phase does NOT write new test files. It verifies that Phase 2 tests are
well-structured, checks CI compliance, and fixes any issues — then completes
the tasks. The goal is to catch problems before CI does, not to add volume.

Spawn an Agent with this prompt:

```
You are verifying test quality and CI compliance for a batch of implemented
features. All features have tests from Phase 2 and have passed a code health
review. Your job is to verify the tests are efficient and CI-compliant, fix
any issues, and complete the tasks.

CRITICAL RULES — read before doing anything:
- ALWAYS commit and push BEFORE running tests. Tests can hang or time out.
  Committed code is recoverable; uncommitted code is lost.
- NEVER pipe ./bin/test through tail, head, grep, or any other command.
  The script writes output to a file — read that file with the Read tool.
- NEVER run ./bin/test in the background. Always foreground with timeout.
- If you are interrupted or a test times out, your work is safe because you
  committed first. Acknowledge the interruption neutrally and continue.

DO NOT write new test files. DO NOT add "comprehensive" test variants.
The tests from Phase 2 are the tests. Your job is quality, not quantity.

Follow these steps:

1. Read the handoff file at /tmp/claim-tasks-<worktree>.json. Collect all
   tests_written across all tasks.

2. For each test file, review against this checklist:

   **Fixture efficiency:**
   - Do tests share fixtures via conftest.py or class-scoped fixtures?
   - Are there function-scoped fixtures that could be class-scoped?

   **Duplication check:**
   - Does this test file duplicate the scope of an existing test file?
     (e.g., did Phase 2 create test_foo_new.py when test_foo.py exists?)
     If so, merge the new tests INTO the existing file and delete the new
     file.
   - Do any tests assert the same thing as an existing test?
     If so, delete the redundant test.

   **CI compliance:**
   - Will new test files be picked up by the correct CI configuration?
     Check .github/workflows/ to see how tests are organized.

   **Test value:**
   - Does each test assert something meaningfully different?
   - Remove tests that only check trivial properties already covered
     elsewhere.

3. Fix issues directly. Commit after each fix:
   ```bash
   git add -A && git commit -m "Test quality: <what>"
   git push --force-with-lease origin HEAD
   ```

4. Run scoped tests:
   ```bash
   ./bin/test
   ```
   Use the Bash tool's timeout parameter: 300000 (5 minutes).

5. If tests fail: diagnose, fix, commit and push, re-run. Maximum 2 cycles.
   **"Pre-existing" is NOT a valid reason to skip failures.** Fix or report.

6. Run type checks:
   ```bash
   mypy src/
   ```

7. Update the handoff file: set all task statuses to "verified".

Report: issues found and fixed, tests removed or merged, final test count,
and test results.
```

After the subagent completes:
- Read its output to verify success
- Read the handoff file to confirm all statuses are "verified"

Then:

1. Mark tasks complete (batch):
   ```bash
   ./bin/complete-tasks --summary "<what was done>" slug1 slug2 slug3
   ```

2. If any tasks have unresolved test failures, present them and ask the user
   whether to ship anyway or fix first.

**Phase 3 is complete. Auto-invoke `/ship`.**

---

### Auto-Ship

After Phase 3 succeeds, immediately invoke the `/ship` skill using the Skill
tool. Do not wait for user input.

---

## Handoff File

Path: `/tmp/claim-tasks-<worktree>.json`

This file is the contract between phases. Each phase reads it for context and
updates it with results. The main agent orchestrates by spawning subagents
and verifying the handoff file state after each.

### Fields

| Field | Set By | Description |
|-------|--------|-------------|
| `worktree` | Phase 1 | Worktree name |
| `main_repo` | Phase 1 | Absolute path to main repo root |
| `tasks[].index` | Phase 1 | 1-based task number |
| `tasks[].title` | Phase 1 | Exact task title from the task file's `# heading` |
| `tasks[].slug` | Phase 1 | Task slug |
| `tasks[].section` | Phase 1 | Priority section |
| `tasks[].roles` | Phase 1 | Roles array (e.g. `["steward"]`, `["designer", "editor"]`) |
| `tasks[].review_path` | Phase 1 | Path to review file (relative to main_repo) |
| `tasks[].has_review` | Phase 1 | Whether review file exists |
| `tasks[].status` | All | `pending` -> `implemented` -> `health-checked` -> `verified` |
| `tasks[].files_changed` | Phase 2 | Source files modified |
| `tasks[].tests_written` | Phase 2 | Test file paths |
| `tasks[].health_notes` | Phase 2.5 | Code health changes made to task's files |
| `tasks[].notes` | Phase 2/3 | Implementation notes |

---

## Presentation Format

After claiming (Phase 1, step 8), present:

```
===================================================
            TASKS CLAIMED
===================================================

Worktree: <name>
Claimed: N tasks | Skipped: M (claimed) | Already done: J | In-flight: K (open PRs)
Execution: merge-queue (implement -> health -> verify -> ship)

---------------------------------------------------
YOUR TASKS
---------------------------------------------------

1. [role] Task title
   Section: High Priority
   Files: src/package/config.py
   Review: fresh | stale | none

2. [role] Task title
   ...

---------------------------------------------------
ALREADY IMPLEMENTED (auto-completed)
---------------------------------------------------

  - Task title (code found in src/package/foo.py)

---------------------------------------------------
CLAIMED BY OTHERS
---------------------------------------------------

<worktree>:
  - [role] Task title (42 min ago)

---------------------------------------------------
IN-FLIGHT (OPEN PRs)
---------------------------------------------------

  - Task title (PR #145)

---------------------------------------------------
PR CONFLICT RISK
---------------------------------------------------

  - Task "Task title" overlaps with PR #123 "PR title"
    Shared dirs: src/package/

  (If no conflicts detected, omit this section entirely.)

===================================================
```

Between phases, announce transitions:

```
---------------------------------------------------
PHASE 2: Implementing 3 tasks with tests
---------------------------------------------------
Starting task 1/3: [steward] Fix config validation edge case
```

```
---------------------------------------------------
PHASE 2.5: Code health review on 12 changed files
---------------------------------------------------
```

```
---------------------------------------------------
PHASE 3: Verify and harden tests for 3 features
---------------------------------------------------
```

---

## Already-Implemented Check

Before claiming, verify each candidate task hasn't already been implemented on
main. Task files in `next-steps/active/` may lag behind the actual codebase —
code lands via PRs but the task file isn't always moved to `completed/`.

For each candidate task:

1. Read the task file from `next-steps/active/<slug>.md` to understand what
   the task asks for (the `files` field lists relevant source files).

2. **Quick codebase check**: Read the referenced files and grep for key
   indicators described in the task. For example:
   - A task asking to "add X to template Y" -> check if template Y already
     contains X
   - A task asking to "add command Z" -> grep for the command name in CLI files
   - A task asking to "add field F to model M" -> check the model definition

3. If the feature already exists on main, **do not claim it**. Instead:
   - Mark it complete immediately:
     ```bash
     ./bin/complete-tasks --summary "Already implemented in main" <slug>
     ```
   - Log it as skipped in the presentation output
   - Select the next eligible task as a replacement

This check is fast (a few file reads per task) and prevents wasting full
subagent cycles discovering work that's already done.

---

## Safety Rules

1. **Never `rm -f` claim files directly.** Always use `scripts/work-queue.sh
   release` or `release-all`.
2. **Never `cd` to the main repo before running the script.** The script
   resolves paths internally.
3. **Never edit claim JSON files directly.** Use the script's subcommands.
4. **Run `scripts/work-queue.sh validate`** if you suspect claim issues.

## Conflict Handling

The `try-claim` command handles conflicts automatically. Status codes:

- `CLAIMED` — successfully claimed
- `ALREADY_OWNED` — this worktree already owns it (counts as claimed)
- `EXPIRED_RECLAIMED` — reclaimed from an expired agent
- `CLAIMED_BY:<worktree>` — another active agent owns it (skipped)
- `SHIPPED_BY:<worktree>` — in the merge queue (skipped)
- `LOCK_FAILED` — transient lock contention (skipped)
- `DUPLICATE_TITLE` — same title under a different slug (skipped)

## Task Slug Generation

Slugs are auto-generated by the script from the task title. Do NOT manually
compute slugs — pass the exact title and a placeholder slug.

## Expiration

Claims have a TTL (default: 10 hours). After the TTL, other agents can
reclaim the task. To clean up expired claims:

```bash
scripts/work-queue.sh expire
```

## Integration

- **After completion**: `/ship` is auto-invoked (commits, PRs, merges, syncs)
- **Manual release**: Run `/release-tasks` to give back unclaimed work
