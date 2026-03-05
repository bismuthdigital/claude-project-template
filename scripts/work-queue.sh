#!/usr/bin/env bash
# work-queue.sh — Manage task claims for concurrent Claude Code agents
#
# All worktrees share the same main repo, so we store claims in a known
# location relative to the main repo root. This script resolves that path
# automatically from any worktree.
#
# Usage:
#   work-queue.sh claim  <slug> <title> <section> <role_tag> [version] [purpose]  # Claim a task
#   work-queue.sh release <slug>                               # Release a claim
#   work-queue.sh release-all                                  # Release all claims for this worktree
#   work-queue.sh list                                         # List all active claims
#   work-queue.sh check <slug>                                 # Check if a task is claimed
#   work-queue.sh claimed-by-me                                # List tasks claimed by this worktree
#   work-queue.sh expire                                       # Remove stale claims past TTL
#   work-queue.sh init                                         # Ensure queue directory exists
#   work-queue.sh inflight-tasks                               # List tasks completed in open PRs (not yet merged)
#   work-queue.sh max-claimed-version                          # Show highest speculated version across all claims
#   work-queue.sh validate                                     # Health check: detect claim issues
#   work-queue.sh mark-shipped <pr_number> <pr_url>            # Transition this worktree's claims to shipped
#   work-queue.sh auto-release-merged                          # Release shipped claims whose PRs are merged/closed
#   work-queue.sh try-claim <count> <json_file>                # Try claiming tasks from a candidates file
#   work-queue.sh mark-reviewed <slug> [sha]                   # Record that a task has been reviewed
#   work-queue.sh is-reviewed <slug>                           # Check if a task has been reviewed
#   work-queue.sh list-reviewed                                # List all reviewed tasks
#   work-queue.sh clean-review <slug>                          # Delete review file and reviewed marker

set -euo pipefail

# --- Resolve paths ---

# Find the main repo root (first line of worktree list is always the main repo)
MAIN_REPO=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')

# Determine which worktree we're in (layered detection)
_detect_worktree() {
    # 1. Explicit env var (highest priority — set by caller)
    if [[ -n "${WORK_QUEUE_WORKTREE:-}" ]]; then
        echo "$WORK_QUEUE_WORKTREE"
        return
    fi

    # 2. Check script's own resolved path for .claude/worktrees/<name>/
    local script_path
    script_path=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
    if [[ "$script_path" =~ \.claude/worktrees/([^/]+)/ ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi

    # 3. Check git's internal worktree directory for /worktrees/<name> suffix
    local git_dir
    git_dir=$(git rev-parse --git-dir 2>/dev/null || true)
    if [[ "$git_dir" =~ /worktrees/([^/]+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi

    # 4. CWD-based detection (legacy fallback)
    local current_dir
    current_dir=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    if [[ "$current_dir" == "$MAIN_REPO" ]]; then
        echo "main"
    else
        basename "$current_dir"
    fi
}

WORKTREE_NAME=$(_detect_worktree)

# Warn if detected as "main" but context suggests otherwise
if [[ "$WORKTREE_NAME" == "main" ]]; then
    _script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
    if [[ "$_script_dir" =~ \.claude/worktrees/ ]]; then
        echo "WARNING: Worktree detected as 'main' but script is running from a worktree path." >&2
        echo "Set WORK_QUEUE_WORKTREE=<name> to override." >&2
    fi
    unset _script_dir
fi

# Queue directory lives in the main repo (shared across all worktrees)
QUEUE_DIR="${MAIN_REPO}/.claude/work-queue"
CLAIMS_DIR="${QUEUE_DIR}/claims"
REVIEWED_DIR="${QUEUE_DIR}/reviewed"
REVIEWS_DIR="${MAIN_REPO}/.claude/reviews"
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

# --- Per-slug locking (mkdir-based atomic primitive) ---

_HELD_LOCK=""

_acquire_lock() {
    local slug="$1"
    local lock_dir="${CLAIMS_DIR}/${slug}.lock"
    local max_retries=5
    local retry_delay_ms=200

    mkdir -p "$CLAIMS_DIR"

    for (( i=0; i<max_retries; i++ )); do
        if mkdir "$lock_dir" 2>/dev/null; then
            # Won the lock — write owner file for diagnostics
            echo "$$:$(now_epoch):${WORKTREE_NAME}" > "${lock_dir}/owner"
            _HELD_LOCK="$lock_dir"
            trap '_release_lock' EXIT
            return 0
        fi

        # Lock exists — check if it's stale (>30 seconds old)
        if [[ -d "$lock_dir" ]]; then
            local lock_age_s=999
            if [[ -f "${lock_dir}/owner" ]]; then
                local lock_epoch
                lock_epoch=$(cut -d: -f2 < "${lock_dir}/owner" 2>/dev/null) || true
                if [[ -n "$lock_epoch" ]]; then
                    lock_age_s=$(( $(now_epoch) - lock_epoch ))
                fi
            else
                # No owner file yet — use directory mtime for staleness
                # (owner file may not be written yet if lock was just created)
                local dir_mtime
                if [[ "$(uname)" == "Darwin" ]]; then
                    dir_mtime=$(stat -f %m "$lock_dir" 2>/dev/null) || true
                else
                    dir_mtime=$(stat -c %Y "$lock_dir" 2>/dev/null) || true
                fi
                if [[ -n "$dir_mtime" ]]; then
                    lock_age_s=$(( $(now_epoch) - dir_mtime ))
                fi
            fi

            if (( lock_age_s > 30 )); then
                echo "STALE_LOCK_CLEANED:${slug}" >&2
                rm -rf "$lock_dir"
                # Retry immediately after cleaning
                continue
            fi
        fi

        # Backoff before retry
        if command -v python3 &>/dev/null; then
            python3 -c "import time; time.sleep(${retry_delay_ms}/1000.0)"
        else
            sleep 1
        fi
    done

    # Could not acquire lock after retries
    return 1
}

_release_lock() {
    if [[ -n "$_HELD_LOCK" && -d "$_HELD_LOCK" ]]; then
        rm -rf "$_HELD_LOCK"
        _HELD_LOCK=""
    fi
}

_find_claim_by_title() {
    # Search all existing claim files for a matching task_title.
    # Returns the slug (filename without .json) if found, empty string otherwise.
    local target_title="$1"
    mkdir -p "$CLAIMS_DIR"
    for claim_file in "$CLAIMS_DIR"/*.json; do
        [[ -f "$claim_file" ]] || continue
        local title
        title=$(python3 -c "import json; print(json.load(open('$claim_file')).get('task_title', ''))" 2>/dev/null) || continue
        if [[ "$title" == "$target_title" ]]; then
            basename "$claim_file" .json
            return 0
        fi
    done
    echo ""
    return 0
}

# --- Commands ---

cmd_init() {
    mkdir -p "$CLAIMS_DIR"
    mkdir -p "$REVIEWED_DIR"
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
    local purpose="${6:-}"

    mkdir -p "$CLAIMS_DIR"

    # --- Safeguard: canonical slug enforcement ---
    # If a title was provided, compute the canonical slug and correct if needed
    if [[ -n "$title" && "$title" != "$slug" ]]; then
        local canonical
        canonical=$(slug_from_title "$title")
        if [[ "$canonical" != "$slug" ]]; then
            echo "SLUG_CORRECTED:${slug}:${canonical}" >&2
            slug="$canonical"
        fi
    fi

    # Acquire per-slug lock (atomic via mkdir)
    if ! _acquire_lock "$slug"; then
        echo "LOCK_FAILED"
        return 1
    fi

    # --- Everything below runs under the lock ---

    # --- Safeguard: duplicate title detection ---
    # Check if this exact title is already claimed under a different slug
    local existing_slug
    existing_slug=$(_find_claim_by_title "$title")
    if [[ -n "$existing_slug" && "$existing_slug" != "$slug" ]]; then
        local existing_owner
        existing_owner=$(python3 -c "import json; print(json.load(open('${CLAIMS_DIR}/${existing_slug}.json'))['agent_worktree'])" 2>/dev/null)
        echo "DUPLICATE_TITLE:${existing_slug}:${existing_owner}" >&2
        _release_lock
        echo "DUPLICATE_TITLE"
        return 1
    fi

    local claim_file="${CLAIMS_DIR}/${slug}.json"

    # Check if already claimed
    if [[ -f "$claim_file" ]]; then
        local owner
        owner=$(python3 -c "import json; print(json.load(open('$claim_file'))['agent_worktree'])")
        if [[ "$owner" == "$WORKTREE_NAME" ]]; then
            _release_lock
            echo "ALREADY_OWNED"
            return 0
        fi

        # Shipped claims are in the merge queue — not reclaimable by TTL
        local state
        state=$(python3 -c "import json; print(json.load(open('$claim_file')).get('state', 'claimed'))" 2>/dev/null) || true
        if [[ "$state" == "shipped" ]]; then
            _release_lock
            echo "SHIPPED_BY:${owner}"
            return 1
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
            _release_lock
            echo "CLAIMED_BY:${owner}"
            return 1
        fi
    fi

    # Write claim atomically via temp file + mv
    local ttl
    ttl=$(get_ttl)
    local tmp_file="${CLAIMS_DIR}/${slug}.tmp.$$"
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
    'speculated_version': '${version}' if '${version}' else None,
    'purpose': '${purpose}' if '${purpose}' else None
}
with open('${tmp_file}', 'w') as f:
    json.dump(claim, f, indent=2)
"
    mv -f "$tmp_file" "$claim_file"

    # Post-write verification: confirm our worktree owns the claim
    local verify_owner
    verify_owner=$(python3 -c "import json; print(json.load(open('$claim_file'))['agent_worktree'])" 2>/dev/null) || true
    if [[ "$verify_owner" != "$WORKTREE_NAME" ]]; then
        _release_lock
        echo "CLAIM_VERIFY_FAILED"
        return 1
    fi

    _release_lock
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
    # Clean up any orphaned lock directory
    rm -rf "${CLAIMS_DIR}/${slug}.lock"
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
            local slug
            slug=$(basename "$claim_file" .json)
            rm -f "$claim_file"
            # Clean up any orphaned lock directory
            rm -rf "${CLAIMS_DIR}/${slug}.lock"
            count=$((count + 1))
        fi
    done
    echo "RELEASED:${count}"
}

cmd_mark_shipped() {
    local pr_number="$1"
    local pr_url="$2"
    mkdir -p "$CLAIMS_DIR"
    local count=0

    for claim_file in "$CLAIMS_DIR"/*.json; do
        [[ -f "$claim_file" ]] || continue
        local owner
        owner=$(python3 -c "import json; print(json.load(open('$claim_file'))['agent_worktree'])" 2>/dev/null) || continue
        [[ "$owner" == "$WORKTREE_NAME" ]] || continue

        local slug
        slug=$(basename "$claim_file" .json)
        if ! _acquire_lock "$slug"; then
            echo "LOCK_FAILED:${slug}" >&2
            continue
        fi

        local tmp_file="${CLAIMS_DIR}/${slug}.tmp.$$"
        python3 -c "
import json
with open('${claim_file}') as f:
    claim = json.load(f)
claim['state'] = 'shipped'
claim['pr_number'] = ${pr_number}
claim['pr_url'] = '${pr_url}'
claim['shipped_at'] = '$(now_iso)'
with open('${tmp_file}', 'w') as f:
    json.dump(claim, f, indent=2)
"
        mv -f "$tmp_file" "$claim_file"
        _release_lock
        echo "SHIPPED:${slug}"
        count=$((count + 1))
    done
    echo "TOTAL_SHIPPED:${count}"
}

cmd_auto_release_merged() {
    mkdir -p "$CLAIMS_DIR"
    if ! command -v gh &>/dev/null; then
        echo "SKIPPED"
        return 0
    fi

    local count=0
    for claim_file in "$CLAIMS_DIR"/*.json; do
        [[ -f "$claim_file" ]] || continue

        local state
        state=$(python3 -c "import json; print(json.load(open('$claim_file')).get('state', 'claimed'))" 2>/dev/null) || continue
        [[ "$state" == "shipped" ]] || continue

        local pr_number
        pr_number=$(python3 -c "import json; print(json.load(open('$claim_file')).get('pr_number', ''))" 2>/dev/null) || continue
        [[ -n "$pr_number" ]] || continue

        local pr_state
        pr_state=$(gh pr view "$pr_number" --json state --jq '.state' 2>/dev/null) || continue

        if [[ "$pr_state" == "MERGED" || "$pr_state" == "CLOSED" ]]; then
            local slug
            slug=$(basename "$claim_file" .json)
            rm -f "$claim_file"
            rm -rf "${CLAIMS_DIR}/${slug}.lock"
            echo "RELEASED:${slug}:${pr_state}"
            count=$((count + 1))
        fi
    done
    echo "TOTAL_RELEASED:${count}"
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
        local state
        state=$(python3 -c "import json; print(json.load(open('$claim_file')).get('state', 'claimed'))" 2>/dev/null) || true
        local expired="false"
        if [[ "$state" != "shipped" ]] && (( age > ttl )); then
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
claim['state'] = claim.get('state', 'claimed')
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

    local owner
    owner=$(python3 -c "import json; print(json.load(open('$claim_file'))['agent_worktree'])")

    local state
    state=$(python3 -c "import json; print(json.load(open('$claim_file')).get('state', 'claimed'))" 2>/dev/null) || true
    if [[ "$state" == "shipped" ]]; then
        echo "SHIPPED_BY:${owner}"
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

        # Shipped claims are released by auto-release-merged, not TTL
        local state
        state=$(python3 -c "import json; print(json.load(open('$claim_file')).get('state', 'claimed'))" 2>/dev/null) || true
        if [[ "$state" == "shipped" ]]; then
            continue
        fi

        local age
        age=$(file_age_minutes "$claim_file")
        if (( age > ttl )); then
            local slug
            slug=$(basename "$claim_file" .json)
            rm -f "$claim_file"
            # Clean up any orphaned lock directory
            rm -rf "${CLAIMS_DIR}/${slug}.lock"
            echo "EXPIRED:${slug}"
            count=$((count + 1))
        fi
    done
    echo "TOTAL_EXPIRED:${count}"
}

cmd_inflight_tasks() {
    # Query GitHub for open PRs and extract task titles being marked complete.
    # Returns a JSON array of task title strings.
    # Detects both:
    #   1. Legacy: [x] marks in NEXT-STEPS.md diffs
    #   2. Per-task files: moves from next-steps/active/ to next-steps/completed/
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

        # Extract task titles from diff using two detection methods:
        # 1. Legacy [x] marks in NEXT-STEPS.md
        # 2. Task file moves: files deleted from next-steps/active/ (renamed to completed/)
        #    Title extracted from the "# Title" heading in the file content within the diff
        local titles
        titles=$(echo "$diff" | python3 -c "
import re, sys

titles = set()
lines = sys.stdin.readlines()

for line in lines:
    # Method 1: Legacy [x] marks in NEXT-STEPS.md
    m = re.match(r'^\+\s*-\s*\[x\]\s*\*\*(?:\[[^\]]*\]\s*)?(.+?)\*\*\s*(?:T\d{3,}\s*)?', line)
    if m:
        title = m.group(1).strip()
        title = re.split(r'\s*[—]\s*|\s+--\s+', title)[0].strip()
        if title:
            titles.add(title)

# Method 2: Task file moves (active/ -> completed/)
# Look for files being removed from next-steps/active/
# The title is in the '# Title' heading line within the deleted content
current_is_active_file = False
for line in lines:
    # Detect rename from active/ or deletion of active/ file
    if re.match(r'^rename from next-steps/active/', line):
        current_is_active_file = True
        continue
    if re.match(r'^--- a/next-steps/active/', line):
        current_is_active_file = True
        continue
    # Reset on new diff section
    if line.startswith('diff --git'):
        current_is_active_file = False
        continue
    # Extract title from heading in the deleted file content
    if current_is_active_file:
        # In a rename, content lines are prefixed with space (context) or -/+
        # In a delete, content lines are prefixed with -
        heading = re.match(r'^[-  ]# (.+)', line)
        if heading:
            titles.add(heading.group(1).strip())
            current_is_active_file = False

for t in sorted(titles):
    print(t)
") || true

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

cmd_validate() {
    mkdir -p "$CLAIMS_DIR"
    local ttl
    ttl=$(get_ttl)

    # Collect all worktrees for orphan detection
    local worktree_names
    worktree_names=$(git worktree list --porcelain | grep '^worktree ' | while read -r _ wt_path; do
        if [[ "$wt_path" == "$MAIN_REPO" ]]; then
            echo "main"
        else
            basename "$wt_path"
        fi
    done)

    python3 -c "
import json, os, re, sys, time

claims_dir = '${CLAIMS_DIR}'
ttl = ${ttl}
worktree_names = set('''${worktree_names}'''.strip().split('\n'))

def slug_from_title(title):
    \"\"\"Match the bash slug_from_title exactly: lowercase, replace non-alnum
    with hyphens, collapse runs, strip ONE leading and ONE trailing hyphen,
    truncate to 80 bytes.\"\"\"
    s = re.sub(r'[^a-z0-9]', '-', title.lower())
    s = re.sub(r'-+', '-', s)
    if s.startswith('-'):
        s = s[1:]
    if s.endswith('-'):
        s = s[:-1]
    return s[:80]

issues = []
claims_by_title = {}  # title -> [(slug, owner)]
claims_by_slug = {}   # slug -> claim data

for fname in sorted(os.listdir(claims_dir)):
    if not fname.endswith('.json'):
        continue
    slug = fname[:-5]
    fpath = os.path.join(claims_dir, fname)
    try:
        with open(fpath) as f:
            claim = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        issues.append({'type': 'invalid_json', 'file': fname, 'error': str(e)})
        continue

    claims_by_slug[slug] = claim
    title = claim.get('task_title', '')
    owner = claim.get('agent_worktree', '')

    # Check slug/title mismatch
    canonical = slug_from_title(title)
    if canonical and slug != canonical:
        issues.append({
            'type': 'slug_mismatch',
            'file': fname,
            'current_slug': slug,
            'canonical_slug': canonical,
            'title': title
        })

    # Track titles for duplicate detection
    if title:
        claims_by_title.setdefault(title, []).append((slug, owner))

    # Check orphaned worktrees
    if owner and owner not in worktree_names:
        issues.append({
            'type': 'orphaned_worktree',
            'file': fname,
            'owner': owner,
            'title': title
        })

    # Check shipped claims have required fields
    state = claim.get('state', 'claimed')
    if state == 'shipped':
        for field in ('pr_number', 'pr_url', 'shipped_at'):
            if not claim.get(field):
                issues.append({
                    'type': 'shipped_missing_field',
                    'file': fname,
                    'field': field,
                    'owner': owner,
                    'title': title
                })

    # Check expired (skip shipped claims — they are released by auto-release-merged)
    if state != 'shipped':
        try:
            mtime = os.path.getmtime(fpath)
            age_min = (time.time() - mtime) / 60
            if age_min > ttl:
                issues.append({
                    'type': 'expired',
                    'file': fname,
                    'age_minutes': int(age_min),
                    'ttl_minutes': ttl,
                    'owner': owner,
                    'title': title
                })
        except OSError:
            pass

# Check duplicate titles
for title, entries in claims_by_title.items():
    if len(entries) > 1:
        issues.append({
            'type': 'duplicate_title',
            'title': title,
            'claims': [{'slug': s, 'owner': o} for s, o in entries]
        })

result = {
    'issues': issues,
    'total_claims': len(claims_by_slug),
    'issue_count': len(issues),
    'healthy': len(issues) == 0
}
print(json.dumps(result, indent=2))
"
}

cmd_max_claimed_version() {
    mkdir -p "$CLAIMS_DIR"
    local ttl
    ttl=$(get_ttl)

    # Collect all non-expired speculated versions and find the highest
    python3 -c "
import json, os, sys, time

claims_dir = '${CLAIMS_DIR}'
ttl_seconds = ${ttl} * 60
versions = []
now = time.time()

for fname in sorted(os.listdir(claims_dir)):
    if not fname.endswith('.json'):
        continue
    fpath = os.path.join(claims_dir, fname)
    try:
        with open(fpath) as f:
            claim = json.load(f)
        # Shipped claims are still active; only skip expired non-shipped claims
        state = claim.get('state', 'claimed')
        if state != 'shipped':
            mtime = os.path.getmtime(fpath)
            if (now - mtime) > ttl_seconds:
                continue
        v = claim.get('speculated_version')
        if v:
            versions.append(v)
    except (json.JSONDecodeError, KeyError, OSError):
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

cmd_try_claim() {
    # Try claiming tasks from a JSON candidate list until <count> succeed.
    # Avoids the need for agents to write inline bash loops.
    #
    # Usage: work-queue.sh try-claim <count> <json_file>
    #   json_file: path to a JSON array of candidate tasks, or "-" for stdin
    #   Each element: {"title": "...", "section": "...", "role_tag": "...", "version": "...", "purpose": "..."}
    #   "title" is required; all other fields are optional.
    #
    # Output: JSON object with "claimed" and "skipped" arrays, plus "wanted" and "got" counts.

    local count="${1:-1}"
    local json_file="${2:--}"

    # Read candidates from file or stdin into a temp file for Python
    local tmp_input=""
    if [[ "$json_file" == "-" ]]; then
        tmp_input=$(mktemp "${TMPDIR:-/tmp}/wq-try-claim.XXXXXX")
        cat > "$tmp_input"
        json_file="$tmp_input"
    fi

    if [[ ! -f "$json_file" ]]; then
        echo "Error: candidates file not found: $json_file" >&2
        exit 1
    fi

    local script_path
    script_path=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/$(basename "${BASH_SOURCE[0]}")

    python3 -c "
import json, subprocess, sys, os

with open(sys.argv[1]) as f:
    candidates = json.load(f)

count = int(sys.argv[2])
script = sys.argv[3]
worktree = sys.argv[4]
claimed = []
skipped = []

for task in candidates:
    if len(claimed) >= count:
        break

    title = task.get('title', '')
    if not title:
        skipped.append({'title': '(empty)', 'status': 'INVALID_NO_TITLE'})
        continue

    slug = task.get('slug', 'placeholder')
    section = task.get('section', '')
    role_tag = task.get('role_tag', '')
    version = task.get('version', '')
    purpose = task.get('purpose', '')

    result = subprocess.run(
        [script, 'claim', slug, title, section, role_tag, version, purpose],
        capture_output=True, text=True,
        env={**os.environ, 'WORK_QUEUE_WORKTREE': worktree}
    )

    # Last non-empty line of stdout is the status
    lines = [l for l in result.stdout.strip().split('\n') if l.strip()]
    status = lines[-1] if lines else 'ERROR'

    if status in ('CLAIMED', 'EXPIRED_RECLAIMED', 'ALREADY_OWNED'):
        claimed.append({
            'title': title,
            'section': section,
            'role_tag': role_tag,
            'status': status
        })
    else:
        skipped.append({
            'title': title,
            'status': status
        })

output = {
    'claimed': claimed,
    'skipped': skipped,
    'wanted': count,
    'got': len(claimed)
}
print(json.dumps(output, indent=2))
" "$json_file" "$count" "$script_path" "$WORKTREE_NAME"

    # Clean up temp file
    if [[ -n "$tmp_input" ]]; then
        rm -f "$tmp_input"
    fi
}

cmd_mark_reviewed() {
    local slug="$1"
    local sha="${2:-}"
    mkdir -p "$REVIEWED_DIR"

    # Resolve SHA if not provided
    if [[ -z "$sha" ]]; then
        sha=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    fi

    local marker_file="${REVIEWED_DIR}/${slug}.json"
    local tmp_file="${REVIEWED_DIR}/${slug}.tmp.$$"
    python3 -c "
import json
marker = {
    'task_slug': '${slug}',
    'reviewed_by': '${WORKTREE_NAME}',
    'reviewed_at': '$(now_iso)',
    'reviewed_sha': '${sha}'
}
with open('${tmp_file}', 'w') as f:
    json.dump(marker, f, indent=2)
"
    mv -f "$tmp_file" "$marker_file"
    echo "MARKED_REVIEWED"
    return 0
}

cmd_is_reviewed() {
    local slug="$1"
    local marker_file="${REVIEWED_DIR}/${slug}.json"

    if [[ -f "$marker_file" ]]; then
        local reviewer
        reviewer=$(python3 -c "import json; print(json.load(open('$marker_file'))['reviewed_by'])" 2>/dev/null) || true
        echo "REVIEWED_BY:${reviewer}"
        return 0
    fi

    echo "NOT_REVIEWED"
    return 0
}

cmd_list_reviewed() {
    mkdir -p "$REVIEWED_DIR"
    echo "["
    local first=true
    for marker_file in "$REVIEWED_DIR"/*.json; do
        [[ -f "$marker_file" ]] || continue
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        python3 -c "
import json
with open('$marker_file') as f:
    print('  ' + json.dumps(json.load(f)), end='')
"
    done
    echo ""
    echo "]"
}

cmd_clean_review() {
    local slug="$1"
    local count=0

    local review_file="${REVIEWS_DIR}/${slug}.md"
    if [[ -f "$review_file" ]]; then
        rm -f "$review_file"
        count=$((count + 1))
    fi

    local marker_file="${REVIEWED_DIR}/${slug}.json"
    if [[ -f "$marker_file" ]]; then
        rm -f "$marker_file"
        count=$((count + 1))
    fi

    echo "CLEANED:${count}"
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
            echo "Usage: work-queue.sh claim <slug> [title] [section] [role_tag] [version] [purpose]" >&2
            exit 1
        fi
        cmd_claim "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}"
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
    mark-shipped)
        if [[ $# -lt 2 ]]; then
            echo "Usage: work-queue.sh mark-shipped <pr_number> <pr_url>" >&2
            exit 1
        fi
        cmd_mark_shipped "$1" "$2"
        ;;
    auto-release-merged)
        cmd_auto_release_merged
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
    validate)
        cmd_validate
        ;;
    try-claim)
        cmd_try_claim "${1:-1}" "${2:--}"
        ;;
    mark-reviewed)
        if [[ $# -lt 1 ]]; then
            echo "Usage: work-queue.sh mark-reviewed <slug> [sha]" >&2
            exit 1
        fi
        cmd_mark_reviewed "$1" "${2:-}"
        ;;
    is-reviewed)
        if [[ $# -lt 1 ]]; then
            echo "Usage: work-queue.sh is-reviewed <slug>" >&2
            exit 1
        fi
        cmd_is_reviewed "$1"
        ;;
    list-reviewed)
        cmd_list_reviewed
        ;;
    clean-review)
        if [[ $# -lt 1 ]]; then
            echo "Usage: work-queue.sh clean-review <slug>" >&2
            exit 1
        fi
        cmd_clean_review "$1"
        ;;
    help|--help|-h)
        echo "Usage: work-queue.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  init                          Initialize the work queue directory"
        echo "  claim <slug> [title] [section] [role] [version] [purpose]  Claim a task"
        echo "  release <slug> [--force]      Release a claimed task"
        echo "  release-all                   Release all claims for this worktree"
        echo "  mark-shipped <pr> <url>       Transition this worktree's claims to shipped"
        echo "  auto-release-merged           Release shipped claims whose PRs are merged/closed"
        echo "  list                          List all active claims (JSON)"
        echo "  check <slug>                  Check if a task is claimed"
        echo "  claimed-by-me                 List tasks claimed by this worktree"
        echo "  expire                        Remove claims past TTL"
        echo "  inflight-tasks                List tasks completed in open PRs (JSON)"
        echo "  max-claimed-version           Show highest speculated version across claims"
        echo "  validate                      Health check: detect slug mismatches, duplicates, orphans, expired"
        echo "  try-claim <count> <json_file> Try claiming tasks from a candidates file (or - for stdin)"
        echo "  mark-reviewed <slug> [sha]    Record that a task has been reviewed"
        echo "  is-reviewed <slug>            Check if a task has been reviewed"
        echo "  list-reviewed                 List all reviewed tasks (JSON)"
        echo "  clean-review <slug>           Delete review file and reviewed marker for a task"
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
