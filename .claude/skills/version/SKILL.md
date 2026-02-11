---
name: version
description: >
  Manages semantic versioning. Analyzes changes to determine appropriate
  increment level (major/minor/patch) or accepts manual override.
  Updates version files and creates a git tag.
argument-hint: "[major|minor|patch] or empty for auto-detect"
allowed-tools: Read, Glob, Grep, Edit, Bash(git *)
---

# Semantic Version Management

Manage project versioning with automatic change analysis and git tagging.

## What This Skill Does

1. **Analyze** - Review changes since last tag to determine version increment
2. **Update** - Modify version in all project files
3. **Tag** - Create and push an annotated git tag

## Usage

```
/version              # Auto-detect increment level from changes
/version patch        # Force patch increment (bug fixes)
/version minor        # Force minor increment (new features)
/version major        # Force major increment (breaking changes)
```

## Version Files

This skill updates version in two locations:

| File | Format |
|------|--------|
| `pyproject.toml` | `version = "X.Y.Z"` |
| `src/your_package/__init__.py` | `__version__ = "X.Y.Z"` |

## Process

### Step 1: Pre-flight Checks

Detect if running in a worktree:

```bash
# Detect worktree vs main repo
git rev-parse --git-dir
```

If `--git-dir` output contains `/worktrees/`, you are in a worktree. This affects push behavior (Step 8).

Verify the repository state:

```bash
# Check for uncommitted changes
git status --porcelain
```

If there are uncommitted changes, warn the user:
> "You have uncommitted changes. Commit them before versioning."

**Worktree safety:** Never suggest `git stash` — in worktrees, the stash is shared across all worktrees. A stash created here could be accidentally popped in another worktree, losing changes. Always recommend committing (even a WIP commit) instead.

```bash
# Get current version from pyproject.toml
grep -E "^version" pyproject.toml
```

### Step 2: Get Version History

Find the last version tag:

```bash
# List version tags, sorted by version number (descending)
git tag -l "v*" --sort=-v:refname | head -1
```

If no tags exist, this will be the first release. Use the initial commit as the base:

```bash
git rev-list --max-parents=0 HEAD
```

### Step 3: Analyze Changes (Auto-detect Mode)

If no increment level was specified, analyze changes since last tag:

```bash
# Get commit messages since last tag (or initial commit)
git log <base>..HEAD --format="%s"
```

**Detection Rules:**

| Pattern | Increment | Example |
|---------|-----------|---------|
| `BREAKING CHANGE` in message | MAJOR | "refactor!: BREAKING CHANGE remove legacy API" |
| `!:` in subject line | MAJOR | "feat!: redesign auth system" |
| `feat:` prefix | MINOR | "feat: add user preferences" |
| `feat(scope):` prefix | MINOR | "feat(api): add new endpoint" |
| `fix:` prefix | PATCH | "fix: resolve null pointer" |
| `docs:`, `chore:`, `test:` | PATCH | "docs: update README" |
| No conventional commits | PATCH | Default to patch |

Apply the highest applicable increment level.

### Step 4: Calculate New Version

Parse the current version and calculate the new one:

```
Current: 0.1.0
  + PATCH → 0.1.1
  + MINOR → 0.2.0
  + MAJOR → 1.0.0
```

Ask user for confirmation before proceeding:
> "Bump version from 0.1.0 to 0.2.0 (MINOR)? [Y/n]"

### Step 5: Update Version Files

Update both version locations:

**pyproject.toml:**
```toml
version = "X.Y.Z"
```

**src/your_package/__init__.py:**
```python
__version__ = "X.Y.Z"
```

### Step 6: Commit Version Bump

```bash
git add pyproject.toml src/your_package/__init__.py
git commit -m "$(cat <<'EOF'
Bump version to X.Y.Z

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Step 7: Create Git Tag

Create an annotated tag:

```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
```

### Step 8: Push Tag

Ask user for confirmation, then push:

```bash
git push origin vX.Y.Z
```

If in a worktree, also push the commit:

```bash
git push origin HEAD
```

## Output Format

```
═══════════════════════════════════════════════════
              VERSION MANAGEMENT
═══════════════════════════════════════════════════

Current version: 0.1.0
Last tag: (none)

───────────────────────────────────────────────────
CHANGE ANALYSIS
───────────────────────────────────────────────────
Commits since last release: 12

Detected signals:
  • feat: Add /ship skill for deployment workflow
  • feat: Add /docs skill for documentation review
  • fix: Resolve linting configuration issue

Recommendation: MINOR (new features detected)

───────────────────────────────────────────────────
VERSION UPDATE
───────────────────────────────────────────────────
New version: 0.2.0

Proceed? [Y/n]

───────────────────────────────────────────────────
APPLYING
───────────────────────────────────────────────────
✓ Updated pyproject.toml
✓ Updated src/your_package/__init__.py
✓ Committed: "Bump version to 0.2.0"
✓ Created tag: v0.2.0

Push tag to origin? [Y/n]
✓ Pushed v0.2.0 to origin

═══════════════════════════════════════════════════
           VERSION 0.2.0 RELEASED
═══════════════════════════════════════════════════
```

## Error Handling

| Error | Resolution |
|-------|------------|
| Uncommitted changes | Ask user to commit first (never suggest stash in worktrees) |
| Version file not found | List expected paths, check project structure |
| Tag already exists | Suggest incrementing further or using `--force` |
| Push fails | Show error, provide manual push command |
| No changes since last tag | Inform user, suggest using explicit level |
| Invalid version format | Show current value, ask for manual correction |

## Semantic Versioning Reference

| Version Part | When to Increment |
|--------------|-------------------|
| **MAJOR** (X.0.0) | Breaking changes, incompatible API changes |
| **MINOR** (0.X.0) | New features, backward-compatible additions |
| **PATCH** (0.0.X) | Bug fixes, documentation, minor improvements |

## Worktree Safety

This skill is safe to run in git worktrees. Key considerations:

- **Never use `git stash`** — stashes are shared across all worktrees and can be lost
- **Tags are global** — a tag created in a worktree is visible in the main repo and all worktrees
- **Push the commit** — in a worktree, the version bump commit must be pushed explicitly (`git push origin HEAD`) since the main repo won't see it otherwise

## Notes

- Tags use the `v` prefix (e.g., `v1.2.3`) following common convention
- The skill creates annotated tags (not lightweight) for better metadata
- Version commits include the Co-Authored-By trailer
- If using conventional commits, the skill will parse them automatically
- For first release, considers all commits since initial commit
