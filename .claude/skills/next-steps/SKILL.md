---
name: next-steps
description: >
  Identifies and maintains project next steps. Reviews existing NEXT-STEPS.md,
  consolidates scattered TODOs, analyzes code and commits for opportunities,
  or asks the user for goals when none are found.
argument-hint: "[refresh|clean]"
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(git log *), Bash(git diff *), AskUserQuestion
---

# Next Steps

Identify, consolidate, and maintain actionable next steps for the project. Works through a priority cascade: existing next-steps file, scattered TODOs, code/commit analysis, then user input.

## What This Skill Does

1. **Check** for an existing `NEXT-STEPS.md` — review and refresh it if found
2. **Scan** for scattered TODOs, FIXMEs, and HACKs across the codebase
3. **Analyze** code, documentation, and recent commits for improvement opportunities
4. **Ask** the user for their goals if no next steps can be inferred
5. **Write** or update `NEXT-STEPS.md` with prioritized, actionable items

## Arguments

- **(none)**: Run the full cascade — check file, scan TODOs, analyze, ask if needed
- **refresh**: Force a full re-analysis even if `NEXT-STEPS.md` already exists
- **clean**: Remove completed items and re-prioritize the remaining list

## Process

### Phase 1: Check for Existing Next Steps File

```bash
# Look for existing next-steps files (case-insensitive variants)
```

Search for: `NEXT-STEPS.md`, `NEXT_STEPS.md`, `next-steps.md`, `TODO.md`, `ROADMAP.md`

**If found** (and argument is not `refresh`):
1. Read the file
2. Review each item for staleness:
   - Check if referenced files/functions still exist
   - Check recent commits to see if items were already completed
   - Check if items reference outdated patterns or removed code
3. Present a status report (see Output Format)
4. Offer to update the file: remove completed items, flag stale ones, re-prioritize

**If found and argument is `refresh`**: Skip to Phase 2 but preserve any items from the existing file that are still relevant.

**If found and argument is `clean`**: Remove completed/stale items, re-prioritize remaining, and update the file.

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

**If >5 scattered TODOs found**: Recommend consolidating them into `NEXT-STEPS.md` and offer to do so.

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

## Writing NEXT-STEPS.md

When creating or updating the file, use this format:

```markdown
# Next Steps

> Last updated: YYYY-MM-DD

## High Priority

- [ ] **Item title** — Brief description of what needs to be done
  - Context: Why this matters or what triggered it
  - Files: `path/to/relevant/file.py`

## Medium Priority

- [ ] **Item title** — Brief description
  - Context: Why this matters

## Low Priority / Nice to Have

- [ ] **Item title** — Brief description

## Completed

- [x] **Item title** — What was done *(completed YYYY-MM-DD)*
```

Guidelines for writing items:
- Each item should be **actionable** — someone reading it should know what to do
- Include file paths when referencing specific code
- Group related items under a single heading rather than listing them separately
- Limit to 10-15 active items maximum — if more exist, keep only the most important
- Items sourced from inline TODOs should reference the original location
- Move completed items to the Completed section rather than deleting them (keeps a record)

## Output Format

### When an existing file is found

```
═══════════════════════════════════════════════════
            NEXT STEPS REVIEW
═══════════════════════════════════════════════════

File: NEXT-STEPS.md (last updated: YYYY-MM-DD)

───────────────────────────────────────────────────
STATUS
───────────────────────────────────────────────────
✓ Item 1 — Still relevant, no progress detected
✓ Item 2 — Still relevant
✗ Item 3 — Appears completed (see commit abc1234)
⚠ Item 4 — References file that no longer exists
? Item 5 — Cannot determine status

Active: X items | Completed: Y | Stale: Z

───────────────────────────────────────────────────
INLINE TODOs FOUND
───────────────────────────────────────────────────
3 TODOs not captured in NEXT-STEPS.md:
  src/module.py:42    — TODO: Add retry logic
  src/utils.py:18     — FIXME: Handle empty input
  tests/conftest.py:7 — TODO: Add integration fixtures

───────────────────────────────────────────────────
RECOMMENDATION
───────────────────────────────────────────────────
• Remove 1 completed item
• Remove 1 stale item
• Add 3 inline TODOs to the file

Say **update** to apply these changes, or **refresh**
to do a full re-analysis.
═══════════════════════════════════════════════════
```

### When no file exists (new analysis)

```
═══════════════════════════════════════════════════
            NEXT STEPS ANALYSIS
═══════════════════════════════════════════════════

No NEXT-STEPS.md found. Analyzing project state...

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
• 3 source files have no corresponding tests
• README.md contains template placeholder text
• No CI/CD configuration found
• 2 public functions missing type hints

───────────────────────────────────────────────────
RECENT COMMITS SUGGEST
───────────────────────────────────────────────────
• Active work on skill system — may need docs update
• New features added without test coverage

───────────────────────────────────────────────────
PROPOSED NEXT-STEPS.md
───────────────────────────────────────────────────
[Preview of the file that will be created]

Say **create** to write NEXT-STEPS.md, or provide
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
