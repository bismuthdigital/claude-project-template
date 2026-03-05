# Project Context

## Overview

A reusable Claude Code configuration template for Python projects. Provides pre-configured permissions, automated linting hooks, code review workflows, and 21 custom skills — so you can start building immediately with sensible defaults.

## Architecture

```
src/
└── your_package/          # Main package source code
    └── __init__.py

tests/                     # Test files
└── conftest.py            # Shared pytest fixtures

scripts/                   # Utility scripts
├── work-queue.sh          # Task claiming for concurrent agents
├── task-format.py         # Task file parser, validator, and renderer
└── sync-all-projects.sh   # Sync config across all repos

.claude/
├── settings.json          # Permissions and hooks
├── ship.json              # Ship workflow settings
├── hooks/                 # Auto-linting, venv activation
└── skills/                # 21 skill definitions

install.sh                 # Template installer
```

## Development Setup

```bash
# Create virtual environment
python -m venv .venv
source .venv/bin/activate

# Install package with dev dependencies
pip install -e ".[dev]"
```

## Common Commands

| Command | Description |
|---------|-------------|
| `pytest` | Run all tests |
| `pytest -v --cov` | Run tests with coverage |
| `ruff check --fix .` | Lint and auto-fix issues |
| `ruff format .` | Format all Python files |
| `mypy src/` | Type check source code |

## Code Style

- Follow PEP 8 (enforced by ruff)
- Use type hints for all public functions
- Write docstrings in Google style format
- Keep functions focused and under 50 lines
- Prefer composition over inheritance

## Testing Requirements

- All new features require tests
- Maintain minimum 80% code coverage
- Use pytest fixtures for test setup
- Test edge cases and error conditions
- Mark slow tests with `@pytest.mark.slow`

## Project Conventions

### Naming
- `snake_case` for functions and variables
- `PascalCase` for classes
- `UPPER_CASE` for constants
- Prefix private members with `_`

### Imports
- Group imports: stdlib, third-party, local
- Use absolute imports for package code
- Sorted alphabetically (handled by ruff)

### Error Handling
- Use specific exception types
- Always log exceptions before re-raising
- Use context managers for resources

## Claude Skills

This project includes Claude Code skills for development:

| Skill | Purpose |
|-------|---------|
| `/lint` | Run linters and formatters |
| `/test` | Run tests with coverage |
| `/review` | Code review for issues |
| `/bash-review` | Review bash scripts for issues |
| `/docs` | Review documentation and comments |
| `/check` | Full validation pipeline |
| `/init-from-template` | Create new project from template (local only) |
| `/init-project` | Create new project with GitHub repository |
| `/sync-config` | Compare config against template |
| `/comic` | Generate SVG explainer comics about the project |
| `/ship` | Commit, PR, merge, and sync local repo |
| `/version` | Bump version, create and push git tag |
| `/claim-tasks` | Claim tasks from NEXT-STEPS.md for parallel worktree agents |
| `/release-tasks` | Release claimed tasks back to the work queue |
| `/cost-estimate` | Estimate API costs and suggest optimizations |
| `/model-alternatives` | Find free open-source replacements for paid API calls |
| `/prompt-review` | Review AI prompts for quality and suggest improvements |
| `/next-steps` | Identify, consolidate, and maintain project next steps |
| `/ci-review` | Diagnose GitHub Actions CI failures and suggest fixes |
| `/fix-failed-pr` | Find and repair PRs with CI failures or merge conflicts |
| `/aws-manifest` | Generate AWS infrastructure manifest |
