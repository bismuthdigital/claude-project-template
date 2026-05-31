# Template Modernization for Current Claude Code Capabilities (2026-05)

**Created**: 2026-05-31
**Status**: Active
**Context**: Why 28→27 skills, why `/code-health` and the `version:` field were removed, and what was deliberately *not* changed.
**Conversation**: A review of the template before spawning a new project, after Claude Code's capabilities advanced (built-in skills, the Workflow tool, plan mode, current models). Shipped as PR #27.

## Background

The template had accreted over ~10 months. In that time Claude Code shipped capabilities that the template predated and never absorbed:

1. **Built-in skills** now cover work the template implemented as custom skills — `/code-review` (with `--fix`, `--comment`, and a cloud multi-agent `ultra` mode), `/simplify`, `/verify`, `/run`, `/security-review`, `/deep-research`.
2. **The Workflow tool** (deterministic `pipeline`/`parallel`/`agent` orchestration with worktree isolation, structured output, resume) now exists for the multi-agent fan-out the template hand-rolled.
3. **Plan mode** (`EnterPlanMode`/`ExitPlanMode`) now exists for the design-before-edit step.
4. **Models** advanced to Opus 4.8 / Sonnet 4.6 / Haiku 4.5; the template carried stale model names, IDs, and pricing.

A three-agent audit (model-staleness sweep, skill format/redundancy review, docs/config hygiene) produced the findings below. This file records the *decisions and their rationale* so a future maintainer doesn't re-litigate them.

## Key Decisions

1. **Decision**: Retire `/code-health` entirely.
   **Rationale**: Its description and behavior were a near-verbatim match for built-in `/simplify` (quality-only, diff-scoped, auto-fix). Carrying a duplicate in a *template* propagates clutter to every spawned project.
   **Alternatives considered**: Keep it as a thin delegating stub — rejected; a stub that just calls `/simplify` adds indirection with no value. Its one semi-unique step (read one hop of callers/callees to check assumptions) is covered well enough by `/code-review` at higher effort.

2. **Decision**: Thin `/review` (189→~110 lines) instead of retiring it.
   **Rationale**: Generic bug-finding overlaps `/code-review`, but `/review` carries genuinely project-specific value with no built-in equivalent: the **resiliency/recovery** checklist and especially the **venv-hygiene rule** (flag direct `python` calls that bypass `.claude/hooks/venv-activate.sh`). Kept only those two lenses; delegated everything generic to `/code-review` (including parallelism, now `/code-review ultra`).
   **Alternatives considered**: Full retirement — rejected; would lose the venv-hygiene enforcement that is tied to this template's hook architecture.

3. **Decision**: Keep `/check` as an orchestrator but rewire it to `/code-review` + `/review`, and add its missing `allowed-tools`.
   **Rationale**: Its aggregation across lint/test/review/docs/bash-review into one report is not a built-in and is genuinely useful. It was missing `allowed-tools` entirely, so it could not reliably invoke the sub-skills it depends on.

4. **Decision**: Remove the `version:` frontmatter from all skills and switch `/sync-config` and `/port-from-project` from version-comparison to **content-diff**.
   **Rationale**: The field was non-standard, was present on only 15/27 skills, and had drifted (everything stuck at `1.0.0` — nobody bumped it). Both consumer skills already diffed *scripts and hooks* by content; comparing skills the same way is more robust and removes a manual step that was never maintained.
   **Alternatives considered**: Add `version:` to all 27 and keep version-compare — rejected; it perpetuates an unmaintained manual mechanism. (Note: removing the field is what *forced* the consumer-skill rewrite — they were load-bearing on it.)

5. **Decision**: Do NOT migrate `/claim-tasks` to the Workflow tool.
   **Rationale**: `/claim-tasks` is a **sequential merge queue by design** — it implements each task with commits/tests between to avoid conflicts. The Workflow tool's value is *parallel* fan-out, which is the wrong shape for a merge queue. The genuinely parallelizable fits are `/fix-failed-pr`'s combine step and `/docs` batching. Modernized the orchestration *prose* ("Task tool" → `Agent`/`subagent_type`, documented the Workflow tool) without rewriting the working engine.

6. **Decision**: Bump the Python floor 3.10 → 3.11.
   **Rationale**: 3.10 is the oldest still-supported baseline (EOL Oct 2026). The bump immediately paid off: ruff's pyupgrade modernized `timezone.utc` → `datetime.UTC` in the scripts.

## Findings (audit results)

- **Live pricing verified** (source: anthropic.com/pricing, 2026-05-30): Opus 4.8 `$5/$25`, Sonnet 4.6 `$3/$15`, Haiku 4.5 `$1/$5` per MTok. `cost-estimate` now carries a "verify before relying" note since pricing drifts.
- **Docs had drifted out of sync across three places** in README (features list, structure diagram, skills table) plus QUICKSTART — including a phantom `/simplify` row, a documented-but-nonexistent Stop hook, and contradictory skill counts (24 vs 28). `CLAUDE.md` was the accurate source of truth.
- **Deny-list gaps**: `Bash(rm -rf *)` / `Bash(sudo *)` missed the colon-style and flag-reordered twins the harness now auto-generates.
- **`pytest-xdist` was documented but never in dev deps.**

## Deferred Work (intentional, with rationale)

1. **Full Workflow-tool rewrite of the `/fix-failed-pr` and `/claim-tasks` execution engines.** These hand-roll multi-agent orchestration on top of `work-queue.sh` (~2,144 lines). Re-expressing the *orchestration layer* (not the task/queue business logic) on the Workflow tool would buy structured output and built-in worktree isolation — but it is a behavioral change that needs live multi-agent testing to do safely. Not a same-PR change.
2. **Normalizing all 102 allow-list permissions in `settings.json` from space-style (`Bash(python *)`) to colon-style (`Bash(python:*)`).** Cosmetic; both styles work; churning 102 security-relevant lines risks subtly changing match semantics. Left as-is.
3. **Latent**: `/port-from-project` declares `Bash(rm -rf *)` in `allowed-tools`, which the global deny overrides (it will prompt). Untouched.

## Open Questions

- Should the orchestration skills (`/fix-failed-pr`, `/docs`) eventually be re-expressed as actual Workflow scripts, or is documenting the pattern enough? Revisit once the Workflow tool has more mileage in this portfolio.
- Should `cost-estimate` fetch live pricing at runtime rather than carrying a (drift-prone) hardcoded table?

## References

- PR: #27 — "Modernize template for current Claude Code capabilities" (merge commit `35b6351`)
- Built-in mapping: see the "Built-in Claude Code Capabilities" section in `CLAUDE.md`
- Affected skills: `.claude/skills/{review,check,fix-failed-pr,sync-config,port-from-project,capture,docs,cost-estimate,model-alternatives,prompt-review}/SKILL.md`
- Removed: `.claude/skills/code-health/` (use built-in `/simplify`)
