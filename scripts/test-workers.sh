#!/usr/bin/env bash
# Compute the optimal pytest-xdist worker count for concurrent agent work.
#
# Divides available CPU cores by the number of active git worktrees so
# multiple agents don't oversubscribe the machine.
#
# Override: TEST_WORKERS=N  (bypass auto-detection)
#
# Usage:
#   .venv/bin/python -m pytest -n "$(bash scripts/test-workers.sh)" ...

set -euo pipefail

# Allow explicit override
if [[ -n "${TEST_WORKERS:-}" ]]; then
    echo "$TEST_WORKERS"
    exit 0
fi

# Detect CPU count (macOS and Linux)
if command -v sysctl &>/dev/null; then
    CPUS=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
else
    CPUS=$(nproc 2>/dev/null || echo 4)
fi

# Count git worktrees (includes main repo)
MAIN_REPO=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [[ -n "$MAIN_REPO" ]]; then
    # In a worktree, find the main repo first
    MAIN_REPO=$(git -C "$MAIN_REPO" worktree list --porcelain 2>/dev/null \
        | head -1 | sed 's/^worktree //' || echo "$MAIN_REPO")
    WORKTREES=$(git -C "$MAIN_REPO" worktree list 2>/dev/null | wc -l | tr -d ' ')
else
    WORKTREES=1
fi

# At least 1 worktree
WORKTREES=$((WORKTREES > 0 ? WORKTREES : 1))

# Divide cores by worktrees, floor of 2 (below 2 workers xdist overhead isn't worth it)
WORKERS=$((CPUS / WORKTREES))
WORKERS=$((WORKERS > 2 ? WORKERS : 2))

# Cap at half of total cores — leave headroom for the OS, Claude, and other agents
MAX=$((CPUS / 2))
MAX=$((MAX > 2 ? MAX : 2))
WORKERS=$((WORKERS < MAX ? WORKERS : MAX))

echo "$WORKERS"
