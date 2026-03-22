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
# The local .venv is auto-created on first Python command via worktree-setup.sh.

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

# Helper: ensure local venv exists (creates on first call)
ensure_venv() {
    if [[ ! -f "$LOCAL_VENV/bin/python" ]]; then
        bash "$SETUP_SCRIPT" "$CLAUDE_PROJECT_DIR"
    fi
}

# Helper: detect the project's package name from pyproject.toml
get_package_name() {
    "$LOCAL_VENV/bin/python" -c "
try:
    import tomllib
except ImportError:
    import tomli as tomllib
with open('$CLAUDE_PROJECT_DIR/pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
name = data.get('project', {}).get('name', '')
print(name.replace('-', '_'))
" 2>/dev/null || echo ""
}

# Helper: verify editable install points to this worktree, fix if not
verify_install() {
    local pkg_name
    pkg_name=$(get_package_name)
    [[ -z "$pkg_name" ]] && return 0

    local install_loc
    install_loc=$("$LOCAL_VENV/bin/python" -c "
import ${pkg_name}, os
print(os.path.dirname(os.path.dirname(${pkg_name}.__file__)))
" 2>/dev/null || true)
    if [[ -n "$install_loc" ]]; then
        local real_project real_install
        real_project=$(cd "$CLAUDE_PROJECT_DIR" && pwd -P)
        real_install=$(cd "$install_loc" 2>/dev/null && pwd -P || echo "")
        if [[ "$real_install" != "$real_project"* ]]; then
            echo "Fixing editable install (was: $real_install)..."
            "$LOCAL_VENV/bin/pip" install -e "$CLAUDE_PROJECT_DIR[dev]" --quiet 2>&1
        fi
    fi
}

# ── Route by command pattern ──────────────────────────────────────────
case "$COMMAND" in

    # ── Commands explicitly using local .venv — verify and proceed ────
    .venv/bin/*)
        ensure_venv
        verify_install
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
        echo ""
        echo "WORKTREE: Use '.venv/bin/pytest${COMMAND#pytest}' instead of bare 'pytest'."
        echo "Each worktree has its own .venv for isolation from concurrent agents."
        echo ""
        exit 1
        ;;

    python\ *|python3\ *)
        ensure_venv
        local_bin=".venv/bin/python"
        bare_cmd="${COMMAND%%\ *}"
        args="${COMMAND#"$bare_cmd"}"
        echo ""
        echo "WORKTREE: Use '${local_bin}${args}' instead of bare '${bare_cmd}'."
        echo "Each worktree has its own .venv for isolation from concurrent agents."
        echo ""
        exit 1
        ;;

    pip\ install*|pip3\ install*)
        ensure_venv
        bare_cmd="${COMMAND%%\ *}"
        args="${COMMAND#"$bare_cmd"}"
        echo ""
        echo "WORKTREE: Use '.venv/bin/pip${args}' instead of bare '${bare_cmd}'."
        echo "Each worktree has its own .venv for isolation from concurrent agents."
        echo ""
        exit 1
        ;;

    # ── Compound commands with bare python ─────────────────────────────
    *python\ -m\ pytest*|*python3\ -m\ pytest*|*python\ -c\ *|*python3\ -c\ *)
        ensure_venv
        echo ""
        echo "WORKTREE: Use '.venv/bin/python' instead of bare 'python' in compound commands."
        echo "Example: echo \"\$AFFECTED\" | xargs .venv/bin/python -m pytest ..."
        echo ""
        exit 1
        ;;

    # ── Everything else — pass through ────────────────────────────────
    *)
        exit 0
        ;;
esac
