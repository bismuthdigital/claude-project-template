---
name: check
description: >
  Runs full validation pipeline: lint, test, and review.
  Use before committing to ensure code quality.
argument-hint: "[path or empty for full project]"
disable-model-invocation: true
---

# Full Project Validation

Run complete code quality checks in sequence: linting, testing, and code review.

## Pipeline Steps

Execute these in order, stopping if critical failures occur:

### Step 1: Lint
Run `/lint` to fix formatting and check for issues.

If ruff/mypy report errors that cannot be auto-fixed, note them but continue.

### Step 2: Test
Run `/test` to execute the test suite with coverage.

If tests fail, note the failures but continue to review.

### Step 3: Review
Run `/review recent` to check for common issues in changed code.

### Step 4: Bash Review
Run `/bash-review recent` to check shell scripts for issues.

If no `.sh` files exist in the project, skip this step and mark as SKIP in the report.

## Output Format

Provide a consolidated validation report:

```
=====================================
        VALIDATION REPORT
=====================================

LINT ............ [PASS/FAIL]
  - X issues auto-fixed
  - Y issues remaining

TEST ............ [PASS/FAIL]
  - X passed, Y failed, Z skipped
  - Coverage: XX%

REVIEW .......... [PASS/FAIL]
  - X critical, Y warnings, Z suggestions

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

Provide a recommended order for addressing issues (critical first).
