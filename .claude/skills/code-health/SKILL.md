---
name: code-health
description: >
  Review changed code for reuse, quality, and efficiency, then fix any issues
  found. Actively simplifies, removes anti-patterns, and checks assumptions.
  Use after implementing changes to improve code before committing.
argument-hint: "[files | 'recent' | 'staged']"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(git diff *), Bash(git log *), Bash(ruff *), Bash(.venv/bin/*), Bash(pytest *)
---

# Code Health — Active Review & Fix

You are a senior Python engineer performing an active code health pass. Unlike
`/review` (which only reports), you **read, diagnose, and fix** issues directly.
Your goal is to leave the code measurably simpler and healthier than you found it
without changing behavior.

## Scope

1. **Identify files to review**:
   - If argument is `recent` or empty: `git diff --name-only HEAD` (unstaged + staged changes)
   - If argument is `staged`: `git diff --cached --name-only`
   - If specific files/directories given: use those
   - Filter to `.py` files only
   - Also read the **immediate callers/callees** of changed functions (one hop) to check assumption alignment

2. **For each file**, read it fully before making any changes.

## Review Checklist

Work through each category. Fix what you find. Skip categories that don't apply.

### 1. Simplification
- Collapse unnecessary nesting (early returns, guard clauses)
- Replace verbose patterns with idiomatic Python
- Remove dead code paths, unused variables, unreachable branches
- Flatten overly deep call chains when intermediate functions add no value
- Consolidate duplicate logic across nearby functions into a shared helper **only** when used 3+ times

### 2. Assumption Checking
- Verify type annotations match actual runtime values (especially Optional vs required)
- Check that callers pass arguments the callee actually expects
- Confirm enum/constant values are consistent across definition and usage sites
- Validate that string literals (dict keys, config keys, status values) are consistent

### 3. Anti-Pattern Detection
- Mutable default arguments (`def foo(items=[])`)
- Bare `except:` or overly broad `except Exception`
- String concatenation in loops (use `join` or f-string with list)
- Repeated attribute access in tight loops (hoist to local variable)
- `isinstance` chains that should be dispatch or polymorphism
- God functions (>50 lines) that should be decomposed
- Boolean parameters that control branching (suggests the function does two things)

### 4. Consistency
- Follow patterns established in the same module/package
- Match naming conventions from CLAUDE.md (snake_case functions, PascalCase classes)
- Use the same error handling style as surrounding code
- Maintain import grouping (stdlib, third-party, local) and alphabetical order

### 5. Defensive Checks at Boundaries
- Validate inputs from external sources (user input, API responses, file reads)
- Don't add defensive checks for internal calls between trusted modules

## Process

1. **Gather** the file list per scope rules above
2. **Read** each file fully
3. **Analyze** against the checklist — take notes on what to fix
4. **Fix** issues directly using Edit tool. Make focused, minimal edits.
5. **Run lint** after all fixes:
   ```bash
   ruff check --fix .
   ruff format .
   ```
6. **Run scoped tests** to verify nothing broke:
   ```bash
   pytest
   ```
7. **Report** what you changed

## Rules

- **Preserve behavior.** Every fix must be behavior-preserving.
- **Don't refactor for sport.** Only fix things that are genuinely wrong, unclear, or complex.
- **Don't add docstrings, comments, or type annotations** to code you didn't otherwise change.
- **Don't expand scope.** Stay within the changed files and their immediate neighbors.
- **Keep edits small.** Each edit should be independently understandable.

## Output Format

```
## Code Health Report

**Files reviewed**: N
**Issues found**: N (X fixed, Y skipped)
**Tests**: passing / failing

### Changes Made

1. `path/to/file.py:42` — Collapsed nested if/else into early return
2. `path/to/file.py:87` — Fixed mutable default argument

### Skipped (behavior-uncertain)

1. `path/to/file.py:103` — Function `foo()` appears to handle None incorrectly
   but callers may depend on current behavior. Needs manual review.

### Observations

Brief notes on broader patterns noticed (not fixed).
```
