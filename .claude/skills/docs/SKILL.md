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

## Process

### Phase 1: Scan

```bash
# Find documentation files
find . -maxdepth 2 -name "*.md" -type f

# Find Python files with public APIs
find src -name "*.py" -type f

# Get current version
grep -E "^version\s*=" pyproject.toml
```

### Phase 2: Analyze

For each documentation file:
1. Extract code blocks and command examples
2. Verify referenced paths exist
3. Check version references match pyproject.toml
4. Compare feature lists against actual code

For each Python file:
1. Find public functions (not prefixed with `_`)
2. Check for docstrings
3. Find complex code blocks (>10 lines, nested logic)
4. Check for explanatory comments

### Phase 3: Report (check mode)

Output findings in structured format showing:
- Documentation gaps
- Inconsistencies found
- Stale or outdated content
- Missing "why" explanations

### Phase 4: Update (update mode)

For each issue found:
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
✗ No CONTRIBUTING.md found (optional)

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
> "Say **update** to fix these issues, or **fix [N]** to address a specific item."

In **update** mode:
> Show each proposed change and ask for confirmation before applying.

## Examples

```
/docs                    # Check all documentation (default)
/docs check              # Explicitly check without changes
/docs update             # Fix identified issues
/docs check src/         # Check only src/ directory
/docs update README.md   # Update only README.md
```
