# Project Context

## Overview

[Brief description of what this project does - update this when you start using the template]

## Architecture

```
src/
└── your_package/       # Main package source code
    └── __init__.py

tests/                  # Test files
└── conftest.py         # Shared pytest fixtures
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
| `/init-from-template` | Create new project from template |
| `/sync-config` | Compare config against template |
