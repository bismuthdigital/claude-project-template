#!/bin/bash
# Shared virtual environment activation for Claude Code skills and hooks.
# Source this file; do not execute it directly.
#
# Sets on success:
#   VENV_ACTIVATED=1
#   VENV_METHOD=<method>  (venv, poetry, conda, uv, pipenv, pyenv, none)
#
# Usage in skills/hooks:
#   source .claude/hooks/venv-activate.sh 2>/dev/null || true

# Guard against double-activation
if [[ "${VENV_ACTIVATED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

# Wrap in a function to safely use `local` when sourced
_venv_activate() {
    local project_dir="${CLAUDE_PROJECT_DIR:-.}"

    # Strategy 1: .venv (most common — default for python -m venv .venv)
    if [[ -f "$project_dir/.venv/bin/activate" ]]; then
        # shellcheck disable=SC1091
        source "$project_dir/.venv/bin/activate" 2>/dev/null || true
        export VENV_ACTIVATED=1 VENV_METHOD="venv"
        return 0
    fi

    # Strategy 2: venv/ directory
    if [[ -f "$project_dir/venv/bin/activate" ]]; then
        # shellcheck disable=SC1091
        source "$project_dir/venv/bin/activate" 2>/dev/null || true
        export VENV_ACTIVATED=1 VENV_METHOD="venv"
        return 0
    fi

    # Strategy 3: Poetry
    if [[ -f "$project_dir/poetry.lock" ]] && command -v poetry &>/dev/null; then
        local venv_path
        venv_path="$(cd "$project_dir" && poetry env info -p 2>/dev/null)"
        if [[ -n "$venv_path" && -f "$venv_path/bin/activate" ]]; then
            # shellcheck disable=SC1091
            source "$venv_path/bin/activate" 2>/dev/null || true
            export VENV_ACTIVATED=1 VENV_METHOD="poetry"
            return 0
        fi
    fi

    # Strategy 4: Conda
    if [[ -f "$project_dir/environment.yml" ]] && command -v conda &>/dev/null; then
        local conda_env
        conda_env="$(grep 'name:' "$project_dir/environment.yml" 2>/dev/null | head -1 | awk '{print $2}')"
        if [[ -n "$conda_env" ]]; then
            conda activate "$conda_env" 2>/dev/null || true
            export VENV_ACTIVATED=1 VENV_METHOD="conda"
            return 0
        fi
    fi

    # Strategy 5: uv (creates .venv by convention, but check uv.lock as signal)
    if command -v uv &>/dev/null && [[ -f "$project_dir/uv.lock" ]]; then
        if [[ -f "$project_dir/.venv/bin/activate" ]]; then
            # shellcheck disable=SC1091
            source "$project_dir/.venv/bin/activate" 2>/dev/null || true
            export VENV_ACTIVATED=1 VENV_METHOD="uv"
            return 0
        fi
    fi

    # Strategy 6: Pipenv
    if [[ -f "$project_dir/Pipfile" ]] && command -v pipenv &>/dev/null; then
        local pipenv_venv
        pipenv_venv="$(cd "$project_dir" && pipenv --venv 2>/dev/null)"
        if [[ -n "$pipenv_venv" && -f "$pipenv_venv/bin/activate" ]]; then
            # shellcheck disable=SC1091
            source "$pipenv_venv/bin/activate" 2>/dev/null || true
            export VENV_ACTIVATED=1 VENV_METHOD="pipenv"
            return 0
        fi
    fi

    # Strategy 7: pyenv-virtualenv
    if command -v pyenv &>/dev/null && [[ -f "$project_dir/.python-version" ]]; then
        eval "$(pyenv init - 2>/dev/null)" || true
        eval "$(pyenv virtualenv-init - 2>/dev/null)" || true
        export VENV_ACTIVATED=1 VENV_METHOD="pyenv"
        return 0
    fi

    # Fallback: no venv found, continue without error
    export VENV_ACTIVATED=0 VENV_METHOD="none"
    return 0
}

_venv_activate
unset -f _venv_activate
