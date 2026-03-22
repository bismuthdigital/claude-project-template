#!/bin/bash
# Worktree cleanup — find and remove stale worktrees.
#
# Usage:
#   scripts/worktree-cleanup.sh [--dry-run] [--force] [--save-diffs DIR]
#
# Categorizes worktrees as:
#   - orphaned: directory exists but no git worktree registration
#   - merged:   branch fully merged to main, no dirty changes
#   - dirty:    has uncommitted changes (requires --force or --save-diffs)
#   - active:   current worktree (never removed)
#
# Safety:
#   - Never removes the current worktree
#   - Never removes dirty worktrees with active claims unless --force
#   - Never removes other dirty worktrees unless --force or --save-diffs
#   - Releases stale work-queue claims for removed worktrees
#   - Prunes git worktree metadata after removal

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Resolve main repo root (works from worktrees too)
MAIN_REPO="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"
if [[ "$MAIN_REPO" == *".claude/worktrees/"* ]]; then
    MAIN_REPO="${MAIN_REPO%%/.claude/worktrees/*}"
fi

WORKTREE_DIR="$MAIN_REPO/.claude/worktrees"
WORK_QUEUE_DIR="$MAIN_REPO/.claude/work-queue/claims"
CURRENT_WORKTREE=""

# Detect if we're running inside a worktree
if [[ "${CLAUDE_PROJECT_DIR:-$PWD}" == *".claude/worktrees/"* ]]; then
    CURRENT_WORKTREE="$(echo "${CLAUDE_PROJECT_DIR:-$PWD}" | sed 's|.*/.claude/worktrees/||; s|/.*||')"
fi

DRY_RUN=false
FORCE=false
SAVE_DIFFS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --force) FORCE=true; shift ;;
        --save-diffs) SAVE_DIFFS="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Collect git-registered worktree names as newline-separated list
GIT_WORKTREES="$(git -C "$MAIN_REPO" worktree list | awk '{print $1}' | while read -r wt_path; do
    if [[ "$wt_path" == *"/.claude/worktrees/"* ]]; then
        basename "$wt_path"
    fi
done)"

# Helper: check if a name is in the git worktree list
is_registered() {
    echo "$GIT_WORKTREES" | grep -qx "$1" 2>/dev/null
}

# Collect worktree names with active (non-expired) claims
CLAIMED_WORKTREES=""
if [[ -d "$WORK_QUEUE_DIR" ]]; then
    for claim_file in "$WORK_QUEUE_DIR"/*.json; do
        [[ -f "$claim_file" ]] || continue
        claim_info="$(python3 -c "
import json, sys
from datetime import datetime, timezone, timedelta
d = json.load(open('$claim_file'))
wt = d.get('agent_worktree', '')
claimed = d.get('claimed_at', '')
ttl = d.get('ttl_minutes', 120)
state = d.get('state', '')
# Expired or shipped claims don't protect worktrees
if state in ('shipped', 'released'):
    sys.exit(0)
if claimed:
    try:
        t = datetime.fromisoformat(claimed.replace('Z', '+00:00'))
        if t + timedelta(minutes=ttl) < datetime.now(timezone.utc):
            sys.exit(0)  # expired
    except Exception:
        pass
if wt:
    print(wt)
" 2>/dev/null)"
        if [[ -n "$claim_info" ]]; then
            CLAIMED_WORKTREES="$CLAIMED_WORKTREES
$claim_info"
        fi
    done
fi

# Helper: check if a worktree has active claims
has_active_claims() {
    echo "$CLAIMED_WORKTREES" | grep -qx "$1" 2>/dev/null
}

# Counters
orphaned=()
merged=()
dirty=()
active=()
skipped=()
total_freed=0

echo "Scanning worktrees in $WORKTREE_DIR ..."
echo

for dir in "$WORKTREE_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"

    # Never remove current worktree
    if [[ "$name" == "$CURRENT_WORKTREE" ]]; then
        size="$(du -sh "$dir" 2>/dev/null | awk '{print $1}')"
        active+=("$name ($size) [current session]")
        continue
    fi

    size="$(du -sh "$dir" 2>/dev/null | awk '{print $1}')"
    size_bytes="$(du -s "$dir" 2>/dev/null | awk '{print $1}')"

    # Check if orphaned (directory exists but no git worktree registration)
    if ! is_registered "$name"; then
        orphaned+=("$name ($size)")
        if [[ "$DRY_RUN" == false ]]; then
            rm -rf "$dir"
            total_freed=$((total_freed + size_bytes))
        fi
        continue
    fi

    # Check branch merge status
    branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
    is_dirty="$(git -C "$dir" status --porcelain 2>/dev/null | head -1)"
    is_merged=false

    if [[ -n "$branch" && "$branch" != "HEAD" && "$branch" != "main" ]]; then
        # Check for fast-forward merge (commits in main's history)
        ahead="$(git -C "$MAIN_REPO" log --oneline "main..$branch" 2>/dev/null | wc -l | tr -d ' ')"
        if [[ "$ahead" == "0" ]]; then
            is_merged=true
        else
            # Check for squash merge via GitHub PR status
            pr_state="$(gh pr list --head "$branch" --state merged --json number --limit 1 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print('merged' if d else '')" 2>/dev/null)"
            if [[ "$pr_state" == "merged" ]]; then
                is_merged=true
            fi
        fi
    elif [[ "$branch" == "main" || "$branch" == "HEAD" ]]; then
        is_merged=true
    fi

    # Dirty worktree handling
    if [[ -n "$is_dirty" ]]; then
        # Dirty + active claims = protected (only --force overrides)
        if has_active_claims "$name" && [[ "$FORCE" != true ]]; then
            skipped+=("$name ($size) [dirty + active claims, use --force]")
            continue
        fi

        if [[ -n "$SAVE_DIFFS" ]]; then
            mkdir -p "$SAVE_DIFFS"
            git -C "$dir" diff > "$SAVE_DIFFS/$name.patch" 2>/dev/null
            git -C "$dir" status --porcelain > "$SAVE_DIFFS/$name.status" 2>/dev/null
            dirty+=("$name ($size) [diff saved]")
        elif [[ "$FORCE" == true ]]; then
            dirty+=("$name ($size) [force removed]")
        else
            skipped+=("$name ($size) [dirty, use --force or --save-diffs]")
            continue
        fi
    elif [[ "$is_merged" == true ]]; then
        merged+=("$name ($size)")
    else
        skipped+=("$name ($size) [branch not merged to main]")
        continue
    fi

    # Remove the worktree
    if [[ "$DRY_RUN" == false ]]; then
        # Release any claims for this worktree
        if [[ -d "$WORK_QUEUE_DIR" ]]; then
            for claim_file in "$WORK_QUEUE_DIR"/*.json; do
                [[ -f "$claim_file" ]] || continue
                claim_wt="$(python3 -c "import json; print(json.load(open('$claim_file')).get('agent_worktree',''))" 2>/dev/null)"
                if [[ "$claim_wt" == "$name" ]]; then
                    rm -f "$claim_file"
                fi
            done
        fi

        # Remove via git worktree (handles lock files, metadata)
        git -C "$MAIN_REPO" worktree remove --force "$dir" 2>/dev/null || rm -rf "$dir"

        # Delete the remote branch
        git -C "$MAIN_REPO" push origin --delete "worktree-$name" 2>/dev/null || true

        total_freed=$((total_freed + size_bytes))
    fi
done

# Prune any stale worktree metadata
if [[ "$DRY_RUN" == false ]]; then
    git -C "$MAIN_REPO" worktree prune 2>/dev/null || true
fi

# Report
echo "============================================="
if [[ "$DRY_RUN" == true ]]; then
    echo "  WORKTREE CLEANUP (DRY RUN)"
else
    echo "  WORKTREE CLEANUP COMPLETE"
fi
echo "============================================="
echo

if [[ ${#orphaned[@]} -gt 0 ]]; then
    echo "Orphaned directories removed (${#orphaned[@]}):"
    for item in "${orphaned[@]}"; do echo "  - $item"; done
    echo
fi

if [[ ${#merged[@]} -gt 0 ]]; then
    echo "Merged worktrees removed (${#merged[@]}):"
    for item in "${merged[@]}"; do echo "  - $item"; done
    echo
fi

if [[ ${#dirty[@]} -gt 0 ]]; then
    echo "Dirty worktrees removed (${#dirty[@]}):"
    for item in "${dirty[@]}"; do echo "  - $item"; done
    echo
fi

if [[ ${#active[@]} -gt 0 ]]; then
    echo "Active (kept):"
    for item in "${active[@]}"; do echo "  - $item"; done
    echo
fi

if [[ ${#skipped[@]} -gt 0 ]]; then
    echo "Skipped (${#skipped[@]}):"
    for item in "${skipped[@]}"; do echo "  - $item"; done
    echo
fi

if [[ "$DRY_RUN" == false && $total_freed -gt 0 ]]; then
    freed_human="$(echo "$total_freed" | awk '{
        if ($1 >= 1048576) printf "%.1f GB", $1/1048576;
        else if ($1 >= 1024) printf "%.0f MB", $1/1024;
        else printf "%d KB", $1;
    }')"
    echo "Disk space freed: ~$freed_human"
elif [[ "$DRY_RUN" == true ]]; then
    echo "No changes made (dry run)."
fi
echo "============================================="
