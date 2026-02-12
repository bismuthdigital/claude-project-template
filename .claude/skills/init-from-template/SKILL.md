---
name: init-from-template
version: 1.0.0
description: >
  Initialize a new Python project from the claude-project-template.
  Clones the template, customizes package names, and sets up the project structure.
  Works with private repos in cloud environments.
argument-hint: "<project-name> [target-directory]"
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(gh *), Bash(curl *), Bash(mkdir *), Bash(mv *), Bash(rm -rf *), Bash(mktemp *), Bash(tar *), Bash(cat *), Read, Edit, Write, Glob
---

# Initialize Project from Template

Create a new Python project using the claude-project-template as a starting point.

## Arguments

- `$1` (required): Project name (e.g., `my-awesome-project`)
- `$2` (optional): Target directory (defaults to `~/code/claude/$1`)

### Examples

Default location (creates at `~/code/claude/my-project/`):
```bash
/init-from-template my-project
```

Custom location:
```bash
/init-from-template my-project /path/to/custom/location
```

## Configuration

The template source can be overridden via `.claude/template.json` in the current directory (if it exists):

```json
{
  "repo": "janewilkin/claude-project-template",
  "branch": "main"
}
```

Defaults to `janewilkin/claude-project-template` on `main`.

## Process

### 1. Validate Arguments

```bash
PROJECT_NAME="$1"
TARGET_DIR="${2:-$HOME/code/claude/$PROJECT_NAME}"

if [ -z "$PROJECT_NAME" ]; then
    echo "Error: Project name is required"
    echo "Usage: /init-from-template <project-name> [target-directory]"
    exit 1
fi

# Convert project name to valid Python package name
PACKAGE_NAME=$(echo "$PROJECT_NAME" | tr '-' '_' | tr '[:upper:]' '[:lower:]')
```

### 2. Read Template Config

```bash
TEMPLATE_REPO=$(cat .claude/template.json 2>/dev/null | grep -o '"repo"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
TEMPLATE_BRANCH=$(cat .claude/template.json 2>/dev/null | grep -o '"branch"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
TEMPLATE_REPO="${TEMPLATE_REPO:-janewilkin/claude-project-template}"
TEMPLATE_BRANCH="${TEMPLATE_BRANCH:-main}"
```

### 3. Clone Template

Try these strategies in order — use the first one that succeeds. This handles private repos and cloud environments where SSH keys and credential helpers are unavailable.

#### Strategy 1: `gh` CLI (best for cloud environments)

```bash
if gh auth status &>/dev/null; then
    TEMP_DIR=$(mktemp -d)
    gh api "repos/${TEMPLATE_REPO}/tarball/${TEMPLATE_BRANCH}" > "$TEMP_DIR/template.tar.gz" 2>/dev/null
    if [ $? -eq 0 ]; then
        mkdir -p "$TARGET_DIR"
        tar -xzf "$TEMP_DIR/template.tar.gz" -C "$TARGET_DIR" --strip-components=1
        rm -rf "$TEMP_DIR"
        CLONE_METHOD="gh api (tarball)"
    fi
fi
```

#### Strategy 2: `git clone` with token from environment

```bash
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

if [ -z "$CLONE_METHOD" ] && [ -n "$TOKEN" ]; then
    git clone --depth 1 --branch "$TEMPLATE_BRANCH" \
        "https://x-access-token:${TOKEN}@github.com/${TEMPLATE_REPO}.git" \
        "$TARGET_DIR" 2>/dev/null
    if [ $? -eq 0 ]; then
        CLONE_METHOD="git clone (token)"
    fi
fi
```

#### Strategy 3: `git clone` with credential helper

```bash
if [ -z "$CLONE_METHOD" ]; then
    git clone --depth 1 --branch "$TEMPLATE_BRANCH" \
        "https://github.com/${TEMPLATE_REPO}.git" \
        "$TARGET_DIR" 2>/dev/null
    if [ $? -eq 0 ]; then
        CLONE_METHOD="git clone (credentials)"
    fi
fi
```

#### If all strategies fail

```
✗ Could not clone template repository: ${TEMPLATE_REPO}

This is likely a private repository and no authentication is configured.

To fix, do ONE of the following:

  1. Authenticate the gh CLI (recommended):
     gh auth login

  2. Set a GitHub token in your environment:
     export GH_TOKEN=ghp_xxxxxxxxxxxx

  3. Configure git credentials:
     git config --global credential.helper store

  4. If using Claude Code on the web, add a GitHub integration
     in your Claude Code settings to enable repo access.
```

Stop execution here if the template cannot be fetched.

### 4. Clean Up Git History

```bash
cd "$TARGET_DIR"
rm -rf .git
```

### 5. Customize Project

Replace placeholder names with the actual project/package names:

**Files to update:**
- `pyproject.toml`: Update `name`, `known-first-party`
- `src/your_package/` → `src/$PACKAGE_NAME/`
- `CLAUDE.md`: Update project description placeholder
- `.claude/skills/lint/SKILL.md`: Update `known-first-party` reference

**Replacements:**
- `your-project-name` → `$PROJECT_NAME`
- `your_package` → `$PACKAGE_NAME`
- `Your project description` → prompt user or leave as TODO

### 6. Initialize Git

```bash
git init
git add .
git commit -m "Initial commit from claude-project-template"
```

### 7. Provide Next Steps

After creating the project, output:

```
/init-from-template v1.0.0

✓ Project '$PROJECT_NAME' created at $TARGET_DIR
  (template: ${TEMPLATE_REPO} via ${CLONE_METHOD})

Next steps:
1. cd $TARGET_DIR
2. python -m venv .venv && source .venv/bin/activate
3. pip install -e ".[dev]"
4. Update CLAUDE.md with your project description
5. Start coding in src/$PACKAGE_NAME/

Available skills:
  /lint           - Run linters and formatters
  /test           - Run tests with coverage
  /review         - Code review for issues
  /bash-review    - Review bash scripts for issues
  /docs           - Review documentation and comments
  /check          - Full validation pipeline
  /ship           - Commit, PR, merge, and sync
  /version        - Bump version and create git tag
  /cost-estimate  - Estimate API costs
  /sync-config    - Compare config against template
```

## Error Handling

- If target directory exists, ask user before overwriting
- If clone fails, try next auth strategy before giving up
- Validate that package name is a valid Python identifier
- If all clone strategies fail, provide clear instructions for the user's environment
