---
name: capture
version: 1.0.0
description: >
  Capture planning artifacts, research findings, and decision context from the
  current conversation into discoverable plan files. Ships knowledge the way
  /ship ships code. Writes to .claude/plans/ so future agents and reviewers
  can encounter the context when exploring the codebase.
argument-hint: "[topic slug or description]"
allowed-tools: Read, Glob, Grep, Write, Edit, Bash(git diff *), Bash(git log *), Bash(ls *), AskUserQuestion
---

# Capture Knowledge Artifacts

Synthesize conversation context — planning discussions, research findings, strategic decisions, design iterations — into structured plan files that persist in the codebase.

**This skill ships knowledge.** `/ship` ships code. `/capture` ships the reasoning, research, and decisions that informed the code. Without `/capture`, that context exists only in the conversation transcript and is lost when the session ends.

## Why This Exists

Conversations produce valuable artifacts beyond code:
- Multi-iteration design discussions with conclusions
- Research findings (contacts, organizations, strategies)
- Decision rationale ("we chose X because Y")
- Domain analysis and expert assessments
- Planning context that tasks need during implementation

Currently these either:
1. Get written to **memory** — persists for Claude but invisible to agents exploring the codebase
2. Get lost entirely — conversation ends, context evaporates
3. Get partially captured in task descriptions — but tasks are terse by design

Plan files in `.claude/plans/` solve this: they're in the repo, discoverable by grep, readable by any agent, and linkable from tasks.

## When to Use

- After a planning conversation that produced decisions or research worth preserving
- When the user says "save this", "capture this", "remember this plan"
- Before `/ship` if the conversation involved significant planning beyond just implementation
- When `/cleanup` flags `UNCAPTURED KNOWLEDGE`
- After a domain advisory session whose findings should be preserved (not just the resulting tasks)
- After a multi-iteration design discussion where the final decision and the rejected alternatives both matter

## When NOT to Use

- For code patterns or conventions — those belong in CLAUDE.md or are derivable from the code
- For user preferences or behavioral feedback — those belong in memory (feedback type)
- For operational runbooks — those belong in `docs/operations/`
- For a single fact or preference — use memory instead

## Process

### Step 1: Identify What to Capture

Review the conversation for artifacts worth preserving. Look for:

| Signal | Example |
|--------|---------|
| Multi-iteration design | "Let's try approach A... no, approach B is better because..." |
| Research findings | Contacts, organizations, funding chains, legal landscape |
| Strategic decisions | "We're going with X over Y because of Z" |
| Domain analysis | Expert assessments, evidence synthesis |
| Implementation plans | Phased rollout, dependency ordering, risk mitigations |
| Rejected alternatives | "We considered X but rejected it because Y" — valuable for future agents who might re-propose X |

### Step 2: Determine the Artifact Type

| Type | Destination | When |
|------|-------------|------|
| Strategic plan | `.claude/plans/<slug>.md` | Multi-step strategy with phases, decisions, rationale |
| Research brief | `.claude/plans/<slug>.md` | Findings from investigation that inform future work |
| Design decision | `.claude/plans/<slug>.md` | Architecture or approach choice with alternatives considered |
| Operational doc | `docs/operations/<slug>.md` | How-to or process documentation |

Most things go to `.claude/plans/`. Use `docs/` subdirectories only when the content is operational documentation that other docs already reference.

### Step 3: Choose a Slug

The slug should be descriptive and stable:
- `api-rate-limiting-strategy` not `plan-2026-03-22`
- `auth-provider-design` not `auth`
- `migration-2026-03-22-database-schema` for dated output

Check for existing plans that should be **updated** rather than duplicated:

```bash
ls .claude/plans/
```

If an existing plan covers the same topic, update it (add a dated section or revise the content) rather than creating a parallel file.

### Step 4: Write the Plan File

Use this structure:

```markdown
# <Title>

**Created**: <YYYY-MM-DD>
**Updated**: <YYYY-MM-DD> (if updating an existing plan)
**Status**: Active | Superseded by <link> | Archived
**Context**: <one-line summary of why this plan exists>
**Conversation**: <brief description of the conversation that produced this>

## Background

<What problem or question prompted this work. Include enough context that an agent
encountering this file for the first time understands why it matters.>

## Key Decisions

<Numbered list of decisions made, each with rationale. This is the most valuable
section — it prevents future agents from re-litigating settled questions.>

1. **Decision**: <what was decided>
   **Rationale**: <why>
   **Alternatives considered**: <what was rejected and why>

## Findings

<Research results, analysis, data points. Structure depends on the topic.>

## Plan

<If this is a strategic plan with phases or steps, lay them out here.
Link to task files where they exist.>

## Open Questions

<Anything unresolved that future conversations should address.
These are prompts for the next agent who picks this up.>

## References

<Links to related files, external resources, task IDs, other plans.>
- Related tasks: T1234, T1235
- See also: `.claude/plans/related-plan.md`
- External: <URLs if applicable>
```

Not every section is required. A research brief might skip "Plan". A design decision might skip "Findings". Use what fits.

### Step 5: Update the Plans Index

After writing the plan file, update `.claude/plans/INDEX.md`:

```markdown
- [<title>](<filename>) — <one-line description> (<date>)
```

Keep the index sorted by topic (not chronologically). The index exists so agents exploring the codebase have a single entry point to discover all planning context.

### Step 6: Link from Tasks (if applicable)

If tasks exist that relate to this plan, add a Context line to their description:

```markdown
## Context
See `.claude/plans/<slug>.md` for the full planning context.
```

If tasks will be created **after** this capture, note the plan path so task creation can reference it.

### Step 7: Report What Was Captured

```
===============================================
          KNOWLEDGE CAPTURED
===============================================

  File: .claude/plans/<slug>.md
  Type: <strategic plan | research brief | design decision>
  Size: <line count>

  Key decisions preserved: <count>
  Open questions flagged:  <count>
  Related tasks linked:    <list or "none">

  Index updated: .claude/plans/INDEX.md

===============================================
```

## Updating Existing Plans

When a conversation revisits a topic that already has a plan file:

1. **Read the existing plan** first
2. **Add a dated update section** rather than rewriting (preserves the decision history):
   ```markdown
   ## Update: 2026-03-22

   <New findings, revised decisions, changed context.>
   ```
3. **Update the Status** field if the plan's status changed
4. **Update the INDEX.md** description if the one-liner is now stale

## What Makes a Good Capture

**Good captures:**
- Preserve *why* decisions were made, not just *what* was decided
- Include rejected alternatives (prevents re-proposal)
- Flag open questions explicitly (guides future work)
- Link to related tasks and other plans (builds the knowledge graph)
- Include enough background that a cold-start agent can orient

**Bad captures:**
- Verbatim conversation transcript (too noisy, use synthesis)
- Code snippets without context (put those in the code itself)
- Duplicating content already in CLAUDE.md or docs/ (link instead)
- Capturing ephemeral state that will be stale tomorrow

## Integration with Other Skills

| Skill | Integration |
|-------|-------------|
| `/cleanup` | Detects uncaptured knowledge and suggests `/capture` |
| `/ship` | Ships code; `/capture` ships the reasoning behind it |
| `/claim-tasks` | Implementation agents read plan files linked from tasks |

## Arguments

| Argument | Effect |
|----------|--------|
| (none) | Interactive — assess conversation, ask user what to capture |
| `<slug>` | Create/update `.claude/plans/<slug>.md` with conversation context |
| `<description>` | If not a valid slug, use as the plan title and derive the slug |
