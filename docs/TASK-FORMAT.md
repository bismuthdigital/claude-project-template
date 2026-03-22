# Task Format Specification

> Canonical grammar for tasks. All skills that read or write tasks must follow
> this specification.
>
> Tasks are stored as **per-task files** in `next-steps/active/` (pending) and
> `next-steps/completed/` (done). `NEXT-STEPS.md` is a **generated artifact**
> produced by `scripts/task-format.py render`. Do not edit NEXT-STEPS.md directly.

## Task Line Grammar

```
- [<state>] **[<roles>] <title>** T### — <description>
```

| Field | Required | Description |
|-------|----------|-------------|
| `<state>` | yes | Space (pending) or `x` (completed) |
| `<roles>` | recommended | One or more roles joined by `+` inside brackets |
| `<title>` | yes | Human-readable task name (identity string) |
| `T###` | recommended | Stable numeric ID (3+ digits, zero-padded), placed **after** closing `**` |
| `—` | yes | Em dash (U+2014) — the **only** valid separator. Never use `--`. |
| `<description>` | yes | Brief description of the task |

### Roles

Valid role tags: `dev`, `design`, `docs`, `test`, `ops`, `security`.

Multiple roles are joined with `+`: `[dev+test]`, `[ops+security]`.

Customize for your project by editing `VALID_ROLES` in `scripts/task-format.py`.

### Task IDs

- Format: `T` followed by 3+ zero-padded digits: `T001`, `T047`, `T123`
- Sequential from a counter stored in `.tasks.json` (`next_id` field)
- **Permanent** — never reused after deletion or archival
- Assigned via `scripts/task-format.py assign-ids`, not manually
- Placed after the closing `**` bold marker and before the em dash

### Examples

```markdown
- [ ] **[dev] Add user authentication middleware** T001 — New auth middleware in routes.py
- [ ] **[dev+test] Add integration test suite** T002 — End-to-end tests for API endpoints
- [x] **[dev] Build REST API client** T003 — *(Sprint 1, 2026-03-01)* New APIClient class
```

## Sub-fields

Sub-fields appear as indented list items below the task line, in this canonical
order:

1. `- Context:` why this matters
2. `- Files:` backtick-enclosed paths (comma-separated)
3. `- Priority:` `high` | `medium` | `low`
4. `- Dependencies:` task titles or IDs

```markdown
- [ ] **[dev] Wire GET /health endpoint** T004 — Add health check route
  - Context: Unblocks monitoring and integration tests
  - Files: `src/your_package/routes.py`, `tests/test_routes.py`
  - Priority: high
  - Dependencies: T001
```

## Completed Tasks

Completed tasks append sprint metadata after the em dash:

```markdown
- [x] **[dev] Build data pipeline** T005 — *(Sprint 2, 2026-03-15)* New Pipeline class
```

Format: `*(Sprint NN, YYYY-MM-DD)*` followed by a summary of what was done.

## Sections

Tasks are organized under `##` headings (sections) and optional `###` headings
(subsections). Standard sections:

- `## High Priority`
- `## Medium Priority`
- `## Low Priority / Nice to Have`
- `## Completed`
- `## Deferred`
- `## Dropped`

Custom sections (e.g., `## API Redesign`) are allowed.

## Non-task Content

Lines that are not task lines — preamble text, blockquotes, tables, horizontal
rules — are preserved verbatim by all tooling. Only lines matching the task
regex are parsed as tasks.

## `.tasks.json` Sidecar

The index file `.tasks.json` lives at the repo root (gitignored). It contains:

```json
{
  "next_id": 50,
  "generated_from": "NEXT-STEPS.md",
  "generated_from_sha": "abc1234",
  "generated_at": "2026-02-26T14:30:00Z",
  "tasks": [...]
}
```

Regenerated on demand via `scripts/task-format.py index`.

## Per-Task File Format

Each task is stored as a separate `.md` file with YAML-style frontmatter.

### Directory Structure

```
next-steps/
├── _meta.md              # Static header (project context, dev cycle)
├── _sections.toml        # Section ordering, titles, descriptions
├── active/               # One .md file per pending task
│   ├── add-auth-middleware.md
│   └── ...
└── completed/            # One .md file per completed task
    ├── build-api-client.md
    └── ...
```

### Task File Format

```markdown
---
role: dev
section: high-priority
priority: high
status: pending
sprint:
completed_date:
completed_summary:
created: 2026-03-01
---

# Add user authentication middleware

Description of what needs to be done.

## Context

Why this matters.

## Files

- `src/your_package/routes.py`

## Dependencies

- None
```

### Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `role` | yes | Role tag (dev, design, etc.) |
| `section` | yes | Section ID from `_sections.toml` |
| `priority` | yes | `high`, `medium`, or `low` |
| `status` | yes | `pending` or `completed` |
| `sprint` | no | Sprint number (set on completion) |
| `completed_date` | no | ISO date (set on completion) |
| `completed_summary` | no | What was done (set on completion) |
| `created` | yes | ISO date when task was created |

### Section Metadata (`_sections.toml`)

```toml
[[sections]]
id = "high-priority"
title = "High Priority"
priority = "high"
sort_order = 1
description = """Critical tasks that should be addressed first."""
```

Optional `parent` field groups sections under a feature track heading.

### CLI Commands

| Command | Purpose |
|---------|---------|
| `task-format.py render` | Generate NEXT-STEPS.md + COMPLETED from task files |
| `task-format.py split` | One-time migration: split NEXT-STEPS.md into per-task files |
| `task-format.py create-task --role X --section Y --priority Z --title "..."` | Create a new task file |
| `task-format.py complete-task <slug> --sprint N --summary "..."` | Mark task complete, move to completed/ |

All existing commands (`parse`, `validate`, `lookup`, `stats`, etc.) auto-detect: if `next-steps/` exists, read from files; otherwise fall back to NEXT-STEPS.md.
