#!/bin/bash
# PostToolUse hook: Suggest /sync-config when Claude config files are edited
# Runs after Edit operations on .claude/ files

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only trigger for .claude/ configuration files
if [[ "$FILE_PATH" != *.claude/settings.json ]] && \
   [[ "$FILE_PATH" != *.claude/hooks/* ]] && \
   [[ "$FILE_PATH" != */.claude/settings.json ]] && \
   [[ "$FILE_PATH" != */.claude/hooks/* ]]; then
    exit 0
fi

# Don't trigger for skill files (those are expected to be customized)
if [[ "$FILE_PATH" == *skills* ]]; then
    exit 0
fi

echo ""
echo "Tip: Configuration file modified. Run /sync-config to compare against the official template."

exit 0
