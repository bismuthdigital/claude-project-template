---
name: sync-config
description: >
  Compare this project's Claude configuration against the official template.
  Identifies missing features, outdated patterns, and suggests specific updates.
argument-hint: "[--detailed]"
allowed-tools: Read, Glob, Grep, Bash(git *), Bash(curl *), Bash(mktemp *), Bash(rm -rf *), Bash(gh *), Bash(cat *), Bash(source *)
---

# Sync Configuration with Template

Compare the current project's Claude Code configuration against the latest official template and suggest updates.

## Arguments

- `--detailed`: Show full diffs instead of summaries

## Configuration

The template source is configured in `.claude/template.json`:

```json
{
  "repo": "janewilkin/claude-project-template",
  "branch": "main"
}
```

If this file doesn't exist, defaults to `janewilkin/claude-project-template` on `main`.

## Process

### 1. Fetch Latest Template

Fetch the template using an authentication strategy that works in cloud environments, CI, and local machines — including private repos.

**Read configuration:**

```bash
# Read template source config (or use defaults)
TEMPLATE_REPO=$(cat .claude/template.json 2>/dev/null | grep -o '"repo"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
TEMPLATE_BRANCH=$(cat .claude/template.json 2>/dev/null | grep -o '"branch"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
TEMPLATE_REPO="${TEMPLATE_REPO:-janewilkin/claude-project-template}"
TEMPLATE_BRANCH="${TEMPLATE_BRANCH:-main}"
```

**Try these fetch strategies in order — use the first one that succeeds:**

#### Strategy 1: GitHub API via `gh` CLI (best for cloud environments)

Works when `gh auth` is configured, which covers GitHub Codespaces, cloud IDEs with GitHub OAuth, and local machines with `gh auth login`.

```bash
# Check if gh is available and authenticated
if gh auth status &>/dev/null; then
    TEMPLATE_DIR=$(mktemp -d)
    # Fetch the repo as a tarball via the API (works for private repos)
    gh api "repos/${TEMPLATE_REPO}/tarball/${TEMPLATE_BRANCH}" > "$TEMPLATE_DIR/template.tar.gz" 2>/dev/null
    if [ $? -eq 0 ]; then
        tar -xzf "$TEMPLATE_DIR/template.tar.gz" -C "$TEMPLATE_DIR" --strip-components=1
        rm "$TEMPLATE_DIR/template.tar.gz"
        FETCH_METHOD="gh api (tarball)"
    fi
fi
```

#### Strategy 2: `git clone` with token from environment

Works in CI pipelines, cloud environments with `GH_TOKEN` / `GITHUB_TOKEN` set, and Claude Code web sessions where a token may be available.

```bash
# Try common token environment variables
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

if [ -z "$FETCH_METHOD" ] && [ -n "$TOKEN" ]; then
    TEMPLATE_DIR="${TEMPLATE_DIR:-$(mktemp -d)}"
    git clone --depth 1 --branch "$TEMPLATE_BRANCH" \
        "https://x-access-token:${TOKEN}@github.com/${TEMPLATE_REPO}.git" \
        "$TEMPLATE_DIR" 2>/dev/null
    if [ $? -eq 0 ]; then
        FETCH_METHOD="git clone (token)"
    fi
fi
```

#### Strategy 3: `git clone` with credential helper

Works on local machines with git credential manager, macOS Keychain, or `~/.netrc` configured.

```bash
if [ -z "$FETCH_METHOD" ]; then
    TEMPLATE_DIR="${TEMPLATE_DIR:-$(mktemp -d)}"
    git clone --depth 1 --branch "$TEMPLATE_BRANCH" \
        "https://github.com/${TEMPLATE_REPO}.git" \
        "$TEMPLATE_DIR" 2>/dev/null
    if [ $? -eq 0 ]; then
        FETCH_METHOD="git clone (credentials)"
    fi
fi
```

#### Strategy 4: GitHub API file-by-file via `curl` with token

Fallback for environments where `gh` isn't installed and `git clone` fails, but a token is available. Fetches only the files needed for comparison.

```bash
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

if [ -z "$FETCH_METHOD" ] && [ -n "$TOKEN" ]; then
    TEMPLATE_DIR="${TEMPLATE_DIR:-$(mktemp -d)}"
    API_BASE="https://api.github.com/repos/${TEMPLATE_REPO}/contents"

    # Fetch each config file individually
    FILES_TO_FETCH=(
        ".claude/settings.json"
        ".claude/hooks/lint-format.sh"
        ".claude/hooks/config-suggest.sh"
        "pyproject.toml"
        ".gitignore"
    )

    FETCH_OK=true
    for FILE in "${FILES_TO_FETCH[@]}"; do
        mkdir -p "$TEMPLATE_DIR/$(dirname "$FILE")"
        curl -sf -H "Authorization: Bearer $TOKEN" \
            -H "Accept: application/vnd.github.raw+json" \
            "${API_BASE}/${FILE}?ref=${TEMPLATE_BRANCH}" \
            -o "$TEMPLATE_DIR/$FILE" 2>/dev/null || true
    done

    # Fetch skill files (need to list directory first)
    SKILLS=$(curl -sf -H "Authorization: Bearer $TOKEN" \
        "${API_BASE}/.claude/skills?ref=${TEMPLATE_BRANCH}" 2>/dev/null \
        | grep -o '"name":"[^"]*"' | cut -d'"' -f4)

    for SKILL in $SKILLS; do
        mkdir -p "$TEMPLATE_DIR/.claude/skills/$SKILL"
        curl -sf -H "Authorization: Bearer $TOKEN" \
            -H "Accept: application/vnd.github.raw+json" \
            "${API_BASE}/.claude/skills/${SKILL}/SKILL.md?ref=${TEMPLATE_BRANCH}" \
            -o "$TEMPLATE_DIR/.claude/skills/$SKILL/SKILL.md" 2>/dev/null || true
    done

    # Verify we got at least settings.json
    if [ -f "$TEMPLATE_DIR/.claude/settings.json" ]; then
        FETCH_METHOD="curl (GitHub API)"
    fi
fi
```

#### If all strategies fail

Provide a clear error with instructions for the user's environment:

```
✗ Could not fetch template repository: ${TEMPLATE_REPO}

This is likely a private repository and no authentication is configured.

To fix, do ONE of the following:

  1. Authenticate the gh CLI (recommended):
     gh auth login

  2. Set a GitHub token in your environment:
     export GH_TOKEN=ghp_xxxxxxxxxxxx

  3. Configure git credentials:
     git config --global credential.helper store
     # then clone any repo from github.com to trigger login

  4. If using Claude Code on the web, add a GitHub integration
     in your Claude Code settings to enable repo access.

  5. Make the template repo public (not recommended for
     proprietary templates).
```

Stop execution here if the template cannot be fetched. Do NOT proceed with stale or missing data.

### 2. Compare Configuration Files

Compare these key files between local project and template:

| Local Path | Template Path | What to Compare |
|------------|---------------|-----------------|
| `.claude/settings.json` | `.claude/settings.json` | Permissions, hooks, deny rules |
| `.claude/hooks/*.sh` | `.claude/hooks/*.sh` | Hook scripts |
| `.claude/skills/*/SKILL.md` | `.claude/skills/*/SKILL.md` | Skill definitions |
| `pyproject.toml` | `pyproject.toml` | Tool configurations (ruff, pytest, mypy) |
| `.gitignore` | `.gitignore` | Ignored patterns |

### 3. Analyze Differences

For each configuration area, identify:

**Permissions (`settings.json`):**
- New `allow` rules in template (features you're missing)
- New `deny` rules in template (security improvements)
- Deprecated patterns you're still using

**Hooks:**
- New hooks in template
- Updated hook logic
- Missing hook scripts

**Skills:**
- New skills available
- Updated skill instructions
- Deprecated skill patterns

**Python Tooling (`pyproject.toml`):**
- New ruff rules enabled
- Updated tool versions
- New pytest/mypy configurations

### 4. Generate Report

Output a structured comparison report:

```
═══════════════════════════════════════════════════
       CONFIGURATION SYNC REPORT
═══════════════════════════════════════════════════

Template: [repo] @ [branch]
Fetch method: [strategy used]
Template version: [commit hash or date]
Local config last modified: [date]

───────────────────────────────────────────────────
PERMISSIONS (.claude/settings.json)
───────────────────────────────────────────────────

✓ Up to date: 15 allow rules match
⚠ Missing (3 new in template):
  + Bash(uv *)           - UV package manager support
  + WebFetch(domain:mypy.readthedocs.io)
  + Bash(git switch *)

⚠ Consider adding (security):
  + deny: Read(**/*_key*)
  + deny: Bash(curl * | *)

───────────────────────────────────────────────────
HOOKS (.claude/hooks/)
───────────────────────────────────────────────────

✓ lint-format.sh: Up to date
⚠ New hook available:
  + config-suggest.sh - Suggests /sync-config after config edits

───────────────────────────────────────────────────
SKILLS (.claude/skills/)
───────────────────────────────────────────────────

✓ Present: review, lint, test, check
⚠ New skills available:
  + init-from-template - Create projects from template
  + sync-config - This skill (meta!)

⚠ Updated skills:
  ~ review/SKILL.md - New review focus areas added

───────────────────────────────────────────────────
PYTHON TOOLING (pyproject.toml)
───────────────────────────────────────────────────

✓ ruff: Configuration matches
⚠ New ruff rules in template:
  + "PTH"  - flake8-use-pathlib
  + "ERA"  - eradicate (commented code)
  + "RUF"  - Ruff-specific rules

───────────────────────────────────────────────────
SUMMARY
───────────────────────────────────────────────────

Total differences: X
  - Permissions: Y new, Z security improvements
  - Hooks: A new
  - Skills: B new, C updated
  - Tooling: D new rules

Recommendation: [UP TO DATE / MINOR UPDATES / SIGNIFICANT UPDATES]
```

### 5. Suggest Specific Updates

For each difference, provide actionable suggestions:

```
Would you like me to apply any of these updates?

[1] Add new permission rules (low risk)
[2] Add new deny rules (security improvement)
[3] Update hooks (review changes first)
[4] Add new skills (copy from template)
[5] Update pyproject.toml ruff rules (may require fixes)

Say "apply [N]" or "apply all" to make changes.
Say "show [N]" to see the full diff for that section.
```

### 6. Cleanup

```bash
rm -rf "$TEMPLATE_DIR"
```

## Output Modes

**Default**: Summary with counts and key differences
**--detailed**: Full file diffs for each section

## Notes

- This skill is read-only by default; it only suggests changes
- User must explicitly request changes to be applied
- Always fetch fresh template to ensure comparison is current
- Preserve any custom configurations that aren't in template
- For private repos, at least one auth method must be available (see Strategy 1-4)
- The `template.json` config lets teams point at their own fork or branch
- **Worktree safe:** Template is cloned into a temp directory (`mktemp -d`), not into the project tree, so it never interferes with worktree or main repo state
