# Claude Project Template

A reusable Claude Code configuration template for Python projects. Provides sensible defaults for permissions, automated linting, code review workflows, and custom skills.

## Features

- **No prompts for safe operations** - Edit Python files, run tests/linters, search docs without interruption
- **Auto-linting** - Runs ruff after every file edit
- **Code review reminders** - Suggests `/review` after implementation work
- **Custom skills** - `/lint`, `/test`, `/review`, `/check`, `/docs`, `/bash-review`, `/comic`, `/ship`, `/version`, `/cost-estimate`, `/sync-config` and more
- **Python tooling** - Pre-configured ruff, pytest, coverage, and mypy

## Installation

### Quick Install (New Project)

```bash
curl -fsSL https://raw.githubusercontent.com/janewilkin/claude-project-template/main/install.sh | bash -s -- my-project
```

This creates a new project with:
- Package renamed to match your project
- Git repository initialized
- Ready to use immediately

### Quick Install (Existing Project)

```bash
cd your-project
curl -fsSL https://raw.githubusercontent.com/janewilkin/claude-project-template/main/install.sh | bash -s -- --existing
```

This adds the `.claude/` configuration to your current directory.

### Manual Installation

<details>
<summary>New project (manual steps)</summary>

```bash
# Clone the template
git clone https://github.com/janewilkin/claude-project-template.git my-project
cd my-project

# Remove template's git history and start fresh
rm -rf .git
git init

# Rename the package to match your project
mv src/your_package src/my_package

# Update pyproject.toml: change "your-project-name" and "your_package"
# Update CLAUDE.md with your project description
```

</details>

<details>
<summary>Existing project (manual steps)</summary>

```bash
# Clone the template somewhere temporary
git clone https://github.com/janewilkin/claude-project-template.git /tmp/claude-template

# Copy the .claude directory to your project
cp -r /tmp/claude-template/.claude your-project/

# Optionally copy the Python tooling config
cp /tmp/claude-template/pyproject.toml your-project/  # merge with existing if needed
cp /tmp/claude-template/.gitignore your-project/      # merge with existing if needed

# Clean up
rm -rf /tmp/claude-template
```

</details>

### Development Setup

After installation, set up your Python environment:

```bash
cd your-project
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

This installs ruff, pytest, pytest-cov, and mypy.

## Project Structure

```
your-project/
├── .claude/
│   ├── settings.json          # Permissions and hooks
│   ├── hooks/
│   │   ├── lint-format.sh     # Auto-runs ruff after edits
│   │   └── config-suggest.sh  # Suggests /sync-config
│   ├── ship.json              # Ship workflow settings
│   └── skills/
│       ├── bash-review/       # /bash-review - Shell script analysis
│       ├── check/             # /check - Full validation
│       ├── comic/             # /comic - SVG explainer comics
│       ├── cost-estimate/     # /cost-estimate - API cost analysis
│       ├── docs/              # /docs - Documentation review
│       ├── init-from-template/ # /init-from-template
│       ├── init-project/      # /init-project - New project + GitHub repo
│       ├── lint/              # /lint - Run linters
│       ├── model-alternatives/ # /model-alternatives - Free model replacements
│       ├── next-steps/        # /next-steps - Roadmap review and planning
│       ├── prompt-review/     # /prompt-review - AI prompt quality review
│       ├── review/            # /review - Code review
│       ├── ship/              # /ship - Commit, PR, merge workflow
│       ├── sync-config/       # /sync-config
│       ├── test/              # /test - Run tests
│       └── version/           # /version - Semantic versioning
├── src/your_package/
├── tests/
├── pyproject.toml             # Python tooling config
├── CLAUDE.md                  # Project context for Claude
└── .gitignore
```

## Available Skills

Once installed, these skills are available in Claude Code:

| Skill | Description |
|-------|-------------|
| `/lint` | Run ruff check, ruff format, and mypy |
| `/test` | Run pytest with coverage reporting |
| `/review` | Review code for bugs and common issues |
| `/bash-review` | Review bash scripts for issues |
| `/docs` | Review documentation and comments for consistency |
| `/check` | Full validation: lint → test → review → docs → bash-review |
| `/comic` | Generate SVG explainer comics about the project |
| `/cost-estimate` | Estimate API costs and suggest optimizations |
| `/model-alternatives` | Find free open-source replacements for paid API calls |
| `/prompt-review` | Review AI prompts for quality and suggest improvements |
| `/init-from-template` | Create a new project from this template (local only) |
| `/init-project` | Create a new project with GitHub repository |
| `/sync-config` | Compare your config against latest template |
| `/next-steps` | Review roadmap, reconcile with recent work, suggest next step |
| `/ship` | Commit, PR, merge, and sync local repo |
| `/version` | Bump version, create and push git tag |

## Keeping Up to Date

After installing, you can check for template updates using the `/sync-config` skill:

```
/sync-config           # Summary of differences
/sync-config --detailed # Full diffs
```

This compares your project against the latest template and shows:
- New permissions or deny rules
- Updated hooks
- New skills available
- Python tooling updates

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
