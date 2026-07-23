#!/bin/bash
# PreToolUse hook: Ensure worktree Python commands use the local .venv.
#
# Each worktree has its own .venv to prevent concurrent agents from
# clobbering each other's editable installs via the shared .pth file.
#
# Behavior:
#   - Non-worktree contexts: pass through (no-op)
#   - Non-Python commands: pass through (no-op)
#   - .venv/bin/* commands: verify install, auto-fix if needed
#   - Commands with venv activation: allow (activation uses local .venv)
#   - Bare pytest/python/pip: block and suggest .venv/bin/ prefix
#
# Blocking uses exit 2 with the reason on stderr — the only combination
# Claude Code feeds back to the model (exit 1 does not block; stdout is
# not returned).
#
# The local .venv is auto-created on first Python command via
# worktree-setup.sh, which is the single implementation of
# create/verify/fix. A stamp file newer than site-packages skips the
# Python-spawn verification on the hot path; any pip activity updates
# site-packages' mtime and invalidates the stamp.

set -e

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[[ -z "$COMMAND" ]] && exit 0

# ── Only relevant in worktree contexts ────────────────────────────────
if [[ "$CLAUDE_PROJECT_DIR" != *".claude/worktrees/"* ]]; then
    exit 0
fi

LOCAL_VENV="$CLAUDE_PROJECT_DIR/.venv"
SETUP_SCRIPT="$CLAUDE_PROJECT_DIR/.claude/hooks/worktree-setup.sh"
STAMP="$LOCAL_VENV/.install-verified"

# Helper: ensure local venv exists with a correct editable install.
ensure_venv() {
    local site_pkgs
    site_pkgs=("$LOCAL_VENV"/lib/python*/site-packages)
    if [[ -f "$STAMP" && -d "${site_pkgs[0]}" && "$STAMP" -nt "${site_pkgs[0]}" ]]; then
        return 0
    fi
    if ! bash "$SETUP_SCRIPT" "$CLAUDE_PROJECT_DIR"; then
        echo "WORKTREE: local .venv setup failed — fix the venv (bash .claude/hooks/worktree-setup.sh) before running Python commands." >&2
        exit 2
    fi
    touch "$STAMP"
}

# ── Route by command pattern ──────────────────────────────────────────
case "$COMMAND" in

    # ── Commands explicitly using local .venv — verify and proceed ────
    .venv/bin/*)
        ensure_venv
        exit 0
        ;;

    # ── Commands that activate local .venv first — allow ──────────────
    *"source .venv/bin/activate"*|*". .venv/bin/activate"*)
        ensure_venv
        exit 0
        ;;

    # ── Bare Python commands — block with suggestion ──────────────────
    pytest\ *|pytest)
        ensure_venv
        {
            echo "WORKTREE: Use '.venv/bin/pytest${COMMAND#pytest}' instead of bare 'pytest'."
            echo "Each worktree has its own .venv for isolation from concurrent agents."
        } >&2
        exit 2
        ;;

    python\ *|python3\ *)
        ensure_venv
        local_bin=".venv/bin/python"
        bare_cmd="${COMMAND%%\ *}"
        args="${COMMAND#"$bare_cmd"}"
        {
            echo "WORKTREE: Use '${local_bin}${args}' instead of bare '${bare_cmd}'."
            echo "Each worktree has its own .venv for isolation from concurrent agents."
        } >&2
        exit 2
        ;;

    pip\ install*|pip3\ install*)
        ensure_venv
        bare_cmd="${COMMAND%%\ *}"
        args="${COMMAND#"$bare_cmd"}"
        {
            echo "WORKTREE: Use '.venv/bin/pip${args}' instead of bare '${bare_cmd}'."
            echo "Each worktree has its own .venv for isolation from concurrent agents."
        } >&2
        exit 2
        ;;

    # ── Compound commands with bare python ─────────────────────────────
    *python\ -m\ pytest*|*python3\ -m\ pytest*|*python\ -c\ *|*python3\ -c\ *)
        ensure_venv
        {
            echo "WORKTREE: Use '.venv/bin/python' instead of bare 'python' in compound commands."
            echo "Example: echo \"\$AFFECTED\" | xargs .venv/bin/python -m pytest ..."
        } >&2
        exit 2
        ;;

    # ── Everything else — pass through ────────────────────────────────
    *)
        exit 0
        ;;
esac
