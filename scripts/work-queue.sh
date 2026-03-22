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
#   work-queue.sh refresh-active                               # Refresh expired claims whose worktree still exists
#   work-queue.sh init                                         # Ensure queue directory exists
#   work-queue.sh inflight-tasks                               # List tasks completed in open PRs (not yet merged)
#   work-queue.sh max-claimed-version                          # Show highest speculated version across all claims
#   work-queue.sh validate                                     # Health check: detect claim issues
#   work-queue.sh mark-shipped <pr_number> <pr_url>            # Transition this worktree's claims to shipped
#   work-queue.sh auto-release-merged                          # Release shipped claims whose PRs are merged/closed
#   work-queue.sh check-overlap <files_json>                   # Check if files overlap with active claims
#   work-queue.sh mark-reviewed <slug> [sha]                   # Record that a task has been reviewed
#   work-queue.sh is-reviewed <slug>                           # Check if a task has been reviewed
#   work-queue.sh list-reviewed                                # List all reviewed tasks
#   work-queue.sh reconcile <task_slug>                         # Find competing PRs for a task and show diff summaries
#   work-queue.sh clean-review <slug>                          # Delete review file and reviewed marker
#   work-queue.sh coordination-snapshot [--full]               # Show worktrees, claims, and optionally open PRs

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
DEFAULT_TTL=600

# --- Helper functions ---

_json_field() {
    # Extract a single field from a JSON file.
    # Usage: _json_field <file> <field> [default]
    # Returns the field value, or default (empty string if unset) on any error.
    local file="$1"
    local field="$2"
    local default="${3:-}"
    _WQ_JF_FILE="$file" _WQ_JF_FIELD="$field" _WQ_JF_DEFAULT="$default" \
    python3 -c "
import json, os
try:
    with open(os.environ['_WQ_JF_FILE']) as f:
        data = json.load(f)
    val = data.get(os.environ['_WQ_JF_FIELD'])
    print(val if val is not None else os.environ['_WQ_JF_DEFAULT'])
except Exception:
    print(os.environ['_WQ_JF_DEFAULT'])
" 2>/dev/null || echo "$default"
}

get_ttl() {
    if [[ -f "$CONFIG_FILE" ]]; then
        _json_field "$CONFIG_FILE" "ttl_minutes" "$DEFAULT_TTL"
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

_atomic_write() {
    # Write content to a file atomically using temp-file + mv.
    # Usage: echo "content" | _atomic_write /path/to/target
    # Or:   _atomic_write /path/to/target < <(generate_content)
    #
    # Creates a temp file in the same directory as target, writes stdin to it,
    # then atomically renames. Cleans up temp file on any failure.
    local target="$1"
    local target_dir
    target_dir=$(dirname "$target")
    mkdir -p "$target_dir"
    local tmp_file
    tmp_file=$(mktemp "${target_dir}/.tmp.XXXXXX")
    # Ensure cleanup on failure
    if ! cat > "$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi
    if ! mv -f "$tmp_file" "$target"; then
        rm -f "$tmp_file"
        return 1
    fi
    return 0
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
        title=$(_json_field "$claim_file" "task_title" "") || continue
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
    if [[ ! -f "$CONFIG_FILE" ]]; then
        _atomic_write "$CONFIG_FILE" << 'CONF'
{
    "ttl_minutes": 600
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
    local claimed_files_json="${7:-[]}"

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
        existing_owner=$(_json_field "${CLAIMS_DIR}/${existing_slug}.json" "agent_worktree" "")
        echo "DUPLICATE_TITLE:${existing_slug}:${existing_owner}" >&2
        _release_lock
        echo "DUPLICATE_TITLE"
        return 1
    fi

    local claim_file="${CLAIMS_DIR}/${slug}.json"

    # Check if already claimed
    if [[ -f "$claim_file" ]]; then
        local owner
        owner=$(_json_field "$claim_file" "agent_worktree" "")
        if [[ "$owner" == "$WORKTREE_NAME" ]]; then
            _release_lock
            echo "ALREADY_OWNED"
            return 0
        fi

        # Check claim state and age
        local state
        state=$(_json_field "$claim_file" "state" "claimed")

        if [[ "$state" == "shipped" ]]; then
            # Shipped claims can be reclaimed — the prior repair was pushed
            # but the PR may still be broken (CI failed again). Safe because
            # ./bin/broken-prs only lists PRs with confirmed CI failures.
            echo "SHIPPED_RECLAIMED"
            # Fall through to write new claim
        else
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
    fi

    # Write claim atomically via _atomic_write (temp file + mv)
    ttl=$(get_ttl)
    _WQ_SLUG="$slug" _WQ_TITLE="$title" _WQ_SECTION="$section" \
    _WQ_ROLE_TAG="$role_tag" _WQ_WORKTREE="$WORKTREE_NAME" \
    _WQ_CLAIMED_AT="$(now_iso)" _WQ_TTL="$ttl" \
    _WQ_VERSION="$version" _WQ_PURPOSE="$purpose" \
    _WQ_CLAIMED_FILES="$claimed_files_json" \
    python3 -c "
import json, os, sys
claimed_files_raw = os.environ.get('_WQ_CLAIMED_FILES', '[]')
try:
    claimed_files = json.loads(claimed_files_raw)
    if not isinstance(claimed_files, list):
        claimed_files = []
except (json.JSONDecodeError, TypeError):
    claimed_files = []
claim = {
    'task_slug': os.environ['_WQ_SLUG'],
    'task_title': os.environ['_WQ_TITLE'],
    'section': os.environ['_WQ_SECTION'],
    'role_tag': os.environ['_WQ_ROLE_TAG'],
    'agent_worktree': os.environ['_WQ_WORKTREE'],
    'claimed_at': os.environ['_WQ_CLAIMED_AT'],
    'ttl_minutes': int(os.environ['_WQ_TTL']),
    'speculated_version': os.environ['_WQ_VERSION'] or None,
    'purpose': os.environ['_WQ_PURPOSE'] or None,
    'claimed_files': claimed_files
}
sys.stdout.write(json.dumps(claim, indent=2))
" | _atomic_write "$claim_file"

    # Post-write verification: confirm our worktree owns the claim
    local verify_owner
    verify_owner=$(_json_field "$claim_file" "agent_worktree" "")
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
    owner=$(_json_field "$claim_file" "agent_worktree" "")

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
        owner=$(_json_field "$claim_file" "agent_worktree" "") || continue
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
        owner=$(_json_field "$claim_file" "agent_worktree" "") || continue
        [[ "$owner" == "$WORKTREE_NAME" ]] || continue

        local slug
        slug=$(basename "$claim_file" .json)
        if ! _acquire_lock "$slug"; then
            echo "LOCK_FAILED:${slug}" >&2
            continue
        fi

        _WQ_CLAIM_FILE="$claim_file" _WQ_PR_NUMBER="$pr_number" \
        _WQ_PR_URL="$pr_url" _WQ_SHIPPED_AT="$(now_iso)" \
        python3 -c "
import json, os, sys
with open(os.environ['_WQ_CLAIM_FILE']) as f:
    claim = json.load(f)
claim['state'] = 'shipped'
claim['pr_number'] = int(os.environ['_WQ_PR_NUMBER'])
claim['pr_url'] = os.environ['_WQ_PR_URL']
claim['shipped_at'] = os.environ['_WQ_SHIPPED_AT']
sys.stdout.write(json.dumps(claim, indent=2))
" | _atomic_write "$claim_file"
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
        state=$(_json_field "$claim_file" "state" "claimed") || continue
        [[ "$state" == "shipped" ]] || continue

        local pr_number
        pr_number=$(_json_field "$claim_file" "pr_number" "") || continue
        [[ -n "$pr_number" ]] || continue

        local pr_state
        pr_state=$(gh pr view "$pr_number" --json state --jq '.state' 2>/dev/null) || continue

        if [[ "$pr_state" == "MERGED" || "$pr_state" == "CLOSED" ]]; then
            local slug
            slug=$(basename "$claim_file" .json)

            # Auto-complete task file if the PR was merged and the task
            # is still in next-steps/active/
            if [[ "$pr_state" == "MERGED" ]]; then
                local task_file="${MAIN_REPO}/next-steps/active/${slug}.md"
                if [[ -f "$task_file" ]]; then
                    local task_format="${MAIN_REPO}/scripts/task-format.py"
                    local py="${MAIN_REPO}/.venv/bin/python"
                    if [[ -x "$py" && -f "$task_format" ]]; then
                        "$py" "$task_format" complete-task "$slug" \
                            --summary "Merged in PR #${pr_number}" 2>/dev/null && \
                            echo "COMPLETED:${slug}:PR#${pr_number}" || true
                    fi
                fi
            fi

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

    # Collect valid claim JSON entries into an array, skipping empty/malformed files
    local entries=()
    for claim_file in "$CLAIMS_DIR"/*.json; do
        [[ -f "$claim_file" ]] || continue
        [[ -s "$claim_file" ]] || continue  # skip empty files
        local age
        age=$(file_age_minutes "$claim_file")
        local state
        state=$(_json_field "$claim_file" "state" "claimed")
        local expired="false"
        if [[ "$state" != "shipped" ]] && (( age > ttl )); then
            expired="true"
        fi

        # Read the claim and add age/expired fields
        local claim_json
        claim_json=$(_WQ_FILE="$claim_file" _WQ_AGE="$age" _WQ_EXPIRED="$expired" \
        python3 -c "
import json, os, sys
try:
    with open(os.environ['_WQ_FILE']) as f:
        claim = json.load(f)
    claim['state'] = claim.get('state', 'claimed')
    claim['age_minutes'] = int(os.environ['_WQ_AGE'])
    claim['expired'] = os.environ['_WQ_EXPIRED'] == 'true'
    print('    ' + json.dumps(claim), end='')
except Exception:
    sys.exit(1)
" 2>/dev/null) || continue
        entries+=("$claim_json")
    done

    # Emit valid JSON with proper comma separation
    echo "{"
    echo '  "claims": ['
    local i
    for (( i=0; i<${#entries[@]}; i++ )); do
        if (( i > 0 )); then
            echo ","
        fi
        echo -n "${entries[$i]}"
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
    owner=$(_json_field "$claim_file" "agent_worktree" "")

    local state
    state=$(_json_field "$claim_file" "state" "claimed")
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
        owner=$(_json_field "$claim_file" "agent_worktree" "") || continue
        if [[ "$owner" == "$WORKTREE_NAME" ]]; then
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            _WQ_FILE="$claim_file" python3 -c "
import json, os
with open(os.environ['_WQ_FILE']) as f:
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
        state=$(_json_field "$claim_file" "state" "claimed")
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

cmd_refresh_active() {
    # Refresh expired/near-expired claims when the owning worktree still exists
    # AND shows recent activity (files modified within the last 30 minutes).
    #
    # Activity is detected by checking if any files referenced by the task
    # (from the claim's claimed_files or the technical review's Files Involved)
    # have been modified recently in the owning worktree's working directory.
    # Falls back to checking git status (any uncommitted changes) if no file
    # list is available.
    #
    # Usage: work-queue.sh refresh-active
    # Output: JSON with refreshed, stale, and orphaned arrays
    #
    # Safe to call from read-only tools (task-board.py) because it only
    # extends existing claims — never creates, deletes, or reassigns them.

    mkdir -p "$CLAIMS_DIR"
    local ttl
    ttl=$(get_ttl)

    # Build worktree name=path lines for Python consumption
    local worktree_mapping=""
    while IFS= read -r line; do
        [[ "$line" =~ ^worktree\ (.+) ]] || continue
        local wt_path="${BASH_REMATCH[1]}"
        local wt_name
        if [[ "$wt_path" == "$MAIN_REPO" ]]; then
            wt_name="main"
        else
            wt_name=$(basename "$wt_path")
        fi
        worktree_mapping="${worktree_mapping}${wt_name}=${wt_path}"$'\n'
    done < <(git worktree list --porcelain 2>/dev/null)

    # Collect results via Python for clean JSON output
    _WQ_CLAIMS_DIR="$CLAIMS_DIR" _WQ_REVIEWS_DIR="$REVIEWS_DIR" \
    _WQ_TTL="$ttl" _WQ_ACTIVITY_WINDOW=30 \
    _WQ_WORKTREE_MAP="$worktree_mapping" \
    python3 -c "
import glob, json, os, re, subprocess, sys, time

claims_dir = os.environ['_WQ_CLAIMS_DIR']
reviews_dir = os.environ.get('_WQ_REVIEWS_DIR', '')
ttl = int(os.environ['_WQ_TTL'])
activity_window = int(os.environ['_WQ_ACTIVITY_WINDOW']) * 60  # seconds
now = time.time()
refresh_threshold = ttl * 60 * 0.8  # 80% of TTL in seconds

# Read worktree name→path mapping from env
worktree_paths = {}
for line in os.environ.get('_WQ_WORKTREE_MAP', '').strip().split('\n'):
    if '=' in line:
        name, path = line.split('=', 1)
        worktree_paths[name] = path

def get_task_files(slug, claim):
    \"\"\"Get file list from claim or technical review.\"\"\"
    # 1. Try claimed_files from the claim itself
    files = claim.get('claimed_files', [])
    if files:
        return files

    # 2. Try technical review file (## Files Involved section)
    if reviews_dir:
        # Review slug may differ slightly from claim slug — try variations
        for review_name in [slug, slug.replace('pages', '').rstrip('-')]:
            for review_file in glob.glob(os.path.join(reviews_dir, f'*{review_name}*')):
                if not os.path.isfile(review_file):
                    continue
                try:
                    content = open(review_file).read()
                    # Extract file paths from ## Files Involved section
                    match = re.search(
                        r'## Files Involved\n((?:- .+\n)+)', content
                    )
                    if match:
                        return [
                            line.lstrip('- ').strip()
                            for line in match.group(1).strip().split('\n')
                            if line.strip().startswith('- ')
                        ]
                except OSError:
                    continue
    return []

def has_recent_activity(worktree_path, task_files):
    \"\"\"Check if the worktree shows recent activity within activity_window.

    Three strategies, checked in order (short-circuit on first hit):
    1. Recent git commits (most reliable — survives commit mtime reset)
    2. Uncommitted file changes with recent mtimes
    3. Task-specific file mtimes (for uncommitted work in progress)
    \"\"\"
    cutoff = now - activity_window

    # Strategy 1: Recent git commits in this worktree
    # git log --since is the strongest signal — a commit within the window
    # means the agent was definitely active recently.
    try:
        window_min = int(activity_window / 60)
        result = subprocess.run(
            ['git', '-C', worktree_path, 'log',
             f'--since={window_min} minutes ago',
             '--oneline', '-1'],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0 and result.stdout.strip():
            return True
    except (subprocess.TimeoutExpired, OSError):
        pass

    # Strategy 2: Uncommitted changes with recent file mtimes
    try:
        result = subprocess.run(
            ['git', '-C', worktree_path, 'status', '--porcelain'],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0 and result.stdout.strip():
            for line in result.stdout.strip().split('\n'):
                # git status --porcelain format: XY filename
                fname = line[3:].strip().strip('\"')
                full_path = os.path.join(worktree_path, fname)
                try:
                    if os.path.getmtime(full_path) > cutoff:
                        return True
                except OSError:
                    continue
    except (subprocess.TimeoutExpired, OSError):
        pass

    # Strategy 3: Task-specific file mtimes (for work in progress)
    if task_files:
        for f in task_files:
            full_path = os.path.join(worktree_path, f)
            try:
                if os.path.getmtime(full_path) > cutoff:
                    return True
            except OSError:
                continue

    return False

refreshed = []
stale = []
orphaned = []

for fname in sorted(os.listdir(claims_dir)):
    if not fname.endswith('.json'):
        continue
    fpath = os.path.join(claims_dir, fname)
    try:
        with open(fpath) as f:
            claim = json.load(f)
    except (json.JSONDecodeError, OSError):
        continue

    # Skip shipped claims
    state = claim.get('state', 'claimed')
    if state == 'shipped':
        continue

    # Only consider claims past 80% of TTL
    try:
        age_s = now - os.path.getmtime(fpath)
    except OSError:
        continue
    if age_s < refresh_threshold:
        continue

    slug = fname[:-5]
    owner = claim.get('agent_worktree', '')
    age_min = int(age_s / 60)

    # Check if worktree exists
    wt_path = worktree_paths.get(owner)
    if not wt_path:
        orphaned.append({'slug': slug, 'owner': owner, 'age_minutes': age_min})
        continue

    # Check for recent activity
    task_files = get_task_files(slug, claim)
    if has_recent_activity(wt_path, task_files):
        # Touch the claim file to reset mtime
        os.utime(fpath, None)
        refreshed.append({
            'slug': slug, 'owner': owner, 'age_minutes': age_min,
            'files_checked': len(task_files)
        })
    else:
        stale.append({
            'slug': slug, 'owner': owner, 'age_minutes': age_min,
            'worktree_exists': True
        })

result = {
    'refreshed': refreshed,
    'stale': stale,
    'orphaned': orphaned,
    'refreshed_count': len(refreshed),
    'stale_count': len(stale),
    'orphaned_count': len(orphaned),
}
print(json.dumps(result, indent=2))
"
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

    # Get open PR numbers, filtering to only those that touch relevant files.
    # Uses --json files (single API call) to skip PRs that don't touch
    # NEXT-STEPS.md or next-steps/. Falls back to fetching all PRs if the
    # files field is unavailable (older gh CLI versions).
    local pr_numbers
    local pr_json
    pr_json=$(gh pr list --state open --json number,files,body 2>/dev/null)
    local gh_rc=$?

    if [[ $gh_rc -ne 0 ]]; then
        echo "[]"
        echo "warning: gh pr list failed — skipping in-flight PR check" >&2
        return 0
    fi

    if [[ -z "$pr_json" ]]; then
        echo "[]"
        return 0
    fi

    # Filter to PRs touching NEXT-STEPS.md or next-steps/ using Python.
    # If files data is null/missing (old gh), fall back to all PR numbers.
    pr_numbers=$(export _WQ_PR_JSON="$pr_json"; python3 -c "
import json, os
data = json.loads(os.environ['_WQ_PR_JSON'])
if not data:
    raise SystemExit(0)
# Check if files field is populated (not None) on at least one PR
has_files = any(pr.get('files') is not None for pr in data)
if not has_files:
    # files field not available — return all PR numbers (fallback)
    for pr in data:
        print(pr['number'])
    raise SystemExit(0)
# Filter to PRs that touch relevant files
for pr in data:
    files = pr.get('files') or []
    paths = [f.get('path', '') for f in files]
    if any(p == 'NEXT-STEPS.md' or p.startswith('next-steps/') for p in paths):
        print(pr['number'])
" 2>/dev/null) || {
        echo "[]"
        echo "warning: PR file filtering failed — skipping in-flight PR check" >&2
        return 0
    }

    if [[ -z "$pr_numbers" ]]; then
        echo "[]"
        return 0
    fi

    # For each relevant PR, get the diff and extract completed task titles
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

    # Method 3: Scan PR bodies for task ID references (e.g. "Closes T1132", "T1132")
    # and resolve them to task titles from active task files.
    local body_titles
    body_titles=$(export _WQ_PR_JSON="$pr_json"; python3 -c "
import json, os, re, glob

data = json.loads(os.environ['_WQ_PR_JSON'])
if not data:
    raise SystemExit(0)

# Collect all task IDs referenced in PR bodies
referenced_ids = set()
for pr in data:
    body = pr.get('body') or ''
    # Match T followed by 3+ digits (task IDs like T1132)
    ids = re.findall(r'T(\d{3,})', body)
    for tid in ids:
        referenced_ids.add(f'T{tid}')

if not referenced_ids:
    raise SystemExit(0)

# Scan active task files to resolve IDs to titles
task_dir = os.path.join('next-steps', 'active')
if not os.path.isdir(task_dir):
    raise SystemExit(0)

for fpath in sorted(glob.glob(os.path.join(task_dir, '*.md'))):
    with open(fpath) as f:
        content = f.read()
    # Check if any referenced ID appears in the frontmatter
    for tid in list(referenced_ids):
        if re.search(rf'^id:\s*{re.escape(tid)}\s*$', content, re.MULTILINE):
            # Extract title from # heading
            m = re.search(r'^# (.+)', content, re.MULTILINE)
            if m:
                print(m.group(1).strip())
            referenced_ids.discard(tid)
" 2>/dev/null) || true

    if [[ -n "$body_titles" ]]; then
        if [[ -n "$all_titles" ]]; then
            all_titles="${all_titles}"$'\n'"${body_titles}"
        else
            all_titles="$body_titles"
        fi
    fi

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

    _WQ_CLAIMS_DIR="$CLAIMS_DIR" _WQ_TTL="$ttl" \
    _WQ_WORKTREE_NAMES="$worktree_names" \
    python3 -c "
import json, os, re, sys, time

claims_dir = os.environ['_WQ_CLAIMS_DIR']
ttl = int(os.environ['_WQ_TTL'])
worktree_names = set(os.environ['_WQ_WORKTREE_NAMES'].strip().split('\n'))

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
    _WQ_CLAIMS_DIR="$CLAIMS_DIR" _WQ_TTL="$ttl" \
    python3 -c "
import json, os, sys, time

claims_dir = os.environ['_WQ_CLAIMS_DIR']
ttl_seconds = int(os.environ['_WQ_TTL']) * 60
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
    #   Each element: {"title": "...", "section": "...", "roles": [...], "version": "...", "purpose": "..."}
    #   "title" is required; all other fields are optional.
    #   "roles" (array) is preferred; "role_tag" (string) is accepted for backward compat.
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
    roles = task.get('roles', [])
    role_tag = ','.join(roles) if isinstance(roles, list) and roles else task.get('role_tag', '')
    version = task.get('version', '')
    purpose = task.get('purpose', '')
    files = task.get('files', [])
    files_json = json.dumps(files) if files else '[]'

    result = subprocess.run(
        [script, 'claim', slug, title, section, role_tag, version, purpose, files_json],
        capture_output=True, text=True,
        env={**os.environ, 'WORK_QUEUE_WORKTREE': worktree}
    )

    # Last non-empty line of stdout is the status
    lines = [l for l in result.stdout.strip().split('\n') if l.strip()]
    status = lines[-1] if lines else 'ERROR'

    if status in ('CLAIMED', 'EXPIRED_RECLAIMED', 'SHIPPED_RECLAIMED', 'ALREADY_OWNED'):
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

cmd_check_overlap() {
    # Check if a set of files overlaps with files claimed by active (non-expired,
    # non-shipped) claims at the directory level.
    #
    # Usage: work-queue.sh check-overlap <files_json>
    #   files_json: JSON array of file paths, or "-" for stdin
    #
    # Output: JSON object with "overlapping_claims" array containing claims whose
    # claimed_files share at least one parent directory with the input files.

    local files_input="${1:--}"
    local files_json=""

    if [[ "$files_input" == "-" ]]; then
        files_json=$(cat)
    else
        files_json="$files_input"
    fi

    mkdir -p "$CLAIMS_DIR"
    local ttl
    ttl=$(get_ttl)

    _WQ_FILES_JSON="$files_json" _WQ_CLAIMS_DIR="$CLAIMS_DIR" \
    _WQ_TTL="$ttl" _WQ_WORKTREE="$WORKTREE_NAME" \
    python3 -c "
import json, os, sys, time

files_json = os.environ['_WQ_FILES_JSON']
claims_dir = os.environ['_WQ_CLAIMS_DIR']
ttl_seconds = int(os.environ['_WQ_TTL']) * 60
current_worktree = os.environ['_WQ_WORKTREE']

try:
    input_files = json.loads(files_json)
    if not isinstance(input_files, list):
        input_files = []
except (json.JSONDecodeError, TypeError):
    input_files = []

def get_dirs(file_list):
    \"\"\"Extract the immediate parent directory of each file path.\"\"\"
    dirs = set()
    for f in file_list:
        parts = f.rstrip('/').split('/')
        if len(parts) > 1:
            dirs.add('/'.join(parts[:-1]))
    return dirs

input_dirs = get_dirs(input_files)
now = time.time()
overlapping = []

for fname in sorted(os.listdir(claims_dir)):
    if not fname.endswith('.json'):
        continue
    fpath = os.path.join(claims_dir, fname)
    try:
        with open(fpath) as f:
            claim = json.load(f)
    except (json.JSONDecodeError, OSError):
        continue

    # Skip shipped claims
    state = claim.get('state', 'claimed')
    if state == 'shipped':
        continue

    # Skip expired claims
    try:
        mtime = os.path.getmtime(fpath)
        if (now - mtime) > ttl_seconds:
            continue
    except OSError:
        continue

    # Skip own claims
    owner = claim.get('agent_worktree', '')
    if owner == current_worktree:
        continue

    # Check directory-level overlap
    claimed_files = claim.get('claimed_files', [])
    if not claimed_files:
        continue

    claim_dirs = get_dirs(claimed_files)
    shared_dirs = input_dirs & claim_dirs
    if shared_dirs:
        overlapping.append({
            'task_slug': claim.get('task_slug', fname[:-5]),
            'task_title': claim.get('task_title', ''),
            'agent_worktree': owner,
            'overlapping_dirs': sorted(shared_dirs),
            'claimed_files': claimed_files
        })

result = {
    'overlapping_claims': overlapping,
    'overlap_count': len(overlapping)
}
print(json.dumps(result, indent=2))
"
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
    _WQ_SLUG="$slug" _WQ_WORKTREE="$WORKTREE_NAME" \
    _WQ_REVIEWED_AT="$(now_iso)" _WQ_SHA="$sha" \
    python3 -c "
import json, os, sys
marker = {
    'task_slug': os.environ['_WQ_SLUG'],
    'reviewed_by': os.environ['_WQ_WORKTREE'],
    'reviewed_at': os.environ['_WQ_REVIEWED_AT'],
    'reviewed_sha': os.environ['_WQ_SHA']
}
sys.stdout.write(json.dumps(marker, indent=2))
" | _atomic_write "$marker_file"
    echo "MARKED_REVIEWED"
    return 0
}

cmd_is_reviewed() {
    local slug="$1"
    local marker_file="${REVIEWED_DIR}/${slug}.json"

    if [[ -f "$marker_file" ]]; then
        local reviewer
        reviewer=$(_json_field "$marker_file" "reviewed_by" "")
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
        _WQ_FILE="$marker_file" python3 -c "
import json, os
with open(os.environ['_WQ_FILE']) as f:
    print('  ' + json.dumps(json.load(f)), end='')
"
    done
    echo ""
    echo "]"
}

cmd_reconcile() {
    # Find competing PRs for a given task slug and show diff summaries.
    # Does NOT auto-merge — presents information for human decision.
    #
    # Usage: work-queue.sh reconcile <task_slug>
    # Output: JSON object with competing PR details and diff summaries

    local slug="$1"

    if ! command -v gh &>/dev/null; then
        echo '{"error": "gh CLI not found — cannot search for competing PRs"}' >&2
        exit 1
    fi

    # Search for open PRs mentioning this task slug in title or body
    local pr_json
    pr_json=$(gh pr list --state open --json number,title,url,author,headRefName,body,createdAt \
        --search "$slug" 2>/dev/null) || {
        echo '{"error": "gh pr list failed"}' >&2
        exit 1
    }

    if [[ -z "$pr_json" || "$pr_json" == "[]" ]]; then
        echo '{"competing_prs": [], "slug": "'"$slug"'"}'
        return 0
    fi

    # Filter to PRs that actually reference this slug (title, body, or branch name)
    local filtered
    filtered=$(export _WQ_SLUG="$slug" _WQ_PR_JSON="$pr_json"; python3 -c "
import json, os
slug = os.environ['_WQ_SLUG']
prs = json.loads(os.environ['_WQ_PR_JSON'])
matches = []
for pr in prs:
    title = (pr.get('title') or '').lower()
    body = (pr.get('body') or '').lower()
    branch = (pr.get('headRefName') or '').lower()
    slug_lower = slug.lower()
    # Check slug presence in title, body, or branch name
    if slug_lower in title or slug_lower in body or slug_lower in branch:
        matches.append(pr)
print(json.dumps(matches))
" 2>/dev/null) || {
        echo '{"error": "PR filtering failed"}' >&2
        exit 1
    }

    if [[ "$filtered" == "[]" ]]; then
        echo '{"competing_prs": [], "slug": "'"$slug"'"}'
        return 0
    fi

    # For each competing PR, get a diff stat summary
    local result
    result=$(export _WQ_SLUG="$slug" _WQ_FILTERED="$filtered"; python3 -c "
import json, os, subprocess
slug = os.environ['_WQ_SLUG']
prs = json.loads(os.environ['_WQ_FILTERED'])
results = []
for pr in prs:
    pr_num = pr['number']
    # Get diff stat for this PR
    try:
        stat = subprocess.run(
            ['gh', 'pr', 'diff', str(pr_num), '--stat'],
            capture_output=True, text=True, timeout=30
        )
        diff_stat = stat.stdout.strip() if stat.returncode == 0 else '(diff unavailable)'
    except Exception:
        diff_stat = '(diff unavailable)'
    # Get changed file list
    try:
        files_out = subprocess.run(
            ['gh', 'pr', 'diff', str(pr_num), '--name-only'],
            capture_output=True, text=True, timeout=30
        )
        files = files_out.stdout.strip().split('\n') if files_out.returncode == 0 else []
    except Exception:
        files = []
    results.append({
        'number': pr_num,
        'title': pr.get('title', ''),
        'url': pr.get('url', ''),
        'author': pr.get('author', {}).get('login', 'unknown'),
        'branch': pr.get('headRefName', ''),
        'created_at': pr.get('createdAt', ''),
        'diff_stat': diff_stat,
        'files_changed': [f for f in files if f],
    })
output = {'competing_prs': results, 'slug': slug}
print(json.dumps(output, indent=2))
" 2>/dev/null) || {
        echo '{"error": "PR analysis failed"}' >&2
        exit 1
    }

    echo "$result"
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

cmd_coordination_snapshot() {
    # Produce a unified coordination snapshot for concurrent agent awareness.
    # Default (fast): worktrees + claims only (~100ms, no GitHub API).
    # --full: adds open PRs with CI status, merge state, and in-flight tasks (~2-3s).
    local full=false
    for arg in "$@"; do
        if [[ "$arg" == "--full" ]]; then
            full=true
        fi
    done

    mkdir -p "$CLAIMS_DIR"
    local ttl
    ttl=$(get_ttl)

    echo "=== COORDINATION SNAPSHOT ==="
    echo "Timestamp: $(now_iso)"
    echo "This worktree: ${WORKTREE_NAME}"
    echo ""

    # --- WORKTREES ---
    echo "--- WORKTREES ---"
    local worktree_branches=()
    while IFS= read -r line; do
        # git worktree list format: /path/to/worktree  <sha> [branch]
        local wt_path wt_branch wt_name
        wt_path=$(echo "$line" | awk '{print $1}')
        wt_branch=$(echo "$line" | sed 's/.*\[//;s/\]//')
        if [[ "$wt_path" == "$MAIN_REPO" ]]; then
            wt_name="main"
        else
            wt_name=$(basename "$wt_path")
        fi
        local marker=""
        if [[ "$wt_name" == "$WORKTREE_NAME" ]]; then
            marker=" (this)"
        fi
        # Check if worktree has non-expired claims (indicates active agent)
        local has_claims=false
        for claim_file in "$CLAIMS_DIR"/*.json; do
            [[ -f "$claim_file" ]] || continue
            local owner
            owner=$(_json_field "$claim_file" "agent_worktree" "")
            if [[ "$owner" == "$wt_name" ]]; then
                local age
                age=$(file_age_minutes "$claim_file")
                local state
                state=$(_json_field "$claim_file" "state" "claimed")
                if [[ "$state" == "shipped" ]] || (( age <= ttl )); then
                    has_claims=true
                    break
                fi
            fi
        done
        local activity=""
        if [[ "$has_claims" == "true" ]]; then
            activity=" [active]"
        fi
        echo "  ${wt_name}: branch=${wt_branch}${activity}${marker}"
        worktree_branches+=("${wt_name}:${wt_branch}")
    done < <(git worktree list 2>/dev/null)
    echo ""

    # --- CLAIMS ---
    echo "--- CLAIMS ---"
    local claim_count=0
    local current_worktree_claims=""
    # Group claims by worktree
    local seen_worktrees=()
    for claim_file in "$CLAIMS_DIR"/*.json; do
        [[ -f "$claim_file" ]] || continue
        claim_count=$((claim_count + 1))
    done

    if (( claim_count == 0 )); then
        echo "  (no active claims)"
    else
        # Use Python to group and format all claims at once
        _WQ_CLAIMS_DIR="$CLAIMS_DIR" _WQ_WORKTREE="$WORKTREE_NAME" _WQ_TTL="$ttl" \
        python3 -c "
import json, os, glob, time

claims_dir = os.environ['_WQ_CLAIMS_DIR']
current_wt = os.environ['_WQ_WORKTREE']
ttl = int(os.environ['_WQ_TTL'])

by_worktree = {}
for path in sorted(glob.glob(os.path.join(claims_dir, '*.json'))):
    try:
        with open(path) as f:
            claim = json.load(f)
    except (json.JSONDecodeError, IOError):
        continue
    owner = claim.get('agent_worktree', 'unknown')
    age = int((time.time() - os.path.getmtime(path)) / 60)
    state = claim.get('state', 'claimed')
    expired = state != 'shipped' and age > ttl
    slug = os.path.basename(path).replace('.json', '')
    title = claim.get('title', slug)
    purpose = claim.get('purpose', 'implementing')

    entry = f'    {title} ({state}'
    if purpose != 'implementing':
        entry += f', {purpose}'
    entry += f', {age}m ago'
    if expired:
        entry += ', EXPIRED'
    # Add PR info if shipped
    pr_num = claim.get('pr_number', '')
    if pr_num:
        entry += f', PR #{pr_num}'
    entry += ')'

    by_worktree.setdefault(owner, []).append(entry)

for wt in sorted(by_worktree):
    marker = ' (this)' if wt == current_wt else ''
    print(f'  {wt}{marker}:')
    for e in by_worktree[wt]:
        print(e)
" 2>/dev/null
    fi
    echo ""

    # --- OPEN PRS (only with --full) ---
    if [[ "$full" == "true" ]]; then
        echo "--- OPEN PRS ---"
        if ! command -v gh &>/dev/null; then
            echo "  (gh CLI not available)"
        else
            local pr_json
            pr_json=$(gh pr list --state open --json number,title,headRefName,mergeable,statusCheckRollup,autoMergeRequest,isDraft 2>/dev/null) || pr_json=""

            if [[ -z "$pr_json" || "$pr_json" == "[]" ]]; then
                echo "  (no open PRs)"
            else
                _WQ_PR_JSON="$pr_json" python3 -c "
import json, os

prs = json.loads(os.environ['_WQ_PR_JSON'])
for pr in sorted(prs, key=lambda p: p['number']):
    num = pr['number']
    title = pr['title']
    branch = pr['headRefName']
    draft = pr.get('isDraft', False)

    # CI status from statusCheckRollup
    checks = pr.get('statusCheckRollup') or []
    if not checks:
        ci = 'no checks'
    else:
        states = [c.get('state', c.get('status', '')) for c in checks]
        if all(s in ('SUCCESS', 'COMPLETED') for s in states):
            ci = 'passing'
        elif any(s in ('FAILURE', 'ERROR') for s in states):
            ci = 'failing'
        elif any(s == 'CANCELLED' for s in states):
            ci = 'cancelled'
        else:
            ci = 'pending'

    # Merge status
    mergeable = pr.get('mergeable', 'UNKNOWN')
    if mergeable == 'MERGEABLE':
        merge = 'clean'
    elif mergeable == 'CONFLICTING':
        merge = 'CONFLICTS'
    else:
        merge = mergeable.lower()

    # Auto-merge
    auto = 'yes' if pr.get('autoMergeRequest') else 'no'

    status = f'CI: {ci} | Merge: {merge} | Auto-merge: {auto}'
    if draft:
        status += ' | DRAFT'
    print(f'  #{num} \"{title}\" [{branch}]')
    print(f'    {status}')
" 2>/dev/null
            fi
        fi
        echo ""

        # --- IN-FLIGHT TASKS (only with --full) ---
        echo "--- IN-FLIGHT TASKS ---"
        echo "  (tasks completed in open PRs, not yet merged to main)"
        local inflight
        inflight=$(cmd_inflight_tasks 2>/dev/null) || inflight="[]"
        if [[ "$inflight" == "[]" ]]; then
            echo "  (none)"
        else
            echo "$inflight" | python3 -c "
import json, sys
titles = json.load(sys.stdin)
for t in titles:
    print(f'  - {t}')
" 2>/dev/null
        fi
        echo ""
    fi

    echo "=== END SNAPSHOT ==="
}

cmd_pr_files() {
    # Fetch open PRs and their changed files from GitHub.
    # Returns JSON array of objects with pr_number, title, branch, files, and dirs.
    # Gracefully degrades to [] if gh CLI is unavailable or fails.
    #
    # Usage: work-queue.sh pr-files
    #
    # Output: JSON array like:
    #   [{"pr_number": 123, "title": "...", "branch": "...",
    #     "files": ["src/foo.py"], "dirs": ["src"]}]

    if ! command -v gh &>/dev/null; then
        echo "[]"
        echo "warning: gh CLI not found — skipping PR file fetch" >&2
        return 0
    fi

    local pr_json
    pr_json=$(gh pr list --state open --json number,title,headRefName,files 2>/dev/null) || true

    if [[ -z "$pr_json" || "$pr_json" == "[]" ]]; then
        echo "[]"
        return 0
    fi

    export _WQ_PR_JSON="$pr_json"
    python3 -c "
import json, os

data = json.loads(os.environ['_WQ_PR_JSON'])
result = []
for pr in data:
    files_raw = pr.get('files') or []
    file_paths = [f.get('path', '') for f in files_raw if f.get('path')]
    # Extract unique parent directories
    dirs = set()
    for p in file_paths:
        parts = p.rstrip('/').split('/')
        if len(parts) > 1:
            dirs.add('/'.join(parts[:-1]))
    result.append({
        'pr_number': pr.get('number'),
        'title': pr.get('title', ''),
        'branch': pr.get('headRefName', ''),
        'files': file_paths,
        'dirs': sorted(dirs),
    })
print(json.dumps(result, indent=2))
" 2>/dev/null || {
        echo "[]"
        echo "warning: PR file parsing failed" >&2
        return 0
    }
}

cmd_check_pr_overlap() {
    # Check if a set of candidate files overlaps with files in open PRs.
    # Similar to check-overlap but checks against open PRs instead of claims.
    #
    # Usage: work-queue.sh check-pr-overlap <files_json>
    #   files_json: JSON array of file paths, or "-" for stdin
    #
    # Output: JSON object with "overlapping_prs" array containing PRs whose
    # changed files share at least one parent directory with the input files.

    local files_input="${1:--}"
    local files_json=""

    if [[ "$files_input" == "-" ]]; then
        files_json=$(cat)
    else
        files_json="$files_input"
    fi

    # Get open PR files
    local pr_data
    pr_data=$(cmd_pr_files 2>/dev/null)

    if [[ -z "$pr_data" || "$pr_data" == "[]" ]]; then
        echo '{"overlapping_prs": [], "overlap_count": 0}'
        return 0
    fi

    _WQ_FILES_JSON="$files_json" _WQ_PR_DATA="$pr_data" \
    python3 -c "
import json, os

files_json = os.environ['_WQ_FILES_JSON']
pr_data_raw = os.environ['_WQ_PR_DATA']

try:
    input_files = json.loads(files_json)
    if not isinstance(input_files, list):
        input_files = []
except (json.JSONDecodeError, TypeError):
    input_files = []

try:
    pr_data = json.loads(pr_data_raw)
    if not isinstance(pr_data, list):
        pr_data = []
except (json.JSONDecodeError, TypeError):
    pr_data = []

def get_dirs(file_list):
    dirs = set()
    for f in file_list:
        parts = f.rstrip('/').split('/')
        if len(parts) > 1:
            dirs.add('/'.join(parts[:-1]))
    return dirs

input_dirs = get_dirs(input_files)
overlapping = []

for pr in pr_data:
    pr_files = pr.get('files', [])
    if not pr_files:
        continue
    pr_dirs = get_dirs(pr_files)
    shared_dirs = input_dirs & pr_dirs
    if shared_dirs:
        overlapping.append({
            'pr_number': pr.get('pr_number'),
            'title': pr.get('title', ''),
            'branch': pr.get('branch', ''),
            'overlapping_dirs': sorted(shared_dirs),
            'pr_files': pr_files,
        })

result = {
    'overlapping_prs': overlapping,
    'overlap_count': len(overlapping),
}
print(json.dumps(result, indent=2))
" 2>/dev/null || {
        echo '{"overlapping_prs": [], "overlap_count": 0}'
        echo "warning: PR overlap check failed" >&2
        return 0
    }
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
            echo "Usage: work-queue.sh claim <slug> [title] [section] [role_tag] [version] [purpose] [claimed_files_json]" >&2
            exit 1
        fi
        cmd_claim "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-[]}"
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
    refresh-active)
        cmd_refresh_active
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
    try-claim)
        cmd_try_claim "${1:-1}" "${2:--}"
        ;;
    check-overlap)
        cmd_check_overlap "${1:--}"
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
    reconcile)
        if [[ $# -lt 1 ]]; then
            echo "Usage: work-queue.sh reconcile <task_slug>" >&2
            exit 1
        fi
        cmd_reconcile "$1"
        ;;
    coordination-snapshot)
        cmd_coordination_snapshot "$@"
        ;;
    pr-files)
        cmd_pr_files
        ;;
    check-pr-overlap)
        cmd_check_pr_overlap "${1:--}"
        ;;
    help|--help|-h)
        echo "Usage: work-queue.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  init                          Initialize the work queue directory"
        echo "  claim <slug> [title] [section] [role] [version] [purpose]  Claim a task"
        echo "  release <slug> [--force]      Release a claimed task"
        echo "  release-all                   Release all claims for this worktree"
        echo "  list                          List all active claims (JSON)"
        echo "  check <slug>                  Check if a task is claimed"
        echo "  claimed-by-me                 List tasks claimed by this worktree"
        echo "  expire                        Remove claims past TTL"
        echo "  refresh-active                Refresh expired claims whose worktree still exists"
        echo "  inflight-tasks                List tasks completed in open PRs (JSON)"
        echo "  max-claimed-version           Show highest speculated version across claims"
        echo "  validate                      Health check: detect slug mismatches, duplicates, orphans, expired"
        echo "  mark-shipped <pr> <url>       Transition this worktree's claims to shipped"
        echo "  auto-release-merged           Release shipped claims whose PRs are merged/closed"
        echo "  try-claim <count> <json_file> Try claiming tasks from a candidates file (or - for stdin)"
        echo "  check-overlap <files_json>    Check if files overlap with active claims (JSON)"
        echo "  reconcile <task_slug>         Find competing PRs for a task and show diff summaries"
        echo "  mark-reviewed <slug> [sha]    Record that a task has been reviewed"
        echo "  is-reviewed <slug>            Check if a task has been reviewed"
        echo "  list-reviewed                 List all reviewed tasks (JSON)"
        echo "  clean-review <slug>           Delete review file and reviewed marker for a task"
        echo "  pr-files                      List open PR changed files (JSON)"
        echo "  check-pr-overlap <files_json> Check if files overlap with open PRs (JSON)"
        echo "  coordination-snapshot [--full] Show worktrees, claims, and optionally open PRs"
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
