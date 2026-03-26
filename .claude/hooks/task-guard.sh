#!/bin/bash
# PreToolUse hook: Block direct Write to next-steps/active/*.md
# Tasks must be created via scripts/task-format.py create-task to get T### IDs.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" ]] && exit 0

# Normalize relative paths against project dir
case "$FILE_PATH" in
    /*) ;; # absolute — use as-is
    *)  FILE_PATH="${CLAUDE_PROJECT_DIR:-.}/$FILE_PATH" ;;
esac

# Only block writes to active task files (not completed/, _sections.toml, etc.)
if [[ "$FILE_PATH" == */next-steps/active/*.md ]]; then
    cat <<'MSG'

BLOCKED: Do not create or edit task files directly.

Task files require auto-assigned T### IDs. Use the create-task command:

  .venv/bin/python scripts/task-format.py create-task \
    --role <role> --section "<section>" --priority "<priority>" \
    --title "Task title" --body "Description" \
    --deps "dep1,dep2"

To edit an existing task's frontmatter (re-prioritize, change section),
use the Edit tool on the file — only new file creation is blocked.

See docs/TASK-FORMAT.md for the full specification.
MSG
    exit 2
fi

exit 0
