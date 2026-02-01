---
name: init-from-template
description: >
  Initialize a new Python project from the claude-project-template.
  Clones the template, customizes package names, and sets up the project structure.
argument-hint: "<project-name> [target-directory]"
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(mkdir *), Bash(mv *), Bash(rm -rf *), Read, Edit, Write, Glob
---

# Initialize Project from Template

Create a new Python project using the claude-project-template as a starting point.

## Arguments

- `$1` (required): Project name (e.g., `my-awesome-project`)
- `$2` (optional): Target directory (defaults to `./$1`)

## Process

### 1. Validate Arguments

```bash
PROJECT_NAME="$1"
TARGET_DIR="${2:-./$PROJECT_NAME}"

if [ -z "$PROJECT_NAME" ]; then
    echo "Error: Project name is required"
    echo "Usage: /init-from-template <project-name> [target-directory]"
    exit 1
fi

# Convert project name to valid Python package name
PACKAGE_NAME=$(echo "$PROJECT_NAME" | tr '-' '_' | tr '[:upper:]' '[:lower:]')
```

### 2. Clone Template

Clone from the official template repository:

```bash
git clone --depth 1 https://github.com/janewilkin/claude-project-template.git "$TARGET_DIR"
cd "$TARGET_DIR"
rm -rf .git
```

### 3. Customize Project

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

### 4. Initialize Git

```bash
git init
git add .
git commit -m "Initial commit from claude-project-template"
```

### 5. Provide Next Steps

After creating the project, output:

```
✓ Project '$PROJECT_NAME' created at $TARGET_DIR

Next steps:
1. cd $TARGET_DIR
2. python -m venv .venv && source .venv/bin/activate
3. pip install -e ".[dev]"
4. Update CLAUDE.md with your project description
5. Start coding in src/$PACKAGE_NAME/

Available skills:
  /lint    - Run linters and formatters
  /test    - Run tests with coverage
  /review  - Code review for issues
  /check   - Full validation pipeline
```

## Error Handling

- If target directory exists, ask user before overwriting
- If git clone fails, provide helpful error message
- Validate that package name is a valid Python identifier
