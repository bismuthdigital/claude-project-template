# Claim Tasks — Reference

On-demand reference for `/claim-tasks`. Each section is loaded when the
corresponding step of SKILL.md points here.

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

## Phase 2.5 Subagent Prompt

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

---

## Phase 3 Subagent Prompt

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

## Task Slug Generation

Slugs are auto-generated by the script from the task title. Do NOT manually
compute slugs — pass the exact title and a placeholder slug.

## Expiration

Claims have a TTL (default: 10 hours). After the TTL, other agents can
reclaim the task. To clean up expired claims:

```bash
scripts/work-queue.sh expire
```
