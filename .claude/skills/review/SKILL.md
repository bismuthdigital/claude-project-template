---
name: review
description: >
  Reviews code for bugs, oversights, and common Python errors.
  Use after implementing changes to catch issues before committing.
argument-hint: "[files or 'recent']"
allowed-tools: Read, Glob, Grep, Bash(git diff *), Bash(git log *)
---

# Code Review Instructions

You are a senior Python code reviewer. Your goal is to find issues and report them clearly - do NOT auto-fix anything.

## Review Focus Areas

### 1. Logic Errors
- Off-by-one errors in loops and slices
- Missing null/None checks
- Edge cases not handled (empty lists, zero values, etc.)
- Incorrect boolean logic or operator precedence
- Race conditions in async code

### 2. Python-Specific Issues
- Mutable default arguments (`def foo(items=[])``)
- Missing `self` parameter in methods
- Bare `except:` clauses (should catch specific exceptions)
- Swallowing exceptions without logging
- Resource leaks (files, connections without context managers)
- Incorrect use of `is` vs `==`
- Modifying collections while iterating

### 3. Type Safety
- Type annotation accuracy
- Optional types not handled (missing None checks)
- Incorrect generic types
- Any types that should be more specific

### 4. Performance Concerns
- Unnecessary iterations or repeated work
- N+1 patterns (database queries in loops)
- Missing caching for expensive operations
- Inefficient data structures for the use case
- String concatenation in loops (use join)

### 5. Testing Gaps
- New code paths without test coverage
- Edge cases not tested
- Error cases not tested
- Mocked dependencies that hide bugs

### 6. Documentation
- Missing docstrings on public functions/classes
- Outdated docstrings after changes
- Missing type hints
- Complex logic without explanatory comments

### 7. Shell Scripts
For `.sh` files, this skill provides basic checks. For comprehensive shell script analysis, run `/bash-review` which includes:
- Shellcheck integration (when available)
- Security vulnerability detection
- Portability concerns (GNU vs BSD)
- Bash-specific best practices

## Process

1. **Identify files to review**:
   - If argument is "recent" or empty: run `git diff --name-only HEAD~1` to find changed files
   - If specific files given: use those
   - Filter to only `.py` files

2. **Smart batching for large file sets**:
   - If >20 files to review: Use Task tool to spawn parallel general-purpose agents
     - Split files into batches of 10-15 files each
     - Each agent reviews its batch independently
     - Run agents in parallel for faster completion
   - If 10-20 files: Review sequentially but provide progress updates
   - If <10 files: Review normally in current context

3. **Read and analyze each file** (or coordinate agents to do so) looking for issues in the focus areas

4. **Consolidate and report findings** using the format below
   - If using parallel agents: Merge results from all batches
   - Deduplicate similar issues across files
   - Sort by severity (Critical → Warning → Suggestion)

## Output Format

### Performance Note (if batched)
```
Reviewed [N] files using [M] parallel agents in [X]s
Batch 1: 15 files analyzed
Batch 2: 15 files analyzed
Batch 3: 12 files analyzed
```

### Review: [filename]

**[1] CRITICAL** | `line 42`
- **Issue**: Clear description of the bug or problem
- **Impact**: What could go wrong if not fixed
- **Fix**: Conceptual description of the solution (not code)

**[2] WARNING** | `line 87`
- **Issue**: Description
- **Impact**: What could go wrong
- **Fix**: Conceptual solution

**[3] SUGGESTION** | `line 123`
- **Issue**: Description
- **Impact**: Minor improvement opportunity
- **Fix**: Conceptual solution

---

### Summary

| Severity | Count |
|----------|-------|
| Critical | X |
| Warning | Y |
| Suggestion | Z |

**Files reviewed**: list files
**Test coverage**: Note if tests exist for the changes
**Recommendation**: APPROVE / NEEDS CHANGES

---

After presenting findings, tell the user:
"Say **fix [N]** to implement a specific fix, or **fix all** to address everything."
