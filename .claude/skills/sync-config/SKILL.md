---
name: sync-config
description: >
  Compare this project's Claude configuration against the official template.
  Identifies missing features, outdated patterns, and suggests specific updates.
argument-hint: "[--detailed]"
allowed-tools: Read, Glob, Grep, Bash(git *), Bash(curl *), Bash(mktemp *), Bash(rm -rf *)
---

# Sync Configuration with Template

Compare the current project's Claude Code configuration against the latest official template and suggest updates.

## Arguments

- `--detailed`: Show full diffs instead of summaries

## Process

### 1. Fetch Latest Template

Fetch the current template from GitHub for comparison:

```bash
TEMPLATE_DIR=$(mktemp -d)
git clone --depth 1 https://github.com/janewilkin/claude-project-template.git "$TEMPLATE_DIR" 2>/dev/null
```

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
