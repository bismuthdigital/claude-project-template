---
name: bash-review
version: 1.0.0
description: >
  Reviews bash scripts for common pitfalls, security issues, and best practices.
  Uses shellcheck when available, with manual analysis fallback.
argument-hint: "[files or 'recent']"
allowed-tools: Read, Glob, Grep, Bash(shellcheck *), Bash(git diff *), Bash(git log *), Bash(command -v *), Bash(head *), Bash(find *)
---

# Bash Script Review Instructions

You are a senior shell script reviewer. Your goal is to find issues and report them clearly - do NOT auto-fix anything.

## Review Focus Areas

### 1. Security Issues (CRITICAL)

- **Command injection**: Unquoted variables in commands
  - Bad: `rm $user_file`
  - Good: `rm "$user_file"`
- **Unsafe eval**: `eval` with external data
- **Pipe to shell**: `curl ... | sh` patterns without verification
- **Path traversal**: User input in file paths without validation
- **Temporary file race conditions**: Predictable temp file names (use `mktemp`)

### 2. Error Handling (WARNING)

- **Missing `set -e`**: Script continues after errors
- **Missing `set -u`**: Undefined variables go unnoticed
- **Missing `set -o pipefail`**: Pipeline errors hidden
- **Unchecked commands**: Commands that can fail silently
- **Missing trap**: No cleanup on exit/error

### 3. Quoting Issues (WARNING)

- **Unquoted variables**: Word splitting and globbing bugs
  - Bad: `if [ $var = "value" ]`
  - Good: `if [ "$var" = "value" ]`
- **Unquoted command substitution**: `$(cmd)` should be `"$(cmd)"`
- **Array expansion**: `${array[@]}` should be `"${array[@]}"`

### 4. Portability Concerns (PORTABILITY)

- **Bashisms in sh scripts**: Arrays, `[[`, `(())` in `#!/bin/sh`
- **GNU vs BSD differences**:
  - `sed -i` (needs `''` on macOS)
  - `readlink -f` (not available on macOS)
  - `echo -e` (use `printf` instead)
- **Command availability**: Assuming `jq`, `curl`, etc. exist without checking

### 5. Best Practices (SUGGESTION)

- **Shebang**: Should be `#!/bin/bash` or `#!/usr/bin/env bash`
- **Local variables**: Functions should use `local`
- **Function style**: Prefer `name() {}` over `function name {}`
- **Exit codes**: Use meaningful exit codes
- **Logging**: Color output should check terminal capability

## Process

1. **Identify files to review**:
   - If argument is "recent": run `git diff --name-only HEAD~1 | grep '\.sh$'`
   - If specific files given: use those
   - If empty: find all `.sh` files with `find . -name "*.sh" -type f`

2. **Check for shellcheck**:
   ```bash
   if command -v shellcheck &> /dev/null; then
       shellcheck --format=gcc "$file"
   fi
   ```
   Use shellcheck results to identify issues. If shellcheck is not available, proceed with manual analysis only.

3. **Manual analysis** for each file:
   - Read file content
   - Check shebang line
   - Look for `set -e`, `set -u`, `set -o pipefail`
   - Search for unquoted variable patterns
   - Check for security-sensitive patterns
   - Identify portability concerns

4. **Report findings** using the format below

## Output Format

```
/bash-review v1.0.0
═══════════════════════════════════════════════════
         BASH SCRIPT REVIEW
═══════════════════════════════════════════════════

Shellcheck: [Available - using for analysis / Not installed - manual review only]

### Review: [filename]

**[1] CRITICAL** | `line N`
- **Issue**: Clear description of the security/critical bug
- **Code**: `the problematic code`
- **Impact**: What could go wrong if not fixed
- **Fix**: Conceptual description of the solution

**[2] WARNING** | `line N`
- **Issue**: Description of the problem
- **Code**: `the problematic code`
- **Impact**: What could go wrong
- **Fix**: Conceptual solution

**[3] PORTABILITY** | `line N`
- **Issue**: Portability concern description
- **Code**: `the code in question`
- **Impact**: Which platforms affected
- **Fix**: How to make it portable

**[4] SUGGESTION** | `line N`
- **Issue**: Best practice recommendation
- **Code**: `current code`
- **Improvement**: What would be better

---

### Summary

| Severity | Count |
|----------|-------|
| Critical | X |
| Warning | Y |
| Portability | Z |
| Suggestion | W |

**Files reviewed**: list of files
**Shellcheck**: Available/Not installed
**Recommendation**: APPROVE / NEEDS CHANGES
```

---

After presenting findings, tell the user:
"Say **fix [N]** to implement a specific fix, or **fix all** to address everything."

## Pattern Reference

### Common Issues to Search For

```bash
# Unquoted variables (WARNING)
# Look for $VAR not inside quotes

# Missing set -e (WARNING)
# Check first 10 lines for 'set -e' or 'set -euo pipefail'

# Eval usage (CRITICAL)
# grep for '\beval\b'

# Pipe to shell (CRITICAL)
# grep for 'curl.*|.*sh' or 'wget.*|.*sh'

# Test with == instead of = (WARNING - bashism in [ ])
# grep for '\[\s+.*==.*\]'
```

## Examples

```
/bash-review                    # Review all .sh files
/bash-review recent             # Review recently changed scripts
/bash-review install.sh         # Review specific file
/bash-review .claude/hooks/     # Review scripts in directory
```
