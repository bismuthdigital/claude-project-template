---
name: test
description: >
  Runs the test suite with pytest and coverage reporting.
  Use to verify code changes and check test coverage.
argument-hint: "[test path or -k filter]"
allowed-tools: Bash(pytest *), Bash(python -m pytest *), Bash(python3 -m pytest *), Bash(source *)
---

# Test Execution

Run pytest with coverage on the specified tests or entire test suite.

## Process

1. Activate virtual environment if present
2. Run pytest with coverage enabled
3. Report results and coverage summary
4. Highlight any failures or low coverage areas

## Commands

```bash
# Activate venv if it exists
source .venv/bin/activate 2>/dev/null || true

# Run tests with coverage
# If arguments provided, pass them through
# Otherwise run all tests
python -m pytest ${ARGUMENTS:-.} \
    --cov \
    --cov-report=term-missing \
    -v \
    --tb=short
```

## Output

Report clearly:

### Test Results
- **Passed**: X tests
- **Failed**: Y tests
- **Skipped**: Z tests
- **Duration**: N seconds

### Failures (if any)
For each failure:
- Test name and file location
- Brief description of what failed
- The assertion or error message

### Coverage Summary
- Overall coverage percentage
- Files with low coverage (<80%)
- Specific uncovered lines to consider testing

### Recommendations
- If coverage is low, suggest specific test cases to add
- If tests fail, briefly explain likely causes
