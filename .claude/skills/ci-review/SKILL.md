---
name: ci-review
description: >
  Check the status of a GitHub Actions CI run, diagnose failures, and suggest fixes.
  Inspects job logs, identifies root causes, and proposes actionable remediation.
argument-hint: "[job name, run ID, 'queue', or empty for latest]"
allowed-tools: Read, Glob, Grep, Bash(./bin/ci-status *), Bash(gh *), Bash(cd * && gh *), Bash(curl *), Bash(source *)
---

# CI Review & Diagnosis

Inspect a GitHub Actions workflow run, diagnose failures, and determine fixes.

## Step 1: Identify the Run

- **No argument**: Most recent run on current branch or `main`
- **`queue`**: Latest merge queue run (`merge_group` event)
- **Run ID** (numeric): That specific run
- **Job name**: Focus on that job in latest run

```bash
# Prefer ./bin/ci-status when available:
./bin/ci-status list
./bin/ci-status latest --branch $(git branch --show-current)
./bin/ci-status latest --event merge_group

# Fallback:
gh run list --limit 5
```

## Step 2: Get Run Overview

```bash
./bin/ci-status jobs <RUN_ID>
./bin/ci-status failed-steps <RUN_ID>

# Fallback:
gh run view <RUN_ID> --json jobs
```

```
═══════════════════════════════════════════════════
              CI RUN #<number>
═══════════════════════════════════════════════════
Run:    <title>
Branch: <branch>
Source: <PR #N if merge queue>
Event:  <pull_request | push | merge_group>
Status: <status>

Jobs:
  Lint .............. success
  Test .............. failure    <-- FOCUS
  Type Check ........ success
```

## Step 3: Diagnose Failures

```bash
./bin/ci-status log-failed <RUN_ID>
./bin/ci-status log-job <JOB_ID>

# Fallback:
gh run view <RUN_ID> --log-failed
```

## Step 4: Classify

| Category | Examples | Fix location |
|----------|----------|-------------|
| **Test failure** | Assertion error, import error | `tests/` or `src/` |
| **Lint/format** | Ruff check failure | Run `ruff check --fix .` |
| **Type error** | mypy annotation errors | Source files |
| **Infrastructure** | Secret missing, timeout | `.github/workflows/` |
| **Flaky/transient** | Network blip, timeout | Retry or add resilience |
| **Configuration** | Missing env var, stale cache | `pyproject.toml`, CI config |

## Step 5: Cross-Reference with Code

Read failing test and source code it exercises. Check CI config files.

## Step 6: Report

```
═══════════════════════════════════════════════════
              DIAGNOSIS
═══════════════════════════════════════════════════

Job: Test
Step: Run pytest
Status: FAILED

FAILURE #1:
  Test:     test_config::test_validate_empty
  Category: Test failure
  Error:    AssertionError
  Root cause: validate() doesn't raise for empty input
  Fix: Add empty check in src/your_package/config.py:42

═══════════════════════════════════════════════════
              REMEDIATION PLAN
═══════════════════════════════════════════════════
1. [ ] Fix validation in config.py
2. [ ] Re-run: gh run rerun <RUN_ID>
```

## Merge Queue

Merge queue runs differ from PR CI:
- Triggered by `merge_group` event
- Run on temporary merge commit (PR + latest main)
- Branch: `gh-readonly-queue/main/pr-<N>-<sha>`

```bash
./bin/ci-status latest --event merge_group
```

| Symptom | Root cause | Fix |
|---------|-----------|-----|
| Pass on PR, fail in queue | Conflict with concurrent PR | Rebase and re-queue |
| Coverage threshold not met | PR CI skips coverage | Add tests |
| Flaky test | Inconsistent under full suite | Fix flaky test |

Re-queue after fixing:
```bash
gh pr merge <PR_NUMBER> --merge --auto
```

## Re-running

```bash
./bin/ci-status rerun <RUN_ID> --failed

# Fallback:
gh run rerun <RUN_ID> --failed
```
