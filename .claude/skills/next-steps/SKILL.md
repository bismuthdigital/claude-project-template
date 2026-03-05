---
name: next-steps
description: >
  Identifies and maintains project next steps. Reviews existing NEXT-STEPS.md,
  consolidates scattered TODOs, analyzes code and commits for opportunities,
  or asks the user for goals when none are found.
argument-hint: "[refresh|clean]"
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(git log *), Bash(git diff *), Bash(*/task-format.py *), Bash(ls *), AskUserQuestion
---

# Next Steps

Identify, consolidate, and maintain actionable next steps for the project. Works through a priority cascade: existing next-steps file, scattered TODOs, code/commit analysis, then user input.

## Task Storage Modes

This skill supports two storage modes:

### Per-Task Files (preferred)

Tasks stored as individual `.md` files in `next-steps/active/` with YAML frontmatter:

```
next-steps/
├── active/          # Current tasks
│   ├── t001-add-retry-logic.md
│   └── t002-fix-validation.md
└── completed/       # Archived tasks
    └── t000-initial-setup.md
```

Each task file has YAML frontmatter with fields like `id`, `title`, `role`, `priority`, `section`, and optional `depends_on`.

Use `scripts/task-format.py` to manage per-task files:
- `render` — generate `NEXT-STEPS.md` from task files
- `split` — migrate monolithic `NEXT-STEPS.md` to per-task files
- `create-task` — create a new task file
- `complete-task` — move a task to `completed/`
- `validate` — check all task files for format compliance
- `stats` — summary statistics

### Monolithic (legacy)

Tasks stored directly in `NEXT-STEPS.md`. This mode is auto-detected when `next-steps/` directory does not exist.

**Note:** `NEXT-STEPS.md` is a generated file when using per-task mode and should not be committed to git. It is rebuilt from task files via `scripts/task-format.py render`.

## What This Skill Does

1. **Check** for existing tasks — per-task files or `NEXT-STEPS.md`
2. **Scan** for scattered TODOs, FIXMEs, and HACKs across the codebase
3. **Analyze** code, documentation, and recent commits for improvement opportunities
4. **Ask** the user for their goals if no next steps can be inferred
5. **Write** or update tasks with prioritized, actionable items

## Arguments

- **(none)**: Run the full cascade — check file, scan TODOs, analyze, ask if needed
- **refresh**: Force a full re-analysis even if tasks already exist
- **clean**: Remove completed items and re-prioritize the remaining list

## Process

### Phase 1: Check for Existing Tasks

First check for per-task file mode:
```bash
ls next-steps/active/ 2>/dev/null
```

If per-task files exist:
1. Render the current state: `scripts/task-format.py render`
2. Get stats: `scripts/task-format.py stats`
3. Validate format: `scripts/task-format.py validate`
4. Review freshness: `scripts/task-format.py review-freshness`

If no per-task files, look for monolithic files: `NEXT-STEPS.md`, `NEXT_STEPS.md`, `next-steps.md`, `TODO.md`, `ROADMAP.md`

**If found** (and argument is not `refresh`):
1. Read the file
2. Review each item for staleness:
   - Check if referenced files/functions still exist
   - Check recent commits to see if items were already completed
   - Check if items reference outdated patterns or removed code
3. Present a status report (see Output Format)
4. Offer to update the file: remove completed items, flag stale ones, re-prioritize

**If found and argument is `refresh`**: Skip to Phase 2 but preserve any items from the existing file that are still relevant.

**If found and argument is `clean`**: Remove completed/stale items, re-prioritize remaining, and update the file. In per-task mode, use `scripts/task-format.py complete-task` for each completed task.

### Phase 2: Scan for Scattered TODOs

Search the codebase for inline markers:

```
# Patterns to search for
TODO, FIXME, HACK, XXX, OPTIMIZE, REFACTOR, NOTE (when followed by actionable text)
```

**Scope**: All source files, config files, and documentation. Exclude:
- `.git/`, `node_modules/`, `.venv/`, `__pycache__/`, `dist/`, `build/`
- Third-party or vendored code

For each match found:
1. Record the file, line number, marker type, and full comment text
2. Group by theme (e.g., "testing", "performance", "documentation", "refactoring")
3. Assess priority based on marker type:
   - `FIXME` / `HACK` / `XXX` → High priority (something is broken or fragile)
   - `TODO` → Medium priority (planned work)
   - `OPTIMIZE` / `REFACTOR` → Lower priority (improvement opportunities)

**If >5 scattered TODOs found**: Recommend consolidating them into task files (or NEXT-STEPS.md) and offer to do so.

**If 1-5 found**: Include them in the analysis but don't necessarily recommend a separate file.

**If 0 found**: Continue to Phase 3.

### Phase 3: Analyze Code, Docs, and Commits

When no explicit next steps or TODOs exist, infer opportunities from the project state.

#### 3a. Recent Commit Analysis

```bash
# Review recent commit history for patterns
git log --oneline -20
git log --format="%s" -20
```

Look for:
- Features that were started but may need follow-up (e.g., "Add X" without corresponding tests)
- Bug fixes that might indicate deeper issues
- Patterns in commit messages suggesting ongoing work areas
- WIP or draft commits that were never finalized

#### 3b. Code Quality Signals

Scan for common improvement opportunities:
- **Missing tests**: Source files in `src/` without corresponding test files in `tests/`
- **Missing documentation**: Public modules or packages without docstrings
- **Missing type hints**: Public functions without type annotations
- **Configuration gaps**: `pyproject.toml` missing common sections (e.g., no test config, no lint config)
- **Security**: Hardcoded values that should be environment variables
- **Missing CI/CD**: No `.github/workflows/` directory

#### 3c. Documentation Gaps

Check for:
- `README.md` with placeholder text (e.g., "[Brief description", template text still present)
- Missing `CHANGELOG.md` when there are multiple releases/tags
- `CLAUDE.md` with template defaults not customized
- Missing `CONTRIBUTING.md` for public repos

#### 3d. Dependency Health

If `pyproject.toml` or `requirements.txt` exists:
- Note if there are no pinned versions (risk of breaking changes)
- Flag if dev dependencies are missing (no test framework, no linter)

### Phase 4: Ask the User

If Phases 1-3 yielded fewer than 3 actionable items, ask the user:

> "I didn't find many documented next steps for this project. To help build a roadmap, can you share:"

Ask using AskUserQuestion with relevant prompts:
1. "What is the primary goal for this project right now?"
2. "Are there specific features or improvements you have in mind?"

Incorporate their answers into the next steps file alongside any items found in earlier phases.

## Writing Tasks

### Per-Task File Mode

Use `scripts/task-format.py create-task` to create new tasks:

```bash
scripts/task-format.py create-task --title "Task title" --role dev --priority high --section "High Priority" --description "What needs to be done"
```

### Monolithic Mode

When creating or updating NEXT-STEPS.md directly, use this format:

```markdown
# Next Steps

> Last updated: YYYY-MM-DD

## High Priority

- [ ] **[role] Item title** — Brief description of what needs to be done
  - Context: Why this matters or what triggered it
  - Files: `path/to/relevant/file.py`

## Medium Priority

- [ ] **[role] Item title** — Brief description
  - Context: Why this matters

## Low Priority / Nice to Have

- [ ] **[role] Item title** — Brief description

## Completed

- [x] **[role] Item title** — What was done *(completed YYYY-MM-DD)*
```

Guidelines for writing items:
- Each item should be **actionable** — someone reading it should know what to do
- Include file paths when referencing specific code
- Group related items under a single heading rather than listing them separately
- Limit to 10-15 active items maximum — if more exist, keep only the most important
- Items sourced from inline TODOs should reference the original location
- Move completed items to the Completed section (monolithic) or `completed/` directory (per-task)
- Valid role tags: `dev`, `design`, `docs`, `test`, `ops`, `security`

## Output Format

### When existing tasks are found

```
═══════════════════════════════════════════════════
            NEXT STEPS REVIEW
═══════════════════════════════════════════════════

File: NEXT-STEPS.md (last updated: YYYY-MM-DD)
Mode: per-task files (12 active, 5 completed)

───────────────────────────────────────────────────
STATUS
───────────────────────────────────────────────────
OK  Item 1 — Still relevant, no progress detected
OK  Item 2 — Still relevant
DONE  Item 3 — Appears completed (see commit abc1234)
STALE  Item 4 — References file that no longer exists
?   Item 5 — Cannot determine status

Active: X items | Completed: Y | Stale: Z

───────────────────────────────────────────────────
INLINE TODOs FOUND
───────────────────────────────────────────────────
3 TODOs not captured in tasks:
  src/module.py:42    — TODO: Add retry logic
  src/utils.py:18     — FIXME: Handle empty input
  tests/conftest.py:7 — TODO: Add integration fixtures

───────────────────────────────────────────────────
RECOMMENDATION
───────────────────────────────────────────────────
- Remove 1 completed item
- Remove 1 stale item
- Add 3 inline TODOs to task list

Say **update** to apply these changes, or **refresh**
to do a full re-analysis.
═══════════════════════════════════════════════════
```

### When no tasks exist (new analysis)

```
═══════════════════════════════════════════════════
            NEXT STEPS ANALYSIS
═══════════════════════════════════════════════════

No tasks found. Analyzing project state...

───────────────────────────────────────────────────
INLINE TODOs (X found)
───────────────────────────────────────────────────
HIGH:
  src/module.py:42    — FIXME: Race condition in handler
  src/utils.py:18     — HACK: Temporary workaround for API bug

MEDIUM:
  src/cli.py:95       — TODO: Add --verbose flag
  tests/conftest.py:7 — TODO: Add integration fixtures

───────────────────────────────────────────────────
CODE ANALYSIS
───────────────────────────────────────────────────
- 3 source files have no corresponding tests
- README.md contains template placeholder text
- No CI/CD configuration found
- 2 public functions missing type hints

───────────────────────────────────────────────────
RECENT COMMITS SUGGEST
───────────────────────────────────────────────────
- Active work on skill system — may need docs update
- New features added without test coverage

───────────────────────────────────────────────────
PROPOSED TASKS
───────────────────────────────────────────────────
[Preview of tasks that will be created]

Say **create** to write tasks, or provide
your own priorities to include.
═══════════════════════════════════════════════════
```

## Error Handling

| Situation | Action |
|-----------|--------|
| Multiple next-steps files found | Ask user which to use as canonical |
| Very large codebase (>100 files) | Use Task tool with parallel agents for TODO scanning |
| Git history unavailable | Skip commit analysis, note in output |
| No source code found | Skip code analysis, focus on documentation and user goals |

## Examples

```
/next-steps                # Full analysis cascade
/next-steps refresh        # Force re-analysis, rebuild from scratch
/next-steps clean          # Remove completed items, re-prioritize
```
