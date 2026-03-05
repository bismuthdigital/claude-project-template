---
name: ci-review
description: >
  Check the status of a GitHub Actions CI run, diagnose failures, and suggest fixes.
  Inspects job logs, identifies root causes, and proposes actionable remediation.
argument-hint: "[job name, run ID, or empty for latest]"
allowed-tools: Read, Glob, Grep, Bash(gh *), Bash(cd * && gh *), Bash(curl *), Bash(source *)
---

# CI Review & Diagnosis

Inspect a GitHub Actions workflow run, diagnose failures, and determine fixes.

## Process

### Step 1: Identify the Run

Determine which run to inspect based on the argument:

- **No argument**: Use the most recent run on the current branch or `main`
- **Run ID** (numeric): Inspect that specific run
- **Job name** (e.g., `test`, `lint`, `build`): Find the most recent run and focus on that job

```bash
# List recent runs
gh run list --limit 5

# If a specific run ID was given:
gh run view <RUN_ID>

# If looking for latest on current branch:
gh run list --branch $(git branch --show-current) --limit 1
```

### Step 2: Get Run Overview

Fetch the run status and all job results:

```bash
# Get job-level status summary
gh run view <RUN_ID> --json jobs --jq '.jobs[] | {name: .name, status: .status, conclusion: .conclusion}'

# Get step-level detail for each job
gh run view <RUN_ID> --json jobs --jq '.jobs[] | {name: .name, conclusion: .conclusion, steps: [.steps[] | select(.conclusion != "success" and .conclusion != "skipped") | {name: .name, conclusion: .conclusion}]}'
```

Report the overall status:

```
===============================================
              CI RUN #<number>
===============================================
Run:    <display title>
Branch: <branch>
Event:  <pull_request | push | merge_group>
Status: <status> (<conclusion>)
URL:    <url>

Jobs:
  Lint .............. success
  Test .............. success
  Type Check ........ failure    <-- FOCUS
  Deploy ............ skipped
```

### Step 3: Diagnose Failures

For any failed job, get the detailed logs:

```bash
# Get failed step logs (most useful — only shows failing steps)
gh run view <RUN_ID> --log-failed

# If --log-failed is empty (job was skipped, not failed), get full job log:
gh run view <RUN_ID> --log | grep -A 50 "<Job Name>"
```

If the argument specified a particular job name, focus on that job's logs even if it passed — the user wants to verify it.

For **passed** jobs where the user wants verification:

```bash
# Get the full log for a specific job
gh run view <RUN_ID> --json jobs --jq '.jobs[] | select(.name == "<Job Name>") | .databaseId'
# Then:
gh run view --job <JOB_ID> --log
```

### Step 4: Analyze & Classify

Classify the failure into one of these categories:

| Category | Examples | Fix location |
|----------|----------|-------------|
| **Test failure** | Assertion error, import error, fixture failure | `tests/` or `src/` |
| **Lint/format** | Ruff check failure, formatting issues | Run `ruff check --fix . && ruff format .` |
| **Type error** | mypy annotation errors | Source files with type annotations |
| **Infrastructure** | Secret missing, network timeout, dependency install fail | `.github/workflows/` or GitHub settings |
| **Flaky/transient** | Timeout, network blip, resource exhaustion | Retry or add resilience |
| **Configuration** | Missing env var, wrong marker expression, stale cache | `pyproject.toml`, CI config, GitHub secrets |

For each failure, determine:

1. **What failed** — the exact test, step, or command
2. **Why it failed** — the root cause from the log output
3. **Where to fix it** — the file(s) and line(s) to change
4. **How to fix it** — a specific, actionable remediation

### Step 5: Cross-Reference with Code

For test failures, look at the failing test and the code it exercises:

```bash
# Read the failing test file
# Read the source file being tested
```

For infrastructure issues, check:
- `.github/workflows/` for CI configuration
- `pyproject.toml` for test/lint configuration
- GitHub secrets configuration

### Step 6: Report

Present a structured diagnosis:

```
===============================================
              DIAGNOSIS
===============================================

Job: Test
Step: Run pytest
Status: FAILED

-----------------------------------------------
FAILURE #1
-----------------------------------------------
Test:     test_config::test_validate_empty_input
Category: Test failure
Error:    AssertionError: expected ValueError, got None

Root cause:
  The validate() function does not raise ValueError
  for empty string input — it returns None silently.

Fix:
  Add empty string check in src/your_package/config.py:42
  before the main validation logic.

Files:
  - src/your_package/config.py:42
  - tests/test_config.py:67

-----------------------------------------------
FAILURE #2 (if any)
-----------------------------------------------
...

===============================================
              REMEDIATION PLAN
===============================================

1. [ ] <first fix step>
2. [ ] <second fix step>
3. [ ] Re-run: gh run rerun <RUN_ID>
```

## Special Cases

### Merge Queue

If your repo uses GitHub's merge queue (`merge_group` event), merge queue CI runs differ from PR CI:
- Triggered by `merge_group` event (not `pull_request`)
- Runs on a temporary merge commit combining the PR with latest `main`
- May run a stricter test suite than PR CI
- Failures block the PR from merging

To inspect merge queue runs:
```bash
gh run list --event merge_group --limit 5
```

### Skipped Jobs

If a job shows as "skipped":
- Check the `if:` condition in the workflow YAML
- Jobs with `needs:` are skipped if their dependency failed

### Re-running

After applying a fix:

```bash
# Re-run only failed jobs
gh run rerun <RUN_ID> --failed

# Re-run entire workflow
gh run rerun <RUN_ID>
```

## Notes

- The `--log-failed` flag is the fastest way to get diagnostic info
- Always cross-reference CI failures with local reproduction when possible
- For flaky tests, check if the test passes locally before adding retry logic
