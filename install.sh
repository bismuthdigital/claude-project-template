#!/bin/bash
# Claude Project Template Installer
# https://github.com/janewilkin/claude-project-template
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/janewilkin/claude-project-template/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/janewilkin/claude-project-template/main/install.sh | bash -s -- my-project
#   curl -fsSL https://raw.githubusercontent.com/janewilkin/claude-project-template/main/install.sh | bash -s -- --existing

set -e

TEMPLATE_REPO="https://github.com/janewilkin/claude-project-template.git"
TEMPLATE_NAME="claude-project-template"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}==>${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }

usage() {
    cat << EOF
Claude Project Template Installer

Usage:
  install.sh [options] [project-name]

Options:
  --existing    Add template to current directory (existing project)
  --help        Show this help message

Examples:
  # Create new project
  install.sh my-awesome-project

  # Create new project in current directory
  install.sh .

  # Add to existing project in current directory
  install.sh --existing

  # Piped installation
  curl -fsSL https://raw.githubusercontent.com/janewilkin/claude-project-template/main/install.sh | bash -s -- my-project
EOF
    exit 0
}

# Parse arguments
EXISTING_PROJECT=false
PROJECT_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --existing)
            EXISTING_PROJECT=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            PROJECT_NAME="$1"
            shift
            ;;
    esac
done

# Check for git
if ! command -v git &> /dev/null; then
    error "git is required but not installed"
fi

if [ "$EXISTING_PROJECT" = true ]; then
    # Adding to existing project
    TARGET_DIR="$(pwd)"
    info "Adding Claude configuration to existing project: $TARGET_DIR"

    if [ -d "$TARGET_DIR/.claude" ]; then
        warn ".claude directory already exists"
        read -p "Overwrite existing configuration? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error "Installation cancelled"
        fi
        rm -rf "$TARGET_DIR/.claude"
    fi

    # Clone to temp and copy
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    info "Fetching template..."
    git clone --depth 1 --quiet "$TEMPLATE_REPO" "$TEMP_DIR"

    info "Copying Claude configuration..."
    cp -r "$TEMP_DIR/.claude" "$TARGET_DIR/"
    chmod +x "$TARGET_DIR/.claude/hooks/"*.sh 2>/dev/null || true

    # Optionally copy other files
    if [ ! -f "$TARGET_DIR/.gitignore" ]; then
        cp "$TEMP_DIR/.gitignore" "$TARGET_DIR/"
        success "Created .gitignore"
    else
        warn ".gitignore exists - you may want to merge with template"
    fi

    if [ ! -f "$TARGET_DIR/CLAUDE.md" ]; then
        cp "$TEMP_DIR/CLAUDE.md" "$TARGET_DIR/"
        success "Created CLAUDE.md"
    fi

    success "Claude configuration installed!"
    echo ""
    echo "Next steps:"
    echo "  1. Review .claude/settings.json permissions"
    echo "  2. Edit CLAUDE.md with your project context"
    echo "  3. Optionally merge pyproject.toml settings from template"
    echo ""

else
    # Creating new project
    if [ -z "$PROJECT_NAME" ]; then
        read -p "Project name: " PROJECT_NAME
    fi

    if [ -z "$PROJECT_NAME" ]; then
        error "Project name is required"
    fi

    # Convert to valid Python package name
    PACKAGE_NAME=$(echo "$PROJECT_NAME" | tr '-' '_' | tr '[:upper:]' '[:lower:]')

    # Determine target directory
    if [ "$PROJECT_NAME" = "." ]; then
        TARGET_DIR="$(pwd)"
        PROJECT_NAME=$(basename "$TARGET_DIR")
        PACKAGE_NAME=$(echo "$PROJECT_NAME" | tr '-' '_' | tr '[:upper:]' '[:lower:]')
    else
        TARGET_DIR="$(pwd)/$PROJECT_NAME"
    fi

    if [ -d "$TARGET_DIR" ] && [ "$PROJECT_NAME" != "." ]; then
        error "Directory $TARGET_DIR already exists"
    fi

    info "Creating project: $PROJECT_NAME"
    info "Package name: $PACKAGE_NAME"
    info "Target: $TARGET_DIR"
    echo ""

    # Clone template
    info "Cloning template..."
    if [ "$PROJECT_NAME" = "." ] || [ "$TARGET_DIR" = "$(pwd)" ]; then
        TEMP_DIR=$(mktemp -d)
        trap "rm -rf $TEMP_DIR" EXIT
        git clone --depth 1 --quiet "$TEMPLATE_REPO" "$TEMP_DIR"

        # Copy files to current directory
        cp -r "$TEMP_DIR"/.* "$TARGET_DIR/" 2>/dev/null || true
        cp -r "$TEMP_DIR"/* "$TARGET_DIR/" 2>/dev/null || true
        rm -rf "$TARGET_DIR/.git"
    else
        git clone --depth 1 --quiet "$TEMPLATE_REPO" "$TARGET_DIR"
        rm -rf "$TARGET_DIR/.git"
    fi

    # Rename package directory
    if [ -d "$TARGET_DIR/src/your_package" ]; then
        mv "$TARGET_DIR/src/your_package" "$TARGET_DIR/src/$PACKAGE_NAME"
        success "Renamed package to $PACKAGE_NAME"
    fi

    # Update pyproject.toml
    if [ -f "$TARGET_DIR/pyproject.toml" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i '' "s/your-project-name/$PROJECT_NAME/g" "$TARGET_DIR/pyproject.toml"
            sed -i '' "s/your_package/$PACKAGE_NAME/g" "$TARGET_DIR/pyproject.toml"
        else
            # Linux
            sed -i "s/your-project-name/$PROJECT_NAME/g" "$TARGET_DIR/pyproject.toml"
            sed -i "s/your_package/$PACKAGE_NAME/g" "$TARGET_DIR/pyproject.toml"
        fi
        success "Updated pyproject.toml"
    fi

    # Make hook scripts executable
    chmod +x "$TARGET_DIR/.claude/hooks/"*.sh 2>/dev/null || true

    # Initialize git
    info "Initializing git repository..."
    cd "$TARGET_DIR"
    git init --quiet
    git add .
    git commit --quiet -m "Initial commit from claude-project-template"
    success "Git repository initialized"

    echo ""
    success "Project '$PROJECT_NAME' created!"
    echo ""
    echo "Next steps:"
    echo "  cd $PROJECT_NAME"
    echo "  python -m venv .venv"
    echo "  source .venv/bin/activate"
    echo "  pip install -e \".[dev]\""
    echo ""
    echo "  # Update CLAUDE.md with your project description"
    echo "  # Start coding in src/$PACKAGE_NAME/"
    echo ""
    echo "Available skills:"
    echo "  /lint           - Run linters and formatters"
    echo "  /test           - Run tests with coverage"
    echo "  /review         - Code review for issues"
    echo "  /bash-review    - Review bash scripts for issues"
    echo "  /docs           - Review documentation and comments"
    echo "  /check          - Full validation pipeline"
    echo "  /next-steps     - Review roadmap and suggest next step"
    echo "  /ship           - Commit, PR, merge, and sync"
    echo "  /version        - Bump version and create git tag"
    echo "  /cost-estimate  - Estimate API costs"
    echo "  /model-alternatives - Find free model replacements"
    echo "  /prompt-review  - Review AI prompts for quality"
    echo "  /sync-config    - Compare config against template"
    echo ""
fi
