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

# Run ruff if available, falling back to black
if command -v ruff &> /dev/null; then
    echo "Running ruff check --fix on $FILE_PATH..."
    ruff check --fix "$FILE_PATH" 2>&1 || true

    echo "Running ruff format on $FILE_PATH..."
    ruff format "$FILE_PATH" 2>&1 || true
elif command -v black &> /dev/null; then
    echo "Running black on $FILE_PATH..."
    black "$FILE_PATH" 2>&1 || true
fi

exit 0
