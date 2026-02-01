# Claude Project Template

A reusable Claude Code configuration template for Python projects. Provides sensible defaults for permissions, automated linting, code review workflows, and custom skills.

## Features

- **No prompts for safe operations** - Edit Python files, run tests/linters, search docs without interruption
- **Auto-linting** - Runs ruff after every file edit
- **Code review reminders** - Suggests `/review` after implementation work
- **Custom skills** - `/lint`, `/test`, `/review`, `/check` for common workflows
- **Python tooling** - Pre-configured ruff, pytest, coverage, and mypy

## Quick Start

### Option 1: Create a New Project

Use the `/init-from-template` skill in any Claude Code session:

```
/init-from-template my-project-name
```

This will:
1. Clone this template
2. Rename the package to match your project
3. Initialize a fresh git repository

### Option 2: Manual Setup

```bash
git clone https://github.com/janewilkin/claude-project-template.git my-project
cd my-project
rm -rf .git && git init

# Rename the package
mv src/your_package src/my_package
# Update pyproject.toml with your project name
```

### Option 3: Add to Existing Project

Copy the `.claude/` directory to your project:

```bash
cp -r claude-project-template/.claude your-project/
```

## Project Structure

```
your-project/
├── .claude/
│   ├── settings.json          # Permissions and hooks
│   ├── hooks/
│   │   ├── lint-format.sh     # Auto-runs ruff after edits
│   │   └── config-suggest.sh  # Suggests /sync-config
│   └── skills/
│       ├── review/            # /review - Code review
│       ├── lint/              # /lint - Run linters
│       ├── test/              # /test - Run tests
│       ├── check/             # /check - Full validation
│       ├── init-from-template/ # /init-from-template
│       └── sync-config/       # /sync-config
├── src/your_package/
├── tests/
├── pyproject.toml             # Python tooling config
├── CLAUDE.md                  # Project context for Claude
└── .gitignore
```

## Available Skills

| Skill | Description |
|-------|-------------|
| `/lint` | Run ruff check, ruff format, and mypy |
| `/test` | Run pytest with coverage reporting |
| `/review` | Review code for bugs and common issues |
| `/check` | Full validation: lint → test → review |
| `/init-from-template` | Create a new project from this template |
| `/sync-config` | Compare config against latest template |

## Configuration

### Permissions (`.claude/settings.json`)

The template allows these operations without prompting:

**Allowed:**
- Reading all files (except secrets)
- Editing `.py` files and `.claude/` config
- Running Python, pytest, ruff, mypy, black
- Git operations (status, diff, log, add, commit, branch)
- Web searches for Python documentation

**Denied:**
- Reading `.env`, credentials, keys, `.pem` files
- `rm -rf`, `sudo`
- Piping curl/wget output (security risk)

### Hooks

| Hook | Trigger | Action |
|------|---------|--------|
| `lint-format.sh` | After Edit/Write on `.py` | Runs ruff check --fix and ruff format |
| `config-suggest.sh` | After Edit on `.claude/` | Suggests running /sync-config |
| Stop hook | End of response | Suggests /review after implementation work |

### Python Tooling (`pyproject.toml`)

Pre-configured with:
- **ruff** - Linting (E, W, F, I, B, C4, UP, ARG, SIM, PTH, ERA, PL, RUF) and formatting
- **pytest** - Test discovery in `tests/`, verbose output
- **coverage** - 80% minimum, branch coverage
- **mypy** - Strict type checking

## Keeping Up to Date

Run `/sync-config` to compare your project against the latest template:

```
/sync-config           # Summary of differences
/sync-config --detailed # Full diffs
```

This shows:
- New permissions or deny rules
- Updated hooks
- New skills available
- Python tooling updates

## Development Setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

## Customization

### Adding Project Context

Edit `CLAUDE.md` to describe your project's architecture, conventions, and important files. Claude reads this for context.

### Local Overrides

Create `.claude/settings.local.json` for personal settings that shouldn't be shared (this file is gitignored).

### Extending Permissions

Add to the `allow` array in `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(docker *)",
      "WebFetch(domain:your-docs.com)"
    ]
  }
}
```

## License

Apache 2.0
