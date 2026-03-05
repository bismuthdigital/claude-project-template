## What

Reusable Claude Code configuration template for Python projects. Provides
permissions, auto-linting hooks, code review workflows, and 21 custom skills.

## Setup

```
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
```

## Key Paths

```
src/your_package/           Main package source code
tests/                      Test suite (pytest)
pyproject.toml              Python tooling config (ruff, pytest, mypy)
CLAUDE.md                   Project context for Claude Code
install.sh                  Template installer script
scripts/work-queue.sh       Task claiming for concurrent agents
scripts/sync-all-projects.sh  Sync config across all repos
.claude/settings.json       Permissions and hooks config
.claude/hooks/              Auto-linting, venv activation, config suggestions
.claude/skills/             All skill definitions (21 skills)
.claude/ship.json           Ship workflow settings
```

## Common Commands

```
pytest                      Run tests
pytest -v --cov             Run tests with coverage
ruff check --fix .          Lint and auto-fix
ruff format .               Format all Python files
mypy src/                   Type check source code
```

## Key Skills

```
/lint                       Run linters and formatters
/test                       Run tests with coverage
/review                     Code review for bugs and issues
/check                      Full validation pipeline
/ship                       Commit, PR, merge, and sync
/claim-tasks                Claim tasks + auto-create worktree
/sync-config                Compare config against template
/next-steps                 Manage project roadmap
```

## New Project From Template

```
curl -fsSL https://raw.githubusercontent.com/bismuthdigital/claude-project-template/main/install.sh | bash -s -- my-project
```

## Add to Existing Project

```
cd your-project
curl -fsSL https://raw.githubusercontent.com/bismuthdigital/claude-project-template/main/install.sh | bash -s -- --existing
```
