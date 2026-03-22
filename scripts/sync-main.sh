#!/usr/bin/env bash
# sync-main.sh — Safely advance local main to match origin/main.
#
# Handles the common case where worktree-merged PRs create files that
# now exist as untracked locals AND in origin/main. Git refuses to
# fast-forward when untracked files would be overwritten, so this script
# detects those conflicts, verifies each file is identical to what's
# incoming, removes the local copy, and then pulls.
#
# Usage:
#   scripts/sync-main.sh              # From the main repo
#   scripts/sync-main.sh --dry-run    # Preview what would happen
#   scripts/sync-main.sh --force      # Remove conflicting files even if they differ
#
# Safety:
#   - Only operates on the main branch (refuses to run on feature branches)
#   - Only fast-forwards (--ff-only) — never creates merge commits
#   - Stashes dirty working tree automatically, restores after pull
#   - Verifies conflicting untracked files match origin before removing
#   - Files that differ from origin are backed up (unless --force)
#   - Exits cleanly if already up to date
#   - Auto-resolves stash conflicts when ALL stashed file contents already
#     match main (i.e., the stash is a subset of merged PRs)
#   - Preserves the stash when any file differs from main (unique local state)

set -euo pipefail

# ── Options ─────────────────────────────────────────────────────────────

DRY_RUN=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n) DRY_RUN=true; shift ;;
        --force|-f)   FORCE=true; shift ;;
        -h|--help)
            sed -n '2,/^$/{ s/^# //; s/^#$//; p }' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ── Resolve paths ──────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# If run from a worktree, find the main repo
if [[ "$PROJECT_DIR" == *"/.claude/worktrees/"* ]]; then
    MAIN_REPO="${PROJECT_DIR%%/.claude/worktrees/*}"
else
    MAIN_REPO="$PROJECT_DIR"
fi

cd "$MAIN_REPO"

# ── Colors ──────────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
    BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; RESET=''
fi

info()  { printf '%b\n' "${BLUE}ℹ${RESET} $*"; }
ok()    { printf '%b\n' "${GREEN}✓${RESET} $*"; }
warn()  { printf '%b\n' "${YELLOW}⚠${RESET} $*"; }
err()   { printf '%b\n' "${RED}✗${RESET} $*" >&2; }
step()  { printf '%b\n' "${BOLD}→${RESET} $*"; }

# ── Preflight checks ───────────────────────────────────────────────────

CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    err "Not on main branch (on '$CURRENT_BRANCH'). Switch to main first."
    exit 1
fi

# ── Fetch latest ────────────────────────────────────────────────────────

step "Fetching origin/main..."
git fetch origin main --quiet

LOCAL_HEAD=$(git rev-parse HEAD)
REMOTE_HEAD=$(git rev-parse origin/main)

if [[ "$LOCAL_HEAD" == "$REMOTE_HEAD" ]]; then
    ok "Already up to date."
    exit 0
fi

# Verify we can fast-forward (local is ancestor of remote)
if ! git merge-base --is-ancestor "$LOCAL_HEAD" "$REMOTE_HEAD"; then
    err "Local main has diverged from origin/main. Manual resolution needed."
    exit 1
fi

BEHIND_COUNT=$(git rev-list --count HEAD..origin/main)
info "Local main is ${BOLD}${BEHIND_COUNT}${RESET} commits behind origin/main."

# ── Stash dirty working tree ───────────────────────────────────────────

STASHED=false
# Warn on unexpected exit if stash is still pending
trap 'if $STASHED; then warn "Stash still pending — run '\''git stash pop'\'' to recover your changes."; fi' EXIT
if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet HEAD 2>/dev/null; then
    step "Stashing uncommitted changes..."
    if $DRY_RUN; then
        info "(dry-run) Would stash uncommitted changes"
    else
        git stash push -m "sync-main: auto-stash before pull $(date -u +%Y%m%dT%H%M%SZ)"
        STASHED=true
    fi
fi

# ── Detect conflicting untracked files ─────────────────────────────────

# Get list of files that are new in origin/main relative to local HEAD.
# --diff-filter=A catches pure additions; --diff-filter=R catches renames
# (e.g., active→completed task files — renamed from active/ to completed/).
# With --name-only, renames show only the destination path.
INCOMING_FILES=$(
    {
        git diff --name-only --diff-filter=A "$LOCAL_HEAD" "$REMOTE_HEAD"
        git diff --name-only --diff-filter=R "$LOCAL_HEAD" "$REMOTE_HEAD"
    } | sort -u
)

CONFLICTS=()
BACKUP_DIR=""

while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if [[ -f "$file" ]] && ! git ls-files --error-unmatch "$file" &>/dev/null; then
        CONFLICTS+=("$file")
    fi
done <<< "$INCOMING_FILES"

if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
    warn "Found ${#CONFLICTS[@]} untracked file(s) that conflict with incoming changes:"
    for file in "${CONFLICTS[@]}"; do
        echo "    $file"
    done

    # Check each file byte-for-byte against what origin/main has
    IDENTICAL=()
    DIFFERENT=()
    for file in "${CONFLICTS[@]}"; do
        if diff -q <(git show "origin/main:$file" 2>/dev/null) "$file" &>/dev/null; then
            IDENTICAL+=("$file")
        else
            DIFFERENT+=("$file")
        fi
    done

    if [[ ${#IDENTICAL[@]} -gt 0 ]]; then
        ok "${#IDENTICAL[@]} file(s) are identical to origin/main — safe to remove."
    fi

    if [[ ${#DIFFERENT[@]} -gt 0 ]]; then
        if $FORCE; then
            warn "${#DIFFERENT[@]} file(s) differ from origin/main — removing anyway (--force)."
        else
            warn "${#DIFFERENT[@]} file(s) differ from origin/main — will back up before removing:"
            for file in "${DIFFERENT[@]}"; do
                echo "    $file"
            done
        fi
    fi

    # Remove/backup conflicting files
    if $DRY_RUN; then
        info "(dry-run) Would remove ${#CONFLICTS[@]} conflicting untracked file(s)"
    else
        # Back up files that differ
        if [[ ${#DIFFERENT[@]} -gt 0 ]] && ! $FORCE; then
            BACKUP_DIR=$(mktemp -d /tmp/sync-main-backup-XXXXXX)
            for file in "${DIFFERENT[@]}"; do
                mkdir -p "$BACKUP_DIR/$(dirname "$file")"
                cp "$file" "$BACKUP_DIR/$file"
            done
            info "Backed up differing files to ${BOLD}${BACKUP_DIR}${RESET}"
        fi

        for file in "${CONFLICTS[@]}"; do
            rm "$file"
        done
        ok "Removed ${#CONFLICTS[@]} conflicting untracked file(s)."
    fi
fi

# ── Pull (fast-forward only) ──────────────────────────────────────────

if $DRY_RUN; then
    info "(dry-run) Would fast-forward main from $(git rev-parse --short HEAD) to $(git rev-parse --short origin/main)"
else
    step "Fast-forwarding main..."
    git merge --ff-only origin/main --quiet
    ok "Advanced main to $(git rev-parse --short HEAD) (${BEHIND_COUNT} commits)."
fi

# ── Restore stash ─────────────────────────────────────────────────────

if $STASHED; then
    step "Restoring stashed changes..."
    if git stash pop --quiet 2>/dev/null; then
        STASHED=false
        ok "Stash restored."
    else
        # Stash pop failed — check if the stash is fully redundant.
        #
        # Strategy: compare each stashed file's content against HEAD
        # (post-fast-forward). If every file in the stash already matches
        # HEAD, the stash is a subset of what was merged and can be safely
        # dropped. If ANY file differs, the stash has unique local state
        # that we must preserve — reset the conflicted merge but keep the
        # stash for manual resolution.

        # First, clean up the failed merge so we can do clean comparisons
        git reset --hard HEAD --quiet

        # Compare each stashed file against HEAD
        STASH_FILES=$(git stash show --name-only 'stash@{0}' 2>/dev/null || true)
        STASH_REDUNDANT=true
        UNIQUE_FILES=()

        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            # git diff exits 0 if identical, 1 if different
            if ! git diff --quiet 'stash@{0}' HEAD -- "$file" 2>/dev/null; then
                STASH_REDUNDANT=false
                UNIQUE_FILES+=("$file")
            fi
        done <<< "$STASH_FILES"

        if $STASH_REDUNDANT; then
            STASH_COUNT=$(printf '%s\n' "$STASH_FILES" | grep -c . || true)
            info "All ${STASH_COUNT} stashed file(s) already match main (from merged PRs)."
            step "Dropping redundant stash..."

            # Clean up untracked files that duplicate what's now tracked on
            # main. These weren't in the stash (untracked), but they're
            # leftover duplicates from the same agent work that merged.
            # Only remove if content is identical to HEAD's tracked version.
            CLEANED=0
            KEPT_UNTRACKED=()
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                if git cat-file -e "HEAD:$file" 2>/dev/null; then
                    if diff -q <(git show "HEAD:$file" 2>/dev/null) "$file" &>/dev/null; then
                        rm "$file"
                        CLEANED=$((CLEANED + 1))
                    else
                        KEPT_UNTRACKED+=("$file")
                    fi
                fi
            done < <(git ls-files --others --exclude-standard)

            if [[ $CLEANED -gt 0 ]]; then
                info "Cleaned up ${CLEANED} redundant untracked file(s)."
            fi

            if [[ ${#KEPT_UNTRACKED[@]} -gt 0 ]]; then
                warn "${#KEPT_UNTRACKED[@]} untracked file(s) differ from main and were kept:"
                for file in "${KEPT_UNTRACKED[@]}"; do
                    echo "    $file"
                done
            fi

            git stash drop --quiet
            STASHED=false
            ok "Dropped redundant stash."
        else
            STASHED=false
            warn "Stash contains ${#UNIQUE_FILES[@]} file(s) with changes not yet on main:"
            for file in "${UNIQUE_FILES[@]}"; do
                echo "    $file"
            done
            echo ""
            info "The failed stash pop was reset, but the stash is preserved."
            info "To inspect:  git stash show -p"
            info "To re-apply: git stash pop  ${YELLOW}(will conflict again — resolve manually)${RESET}"
            info "To discard:  git stash drop  ${YELLOW}(loses the above changes)${RESET}"
        fi
    fi
fi

# ── Summary ────────────────────────────────────────────────────────────

echo ""
if $DRY_RUN; then
    info "Dry run complete. No changes made."
else
    ok "Main branch is at origin/main ($(git rev-parse --short HEAD))."

    # Report remaining working tree state so the user knows where things stand
    UNTRACKED_COUNT=$(git ls-files --others --exclude-standard | grep -c . || true)
    MODIFIED_COUNT=$(git diff --name-only | grep -c . || true)
    STAGED_COUNT=$(git diff --cached --name-only | grep -c . || true)
    STASH_COUNT=$(git stash list | grep -c . || true)

    if [[ $MODIFIED_COUNT -gt 0 ]] || [[ $STAGED_COUNT -gt 0 ]]; then
        warn "Working tree has changes: ${MODIFIED_COUNT} modified, ${STAGED_COUNT} staged."
    fi
    if [[ $UNTRACKED_COUNT -gt 0 ]]; then
        info "${UNTRACKED_COUNT} untracked file(s) remain. Run 'git status' to review."
    fi
    if [[ $STASH_COUNT -gt 0 ]]; then
        info "${STASH_COUNT} stash(es) on stack. Run 'git stash list' to review."
    fi
    if [[ -n "$BACKUP_DIR" ]]; then
        info "Backups at: ${BOLD}${BACKUP_DIR}${RESET}"
    fi
    if [[ $MODIFIED_COUNT -eq 0 ]] && [[ $STAGED_COUNT -eq 0 ]] && [[ $UNTRACKED_COUNT -eq 0 ]] && [[ $STASH_COUNT -eq 0 ]]; then
        ok "Working tree is clean."
    fi
fi
