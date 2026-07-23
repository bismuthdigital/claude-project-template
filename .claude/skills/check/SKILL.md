---
name: check
description: >
  Runs the full validation pipeline: lint, test, code-review, docs, and
  bash-review, then aggregates the results into one report. Use before
  committing to ensure code quality.
argument-hint: "[path or empty for full project]"
disable-model-invocation: true
allowed-tools: Skill, Read, Glob, Grep, Bash(git diff *), Bash(git status *)
---

# Full Project Validation

Run complete code quality checks in sequence, then aggregate them into a single
report. This skill's value is the **aggregation** — the individual steps are
delegated to the built-in and project skills below.

## Smart Path Handling

Before running pipeline steps:

1. **Determine scope**:
   - If path argument provided: use it for all steps
   - If no path: default to "recent" (changed files) for review/bash-review, full project for lint/test/docs

2. **Pass scope to each step**:
   - Lint: pass path (ruff handles large codebases efficiently)
   - Test: pass path (pytest handles selective testing well)
   - Review: pass path or "recent"
   - Docs: pass path
   - Bash Review: pass path or "recent"

## Pipeline Steps

Execute these in order, stopping if critical failures occur:

### Step 1: Lint
Run `/lint [path]` to fix formatting and check for issues.
If ruff/mypy report errors that cannot be auto-fixed, note them but continue.

### Step 2: Test
Run `/test [path]` to execute the test suite with coverage.
If tests fail, note the failures but continue to review.

### Step 3: Review
Run the built-in **`/code-review`** for correctness bugs plus reuse/efficiency
across the changed code. For large diffs it has a cloud multi-agent `ultra`
mode — prefer that over hand-rolling parallel agents here.

Then run the project **`/project-review [path or recent]`** lens for the two
checks the built-in does not cover: resiliency/recovery and
virtual-environment hygiene.

### Step 4: Docs
Run `/docs check [path]` to verify documentation consistency.

### Step 5: Bash Review
Run `/bash-review [path or recent]` to check shell scripts for issues.
If no `.sh` files exist in the project, skip this step and mark as SKIP.

## Output Format

Provide a consolidated validation report:

```
=====================================
        VALIDATION REPORT
=====================================
Scope: [path or "full project" or "recent changes"]
Files analyzed: X Python, Y shell scripts, Z docs

LINT ............ [PASS/FAIL]
  - X issues auto-fixed
  - Y issues remaining

TEST ............ [PASS/FAIL]
  - X passed, Y failed, Z skipped
  - Coverage: XX%

REVIEW .......... [PASS/FAIL]
  - code-review: X critical, Y warnings, Z suggestions
  - project lens: X resiliency, Y venv-hygiene

DOCS ............ [PASS/FAIL]
  - X errors, Y warnings

BASH REVIEW ..... [PASS/FAIL/SKIP]
  - X critical, Y warnings, Z suggestions
  - (or "No shell scripts found")

-------------------------------------
OVERALL: [READY TO COMMIT / NEEDS WORK]
-------------------------------------
```

### If NEEDS WORK

List the specific issues that need attention:

1. **[LINT]** file.py:42 - description
2. **[TEST]** test_foo.py::test_bar - assertion failed
3. **[REVIEW]** file.py:87 - potential bug
4. **[DOCS]** README.md - command example outdated

Provide a recommended order for addressing issues (critical first).
