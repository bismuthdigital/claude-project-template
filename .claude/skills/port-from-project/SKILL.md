---
name: port-from-project
version: 1.0.0
description: >
  Port skills, scripts, hooks, and configuration from a downstream project back
  into this template. Compares the source project against the template, identifies
  new or updated components, helps generalize project-specific references, and
  applies the changes. The reverse of /sync-config.
argument-hint: "<project-path-or-name> [--skill <name>] [--script <name>] [--hook <name>] [--dry-run]"
allowed-tools: Read, Glob, Grep, Write, Edit, Bash(git *), Bash(diff *), Bash(ls *), Bash(cat *), Bash(basename *), Bash(dirname *), Bash(wc *), Bash(mktemp *), Bash(rm -rf *), Bash(cp *), AskUserQuestion
---

# Port from Downstream Project

Import skills, scripts, hooks, and configuration from a downstream project back into this template. This is the upstream counterpart to `/sync-config` — where `/sync-config` pushes template changes *down* to projects, `/port-from-project` pulls innovations *up* from projects into the template.

```
Downstream project ──(/port-from-project)──▶ Template ──(/sync-config)──▶ All projects
```

## Why This Exists

Innovation happens at the edges. Downstream projects develop new skills, improve existing ones, and add scripts to solve real problems. Without a standardized way to port those back, the template falls behind and each project re-invents solutions independently.

This skill makes the upstream flow as consistent as the downstream flow.

## Arguments

| Argument | Effect |
|----------|--------|
| `<path>` | Absolute or relative path to the source project (e.g., `~/code/claude/trans-disco`) |
| `<name>` | Project name — resolved via `$CLAUDE_PROJECTS_DIR/<name>` (default: `~/code/claude/<name>`) |
| `--skill <name>` | Port only the named skill (can be repeated) |
| `--script <name>` | Port only the named script from `scripts/` or `bin/` |
| `--hook <name>` | Port only the named hook from `.claude/hooks/` |
| `--dry-run` | Show what would change without writing files |
| (no filter) | Scan everything and present a menu of portable items |

## Process

### Step 1: Resolve Source Project

```bash
# If argument looks like a path
if [[ "$1" == /* ]] || [[ "$1" == ~* ]] || [[ "$1" == .* ]]; then
    SOURCE_DIR="$1"
else
    # Resolve by name
    PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/code/claude}"
    SOURCE_DIR="$PROJECTS_DIR/$1"
fi
```

Verify the source exists and has a `.claude/` directory:

```bash
ls "$SOURCE_DIR/.claude/settings.json"
```

If not found, report the error and stop.

### Step 2: Discover Portable Components

Scan the source project for components that differ from or don't exist in the template.

#### Skills

```bash
# List source skills
ls "$SOURCE_DIR/.claude/skills/"

# List template skills
ls .claude/skills/
```

For each skill in the source, classify it:

| Classification | Condition | Action |
|---------------|-----------|--------|
| **NEW** | Skill directory doesn't exist in template | Candidate for porting |
| **UPDATED** | Skill exists in both; source version > template version | Candidate for update |
| **SAME** | Skill exists in both; versions match | Skip |
| **LOCAL_NEWER** | Skill exists in both; template version > source version | Skip (template is ahead) |
| **PROJECT_SPECIFIC** | Skill references project-specific domains, data, or concepts | Flag for review |

To detect project-specific skills, check for these signals in the SKILL.md:
- References to project-specific CLI commands (e.g., `td`, `ig`)
- Domain-specific terminology not found in the template
- References to project-specific directories (e.g., `data/`, `content/`)
- Hardcoded project names or URLs

#### Scripts (`scripts/` and `bin/`)

```bash
# Compare script directories
diff <(ls "$SOURCE_DIR/scripts/" 2>/dev/null) <(ls scripts/ 2>/dev/null)
diff <(ls "$SOURCE_DIR/bin/" 2>/dev/null) <(ls bin/ 2>/dev/null)
```

For each new or differing script, check if it's generalizable or project-specific.

#### Hooks (`.claude/hooks/`)

```bash
diff <(ls "$SOURCE_DIR/.claude/hooks/" 2>/dev/null) <(ls .claude/hooks/ 2>/dev/null)
```

#### Configuration (`.claude/settings.json`)

Check for new permissions, deny rules, or hook configurations in the source that aren't in the template.

#### Plans Directory Structure

Check if the source has `.claude/plans/` with structural elements (like INDEX.md) that the template should include.

### Step 3: Present Discovery Report

```
===============================================
       PORT FROM PROJECT: <project-name>
===============================================

Source: <source-path>

-----------------------------------------------
SKILLS
-----------------------------------------------
  NEW (portable):
    + cleanup v1.0.0 — Pre-exit safety check for worktrees
    + capture v1.0.0 — Knowledge shipping lane

  UPDATED:
    ~ review v1.1.0 — Source has newer version (template: v1.0.0)

  PROJECT-SPECIFIC (needs generalization):
    ? counsel v1.0.0 — References domain-specific advisory modes
    ? seed-review v1.0.0 — References project-specific data catalog

  SKIPPED (template is same or newer):
    = lint v1.0.0
    = test v1.0.0

-----------------------------------------------
SCRIPTS
-----------------------------------------------
  NEW:
    + scripts/new-utility.sh
  UPDATED:
    ~ scripts/sync-main.sh — Source differs from template
  SAME:
    = bin/test

-----------------------------------------------
HOOKS
-----------------------------------------------
  (no differences)

-----------------------------------------------
CONFIGURATION
-----------------------------------------------
  New permissions in source:
    + Bash(custom-tool *)

===============================================
```

### Step 4: Generalization Check

For each item to be ported, scan for project-specific references that need generalization:

**Common patterns to generalize:**

| Project-specific | Generalized |
|-----------------|-------------|
| `td` (CLI command) | Remove or make generic |
| Project-specific paths (`data/voices/`, `content/articles/`) | Remove or use generic examples |
| Domain-specific terminology | Replace with generic equivalents |
| Hardcoded repo names/URLs | Use variables or remove |
| Project-specific skill references (`/counsel`, `/seed-review`) | Remove or note as optional |

For each item needing generalization, show the specific lines that need attention:

```
File: .claude/skills/capture/SKILL.md
  Line 74: References /counsel (project-specific skill)
    → Remove or replace with generic example
  Line 76: References docs/outreach/ (project-specific directory)
    → Remove this artifact type row
```

### Step 5: Apply Changes

For each approved item:

1. **New skills**: Copy the SKILL.md, applying generalizations
2. **Updated skills**: Show a diff, then apply (preserving template-specific customizations)
3. **New scripts**: Copy the script file
4. **Updated scripts**: Show a diff, then apply
5. **New hooks**: Copy and register in settings.json
6. **Configuration**: Merge new permissions/deny rules

After applying, verify no project-specific references leaked through:

```bash
# Scan ported files for common project-specific patterns
# (customize this list based on the source project)
grep -rn "project-specific-term" .claude/skills/<ported-skill>/
```

### Step 6: Update Template Documentation

After porting, update these files to reflect new capabilities:

1. **CLAUDE.md** — Add new skills to the skills table, update skill count in overview
2. **Architecture section** — Add new directories if created (e.g., `.claude/plans/`)
3. **QUICKSTART.md** — Update skill count if it exists

### Step 7: Summary Report

```
===============================================
          PORT COMPLETE
===============================================

  Source: <project-name> (<path>)

  Ported:
    + skill: cleanup v1.0.0 (new)
    + skill: capture v1.0.0 (new)
    ~ script: sync-main.sh (updated)

  Generalizations applied:
    - Removed /counsel reference from capture skill
    - Replaced project-specific paths with generic examples

  Skipped:
    ? counsel — project-specific (domain advisory)
    = lint — already up to date

  Files modified:
    .claude/skills/cleanup/SKILL.md (new)
    .claude/skills/capture/SKILL.md (new)
    scripts/sync-main.sh (updated)
    CLAUDE.md (skills table updated)

  Next steps:
    1. Review ported files for any remaining project-specific references
    2. Run /ship to commit and merge
    3. Run sync-all-projects.sh to push to downstream projects

===============================================
```

## Dry Run Mode

When `--dry-run` is passed:
- Run Steps 1-4 (discover and analyze)
- Show what would be changed in Step 5
- Do NOT write any files
- Report ends with "Dry run — no files modified"

## Filtering

When `--skill`, `--script`, or `--hook` filters are provided:
- Only discover and process the named components
- Skip the full scan (faster for targeted ports)
- Still run generalization checks on filtered items

## Safety Rules

1. **Never overwrite template customizations blindly.** If a skill exists in both, show a diff and ask before replacing.
2. **Always check for project-specific references.** A skill that works in trans-disco may reference `/counsel` or `data/voices/` — these must be removed or generalized.
3. **Preserve version ordering.** If the template has v1.1.0 and the source has v1.0.0, don't downgrade.
4. **Don't port domain-specific skills.** Skills like `/counsel`, `/seed-review`, `/examine-bias` solve project-specific problems. Only port skills that are genuinely reusable across projects.
5. **Update docs after porting.** New skills must appear in CLAUDE.md's skills table and the overview skill count.

## Integration with Other Skills

| Skill | Integration |
|-------|-------------|
| `/sync-config` | Reverse direction — pushes template changes down to projects |
| `/ship` | Ship the ported changes after review |
| `/review` | Review ported code for quality before committing |
| `/code-health` | Check ported code for anti-patterns |
