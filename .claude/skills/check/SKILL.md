---
name: check
version: 1.0.0
description: >
  Runs full validation pipeline: lint, test, review, and docs.
  Use before committing to ensure code quality.
argument-hint: "[path or empty for full project]"
disable-model-invocation: true
---

# Full Project Validation

Run complete code quality checks in sequence: linting, testing, code review, and documentation.

## Smart Path Handling

Before running pipeline steps:

1. **Determine scope**:
   - If path argument provided: Use it for all steps
   - If no path: Default to "recent" for review/bash-review, full project for lint/test/docs

2. **Estimate size**:
   - Count Python files in target path
   - If >50 files: Inform user that parallel batching will be used for review/docs
   - If path is a single file: Skip batching optimization

3. **Pass scope to each step**:
   - Lint: Pass path argument (ruff handles large codebases efficiently)
   - Test: Pass path argument (pytest handles selective testing well)
   - Review: Pass path or "recent" - skill will auto-batch if needed
   - Docs: Pass path - skill will auto-batch if needed
   - Bash Review: Pass path or "recent" - handles shell scripts separately

## Pipeline Steps

Execute these in order, stopping if critical failures occur:

### Step 1: Lint
Run `/lint [path]` to fix formatting and check for issues.

If ruff/mypy report errors that cannot be auto-fixed, note them but continue.

### Step 2: Test
Run `/test [path]` to execute the test suite with coverage.

If tests fail, note the failures but continue to review.

### Step 3: Review
Run `/review [path or recent]` to check for common issues in changed code.

The review skill will automatically batch large file sets using parallel agents.

### Step 4: Docs
Run `/docs check [path]` to verify documentation consistency.

The docs skill will automatically batch large file sets using parallel agents.

### Step 5: Bash Review
Run `/bash-review [path or recent]` to check shell scripts for issues.

If no `.sh` files exist in the project, skip this step and mark as SKIP in the report.

## Output Format

Provide a consolidated validation report:

```
/check v1.0.0
=====================================
        VALIDATION REPORT
=====================================
Scope: [path or "full project" or "recent changes"]
Files analyzed: X Python, Y shell scripts, Z docs
[Performance: Used parallel batching for review/docs]

LINT ............ [PASS/FAIL]
  - X issues auto-fixed
  - Y issues remaining

TEST ............ [PASS/FAIL]
  - X passed, Y failed, Z skipped
  - Coverage: XX%

REVIEW .......... [PASS/FAIL]
  - X critical, Y warnings, Z suggestions
  - [Batched: N files across M parallel agents in Xs]

DOCS ............ [PASS/FAIL]
  - X errors, Y warnings
  - [Batched: N files across M parallel agents in Xs]

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
