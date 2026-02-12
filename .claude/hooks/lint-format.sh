#!/bin/bash
# PostToolUse hook: Auto-run linters and formatters on Python file changes
# Runs after Edit or Write operations

set -e

# Read JSON input from stdin
INPUT=$(cat)

# Extract file path from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Exit if no file path or not a Python file
if [[ -z "$FILE_PATH" ]] || [[ "$FILE_PATH" != *.py ]]; then
    exit 0
fi

# Change to project directory
cd "$CLAUDE_PROJECT_DIR" || exit 0

# Activate virtual environment (supports venv, poetry, conda, uv, pipenv, pyenv)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/venv-activate.sh" 2>/dev/null || true

# Track if we made changes
CHANGES_MADE=false

# Run ruff if available
if command -v ruff &> /dev/null; then
    echo "Running ruff check --fix on $FILE_PATH..."
    if ruff check --fix "$FILE_PATH" 2>&1; then
        CHANGES_MADE=true
    fi

    echo "Running ruff format on $FILE_PATH..."
    if ruff format "$FILE_PATH" 2>&1; then
        CHANGES_MADE=true
    fi
elif command -v black &> /dev/null; then
    # Fallback to black if ruff not available
    echo "Running black on $FILE_PATH..."
    if black "$FILE_PATH" 2>&1; then
        CHANGES_MADE=true
    fi
fi

# Check for documentation/test update reminders
# Only for source files, not tests
if [[ "$FILE_PATH" != *test_*.py ]] && [[ "$FILE_PATH" != *_test.py ]] && [[ "$FILE_PATH" != */tests/* ]]; then
    # Check if file contains public API (classes or functions without leading underscore)
    if grep -qE "^(def|class|async def) [a-zA-Z]" "$FILE_PATH" 2>/dev/null; then
        echo ""
        echo "Note: Public API detected in $FILE_PATH"
        echo "  - Consider updating docstrings if interface changed"
        echo "  - Consider updating tests if behavior changed"
        echo "  - Consider updating README.md if public API changed"
    fi
fi

exit 0
