---
name: init-project
version: 1.0.0
description: >
  Initialize a new Python project from claude-project-template and create a private GitHub repository.
  Complete setup: clone template, customize, git init, create GitHub repo, and push.
argument-hint: "<project-name> [target-directory]"
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(gh *), Bash(mkdir *), Bash(mv *), Bash(rm -rf *), Read, Edit, Write, Glob
---

# Initialize Project with GitHub Repository

Create a new Python project using the claude-project-template and set up a private GitHub repository.

## Arguments

- `$1` (required): Project name (e.g., `my-awesome-project`)
- `$2` (optional): Target directory (defaults to sibling of current directory)

### Examples

Default location (creates `../my-project/` next to current directory):
```bash
/init-project my-project
```

Custom location:
```bash
/init-project my-project /path/to/custom/location
```

## Process

### Step 1: Validate Arguments

```bash
# Arguments passed by skill system: $1 = project name, $2 = target directory
PROJECT_NAME="$1"
TARGET_DIR="${2:-$(cd .. && pwd)/$PROJECT_NAME}"

if [ -z "$PROJECT_NAME" ]; then
    echo "Error: Project name is required"
    echo "Usage: /init-project <project-name> [target-directory]"
    exit 1
fi

# Convert project name to valid Python package name
PACKAGE_NAME=$(echo "$PROJECT_NAME" | tr '-' '_' | tr '[:upper:]' '[:lower:]')

# Validate package name is a valid Python identifier
if ! echo "$PACKAGE_NAME" | grep -qE '^[a-z_][a-z0-9_]*$'; then
    echo "Error: Project name must be a valid Python package name"
    echo "Got: $PACKAGE_NAME (from $PROJECT_NAME)"
    echo "Must start with lowercase letter or underscore, contain only lowercase letters, numbers, and underscores"
    exit 1
fi
```

### Step 2: Check Prerequisites

Verify GitHub CLI is authenticated:

```bash
echo "/init-project v1.0.0"
echo "═══════════════════════════════════════════════════"
echo "          INITIALIZING PROJECT: $PROJECT_NAME"
echo "═══════════════════════════════════════════════════"
echo ""
echo "───────────────────────────────────────────────────"
echo "PREREQUISITES"
echo "───────────────────────────────────────────────────"

# Check gh authentication
if ! gh auth status >/dev/null 2>&1; then
    echo "✗ GitHub CLI not authenticated"
    echo ""
    echo "Please authenticate with GitHub:"
    echo "  gh auth login"
    echo ""
    exit 1
fi
echo "✓ GitHub CLI authenticated"
```

### Step 3: Clone Template

Clone from the official template repository:

```bash
echo ""
echo "───────────────────────────────────────────────────"
echo "CLONE TEMPLATE"
echo "───────────────────────────────────────────────────"

if [ -d "$TARGET_DIR" ]; then
    echo "✗ Directory already exists: $TARGET_DIR"
    echo ""
    echo "Please remove it first or choose a different location:"
    echo "  rm -rf \"$TARGET_DIR\""
    echo "  /init-project \"$PROJECT_NAME\" /path/to/different/location"
    exit 1
fi

if ! git clone --depth 1 https://github.com/bismuthdigital/claude-project-template.git "$TARGET_DIR" 2>&1; then
    echo "✗ Failed to clone template"
    exit 1
fi
echo "✓ Cloned claude-project-template"

cd "$TARGET_DIR" || exit 1
rm -rf .git
echo "✓ Removed template git history"
```

### Step 4: Customize Project

Replace placeholder names with the actual project/package names:

```bash
echo ""
echo "───────────────────────────────────────────────────"
echo "CUSTOMIZE PROJECT"
echo "───────────────────────────────────────────────────"

# Detect OS for sed compatibility
if [[ "$OSTYPE" == "darwin"* ]]; then
    SED_INPLACE="sed -i ''"
else
    SED_INPLACE="sed -i"
fi

# Update pyproject.toml - project name
$SED_INPLACE "s/name = \"your-project-name\"/name = \"$PROJECT_NAME\"/" pyproject.toml
echo "✓ Updated pyproject.toml (name: $PROJECT_NAME)"

# Update pyproject.toml - known-first-party
$SED_INPLACE "s/known-first-party = \\[\"your_package\"\\]/known-first-party = [\"$PACKAGE_NAME\"]/" pyproject.toml

# Rename package directory
mv "src/your_package" "src/$PACKAGE_NAME"
echo "✓ Renamed package: your_package → $PACKAGE_NAME"

# CLAUDE.md is left as-is per user preference
echo "✓ CLAUDE.md ready for manual update"

# Update lint skill reference to package name
$SED_INPLACE "s/your_package/$PACKAGE_NAME/g" .claude/skills/lint/SKILL.md
echo "✓ Updated linter configuration"
```

### Step 5: Initialize Git

```bash
echo ""
echo "───────────────────────────────────────────────────"
echo "INITIALIZE GIT"
echo "───────────────────────────────────────────────────"

git init >/dev/null 2>&1
echo "✓ Initialized git repository"

git add .
git commit -m "Initial commit from claude-project-template

Project: $PROJECT_NAME
Package: $PACKAGE_NAME

Co-Authored-By: Claude <noreply@anthropic.com>" >/dev/null 2>&1
echo "✓ Created initial commit"
```

### Step 6: Create GitHub Repository

```bash
echo ""
echo "───────────────────────────────────────────────────"
echo "CREATE GITHUB REPOSITORY"
echo "───────────────────────────────────────────────────"

# Check if repo already exists
if gh repo view "$PROJECT_NAME" >/dev/null 2>&1; then
    echo "✗ GitHub repository already exists: $PROJECT_NAME"
    echo ""
    echo "Please either:"
    echo "  1. Choose a different project name"
    echo "  2. Delete the existing repository: gh repo delete \"$PROJECT_NAME\""
    echo "  3. Use /init-from-template for local-only setup"
    exit 1
fi

# Create private repository
if ! gh repo create "$PROJECT_NAME" \
  --private \
  --source="." \
  --remote=origin \
  --description="Python project initialized from claude-project-template" >/dev/null 2>&1; then
    echo "✗ Failed to create GitHub repository"
    exit 1
fi

# Get the repo URL
REPO_URL=$(git remote get-url origin)
echo "✓ Created private repo: $REPO_URL"
echo "✓ Added remote: origin"
```

### Step 7: Push to GitHub

```bash
echo ""
echo "───────────────────────────────────────────────────"
echo "PUSH TO GITHUB"
echo "───────────────────────────────────────────────────"

if ! git push -u origin main >/dev/null 2>&1; then
    echo "✗ Failed to push to GitHub"
    echo ""
    echo "Repository was created but push failed. You may need to:"
    echo "  cd \"$TARGET_DIR\""
    echo "  git push -u origin main"
    exit 1
fi
echo "✓ Pushed to origin/main"

# Get GitHub web URL
GH_WEB_URL=$(gh repo view --json url -q .url)
echo "✓ Repository URL: $GH_WEB_URL"
```

### Step 8: Success Summary

```bash
echo ""
echo "═══════════════════════════════════════════════════"
echo "            PROJECT READY! 🚀"
echo "═══════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "1. cd $TARGET_DIR"
echo "2. python -m venv .venv && source .venv/bin/activate"
echo "3. pip install -e \".[dev]\""
echo "4. Update CLAUDE.md with detailed project description"
echo "5. Start coding in src/$PACKAGE_NAME/"
echo ""
echo "Available skills:"
echo "  /lint    - Run linters and formatters"
echo "  /test    - Run tests with coverage"
echo "  /review  - Code review for issues"
echo "  /check   - Full validation pipeline"
echo "  /ship    - Commit, PR, merge, and sync workflow"
echo ""
echo "GitHub repository: $GH_WEB_URL"
echo ""
```

## Error Handling

| Error | Resolution |
|-------|------------|
| No project name | Show usage and exit |
| Invalid project name | Validate Python identifier format |
| Target directory exists | Exit with instructions to remove |
| GitHub CLI not authenticated | Show `gh auth login` instructions |
| Template clone fails | Show error with network troubleshooting |
| GitHub repo already exists | Exit with clear options |
| Push fails | Show error with manual push instructions |

## Notes

- This skill creates **private** GitHub repositories by default
- Requires GitHub CLI (`gh`) to be installed and authenticated
- For local-only setup without GitHub, use `/init-from-template` instead
- The skill will fail fast if any prerequisites are missing
- All git operations use the main branch
