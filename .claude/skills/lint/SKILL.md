---
name: lint
version: 1.0.0
description: >
  Runs Python linters and formatters (ruff, black, mypy) on the codebase.
  Use to check and fix code style issues.
argument-hint: "[path or empty for entire project]"
allowed-tools: Bash(ruff *), Bash(black *), Bash(mypy *), Bash(python -m *), Bash(source *)
---

# Linting and Formatting

Run all Python quality tools on the specified path or entire project.

## Tools to Run

1. **ruff check** - Fast Python linter (replaces flake8, isort, etc.)
2. **ruff format** - Fast Python formatter (replaces black)
3. **mypy** - Static type checker (if installed)

## Process

1. Activate virtual environment if present
2. Run ruff check with auto-fix
3. Run ruff format
4. Run mypy for type checking
5. Report results

**First**, print the version banner:
```
/lint v1.0.0
```
Then run the commands below.

## Commands

Run these in order:

```bash
# Activate virtual environment (supports venv, poetry, conda, uv, pipenv, pyenv)
source .claude/hooks/venv-activate.sh 2>/dev/null || true

# Get target path (argument or current directory)
TARGET="${ARGUMENTS:-.}"

# Linting with auto-fix
echo "=== Running ruff check ==="
ruff check --fix "$TARGET"

# Formatting
echo "=== Running ruff format ==="
ruff format "$TARGET"

# Type checking (if mypy installed)
echo "=== Running mypy ==="
mypy "$TARGET" 2>/dev/null || echo "mypy not installed or not configured"
```

## Output

Report:
1. Number of issues auto-fixed by ruff
2. Any remaining lint errors that need manual attention
3. Type checking results from mypy
4. Summary: PASSED (no issues) or FAILED (issues remain)

If issues remain, list them clearly with file:line references.
