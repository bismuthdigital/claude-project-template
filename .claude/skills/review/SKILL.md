---
name: review
description: >
  Project-specific review lens that complements the built-in /code-review.
  Adds resiliency/recovery and virtual-environment-hygiene checks that the
  built-in review does not cover. Run after /code-review on changed code.
argument-hint: "[files or 'recent']"
allowed-tools: Read, Glob, Grep, Bash(git diff *), Bash(git log *)
---

# Project Review Lens

Claude Code ships a built-in **`/code-review`** that finds correctness bugs plus
reuse / simplification / efficiency issues across the diff, with effort levels,
`--fix`, `--comment` (inline PR comments), and a cloud multi-agent **`ultra`**
mode for large diffs. **Run that first** for general review — do not
re-implement generic bug-finding or parallel batching here; `/code-review ultra`
already fans out across agents in the cloud.

This skill adds the two lenses that are **specific to this template** and are
*not* part of the built-in review. Report findings only — to apply changes use
`/code-review --fix` (bugs) or `/simplify` (quality).

## When to use which

| Goal | Use |
|------|-----|
| Correctness bugs, reuse, efficiency | built-in `/code-review` (add `ultra` for large diffs) |
| Apply quality cleanups to the diff | built-in `/simplify` |
| Shell scripts | `/bash-review` |
| Resiliency + venv-hygiene lenses | **this skill** |

## Scope

1. **Identify files**:
   - If argument is "recent" or empty: `git diff --name-only HEAD`
   - If specific files given: use those
   - Consider `.py`, `.sh`, and SKILL.md command blocks (venv-hygiene applies to all three)
2. **Read each file** before flagging.

## Lens 1 — Resiliency & Recovery

Evaluate how the code handles interruptions and partial failures:

**Disk/filesystem failures:**
- File writes without atomic patterns (write-to-temp + rename) — partial writes corrupt data on crash
- Missing `fsync` / `flush` before rename when durability matters
- No cleanup of temporary files on error (orphaned `.tmp`, `.partial`, `.lock` files)
- Missing disk space checks before large writes

**Network unavailability:**
- HTTP/API calls without timeouts — hangs indefinitely if network drops
- No retry logic with backoff for transient failures (connection reset, DNS timeout, 503)
- Missing circuit breaker patterns for repeated downstream failures
- TCP connections held open without keepalive or reconnect logic

**Recoverability & auto-resume:**
- Long operations (downloads, uploads, migrations) with no checkpoint/resume mechanism
- Batch processing that restarts from zero after interruption instead of resuming
- Missing idempotency — re-running after partial completion causes duplicates or errors
- Database transactions spanning too much work (single large tx instead of chunked commits)
- No write-ahead log or equivalent for multi-step operations that must be atomic

**Partial / corrupted state cleanup:**
- No validation of file integrity after write (checksum, size check, format parse)
- Missing rollback on failure — half-applied changes left in place
- Lock files not cleaned up on abnormal exit (missing `atexit`, signal handlers, or `try/finally`)
- Cache files that become stale or corrupted with no invalidation or rebuild mechanism
- No graceful degradation — single component failure brings down the entire operation

## Lens 2 — Virtual Environment Hygiene

Check for Python invocation patterns that bypass the shared venv wrapper
(`.claude/hooks/venv-activate.sh`):

**Direct Python invocations without wrapper (WARNING):**
- `python script.py`, `python3 script.py`, `python -c "..."` in shell scripts or SKILL.md command blocks without first sourcing `venv-activate.sh`
- `pip install`, `pip3 install` without activating the venv first
- Any `Bash(python ...)` in skill definitions that don't first source `venv-activate.sh`

**Hardcoded venv activation patterns (SUGGESTION):**
- `source .venv/bin/activate` / `source venv/bin/activate` in non-wrapper scripts
- `. .venv/bin/activate` / `. venv/bin/activate` (dot-source variants)
- Any hardcoded venv path in scripts other than `.claude/hooks/venv-activate.sh`

**Exceptions (do NOT flag):**
- `.claude/hooks/venv-activate.sh` itself (the shared wrapper)
- Documentation files (README.md, QUICKSTART.md, CLAUDE.md) showing setup instructions for users
- `pyproject.toml` or other configuration files
- Comments explaining the pattern

**Fix:** source `.claude/hooks/venv-activate.sh` instead of hardcoding venv
activation, or ensure the venv is active before invoking Python.

## Output Format

```
### Project Review Lens: [filename]

**[1] WARNING** | `line 42` | venv-hygiene
- **Issue**: Direct `python` call bypasses venv-activate.sh
- **Impact**: Runs against system Python; may import wrong packages
- **Fix**: Source .claude/hooks/venv-activate.sh first

**[2] SUGGESTION** | `line 87` | resiliency
- **Issue**: File write is not atomic
- **Impact**: A crash mid-write corrupts the file
- **Fix**: Write to a temp file and rename
```

### Summary

| Lens | Critical | Warning | Suggestion |
|------|----------|---------|------------|
| Resiliency | X | Y | Z |
| Venv hygiene | X | Y | Z |

**Files reviewed**: list files
**Reminder**: run built-in `/code-review` for general correctness/efficiency if you haven't.

After presenting findings, tell the user:
"Say **fix [N]** to apply a specific fix, or run `/code-review --fix` / `/simplify` for the general passes."
