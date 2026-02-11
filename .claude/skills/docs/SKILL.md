---
name: docs
description: >
  Reviews documentation and comments for consistency and correctness.
  Checks README, CLAUDE.md, docstrings, and code comments.
  Ensures comments explain "why" implementation choices were made.
argument-hint: "[check|update] [path]"
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(git diff *)
---

# Documentation Review

Review and update documentation across the project to ensure consistency, correctness, and completeness.

## Modes

- **check** (default): Analyze and report issues without making changes
- **update**: Fix identified issues and update documentation

## Review Focus Areas

### 1. Documentation Files

Check these common documentation files:

| File | What to Verify |
|------|----------------|
| `README.md` | Installation steps work, features list matches code, examples are correct |
| `CLAUDE.md` | Project context is accurate, commands work, architecture matches reality |
| `QUICKSTART.md` | **REQUIRED** - Entry points are accurate, commands work, paths exist, output is terminal-friendly |
| `USAGE.md` | If present, usage examples are correct |
| `CONTRIBUTING.md` | If present, contribution guidelines are current |
| `CHANGELOG.md` | If present, recent changes are documented |

### 2. Code Comments - The "Why" Not "What"

Comments should explain **why** implementation choices were made, not just describe what the code does.

**Bad comment** (describes what):
```python
# Loop through items
for item in items:
```

**Good comment** (explains why):
```python
# Process items in order to maintain dependency resolution
# Later items may depend on results from earlier ones
for item in items:
```

Look for:
- Complex algorithms without explanation of approach chosen
- Non-obvious business logic without context
- Workarounds without explanation of the problem being solved
- Performance optimizations without rationale

### 3. Docstrings

Check public functions and classes for:
- Missing docstrings entirely
- Docstrings that don't match current signature
- Missing parameter descriptions
- Missing return value descriptions
- Missing exception documentation

### 4. Consistency Checks

Verify documentation matches reality:
- Command examples actually execute successfully
- File paths referenced in docs exist
- Version numbers match `pyproject.toml`
- Skill descriptions match their actual behavior
- Installation instructions produce working setup

### 5. QUICKSTART.md

QUICKSTART.md is a terminal-friendly orientation file. It is designed for humans who `cat QUICKSTART.md` to quickly understand where to start in a project. It is NOT a replacement for README.md — it is a minimal, scannable quick-reference.

**What it should contain:**
- Project purpose in 1-2 sentences
- How to install/set up (exact commands, copy-pasteable)
- Key entry points: where the main code lives, where to start reading
- Most common commands (build, test, run)
- Important file locations (config files, main modules, test directory)

**Format constraints (terminal-optimized):**
- No HTML tags, collapsible sections, or images
- No tables wider than 80 characters
- No deeply nested lists (2 levels maximum)
- Minimal use of bold/italic — prefer plain text and code blocks
- Short lines: aim for under 80 characters
- Total length: ideally under 60 lines so it fits in a single terminal screen
- Section headers should use `##` for clear visual separation when displayed raw

**Bad QUICKSTART.md** (too verbose, not scannable):
```
This project is a comprehensive framework for building distributed
microservices with event-driven architectures. It supports multiple
deployment targets including Kubernetes, Docker Swarm, and bare metal...

## Table of Contents
1. [Introduction](#introduction)
2. [Philosophy](#philosophy)
...
```

**Good QUICKSTART.md** (concise, actionable):
```
## What

Brief project description in one line.

## Setup

python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"

## Key Paths

src/package_name/       Main source code
src/package_name/cli.py CLI entry point
tests/                  Test suite
pyproject.toml          Project config

## Common Commands

pytest                  Run tests
ruff check --fix .      Lint
ruff format .           Format
```

**What to verify:**
- Commands listed in QUICKSTART.md actually work
- File paths referenced actually exist in the repository
- Setup instructions are consistent with README.md and CLAUDE.md
- Content is not stale (no references to removed files or old package names)
- Format stays within terminal-friendly constraints (no wide tables, no HTML)
- Length is reasonable (flag if over 80 lines)

## Process

### Phase 1: Scan

```bash
# Find documentation files
find . -maxdepth 2 -name "*.md" -type f

# Check for QUICKSTART.md specifically (REQUIRED - terminal-friendly orientation file)
test -f QUICKSTART.md && echo "QUICKSTART.md found" || echo "QUICKSTART.md MISSING (required)"

# Find Python files with public APIs
find src -name "*.py" -type f

# Get current version
grep -E "^version\s*=" pyproject.toml
```

**IMPORTANT**: If QUICKSTART.md is missing, this is a critical issue that should be flagged immediately and offered to be created.

### Phase 2: Smart Batching

Based on the number of files found:

- **>30 Python files**: Use Task tool with parallel general-purpose agents
  - Split Python files into batches of 15-20
  - Each agent checks: docstrings, comment quality, complexity
  - Documentation files always checked in main context (usually <10 files)
  - Run agents in parallel for faster analysis

- **15-30 Python files**: Sequential analysis with progress updates

- **<15 files**: Normal analysis in current context

### Phase 3: Analyze

**First priority - Check for QUICKSTART.md:**
- If QUICKSTART.md is missing, this is a critical issue
- In **check** mode: Flag as error and offer to create it
- In **update** mode: Automatically offer to create a default version

For each documentation file:
1. Extract code blocks and command examples
2. Verify referenced paths exist
3. Check version references match pyproject.toml
4. Compare feature lists against actual code

For each Python file (or batch):
1. Find public functions (not prefixed with `_`)
2. Check for docstrings
3. Find complex code blocks (>10 lines, nested logic)
4. Check for explanatory comments

### Phase 4: Report (check mode)

Output findings in structured format showing:
- Documentation gaps
- Inconsistencies found
- Stale or outdated content
- Missing "why" explanations
- If batched: Note performance improvement from parallel processing

### Phase 5: Update (update mode)

**Special handling for missing QUICKSTART.md:**
1. Generate a default QUICKSTART.md by:
   - Reading pyproject.toml for project name and description
   - Reading README.md for installation steps
   - Finding main entry points in src/
   - Extracting common commands from README or CLAUDE.md
   - Identifying key file paths (config, tests, main modules)
2. Present the generated content to the user
3. Ask for confirmation before creating the file
4. Create QUICKSTART.md with the approved content

For each other issue found:
1. Show the problem
2. Propose a fix
3. Ask for confirmation before applying
4. Apply approved changes

## Output Format

```
═══════════════════════════════════════════════════
         DOCUMENTATION REVIEW
═══════════════════════════════════════════════════

DOCUMENTATION FILES
───────────────────────────────────────────────────
✓ README.md - Complete and accurate
⚠ CLAUDE.md:15 - References outdated directory structure
✓ QUICKSTART.md - Concise, commands verified, paths valid
✗ No CONTRIBUTING.md found (optional)

[If QUICKSTART.md is missing, show:]
✗ QUICKSTART.md - MISSING (REQUIRED)
  → This file is required for terminal-friendly quick reference
  → Offer to create a default QUICKSTART.md based on project structure

CODE COMMENTS
───────────────────────────────────────────────────
✓ install.sh - Well documented with clear explanations
⚠ src/module.py:42-58 - Complex logic without "why" explanation
⚠ .claude/hooks/lint-format.sh:25 - Workaround needs context

DOCSTRINGS
───────────────────────────────────────────────────
✓ src/your_package/__init__.py - Has module docstring
⚠ src/utils.py:15 - Function `process_data` missing docstring

CONSISTENCY
───────────────────────────────────────────────────
✓ Version 0.1.0 matches across files
✗ README.md:45 - Command `pip install foo` fails (package is `bar`)
⚠ CLAUDE.md:28 - Path src/old_module/ doesn't exist

───────────────────────────────────────────────────
SUMMARY
───────────────────────────────────────────────────
Documentation files: 2 checked, 1 warning
Code comments: 3 checked, 2 need "why" explanations
Docstrings: 2 checked, 1 missing
Consistency: 3 checked, 1 error, 1 warning

Overall: NEEDS ATTENTION (1 error, 4 warnings)
───────────────────────────────────────────────────
```

## After Review

In **check** mode:
> If QUICKSTART.md is missing: "Say **create quickstart** to generate QUICKSTART.md, or **update** to fix all issues."
> Otherwise: "Say **update** to fix these issues, or **fix [N]** to address a specific item."

In **update** mode:
> If QUICKSTART.md is missing: Proactively offer to create it first before addressing other issues.
> Show each proposed change and ask for confirmation before applying.

## Examples

```
/docs                    # Check all documentation (default)
/docs check              # Explicitly check without changes
/docs update             # Fix identified issues
/docs check src/         # Check only src/ directory
/docs update README.md   # Update only README.md
```
