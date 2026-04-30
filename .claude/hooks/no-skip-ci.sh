#!/bin/bash
# PreToolUse hook: Block git commit messages containing [skip ci].
#
# CI must run on every PR commit. [skip ci] in a PR branch causes required
# checks to never report, blocking merge indefinitely.

set -e

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check git commit commands
case "$COMMAND" in
  git\ commit*) ;;
  *) exit 0 ;;
esac

# Check if the command contains [skip ci] or [ci skip] (case-insensitive)
if echo "$COMMAND" | grep -qi '\[skip ci\]\|\[ci skip\]\|\[no ci\]'; then
  echo "BLOCKED: Commit message contains [skip ci]. CI must run on every commit — required checks will never report otherwise, blocking merge indefinitely. Remove the skip directive."
  exit 2
fi

exit 0
