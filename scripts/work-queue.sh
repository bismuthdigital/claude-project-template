#!/usr/bin/env bash
# work-queue.sh — Manage task claims for concurrent Claude Code agents
#
# All worktrees share the same main repo, so we store claims in a known
# location relative to the main repo root. This script resolves that path
# automatically from any worktree.
#
# Usage:
#   work-queue.sh claim  <slug> <title> <section> <role_tag> [version]  # Claim a task
#   work-queue.sh release <slug>                               # Release a claim
#   work-queue.sh release-all                                  # Release all claims for this worktree
#   work-queue.sh list                                         # List all active claims
#   work-queue.sh check <slug>                                 # Check if a task is claimed
#   work-queue.sh claimed-by-me                                # List tasks claimed by this worktree
#   work-queue.sh expire                                       # Remove stale claims past TTL
#   work-queue.sh init                                         # Ensure queue directory exists
#   work-queue.sh inflight-tasks                               # List tasks completed in open PRs (JSON)
#   work-queue.sh max-claimed-version                          # Show highest speculated version across all claims

set -euo pipefail

# --- Resolve paths ---

# Find the main repo root (first line of worktree list is always the main repo)
MAIN_REPO=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')

# Determine which worktree we're in
CURRENT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
if [[ "$CURRENT_DIR" == "$MAIN_REPO" ]]; then
    WORKTREE_NAME="main"
else
    WORKTREE_NAME=$(basename "$CURRENT_DIR")
fi

# Queue directory lives in the main repo (shared across all worktrees)
QUEUE_DIR="${MAIN_REPO}/.claude/work-queue"
CLAIMS_DIR="${QUEUE_DIR}/claims"
CONFIG_FILE="${QUEUE_DIR}/config.json"

# Default TTL in minutes
DEFAULT_TTL=120

# --- Helper functions ---

get_ttl() {
    if [[ -f "$CONFIG_FILE" ]]; then
        python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('ttl_minutes', $DEFAULT_TTL))" 2>/dev/null || echo "$DEFAULT_TTL"
    else
        echo "$DEFAULT_TTL"
    fi
}

now_iso() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

now_epoch() {
    date +%s
}

file_age_minutes() {
    local file="$1"
    if [[ "$(uname)" == "Darwin" ]]; then
        local file_epoch
        file_epoch=$(stat -f %m "$file")
    else
        local file_epoch
        file_epoch=$(stat -c %Y "$file")
    fi
    local now
    now=$(now_epoch)
    echo $(( (now - file_epoch) / 60 ))
}

slug_from_title() {
    # Convert a task title to a filesystem-safe slug
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 80
}

# --- Commands ---

cmd_init() {
    mkdir -p "$CLAIMS_DIR"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'CONF'
{
    "ttl_minutes": 120
}
CONF
    fi
    echo "Work queue initialized at: ${QUEUE_DIR}"
    echo "Claims dir: ${CLAIMS_DIR}"
    echo "Worktree: ${WORKTREE_NAME}"
}

cmd_claim() {
    local slug="$1"
    local title="${2:-$slug}"
    local section="${3:-}"
    local role_tag="${4:-}"
    local version="${5:-}"

    mkdir -p "$CLAIMS_DIR"

    local claim_file="${CLAIMS_DIR}/${slug}.json"

    # Check if already claimed
    if [[ -f "$claim_file" ]]; then
        local owner
        owner=$(python3 -c "import json; print(json.load(open('$claim_file'))['agent_worktree'])")
        if [[ "$owner" == "$WORKTREE_NAME" ]]; then
            echo "ALREADY_OWNED"
            return 0
        fi

        # Check if the claim is expired
        local age
        age=$(file_age_minutes "$claim_file")
        local ttl
        ttl=$(get_ttl)
        if (( age > ttl )); then
            echo "EXPIRED_RECLAIMED"
            # Fall through to write new claim
        else
            echo "CLAIMED_BY:${owner}"
            return 1
        fi
    fi

    # Write claim
    local ttl
    ttl=$(get_ttl)
    python3 -c "
import json, sys
claim = {
    'task_slug': '${slug}',
    'task_title': $(python3 -c "import json; print(json.dumps('$title'))"),
    'section': $(python3 -c "import json; print(json.dumps('$section'))"),
    'role_tag': $(python3 -c "import json; print(json.dumps('$role_tag'))"),
    'agent_worktree': '${WORKTREE_NAME}',
    'claimed_at': '$(now_iso)',
    'ttl_minutes': ${ttl},
    'speculated_version': '${version}' if '${version}' else None
}
with open('${claim_file}', 'w') as f:
    json.dump(claim, f, indent=2)
"
    echo "CLAIMED"
    return 0
}

cmd_release() {
    local slug="$1"
    local claim_file="${CLAIMS_DIR}/${slug}.json"

    if [[ ! -f "$claim_file" ]]; then
        echo "NOT_FOUND"
        return 0
    fi

    local owner
    owner=$(python3 -c "import json; print(json.load(open('$claim_file'))['agent_worktree'])")

    # Only release your own claims (unless force)
    if [[ "$owner" != "$WORKTREE_NAME" && "${2:-}" != "--force" ]]; then
        echo "NOT_OWNER:${owner}"
        return 1
    fi

    rm -f "$claim_file"
    echo "RELEASED"
    return 0
}

cmd_release_all() {
    mkdir -p "$CLAIMS_DIR"
    local count=0
    for claim_file in "$CLAIMS_DIR"/*.json; do
        [[ -f "$claim_file" ]] || continue
        local owner
        owner=$(python3 -c "import json; print(json.load(open('$claim_file'))['agent_worktree'])" 2>/dev/null) || continue
        if [[ "$owner" == "$WORKTREE_NAME" ]]; then
            rm -f "$claim_file"
            count=$((count + 1))
        fi
    done
    echo "RELEASED:${count}"
}

cmd_list() {
    mkdir -p "$CLAIMS_DIR"
    local ttl
    ttl=$(get_ttl)

    echo "{"
    echo '  "claims": ['
    local first=true
    for claim_file in "$CLAIMS_DIR"/*.json; do
        [[ -f "$claim_file" ]] || continue
        local age
        age=$(file_age_minutes "$claim_file")
        local expired="false"
        if (( age > ttl )); then
            expired="true"
        fi

        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi

        # Read the claim and add age/expired fields
        python3 -c "
import json
with open('$claim_file') as f:
    claim = json.load(f)
claim['age_minutes'] = $age
claim['expired'] = $(if [[ "$expired" == "true" ]]; then echo "True"; else echo "False"; fi)
print('    ' + json.dumps(claim), end='')
"
    done
    echo ""
    echo "  ],"
    echo "  \"queue_dir\": \"${QUEUE_DIR}\","
    echo "  \"current_worktree\": \"${WORKTREE_NAME}\","
    echo "  \"ttl_minutes\": ${ttl}"
    echo "}"
}

cmd_check() {
    local slug="$1"
    local claim_file="${CLAIMS_DIR}/${slug}.json"

    if [[ ! -f "$claim_file" ]]; then
        echo "UNCLAIMED"
        return 0
    fi

    local age
    age=$(file_age_minutes "$claim_file")
    local ttl
    ttl=$(get_ttl)

    if (( age > ttl )); then
        echo "EXPIRED"
        return 0
    fi

    local owner
    owner=$(python3 -c "import json; print(json.load(open('$claim_file'))['agent_worktree'])")
    echo "CLAIMED_BY:${owner}"
    return 0
}

cmd_claimed_by_me() {
    mkdir -p "$CLAIMS_DIR"
    echo "["
    local first=true
    for claim_file in "$CLAIMS_DIR"/*.json; do
        [[ -f "$claim_file" ]] || continue
        local owner
        owner=$(python3 -c "import json; print(json.load(open('$claim_file'))['agent_worktree'])" 2>/dev/null) || continue
        if [[ "$owner" == "$WORKTREE_NAME" ]]; then
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            python3 -c "
import json
with open('$claim_file') as f:
    print('  ' + json.dumps(json.load(f)), end='')
"
        fi
    done
    echo ""
    echo "]"
}

cmd_expire() {
    mkdir -p "$CLAIMS_DIR"
    local ttl
    ttl=$(get_ttl)
    local count=0

    for claim_file in "$CLAIMS_DIR"/*.json; do
        [[ -f "$claim_file" ]] || continue
        local age
        age=$(file_age_minutes "$claim_file")
        if (( age > ttl )); then
            local slug
            slug=$(basename "$claim_file" .json)
            rm -f "$claim_file"
            echo "EXPIRED:${slug}"
            count=$((count + 1))
        fi
    done
    echo "TOTAL_EXPIRED:${count}"
}

cmd_inflight_tasks() {
    # Query GitHub for open PRs and extract task titles being marked complete.
    # Returns a JSON array of task title strings.
    # Gracefully degrades to [] if gh CLI is unavailable or fails.

    if ! command -v gh &>/dev/null; then
        echo "[]"
        echo "warning: gh CLI not found — skipping in-flight PR check" >&2
        return 0
    fi

    # Get open PR numbers
    local pr_numbers
    pr_numbers=$(gh pr list --state open --json number --jq '.[].number' 2>/dev/null) || {
        echo "[]"
        echo "warning: gh pr list failed — skipping in-flight PR check" >&2
        return 0
    }

    if [[ -z "$pr_numbers" ]]; then
        echo "[]"
        return 0
    fi

    # For each PR, get the diff and extract completed task titles
    local all_titles=""
    while IFS= read -r pr_num; do
        [[ -z "$pr_num" ]] && continue
        local diff
        diff=$(gh pr diff "$pr_num" 2>/dev/null) || continue

        # Extract lines that are additions (+) marking tasks as complete [x] with bold title
        # Pattern: +- [x] **[role] Task title** or +- [x] **Task title**
        local titles
        titles=$(echo "$diff" | grep -E '^\+.*\[x\].*\*\*' | sed 's/^+[[:space:]]*//' | \
            sed 's/^- \[x\] //' | \
            sed 's/\*\*\[[^]]*\] //' | \
            sed 's/\*\*//' | \
            sed 's/\*\*//' | \
            sed 's/ *—.*//' | \
            sed 's/[[:space:]]*$//') || true

        if [[ -n "$titles" ]]; then
            if [[ -n "$all_titles" ]]; then
                all_titles="${all_titles}"$'\n'"${titles}"
            else
                all_titles="$titles"
            fi
        fi
    done <<< "$pr_numbers"

    if [[ -z "$all_titles" ]]; then
        echo "[]"
        return 0
    fi

    # Convert newline-separated titles to JSON array
    python3 -c "
import json, sys
titles = [line.strip() for line in sys.stdin if line.strip()]
# Deduplicate while preserving order
seen = set()
unique = []
for t in titles:
    if t not in seen:
        seen.add(t)
        unique.append(t)
print(json.dumps(unique, indent=2))
" <<< "$all_titles"
}

cmd_max_claimed_version() {
    mkdir -p "$CLAIMS_DIR"
    local ttl
    ttl=$(get_ttl)

    # Collect all non-expired speculated versions and find the highest
    python3 -c "
import json, os, sys

claims_dir = '${CLAIMS_DIR}'
ttl = ${ttl}
versions = []

for fname in sorted(os.listdir(claims_dir)):
    if not fname.endswith('.json'):
        continue
    fpath = os.path.join(claims_dir, fname)
    try:
        with open(fpath) as f:
            claim = json.load(f)
        v = claim.get('speculated_version')
        if v:
            versions.append(v)
    except (json.JSONDecodeError, KeyError):
        continue

if not versions:
    print('NONE')
    sys.exit(0)

# Parse and sort semver strings, return the highest
def parse_ver(v):
    parts = v.lstrip('v').split('.')
    return tuple(int(p) for p in parts)

versions.sort(key=parse_ver)
print(versions[-1])
"
}

# --- Main dispatch ---

CMD="${1:-help}"
shift || true

case "$CMD" in
    init)
        cmd_init
        ;;
    claim)
        if [[ $# -lt 1 ]]; then
            echo "Usage: work-queue.sh claim <slug> [title] [section] [role_tag] [version]" >&2
            exit 1
        fi
        cmd_claim "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}"
        ;;
    release)
        if [[ $# -lt 1 ]]; then
            echo "Usage: work-queue.sh release <slug> [--force]" >&2
            exit 1
        fi
        cmd_release "$@"
        ;;
    release-all)
        cmd_release_all
        ;;
    list)
        cmd_list
        ;;
    check)
        if [[ $# -lt 1 ]]; then
            echo "Usage: work-queue.sh check <slug>" >&2
            exit 1
        fi
        cmd_check "$1"
        ;;
    claimed-by-me)
        cmd_claimed_by_me
        ;;
    expire)
        cmd_expire
        ;;
    inflight-tasks)
        cmd_inflight_tasks
        ;;
    max-claimed-version)
        cmd_max_claimed_version
        ;;
    help|--help|-h)
        echo "Usage: work-queue.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  init                          Initialize the work queue directory"
        echo "  claim <slug> [title] [section] [role] [version]  Claim a task"
        echo "  release <slug> [--force]      Release a claimed task"
        echo "  release-all                   Release all claims for this worktree"
        echo "  list                          List all active claims (JSON)"
        echo "  check <slug>                  Check if a task is claimed"
        echo "  claimed-by-me                 List tasks claimed by this worktree"
        echo "  expire                        Remove claims past TTL"
        echo "  inflight-tasks                List tasks completed in open PRs (JSON)"
        echo "  max-claimed-version           Show highest speculated version across claims"
        echo ""
        echo "Current worktree: ${WORKTREE_NAME}"
        echo "Queue dir: ${QUEUE_DIR}"
        ;;
    *)
        echo "Unknown command: $CMD" >&2
        echo "Run 'work-queue.sh help' for usage." >&2
        exit 1
        ;;
esac
