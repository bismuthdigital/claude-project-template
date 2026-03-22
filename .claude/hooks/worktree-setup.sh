#!/bin/bash
# Create a per-worktree virtual environment for test isolation.
#
# Each worktree gets its own .venv so concurrent agents don't clobber
# each other's editable installs via the shared .pth file. This script
# is called automatically by worktree-check.sh on the first Python
# command in a new worktree.
#
# Usage:
#   bash .claude/hooks/worktree-setup.sh [worktree-dir]

set -e

WORKTREE_DIR="${1:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
VENV_DIR="$WORKTREE_DIR/.venv"

# ── Detect the project's package name from pyproject.toml ──────────────
get_package_name() {
    python3 -c "
try:
    import tomllib
except ImportError:
    import tomli as tomllib
with open('$WORKTREE_DIR/pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
name = data.get('project', {}).get('name', '')
print(name.replace('-', '_'))
" 2>/dev/null || echo ""
}

PKG_NAME=$(get_package_name)

# ── If venv exists with correct install, nothing to do ────────────────
if [[ -f "$VENV_DIR/bin/python" && -n "$PKG_NAME" ]]; then
    INSTALL_LOC=$("$VENV_DIR/bin/python" -c "
import ${PKG_NAME}, os
print(os.path.dirname(os.path.dirname(${PKG_NAME}.__file__)))
" 2>/dev/null || true)
    if [[ -n "$INSTALL_LOC" ]]; then
        REAL_PROJECT=$(cd "$WORKTREE_DIR" && pwd -P)
        REAL_INSTALL=$(cd "$INSTALL_LOC" 2>/dev/null && pwd -P || echo "")
        if [[ "$REAL_INSTALL" == "$REAL_PROJECT"* ]]; then
            exit 0
        fi
    fi
    # Venv exists but install points elsewhere — reinstall
    echo "Fixing editable install in existing worktree venv..."
    "$VENV_DIR/bin/pip" install -e "$WORKTREE_DIR[dev]" --quiet 2>&1
    exit 0
fi

# ── Find the correct Python interpreter ───────────────────────────────
# Prefer the same Python that built the main repo's venv.
PYTHON=""
MAIN_REPO=$(git -C "$WORKTREE_DIR" worktree list --porcelain 2>/dev/null \
    | head -1 | sed 's/^worktree //')

if [[ -n "$MAIN_REPO" && -f "$MAIN_REPO/.venv/pyvenv.cfg" ]]; then
    PYTHON_HOME=$(grep '^home' "$MAIN_REPO/.venv/pyvenv.cfg" | sed 's/^home = //')
    if [[ -x "$PYTHON_HOME/python3" ]]; then
        PYTHON="$PYTHON_HOME/python3"
    fi
fi

# Fallback: find python3 outside any venv
if [[ -z "$PYTHON" ]]; then
    for p in /usr/local/bin/python3 /opt/homebrew/bin/python3 /usr/bin/python3; do
        if [[ -x "$p" ]]; then
            PYTHON="$p"
            break
        fi
    done
fi

if [[ -z "$PYTHON" ]]; then
    echo "ERROR: No Python 3 interpreter found" >&2
    exit 1
fi

# ── Create venv and install ───────────────────────────────────────────
echo "Creating per-worktree venv ($PYTHON)..."
"$PYTHON" -m venv "$VENV_DIR"

echo "Installing dependencies (this takes ~15s on first run)..."
"$VENV_DIR/bin/pip" install --upgrade pip --quiet 2>&1
"$VENV_DIR/bin/pip" install -e "$WORKTREE_DIR[dev]" --quiet 2>&1

echo "Per-worktree venv ready at $VENV_DIR"
