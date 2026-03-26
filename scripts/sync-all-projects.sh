#!/usr/bin/env bash
# sync-all-projects.sh — Sync Claude config and ship changes across all projects
#
# Launches a headless Claude Code session per project (in parallel) that:
#   1. Runs /sync-config to compare against the template
#   2. Auto-applies all suggested updates
#   3. Ships changes via /ship (or direct commit+merge if /ship is unavailable)
#
# Results are written to a log directory for review.
#
# Usage:
#   ./scripts/sync-all-projects.sh              # sync all projects
#   ./scripts/sync-all-projects.sh --dry-run    # list projects, don't run
#   ./scripts/sync-all-projects.sh proj1 proj2  # sync specific projects

set -euo pipefail

# Directory containing Claude-configured projects to sync.
# Override with CLAUDE_PROJECTS_DIR env var, e.g.:
#   CLAUDE_PROJECTS_DIR="$HOME/projects" ./scripts/sync-all-projects.sh
CLAUDE_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/code/claude}"
LOG_DIR="$HOME/.claude/sync-logs/$(date +%Y%m%d-%H%M%S)"
MAX_PARALLEL=4
DRY_RUN=false
SPECIFIC_PROJECTS=()

# The template itself doesn't need syncing — it IS the source of truth
SKIP_PROJECTS=("claude-project-template")

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --help|-h)
            echo "Usage: $0 [--dry-run] [project1 project2 ...]"
            echo ""
            echo "Options:"
            echo "  --dry-run   List projects that would be synced, without running"
            echo "  --help      Show this help message"
            echo ""
            echo "If no projects are specified, syncs all Claude-configured repos"
            echo "under $CLAUDE_DIR (except the template itself)."
            exit 0
            ;;
        *) SPECIFIC_PROJECTS+=("$arg") ;;
    esac
done

# ---------------------------------------------------------------------------
# Discover projects
# ---------------------------------------------------------------------------
discover_projects() {
    local projects=()
    for dir in "$CLAUDE_DIR"/*/; do
        [ ! -d "$dir/.claude" ] && continue

        local name
        name="$(basename "$dir")"

        # Skip the template
        local skip=false
        for s in "${SKIP_PROJECTS[@]}"; do
            [ "$name" = "$s" ] && skip=true && break
        done
        $skip && continue

        # If user specified projects, filter to those
        if [ ${#SPECIFIC_PROJECTS[@]} -gt 0 ]; then
            local match=false
            for p in "${SPECIFIC_PROJECTS[@]}"; do
                [ "$name" = "$p" ] && match=true && break
            done
            $match || continue
        fi

        projects+=("$dir")
    done
    printf '%s\n' "${projects[@]}"
}

PROJECTS=()
while IFS= read -r line; do
    PROJECTS+=("$line")
done < <(discover_projects)

if [ ${#PROJECTS[@]} -eq 0 ]; then
    echo "No projects found to sync."
    exit 0
fi

echo "═══════════════════════════════════════════════════"
echo "         SYNC-CONFIG: ALL PROJECTS"
echo "═══════════════════════════════════════════════════"
echo ""
echo "Projects (${#PROJECTS[@]}):"
for p in "${PROJECTS[@]}"; do
    echo "  - $(basename "$p")"
done
echo ""

if $DRY_RUN; then
    echo "(dry run — no changes made)"
    exit 0
fi

# ---------------------------------------------------------------------------
# Run sync-config on each project
# ---------------------------------------------------------------------------
mkdir -p "$LOG_DIR"

run_sync() {
    local project_dir="$1"
    local name
    name="$(basename "$project_dir")"
    local log_file="$LOG_DIR/${name}.log"

    echo "[START] $name"

    # Multi-step prompt: sync config, apply safe updates, then ship
    local prompt
    prompt=$(cat <<'PROMPT'
Run /sync-config to compare this project against the template.

After the report is generated, apply updates with these safety rules:

SAFE TO APPLY AUTOMATICALLY:
- New permissions (allow/deny rules) from the template
- New hooks that don't exist locally
- New skills that don't exist locally
- Updated bin/ scripts (e.g., hardcoded repo names → dynamic detection)
- New utility scripts from the template
- Updated pyproject.toml tool configurations (ruff rules, pytest, mypy)
- New .gitignore patterns

DO NOT OVERWRITE — SKIP THESE:
- Skills that exist in BOTH the project AND the template, when the project
  version has project-specific customizations (references to project-specific
  CLI commands, domain terminology, project-specific paths like src/<project>/,
  seed data checks, custom test directories, domain-specific fixture guidance).
  The template version is generalized — overwriting loses project-specific
  context that agents need.
- Hooks that exist locally with project-specific logic (e.g., references to
  project-specific commands or paths)
- Any file where the local version is NEWER than the template (LOCAL_NEWER)
- Settings.json permissions that reference project-specific tools (e.g.,
  ./bin/td, ./bin/seed-stats) — keep these, only ADD new template permissions

HOW TO DECIDE: If a skill/script exists in both places, compare them. If the
local version contains ANY project-specific references not in the template
(domain terms, project paths, custom CLI tools, domain-specific test rules),
KEEP the local version and skip the update. Only overwrite if the files are
functionally identical or the local version is a strict subset of the template.

If there are no safe updates to apply, say "Already up to date" and stop.

After applying safe updates, ship the changes:
- If the /ship skill is available, run /ship with commit message "Sync Claude config with template".
- If /ship is not available, do it manually:
  1. git checkout -b sync-config-update
  2. git add -A
  3. git commit -m "Sync Claude config with template

Co-Authored-By: Claude <noreply@anthropic.com>"
  4. git push -u origin HEAD
  5. gh pr create --title "Sync Claude config with template" --body "Automated sync of .claude/ configuration against claude-project-template."
  6. gh pr merge --squash --delete-branch --admin
  7. git checkout main && git pull origin main

Do not ask for confirmation at any step. Execute everything autonomously.
PROMPT
    )

    # Run claude in headless mode with dangerouslySkipPermissions
    # Claude CLI uses cwd as the project root, so cd into the project first
    if (cd "$project_dir" && claude -p "$prompt" \
        --dangerously-skip-permissions \
        --output-format text \
        > "$log_file" 2>&1); then
        echo "[DONE]  $name  →  $log_file"
    else
        echo "[FAIL]  $name  →  $log_file"
    fi
}

export -f run_sync
export LOG_DIR

# Run in parallel batches
RUNNING=0
PIDS=()
PROJECT_NAMES=()

for project in "${PROJECTS[@]}"; do
    run_sync "$project" &
    PIDS+=($!)
    PROJECT_NAMES+=("$(basename "$project")")
    RUNNING=$((RUNNING + 1))

    # Wait for a slot to open when at max parallelism
    if [ "$RUNNING" -ge "$MAX_PARALLEL" ]; then
        wait -n 2>/dev/null || true
        RUNNING=$((RUNNING - 1))
    fi
done

# Wait for all remaining
wait

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "───────────────────────────────────────────────────"
echo "RESULTS"
echo "───────────────────────────────────────────────────"

SHIPPED=0
UP_TO_DATE=0
FAILED=0
for log in "$LOG_DIR"/*.log; do
    name="$(basename "$log" .log)"
    if grep -qi "already up to date" "$log" 2>/dev/null; then
        echo "  - $name (already up to date)"
        UP_TO_DATE=$((UP_TO_DATE + 1))
    elif grep -qi "SHIPPED\|squash merged\|merged into main\|Merged" "$log" 2>/dev/null; then
        echo "  ✓ $name (synced and shipped)"
        SHIPPED=$((SHIPPED + 1))
    else
        echo "  ✗ $name (check log)"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "Shipped: $SHIPPED  Up to date: $UP_TO_DATE  Failed: $FAILED"
echo "Logs:    $LOG_DIR/"
echo ""
echo "Review a log:  cat \"$LOG_DIR/<project>.log\""
echo "═══════════════════════════════════════════════════"
