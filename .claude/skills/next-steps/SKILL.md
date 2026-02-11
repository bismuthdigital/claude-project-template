---
name: next-steps
description: >
  Reviews the NEXT_STEPS.md file (or generates one), reconciles with recent
  commit history, and suggests the best next step to implement this session.
argument-hint: "[path to next-steps file or empty]"
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(git log *), Bash(git diff *), Bash(git status *), Bash(ls *)
---

# Next Steps Planner

Review the project's next-steps roadmap, reconcile it with recent work, and suggest the most impactful thing to build next.

## Overview

This skill acts as a session-start planner. It:
1. Finds and reads the next-steps file (default: `NEXT_STEPS.md`)
2. Cross-references with recent commits and code state
3. Updates the file if items are stale or completed
4. Suggests one concrete next step for the current session
5. If no roadmap exists, generates one by analyzing the repo

## Process

### Step 1: Locate the Next-Steps File

Look for a next-steps file in this order:
1. Path provided as argument
2. `NEXT_STEPS.md` in project root
3. `next-steps.md` in project root
4. `TODO.md` in project root

```bash
ls -la NEXT_STEPS.md next-steps.md TODO.md 2>/dev/null
```

### Step 2A: If NO Next-Steps File Exists

Analyze the repository to understand the project and generate a roadmap:

1. **Understand the project**:
   - Read `README.md`, `CLAUDE.md`, and `pyproject.toml` for project context
   - Scan `src/` for main code structure and completeness
   - Check `tests/` for test coverage gaps
   - Review open issues if `gh` is available: `gh issue list --limit 10`
   - Look at recent commit messages for momentum and direction

2. **Identify potential next steps** across these categories:
   - **Features**: Missing functionality based on project description vs actual code
   - **Quality**: Test coverage gaps, missing error handling, type hints
   - **Documentation**: Missing or outdated docs
   - **Infrastructure**: CI/CD, tooling, packaging improvements
   - **Tech debt**: TODOs in code, known workarounds, outdated patterns

3. **Generate `NEXT_STEPS.md`** with the following format:

```markdown
# Next Steps

> Last reviewed: YYYY-MM-DD

## Priority

- [ ] **Step title** — Brief description of what and why
  - Key files: `path/to/relevant/file.py`
  - Estimated scope: Small / Medium / Large

## Backlog

- [ ] **Step title** — Brief description
- [ ] **Step title** — Brief description

## Completed

(Items move here when done)
```

Present the generated file to the user and ask for confirmation before writing it.

### Step 2B: If Next-Steps File EXISTS

1. **Read the file** and parse all items (both checked and unchecked)

2. **Review recent history** to find completed work:
   ```bash
   git log --oneline -20
   ```

3. **Cross-reference** each unchecked item against recent commits:
   - Look for commit messages that relate to each item
   - Check if files referenced by items have been significantly modified
   - Read any referenced files to verify current state

4. **Identify stale items**:
   - Items that were completed but not checked off
   - Items that reference files/features that no longer exist
   - Items that are blocked by unmet prerequisites
   - Items whose priority has changed based on recent work

5. **Update the file**:
   - Mark completed items as done (`[x]`) and move to Completed section
   - Add date annotations for completed items
   - Remove items that are no longer relevant (note the removal)
   - Flag blocked items with a note explaining the blocker
   - Present all changes to the user before writing

### Step 3: Suggest a Next Step

From the current (possibly updated) list, recommend **one** item to work on this session.

Selection criteria (in priority order):
1. **Unblocked** — No dependencies on other incomplete items
2. **High impact** — Moves the project forward meaningfully
3. **Right-sized** — Can make substantial progress in one session
4. **Momentum** — Builds on recent work when possible

Present the suggestion as:

```
═══════════════════════════════════════════════════
            NEXT STEPS
═══════════════════════════════════════════════════

STATUS
───────────────────────────────────────────────────
Total items:     N
Completed:       N (updated M items this review)
Remaining:       N
Blocked:         N

UPDATES APPLIED
───────────────────────────────────────────────────
✓ Marked complete: "<item>" (done in commit abc1234)
✓ Marked complete: "<item>" (files updated since last review)
⚠ Removed stale: "<item>" (feature no longer planned)
⚠ Blocked: "<item>" (needs X first)

SUGGESTED NEXT STEP
───────────────────────────────────────────────────
→ <Item title>

  <Why this is the best next step: 2-3 sentences
   explaining impact, feasibility, and how it
   connects to recent work.>

  Key files to modify:
  - path/to/file.py
  - path/to/other.py

  Approach:
  1. First, ...
  2. Then, ...
  3. Finally, ...

═══════════════════════════════════════════════════
```

### Step 4: If No Good Next Steps

If the remaining items are all blocked, too large, or unclear:

1. Summarize the current state of the project
2. Ask the user targeted questions to generate new next steps:
   - "What problem are you trying to solve with this project?"
   - "Are there any features you've been thinking about adding?"
   - "What's the most annoying thing about the current codebase?"
   - "Who will use this and what do they need most?"
3. Based on answers, generate 3-5 concrete next steps
4. Ask the user to pick priorities
5. Update `NEXT_STEPS.md` with the new items

## Output Format

Use the structured format shown in Step 3 above. Key principles:
- Always show the status summary first
- Show any updates that were applied
- Make the suggestion actionable with specific files and approach
- Keep the approach steps concrete enough to start immediately

## Error Handling

| Scenario | Resolution |
|----------|------------|
| No git history | Skip commit cross-referencing, analyze code directly |
| Referenced files don't exist | Flag as stale, suggest removal |
| Very large next-steps file | Focus on Priority section, summarize Backlog |
| No `src/` directory | Adapt scanning to project's actual structure |
| Empty repository | Focus on project setup and initial structure |

## Notes

- The next-steps file is a living document — it's expected to be out of date
- This skill prefers updating over replacing content
- When generating new items, be specific and actionable, not vague
- Each item should be completable in 1-3 sessions
- The skill respects existing categorization and formatting in the file
