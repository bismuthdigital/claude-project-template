#!/usr/bin/env python3
"""Task format parser, validator, and normalizer for NEXT-STEPS.md.

Provides subcommands for parsing, validating, normalizing, indexing, and
querying tasks in the canonical format defined in docs/TASK-FORMAT.md.

Supports two storage modes:
  - **Monolithic**: Tasks stored directly in NEXT-STEPS.md (legacy)
  - **Per-task files**: Tasks stored as individual .md files in next-steps/
    (auto-detected when next-steps/ directory exists)

Usage:
    scripts/task-format.py parse              # NEXT-STEPS.md → JSON to stdout
    scripts/task-format.py validate           # Format compliance report
    scripts/task-format.py normalize          # Fix formatting in-place
    scripts/task-format.py index              # Generate .tasks.json sidecar
    scripts/task-format.py assign-ids         # Add T### IDs to tasks that lack them
    scripts/task-format.py lookup T047        # Print task details by ID
    scripts/task-format.py review-freshness   # Check staleness of .claude/reviews/
    scripts/task-format.py list-unreviewed    # List pending tasks without reviews
    scripts/task-format.py stats              # Summary statistics
    scripts/task-format.py render             # Generate NEXT-STEPS.md from task files
    scripts/task-format.py split              # Migrate NEXT-STEPS.md → per-task files
    scripts/task-format.py create-task        # Create a new task file
    scripts/task-format.py complete-task      # Mark a task complete (move to completed/)
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import re
import subprocess
import sys
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path

# --- Data structures ---

# Customize for your project's role taxonomy
VALID_ROLES = {
    "dev",
    "design",
    "docs",
    "test",
    "ops",
    "security",
}

# Task line regex — accepts both — and -- separators (-- flagged in validation)
TASK_RE = re.compile(
    r"^- \[([ x])\] "  # checkbox
    r"\*\*"  # bold open
    r"(?:\[([^\]]+)\]\s*)?"  # optional [roles]
    r"(.+?)"  # title (non-greedy)
    r"\*\*"  # bold close
    r"(?:\s+(T\d{3,}))?"  # optional T### ID
    r"\s*"  # whitespace
    r"(?:—|--)\s*"  # em dash or double hyphen separator
    r"(.*)$"  # description
)

# Sub-field regex (indented under a task)
SUBFIELD_RE = re.compile(
    r"^\s+- (Context|Files|Priority|Dependencies|Completed):\s*(.*)$"
)

# Section heading regex
SECTION_RE = re.compile(r"^(#{2,3})\s+(.+)$")

# Sprint metadata in completed task descriptions
SPRINT_RE = re.compile(r"\*\(Sprint\s+(\d+\w?),\s+([\d-]+)\)\*")


@dataclass
class TaskEntry:
    """A single parsed task from NEXT-STEPS.md."""

    id: str | None = None  # "T047" or None
    state: str = "pending"  # "pending" or "completed"
    roles: list[str] = field(default_factory=list)
    title: str = ""
    description: str = ""
    context: str | None = None
    files: list[str] = field(default_factory=list)
    priority: str | None = None
    dependencies: list[str] = field(default_factory=list)
    sprint_number: str | None = None
    sprint_date: str | None = None
    section: str = ""
    subsection: str | None = None
    line_number: int = 0
    raw_lines: list[str] = field(default_factory=list)
    separator: str = "—"  # Track which separator was used


@dataclass
class FormatIssue:
    """A single validation issue."""

    severity: str  # "error", "warning", "info"
    category: str
    line_number: int
    message: str
    fix_available: bool


@dataclass
class FormatReport:
    """Validation report for NEXT-STEPS.md."""

    issues: list[FormatIssue] = field(default_factory=list)
    task_count: int = 0
    pending_count: int = 0
    completed_count: int = 0

    @property
    def score(self) -> int:
        """Score: 100 minus deductions (error -20, warning -5, info -1)."""
        deductions = sum(
            20 if i.severity == "error" else 5 if i.severity == "warning" else 1
            for i in self.issues
        )
        return max(0, 100 - deductions)


# --- Utility functions ---


def find_repo_root() -> Path:
    """Find the git repository root."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True,
        )
        return Path(result.stdout.strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        return Path.cwd()


def find_main_repo_root() -> Path:
    """Find the main repo root (first worktree, shared across all worktrees)."""
    try:
        result = subprocess.run(
            ["git", "worktree", "list", "--porcelain"],
            capture_output=True,
            text=True,
            check=True,
        )
        for line in result.stdout.splitlines():
            if line.startswith("worktree "):
                return Path(line[len("worktree ") :])
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return find_repo_root()


def slug_from_title(title: str) -> str:
    """Convert a task title to a filesystem-safe slug.

    Matches the bash slug_from_title in work-queue.sh exactly.
    """
    s = re.sub(r"[^a-z0-9]", "-", title.lower())
    s = re.sub(r"-+", "-", s)
    s = s.strip("-")
    return s[:80]


def git_hash_object(path: Path) -> str | None:
    """Get the git hash of a file."""
    try:
        result = subprocess.run(
            ["git", "hash-object", str(path)],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def file_sha256(path: Path) -> str:
    """Get the SHA256 hash of a file's content."""
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()[:12]


# --- Parser ---


def _detect_separator(line: str) -> str:
    """Detect whether a task line uses em dash or double hyphen."""
    bold_end = line.find("**", line.find("**") + 2)
    if bold_end >= 0:
        after_bold = line[bold_end + 2 :]
        after_stripped = re.sub(r"^\s*T\d{3,}\s*", "", after_bold)
        if after_stripped.lstrip().startswith("--"):
            return "--"
    return "—"


def _parse_task_line(
    match: re.Match, line: str, line_num: int, section: str, subsection: str | None
) -> TaskEntry:
    """Build a TaskEntry from a regex match."""
    state_char, roles_str, title, task_id, description = match.groups()
    roles = [r.strip() for r in roles_str.split("+")] if roles_str else []

    sprint_number = None
    sprint_date = None
    sprint_match = SPRINT_RE.search(description)
    if sprint_match:
        sprint_number = sprint_match.group(1)
        sprint_date = sprint_match.group(2)

    return TaskEntry(
        id=task_id,
        state="completed" if state_char == "x" else "pending",
        roles=roles,
        title=title.strip(),
        description=description.strip(),
        section=section,
        subsection=subsection,
        line_number=line_num,
        raw_lines=[line],
        separator=_detect_separator(line),
        sprint_number=sprint_number,
        sprint_date=sprint_date,
    )


def _apply_subfield(task: TaskEntry, field_name: str, field_value: str) -> None:
    """Apply a parsed sub-field to a TaskEntry."""
    if field_name == "Context":
        task.context = field_value
    elif field_name == "Files":
        paths = re.findall(r"`([^`]+)`", field_value)
        if not paths:
            paths = [p.strip() for p in field_value.split(",") if p.strip()]
        task.files = paths
    elif field_name == "Priority":
        task.priority = field_value
    elif field_name == "Dependencies":
        task.dependencies = [d.strip() for d in field_value.split(",") if d.strip()]
    elif field_name == "Completed" and not task.sprint_date:
        task.sprint_date = field_value


def parse_tasks(filepath: Path) -> list[TaskEntry]:
    """Parse NEXT-STEPS.md into a list of TaskEntry objects."""
    lines = filepath.read_text().splitlines()
    tasks: list[TaskEntry] = []
    current_section = ""
    current_subsection: str | None = None
    current_task: TaskEntry | None = None

    for i, line in enumerate(lines, start=1):
        section_match = SECTION_RE.match(line)
        if section_match:
            level = len(section_match.group(1))
            heading = section_match.group(2).strip()
            if level == 2:
                current_section = heading
                current_subsection = None
            elif level == 3:
                current_subsection = heading
            current_task = None
            continue

        task_match = TASK_RE.match(line)
        if task_match:
            task = _parse_task_line(
                task_match, line, i, current_section, current_subsection
            )
            tasks.append(task)
            current_task = task
            continue

        if current_task is not None:
            current_task = _handle_continuation(current_task, line)

    return tasks


def _handle_continuation(task: TaskEntry, line: str) -> TaskEntry | None:
    """Process a line that might be a sub-field or continuation of a task.

    Returns the task if still active, None if ended.
    """
    subfield_match = SUBFIELD_RE.match(line)
    if subfield_match:
        task.raw_lines.append(line)
        _apply_subfield(task, subfield_match.group(1), subfield_match.group(2).strip())
        return task

    if line.startswith("  ") and line.strip():
        task.raw_lines.append(line)
        return task

    if line.strip():
        return None

    return task


# --- Validator ---


def _validate_task_format(
    task: TaskEntry, seen_ids: dict[str, int], issues: list[FormatIssue]
) -> None:
    """Validate separator, role tags, IDs, and metadata for a single task."""
    if task.separator == "--":
        issues.append(
            FormatIssue(
                severity="error",
                category="separator",
                line_number=task.line_number,
                message=f'Task "{task.title}" uses "--" instead of em dash "—"',
                fix_available=True,
            )
        )

    if not task.roles:
        issues.append(
            FormatIssue(
                severity="warning",
                category="role_tag",
                line_number=task.line_number,
                message=f'Task "{task.title}" has no role tag',
                fix_available=False,
            )
        )

    for role in task.roles:
        if role not in VALID_ROLES:
            issues.append(
                FormatIssue(
                    severity="warning",
                    category="role_tag",
                    line_number=task.line_number,
                    message=f'Task "{task.title}" uses undeclared role "{role}"',
                    fix_available=False,
                )
            )

    if task.id is None:
        issues.append(
            FormatIssue(
                severity="warning",
                category="missing_id",
                line_number=task.line_number,
                message=f'Task "{task.title}" has no T### ID',
                fix_available=True,
            )
        )
    elif task.id in seen_ids:
        issues.append(
            FormatIssue(
                severity="error",
                category="duplicate_id",
                line_number=task.line_number,
                message=f"Duplicate ID {task.id} (first at line {seen_ids[task.id]})",
                fix_available=False,
            )
        )
    else:
        seen_ids[task.id] = task.line_number

    if task.state == "completed" and not task.sprint_number:
        issues.append(
            FormatIssue(
                severity="info",
                category="sprint_metadata",
                line_number=task.line_number,
                message=f'Completed task "{task.title}" has no sprint metadata',
                fix_available=False,
            )
        )


_CANONICAL_SUBFIELD_ORDER = [
    "Context",
    "Files",
    "Priority",
    "Dependencies",
    "Completed",
]


def _validate_task_content(
    task: TaskEntry, all_tasks: list[TaskEntry], issues: list[FormatIssue]
) -> None:
    """Validate sub-field order, file paths, and dependency references."""
    # Check sub-field order
    subfield_order = []
    for raw_line in task.raw_lines[1:]:
        sf_match = SUBFIELD_RE.match(raw_line)
        if sf_match:
            subfield_order.append(sf_match.group(1))

    if len(subfield_order) > 1:
        filtered = [s for s in subfield_order if s in _CANONICAL_SUBFIELD_ORDER]
        expected = sorted(filtered, key=_CANONICAL_SUBFIELD_ORDER.index)
        if filtered != expected:
            issues.append(
                FormatIssue(
                    severity="info",
                    category="field_order",
                    line_number=task.line_number,
                    message=(
                        f'Task "{task.title}" sub-fields not in canonical order '
                        f"(got {filtered}, expected {expected})"
                    ),
                    fix_available=True,
                )
            )

    # Check file paths exist (pending tasks only)
    if task.state == "pending" and task.files:
        repo_root = find_repo_root()
        for fpath in task.files:
            full = repo_root / fpath
            if not full.exists() and not fpath.startswith("new "):
                issues.append(
                    FormatIssue(
                        severity="warning",
                        category="file_path",
                        line_number=task.line_number,
                        message=f'Task "{task.title}" references non-existent file: {fpath}',
                        fix_available=False,
                    )
                )

    # Check dependency references
    for dep in task.dependencies:
        dep_stripped = dep.strip()
        if (
            dep_stripped.startswith("T")
            and dep_stripped[1:].isdigit()
            and not any(t.id == dep_stripped for t in all_tasks)
        ):
            issues.append(
                FormatIssue(
                    severity="warning",
                    category="dependency_ref",
                    line_number=task.line_number,
                    message=f'Task "{task.title}" depends on {dep_stripped} which was not found',
                    fix_available=False,
                )
            )


def validate_tasks(tasks: list[TaskEntry]) -> FormatReport:
    """Validate tasks against the canonical format spec."""
    issues: list[FormatIssue] = []
    seen_ids: dict[str, int] = {}

    for task in tasks:
        _validate_task_format(task, seen_ids, issues)
        _validate_task_content(task, tasks, issues)

    return FormatReport(
        issues=issues,
        task_count=len(tasks),
        pending_count=sum(1 for t in tasks if t.state == "pending"),
        completed_count=sum(1 for t in tasks if t.state == "completed"),
    )


# --- Normalizer ---


def normalize_file(filepath: Path, *, dry_run: bool = False) -> list[str]:
    """Normalize NEXT-STEPS.md formatting in-place.

    Returns list of changes made.
    """
    content = filepath.read_text()
    lines = content.splitlines()
    changes: list[str] = []
    new_lines: list[str] = []

    for i, line in enumerate(lines, start=1):
        new_line = line

        # Fix double-hyphen separators to em dash
        task_match = TASK_RE.match(line)
        if task_match:
            # Check if this line uses -- separator
            bold_end_pos = _find_bold_close(line)
            if bold_end_pos >= 0:
                after_bold = line[bold_end_pos + 2 :]
                # Skip optional T### ID
                after_stripped = re.sub(r"^\s*T\d{3,}\s*", "", after_bold)
                if re.match(r"\s*--\s+", after_stripped):
                    # Replace the first -- after the bold close (and optional ID)
                    new_line = _replace_separator(line, bold_end_pos)
                    if new_line != line:
                        changes.append(f"Line {i}: Fixed separator '--' → '—'")

        new_lines.append(new_line)

    if changes and not dry_run:
        filepath.write_text("\n".join(new_lines) + "\n")

    return changes


def _find_bold_close(line: str) -> int:
    """Find the position of the closing ** in a task line."""
    # Find the first ** (opening)
    first = line.find("**")
    if first < 0:
        return -1
    # Find the second ** (closing)
    second = line.find("**", first + 2)
    return second


def _replace_separator(line: str, bold_end_pos: int) -> str:
    """Replace -- separator with — after the bold close."""
    before = line[: bold_end_pos + 2]
    after = line[bold_end_pos + 2 :]
    # Replace the first occurrence of -- (with surrounding whitespace) with —
    after = re.sub(r"(\s*(?:T\d{3,}\s*)?)--\s+", r"\1— ", after, count=1)
    return before + after


# --- ID assignment ---


def assign_ids(filepath: Path, *, dry_run: bool = False) -> list[str]:
    """Add T### IDs to tasks that lack them.

    Returns list of changes made.
    """
    main_root = find_main_repo_root()
    index_path = main_root / ".tasks.json"

    # Load or initialize the counter
    next_id = 1
    if index_path.exists():
        try:
            data = json.loads(index_path.read_text())
            next_id = data.get("next_id", 1)
        except (json.JSONDecodeError, OSError):
            pass

    # Also scan existing tasks for the highest ID to avoid collisions
    tasks = parse_tasks(filepath)
    for task in tasks:
        if task.id:
            num = int(task.id[1:])
            if num >= next_id:
                next_id = num + 1

    content = filepath.read_text()
    lines = content.splitlines()
    changes: list[str] = []

    for i, line in enumerate(lines):
        task_match = TASK_RE.match(line)
        if task_match:
            _state_char, _roles_str, title, task_id, _description = task_match.groups()
            if task_id is None:
                # Insert T### after closing **
                new_id = f"T{next_id:03d}"
                bold_end = _find_bold_close(line)
                if bold_end >= 0:
                    before = line[: bold_end + 2]
                    after = line[bold_end + 2 :]
                    lines[i] = f"{before} {new_id}{after}"
                    changes.append(
                        f'Line {i + 1}: Assigned {new_id} to "{title.strip()}"'
                    )
                    next_id += 1

    if changes and not dry_run:
        filepath.write_text("\n".join(lines) + "\n")
        # Update the counter
        index_data = {}
        if index_path.exists():
            try:  # noqa: SIM105
                index_data = json.loads(index_path.read_text())
            except (json.JSONDecodeError, OSError):
                pass
        index_data["next_id"] = next_id
        index_path.write_text(json.dumps(index_data, indent=2) + "\n")

    return changes


# --- Index generation ---


def generate_index(filepath: Path) -> dict:
    """Generate .tasks.json sidecar from NEXT-STEPS.md."""
    tasks = parse_tasks(filepath)
    main_root = find_main_repo_root()
    index_path = main_root / ".tasks.json"

    # Get file hash
    file_sha = file_sha256(filepath)

    # Compute next_id from existing assignments
    max_id = 0
    for task in tasks:
        if task.id:
            num = int(task.id[1:])
            max_id = max(max_id, num)

    # Load existing next_id if higher
    existing_next_id = max_id + 1
    if index_path.exists():
        try:
            data = json.loads(index_path.read_text())
            existing_next_id = max(data.get("next_id", 1), max_id + 1)
        except (json.JSONDecodeError, OSError):
            pass

    index = {
        "next_id": existing_next_id,
        "generated_from": str(filepath.name),
        "generated_from_sha": file_sha,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "task_count": len(tasks),
        "pending_count": sum(1 for t in tasks if t.state == "pending"),
        "completed_count": sum(1 for t in tasks if t.state == "completed"),
        "tasks": [_task_to_dict(t) for t in tasks],
    }

    index_path.write_text(json.dumps(index, indent=2) + "\n")
    return index


def _task_to_dict(task: TaskEntry) -> dict:
    """Convert a TaskEntry to a serializable dict (excluding raw_lines)."""
    d = asdict(task)
    del d["raw_lines"]
    del d["separator"]
    d["slug"] = slug_from_title(task.title)
    return d


# --- Lookup ---


def lookup_task(filepath: Path, query: str) -> TaskEntry | None:
    """Find a task by ID or title substring."""
    tasks = parse_tasks(filepath)

    # Try exact ID match first
    if re.match(r"^T\d{3,}$", query):
        for task in tasks:
            if task.id == query:
                return task
        return None

    # Try title substring match (case-insensitive)
    query_lower = query.lower()
    matches = [t for t in tasks if query_lower in t.title.lower()]

    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        # Return the first match but warn
        print(
            f"Warning: {len(matches)} tasks match '{query}', returning first match",
            file=sys.stderr,
        )
        return matches[0]
    return None


# --- Review freshness ---


def _parse_review_frontmatter(
    content: str,
) -> tuple[str | None, str | None, dict[str, str]]:
    """Extract task_id, task_title, and referenced_files_sha from YAML frontmatter."""
    task_id = None
    task_title = None
    referenced_files: dict[str, str] = {}

    if not content.startswith("---"):
        return task_id, task_title, referenced_files

    end = content.find("---", 3)
    if end <= 0:
        return task_id, task_title, referenced_files

    for line in content[3:end].splitlines():
        if line.startswith("task_id:"):
            task_id = line.split(":", 1)[1].strip().strip('"')
        elif line.startswith("task_title:"):
            task_title = line.split(":", 1)[1].strip().strip('"')
        elif line.startswith("  ") and ":" in line:
            parts = line.strip().split(":")
            if len(parts) == 2:
                referenced_files[parts[0].strip().strip('"')] = (
                    parts[1].strip().strip('"')
                )

    return task_id, task_title, referenced_files


def _check_file_staleness(
    repo_root: Path, referenced_files: dict[str, str], result: dict
) -> None:
    """Check referenced file hashes for staleness, updating result in-place."""
    for fpath, stored_sha in referenced_files.items():
        full_path = repo_root / fpath
        if not full_path.exists():
            result["stale_files"].append({"file": fpath, "reason": "deleted"})
            result["status"] = "stale"
        else:
            current_sha = git_hash_object(full_path)
            if current_sha and current_sha != stored_sha:
                result["stale_files"].append(
                    {
                        "file": fpath,
                        "reason": "modified",
                        "stored_sha": stored_sha,
                        "current_sha": current_sha,
                    }
                )
                result["status"] = "stale"


def check_review_freshness(repo_root: Path) -> list[dict]:
    """Check staleness of .claude/reviews/ files."""
    reviews_dir = find_main_repo_root() / ".claude" / "reviews"
    if not reviews_dir.exists():
        return []

    if _has_task_files():
        tasks = _load_task_files()
    else:
        next_steps = repo_root / "NEXT-STEPS.md"
        tasks = parse_tasks(next_steps) if next_steps.exists() else []
    task_titles = {t.title for t in tasks}
    results = []

    for review_file in sorted(reviews_dir.glob("*.md")):
        if review_file.name == ".gitkeep":
            continue

        content = review_file.read_text()
        result: dict = {"file": review_file.name, "status": "fresh", "stale_files": []}

        task_id, task_title, referenced_files = _parse_review_frontmatter(content)
        result["task_id"] = task_id
        result["task_title"] = task_title

        # Check if task still exists
        if task_title and task_title not in task_titles:
            found_by_id = task_id and any(t.id == task_id for t in tasks)
            if not found_by_id:
                result["status"] = "orphaned"
                results.append(result)
                continue

        _check_file_staleness(repo_root, referenced_files, result)
        results.append(result)

    return results


def list_unreviewed_tasks(repo_root: Path, *, limit: int = 1) -> list[dict]:
    """List pending tasks that have no corresponding review file.

    Checks two locations for review evidence:
    1. Shared ``{main_repo}/.claude/reviews/{slug}.md`` (ephemeral review artifact)
    2. Shared ``{main_repo}/.claude/work-queue/reviewed/{slug}.json`` (cross-worktree marker)

    Returns up to ``limit`` tasks ordered by priority (High > Medium > Low).
    """
    next_steps = repo_root / "NEXT-STEPS.md"
    if not next_steps.exists():
        return []

    tasks = parse_tasks(next_steps)
    main_root = find_main_repo_root()
    reviews_dir = main_root / ".claude" / "reviews"

    # Shared reviewed markers live in the main repo (visible to all worktrees)
    reviewed_dir = main_root / ".claude" / "work-queue" / "reviewed"

    priority_order = {"high": 0, "medium": 1, "low": 2}
    pending = [t for t in tasks if t.state == "pending"]
    pending.sort(key=lambda t: priority_order.get((t.priority or "low").lower(), 2))

    unreviewed = []
    for task in pending:
        slug = slug_from_title(task.title)
        review_path = reviews_dir / f"{slug}.md"
        reviewed_marker = reviewed_dir / f"{slug}.json"
        if not review_path.exists() and not reviewed_marker.exists():
            unreviewed.append(_task_to_dict(task))
            if len(unreviewed) >= limit:
                break

    return unreviewed


# --- Stats ---


def compute_stats(tasks: list[TaskEntry]) -> dict:
    """Compute summary statistics from parsed tasks."""
    sections: dict[str, int] = {}
    roles: dict[str, int] = {}
    priorities: dict[str, int] = {}
    with_ids = 0
    without_ids = 0

    for task in tasks:
        section = task.section or "(no section)"
        sections[section] = sections.get(section, 0) + 1

        for role in task.roles:
            roles[role] = roles.get(role, 0) + 1

        if task.priority:
            priorities[task.priority] = priorities.get(task.priority, 0) + 1

        if task.id:
            with_ids += 1
        else:
            without_ids += 1

    return {
        "total": len(tasks),
        "pending": sum(1 for t in tasks if t.state == "pending"),
        "completed": sum(1 for t in tasks if t.state == "completed"),
        "with_ids": with_ids,
        "without_ids": without_ids,
        "by_section": dict(sorted(sections.items())),
        "by_role": dict(sorted(roles.items(), key=lambda x: -x[1])),
        "by_priority": priorities,
    }


# --- Per-task file support ---

# Frontmatter field names in task files
_FRONTMATTER_FIELDS = [
    "id",
    "role",
    "section",
    "priority",
    "status",
    "sprint",
    "completed_date",
    "completed_summary",
    "created",
]


def _task_files_dir() -> Path:
    """Return the next-steps/ directory path relative to repo root."""
    return find_repo_root() / "next-steps"


def _has_task_files() -> bool:
    """Check if per-task file storage exists."""
    return _task_files_dir().is_dir()


def _parse_task_frontmatter(content: str) -> dict[str, str]:
    """Extract key-value pairs from YAML-style frontmatter.

    Uses the same line-by-line approach as _parse_review_frontmatter().
    No PyYAML dependency required.
    """
    result: dict[str, str] = {}
    if not content.startswith("---"):
        return result

    end = content.find("\n---", 3)
    if end <= 0:
        return result

    for raw_line in content[3:end].splitlines():
        line = raw_line.strip()
        if not line or ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()
        if value:
            result[key] = value

    return result


def _extract_task_body(content: str) -> str:
    """Extract the body content after frontmatter."""
    if not content.startswith("---"):
        return content

    end = content.find("\n---", 3)
    if end <= 0:
        return content

    # Skip past the closing --- and any leading newlines
    body_start = end + 4  # len("\n---")
    return content[body_start:].lstrip("\n")


def _task_file_to_entry(filepath: Path) -> TaskEntry:  # noqa: PLR0912, PLR0915
    """Convert a per-task .md file to a TaskEntry."""
    content = filepath.read_text()
    fm = _parse_task_frontmatter(content)
    body = _extract_task_body(content)

    # Extract title from body (first # heading)
    title = ""
    body_lines = body.splitlines()
    for line in body_lines:
        if line.startswith("# "):
            title = line[2:].strip()
            break

    # Extract description (text after heading, before ## sections)
    description_lines = []
    in_description = False
    for line in body_lines:
        if line.startswith("# ") and not in_description:
            in_description = True
            continue
        if in_description:
            if line.startswith("## "):
                break
            description_lines.append(line)

    description = "\n".join(description_lines).strip()

    # Extract sub-sections
    context = None
    files: list[str] = []
    dependencies: list[str] = []

    current_section = None
    section_lines: list[str] = []
    for line in body_lines:
        if line.startswith("## "):
            if current_section == "Context":
                context = "\n".join(section_lines).strip()
            elif current_section == "Files":
                for raw_sl in section_lines:
                    val = raw_sl.strip()
                    if val.startswith("- "):
                        val = val[2:].strip()
                    val = val.strip("`")
                    if val:
                        files.append(val)
            elif current_section == "Dependencies":
                for raw_sl in section_lines:
                    val = raw_sl.strip()
                    if val.startswith("- "):
                        val = val[2:].strip()
                    if val:
                        dependencies.append(val)
            current_section = line[3:].strip()
            section_lines = []
        elif current_section:
            section_lines.append(line)

    # Handle last section
    if current_section == "Context":
        context = "\n".join(section_lines).strip()
    elif current_section == "Files":
        for raw_sl in section_lines:
            val = raw_sl.strip()
            if val.startswith("- "):
                val = val[2:].strip()
            val = val.strip("`")
            if val:
                files.append(val)
    elif current_section == "Dependencies":
        for raw_sl in section_lines:
            val = raw_sl.strip()
            if val.startswith("- "):
                val = val[2:].strip()
            if val:
                dependencies.append(val)

    # Parse role tags
    roles_str = fm.get("role", "")
    roles = [r.strip() for r in roles_str.split("+") if r.strip()]

    # Parse sprint metadata
    sprint_number = fm.get("sprint") or None
    sprint_date = fm.get("completed_date") or None

    # Use frontmatter priority, fall back to section-based inference
    priority = fm.get("priority")

    # Infer state from directory — files in completed/ are completed
    # regardless of what the frontmatter says
    if filepath.parent.name == "completed":
        state = "completed"
    else:
        state = fm.get("status", "pending")

    return TaskEntry(
        id=fm.get("id"),
        state=state,
        roles=roles,
        title=title,
        description=description,
        context=context,
        files=files,
        priority=priority,
        dependencies=dependencies,
        sprint_number=sprint_number,
        sprint_date=sprint_date,
        section=fm.get("section", ""),
        line_number=0,
        raw_lines=[],
    )


def _load_task_files() -> list[TaskEntry]:
    """Load all task entries from per-task files."""
    task_dir = _task_files_dir()
    entries: list[TaskEntry] = []

    for subdir in ["active", "completed"]:
        d = task_dir / subdir
        if not d.is_dir():
            continue
        for f in sorted(d.glob("*.md")):
            entries.append(_task_file_to_entry(f))

    return entries


def _write_task_file(  # noqa: PLR0912
    task: TaskEntry,
    dest_dir: Path,
    *,
    completed_summary: str = "",
    created: str = "",
) -> Path:
    """Write a TaskEntry as a per-task .md file.

    Returns the path of the written file.
    """
    slug = slug_from_title(task.title)
    filepath = dest_dir / f"{slug}.md"

    # Build frontmatter
    fm_lines = ["---"]
    if task.id:
        fm_lines.append(f"id: {task.id}")
    fm_lines.append(f"role: {'+'.join(task.roles) if task.roles else ''}")
    fm_lines.append(f"section: {task.section}")
    if task.priority:
        fm_lines.append(f"priority: {task.priority}")
    fm_lines.append(f"status: {task.state}")
    if task.sprint_number:
        fm_lines.append(f"sprint: {task.sprint_number}")
    else:
        fm_lines.append("sprint:")
    if task.sprint_date:
        fm_lines.append(f"completed_date: {task.sprint_date}")
    else:
        fm_lines.append("completed_date:")
    if completed_summary:
        fm_lines.append(f"completed_summary: {completed_summary}")
    else:
        fm_lines.append("completed_summary:")
    if created:
        fm_lines.append(f"created: {created}")
    else:
        fm_lines.append(f"created: {datetime.now(timezone.utc).strftime('%Y-%m-%d')}")
    fm_lines.append("---")

    # Build body
    body_lines = [f"# {task.title}", ""]
    if task.description:
        body_lines.append(task.description)
        body_lines.append("")

    if task.context:
        body_lines.append("## Context")
        body_lines.append("")
        body_lines.append(task.context)
        body_lines.append("")

    if task.files:
        body_lines.append("## Files")
        body_lines.append("")
        for f in task.files:
            body_lines.append(f"- `{f}`")
        body_lines.append("")

    if task.dependencies:
        body_lines.append("## Dependencies")
        body_lines.append("")
        for d in task.dependencies:
            body_lines.append(f"- {d}")
        body_lines.append("")

    content = "\n".join(fm_lines) + "\n\n" + "\n".join(body_lines)
    # Ensure single trailing newline
    content = content.rstrip("\n") + "\n"
    filepath.write_text(content)
    return filepath


# --- Section metadata ---


def _parse_sections_toml(filepath: Path) -> list[dict]:  # noqa: PLR0912
    """Parse _sections.toml into a list of section dicts.

    Lightweight TOML parser — only handles the [[sections]] array-of-tables
    format used by this project. No third-party dependency.
    """
    sections: list[dict] = []
    current: dict | None = None
    multiline_key: str | None = None
    multiline_lines: list[str] = []

    for line in filepath.read_text().splitlines():
        stripped = line.strip()

        # Inside a multi-line string
        if multiline_key is not None and current is not None:
            if stripped.endswith('"""'):
                multiline_lines.append(stripped[:-3])
                current[multiline_key] = "\n".join(multiline_lines).strip()
                multiline_key = None
                multiline_lines = []
            else:
                multiline_lines.append(line)
            continue

        if stripped == "[[sections]]":
            if current is not None:
                sections.append(current)
            current = {}
            continue

        if current is None or not stripped or stripped.startswith("#"):
            continue

        if "=" not in stripped:
            continue

        key, _, value = stripped.partition("=")
        key = key.strip()
        value = value.strip()

        if value.startswith('"""'):
            rest = value[3:]
            if rest.endswith('"""'):
                current[key] = rest[:-3]
            else:
                multiline_key = key
                multiline_lines = [rest]
        elif value.startswith('"') and value.endswith('"'):
            current[key] = value[1:-1]
        elif value.isdigit() or (value.startswith("-") and value[1:].isdigit()):
            current[key] = int(value)
        else:
            current[key] = value

    if current is not None:
        sections.append(current)

    return sections


def _load_meta(task_dir: Path) -> str:
    """Load the static header from _meta.md."""
    meta_path = task_dir / "_meta.md"
    if meta_path.exists():
        return meta_path.read_text()
    return ""


# --- Renderer ---


def _section_sort_key(section: dict) -> tuple[int, int]:
    """Sort key: priority bucket first, then sort_order."""
    priority_order = {"high": 0, "medium": 1, "low": 2}
    p = priority_order.get(section.get("priority", "medium"), 1)
    return (p, section.get("sort_order", 99))


def _render_task_line(task: TaskEntry) -> list[str]:
    """Render a single task as NEXT-STEPS.md formatted lines."""
    # Build the task line
    checkbox = "x" if task.state == "completed" else " "
    roles_part = f"[{'+'.join(task.roles)}] " if task.roles else ""
    id_part = f" {task.id}" if task.id else ""

    # Build description with sprint metadata for completed tasks
    desc = task.description
    if task.state == "completed" and task.sprint_number:
        sprint_meta = f"*(Sprint {task.sprint_number}"
        if task.sprint_date:
            sprint_meta += f", {task.sprint_date}"
        sprint_meta += ")*"
        if desc and not desc.startswith("*(Sprint"):
            desc = f"{sprint_meta} {desc}"
        elif not desc:
            desc = sprint_meta

    line = f"- [{checkbox}] **{roles_part}{task.title}**{id_part} — {desc}"
    lines = [line]

    # Add sub-fields for pending tasks
    if task.state != "completed":
        if task.context:
            lines.append(f"  - Context: {task.context}")
        if task.files:
            files_str = ", ".join(f"`{f}`" for f in task.files)
            lines.append(f"  - Files: {files_str}")
        if task.priority:
            lines.append(f"  - Priority: {task.priority}")
        if task.dependencies:
            lines.append(f"  - Dependencies: {', '.join(task.dependencies)}")

    return lines


def _priority_label(priority: str) -> str:
    """Map priority key to display label."""
    return {
        "high": "High Priority",
        "medium": "Medium Priority",
        "low": "Low Priority / Nice to Have",
    }.get(priority, priority)


def _render_section(
    section: dict,
    tasks_by_section: dict[str, list[TaskEntry]],
    rendered_section_ids: set[str],
    output_lines: list[str],
) -> None:
    """Render a single section with its tasks into output_lines.

    Skips sections with no tasks (removes heading/description if already added).
    """
    section_id = section["id"]
    section_tasks = tasks_by_section.get(section_id, [])

    if not section_tasks:
        return

    rendered_section_ids.add(section_id)
    title = section.get("title", section_id)
    sprint = section.get("sprint")

    heading = f"### {title}"
    if sprint:
        heading += f" *(Sprint {sprint})*"
    output_lines.append(heading)
    output_lines.append("")

    desc = section.get("description", "")
    if desc:
        for desc_line in desc.strip().splitlines():
            output_lines.append(f"> {desc_line}" if desc_line.strip() else ">")
        output_lines.append("")

    for task in section_tasks:
        output_lines.extend(_render_task_line(task))
        output_lines.append("")


def render_next_steps(task_dir: Path) -> str:  # noqa: PLR0912, PLR0915
    """Generate NEXT-STEPS.md content from per-task files.

    Reads _meta.md for the header, _sections.toml for section ordering,
    and active/*.md + completed/*.md for task content.
    """
    meta = _load_meta(task_dir)
    sections_toml = task_dir / "_sections.toml"
    sections = _parse_sections_toml(sections_toml) if sections_toml.exists() else []
    sections.sort(key=_section_sort_key)

    # Load all active tasks
    active_tasks: list[TaskEntry] = []
    active_dir = task_dir / "active"
    if active_dir.is_dir():
        for f in sorted(active_dir.glob("*.md")):
            active_tasks.append(_task_file_to_entry(f))

    # Load completed tasks (those in the recent Completed section, not archived)
    completed_tasks: list[TaskEntry] = []
    completed_dir = task_dir / "completed"
    if completed_dir.is_dir():
        for f in sorted(completed_dir.glob("*.md")):
            completed_tasks.append(_task_file_to_entry(f))

    # Group active tasks by section ID
    tasks_by_section: dict[str, list[TaskEntry]] = {}
    for task in active_tasks:
        section_id = task.section or "_unsectioned"
        tasks_by_section.setdefault(section_id, []).append(task)

    # Separate sections into parent-grouped and standalone
    parent_groups: dict[str, list[dict]] = {}
    standalone_sections: list[dict] = []
    for section in sections:
        parent = section.get("parent")
        if parent:
            parent_groups.setdefault(parent, []).append(section)
        else:
            standalone_sections.append(section)

    # Group standalone sections by priority
    sections_by_priority: dict[str, list[dict]] = {}
    for section in standalone_sections:
        p = section.get("priority", "medium")
        sections_by_priority.setdefault(p, []).append(section)

    rendered_section_ids: set[str] = set()
    output_lines: list[str] = []

    # Add meta header
    if meta:
        output_lines.append(meta.rstrip("\n"))
        output_lines.append("")

    # Render by priority group
    for priority in ["high", "medium", "low"]:
        priority_sections = sections_by_priority.get(priority, [])
        if not priority_sections:
            continue

        # Check if any sections in this priority actually have tasks
        has_tasks = any(tasks_by_section.get(s["id"]) for s in priority_sections)
        if not has_tasks:
            continue

        output_lines.append(f"## {_priority_label(priority)}")
        output_lines.append("")

        for section in priority_sections:
            _render_section(
                section, tasks_by_section, rendered_section_ids, output_lines
            )

    # Render parent-grouped sections (e.g., feature groups)
    for parent_id, child_sections in parent_groups.items():
        # Check if any child section has tasks
        has_tasks = any(tasks_by_section.get(s["id"]) for s in child_sections)
        if not has_tasks:
            continue

        # Use a readable title from the parent ID
        parent_title = parent_id.replace("-", " ").title()
        # Look for parent description in first child's context
        output_lines.append(f"## {parent_title}")
        output_lines.append("")

        for section in child_sections:
            _render_section(
                section, tasks_by_section, rendered_section_ids, output_lines
            )

    # Render unsectioned tasks
    unsectioned = tasks_by_section.get("_unsectioned", [])
    if unsectioned:
        output_lines.append("## Uncategorized")
        output_lines.append("")
        for task in unsectioned:
            output_lines.extend(_render_task_line(task))
            output_lines.append("")

    # Render sections not yet rendered
    for section_id, section_tasks in tasks_by_section.items():
        if section_id in rendered_section_ids or section_id == "_unsectioned":
            continue
        if not section_tasks:
            continue
        output_lines.append(f"## {section_id}")
        output_lines.append("")
        for task in section_tasks:
            output_lines.extend(_render_task_line(task))
            output_lines.append("")

    # Render completed section
    if completed_tasks:
        output_lines.append("## Completed")
        output_lines.append("")
        output_lines.append(
            "> Recently completed items are listed here by sprints. "
            "Periodically archived to [NEXT-STEPS-COMPLETED.md]"
            "(NEXT-STEPS-COMPLETED.md) via `/next-steps clean`."
        )
        output_lines.append("")

        # Group completed tasks by sprint
        by_sprint: dict[str, list[TaskEntry]] = {}
        for task in completed_tasks:
            sprint_key = task.sprint_number or "unsprinted"
            by_sprint.setdefault(sprint_key, []).append(task)

        # Sort sprints descending (newest first)
        for sprint_num in sorted(
            by_sprint.keys(), key=lambda s: (s == "unsprinted", s), reverse=True
        ):
            if sprint_num == "unsprinted":
                continue
            sprint_tasks = by_sprint[sprint_num]
            # Get date from first task
            sprint_date = next(
                (t.sprint_date for t in sprint_tasks if t.sprint_date), ""
            )
            heading = f"### Sprint {sprint_num}"
            if sprint_date:
                heading += f" ({sprint_date})"
            # Add a summary if there's a common theme
            output_lines.append(heading)
            output_lines.append("")
            for task in sprint_tasks:
                output_lines.extend(_render_task_line(task))
                output_lines.append("")

    result = "\n".join(output_lines)
    # Collapse 3+ consecutive blank lines into 2
    while "\n\n\n\n" in result:
        result = result.replace("\n\n\n\n", "\n\n\n")
    return result.rstrip("\n") + "\n"


# --- Splitter (migration) ---


def _infer_section_id(section_name: str) -> str:
    """Convert a section heading to a section ID slug."""
    # Strip sprint references and parenthetical annotations
    name = re.sub(r"\s*\*\(.*?\)\*\s*", "", section_name)
    name = re.sub(r"\s*\(.*?\)\s*", "", name)
    return slug_from_title(name.strip())


def _extract_section_description(lines: list[str], start: int) -> tuple[str, int]:
    """Extract blockquote description after a section heading.

    Skips blank lines between the heading and the blockquote.
    Returns (description_text, next_line_index).
    """
    desc_lines: list[str] = []
    i = start
    # Skip blank lines before blockquote
    while i < len(lines) and not lines[i].strip():
        i += 1
    while i < len(lines):
        line = lines[i]
        if line.startswith(">"):
            desc_lines.append(line[1:].strip() if len(line) > 1 else "")
            i += 1
        elif not line.strip() and desc_lines:
            # Blank line within blockquote — check if blockquote continues
            j = i + 1
            while j < len(lines) and not lines[j].strip():
                j += 1
            if j < len(lines) and lines[j].startswith(">"):
                desc_lines.append("")
                i += 1
            else:
                break
        else:
            break

    return "\n".join(desc_lines).strip(), i


def _infer_priority_from_section(
    section: str, subsection: str | None, _file_lines: list[str]
) -> str:
    """Infer priority from section context in NEXT-STEPS.md."""
    combined = f"{section} {subsection or ''}".lower()
    if "high priority" in combined or section.lower().startswith("high"):
        return "high"
    if "medium priority" in combined or section.lower().startswith("medium"):
        return "medium"
    if "low priority" in combined or section.lower().startswith("low"):
        return "low"

    if "future" in combined or "deferred" in combined:
        return "low"

    return "medium"


def split_next_steps(  # noqa: PLR0912, PLR0915
    filepath: Path, task_dir: Path, *, dry_run: bool = False
) -> list[str]:
    """Split NEXT-STEPS.md into per-task files.

    Creates next-steps/active/ and next-steps/completed/ directories
    with individual .md files for each task.

    Returns list of actions taken.
    """
    actions: list[str] = []
    lines = filepath.read_text().splitlines()

    # Parse the meta header (everything before ## High Priority)
    meta_lines: list[str] = []
    first_priority_line = 0
    for i, line in enumerate(lines):
        if re.match(r"^## (High Priority|Medium Priority|Low Priority)", line):
            first_priority_line = i
            break
        # Also check for non-standard top-level ## sections that contain tasks
        if re.match(r"^## ", line) and i > 0:
            # Check if this section or a later one has tasks
            has_tasks = any(TASK_RE.match(ln) for ln in lines[i:])
            if has_tasks:
                first_priority_line = i
                break
        meta_lines.append(line)

    # Extract section descriptions and build _sections.toml entries
    section_configs: list[dict] = []
    current_priority = "medium"
    sort_order = 0
    seen_sections: set[str] = set()

    # Track which sections contain tasks (only create section configs for those)
    task_sections: set[str] = set()
    temp_tasks = parse_tasks(filepath)
    for t in temp_tasks:
        if t.subsection:
            task_sections.add(_infer_section_id(t.subsection))
        elif t.section:
            task_sections.add(_infer_section_id(t.section))

    for i, line in enumerate(lines[first_priority_line:], start=first_priority_line):
        section_match = SECTION_RE.match(line)
        if not section_match:
            continue
        level = len(section_match.group(1))
        heading = section_match.group(2).strip()

        if level == 2:
            # Determine priority from the ## heading
            if "high" in heading.lower():
                current_priority = "high"
            elif "medium" in heading.lower():
                current_priority = "medium"
            elif "low" in heading.lower():
                current_priority = "low"
            elif heading in (
                "Completed",
                "Deferred",
                "Dropped",
                "Future Considerations",
            ):
                current_priority = "none"  # Skip these for sections
        elif level == 3:
            section_id = _infer_section_id(heading)

            if (
                current_priority == "none"
                or section_id in seen_sections
                or heading.startswith("Sprint ")
            ):
                continue

            seen_sections.add(section_id)

            # Look ahead for blockquote description
            desc, _end = _extract_section_description(lines, i + 1)

            # Extract sprint reference from heading
            sprint_match = re.search(r"\*\(Sprint\s+(\S+)\)\*", heading)
            sprint = sprint_match.group(1) if sprint_match else ""

            # Only create section config if it has tasks
            if section_id in task_sections:
                sort_order += 1
                section_configs.append(
                    {
                        "id": section_id,
                        "title": re.sub(r"\s*\*\(.*?\)\*", "", heading).strip(),
                        "priority": current_priority,
                        "sprint": sprint,
                        "sort_order": sort_order,
                        "description": desc,
                    }
                )

    # Parse all tasks
    tasks = parse_tasks(filepath)

    if not dry_run:
        # Create directories
        active_dir = task_dir / "active"
        completed_dir = task_dir / "completed"
        active_dir.mkdir(parents=True, exist_ok=True)
        completed_dir.mkdir(parents=True, exist_ok=True)

        # Write _meta.md
        meta_content = "\n".join(meta_lines).rstrip("\n") + "\n"
        (task_dir / "_meta.md").write_text(meta_content)
        actions.append("Created _meta.md")

        # Write _sections.toml
        toml_lines: list[str] = []
        for sc in section_configs:
            toml_lines.append("[[sections]]")
            toml_lines.append(f'id = "{sc["id"]}"')
            toml_lines.append(f'title = "{sc["title"]}"')
            toml_lines.append(f'priority = "{sc["priority"]}"')
            if sc.get("sprint"):
                toml_lines.append(f'sprint = "{sc["sprint"]}"')
            toml_lines.append(f"sort_order = {sc['sort_order']}")
            if sc.get("description"):
                toml_lines.append(f'description = """{sc["description"]}"""')
            toml_lines.append("")
        (task_dir / "_sections.toml").write_text("\n".join(toml_lines))
        actions.append(f"Created _sections.toml with {len(section_configs)} sections")

    # Determine section ID for each task
    for task in tasks:
        # Map the task's subsection or section to a section ID
        if task.subsection:
            task.section = _infer_section_id(task.subsection)
        elif task.section:
            task.section = _infer_section_id(task.section)

        # Infer priority if not set
        if not task.priority:
            task.priority = _infer_priority_from_section(
                task.section, task.subsection, lines
            )

    # Write task files (deduplicate by slug — same task may appear
    # in its original section AND in ## Completed)
    seen_slugs: set[str] = set()
    for task in tasks:
        slug = slug_from_title(task.title)
        if slug in seen_slugs:
            continue
        seen_slugs.add(slug)

        dest = task_dir / ("completed" if task.state == "completed" else "active")

        if not dry_run:
            # Extract completed_summary from description for completed tasks
            completed_summary = ""
            if task.state == "completed":
                # Strip sprint metadata to get the summary
                desc = task.description
                sprint_stripped = SPRINT_RE.sub("", desc).strip()
                completed_summary = sprint_stripped

            _write_task_file(
                task,
                dest,
                completed_summary=completed_summary,
            )

        subdir = "completed" if task.state == "completed" else "active"
        actions.append(f"  {subdir}/{slug}.md")

    deduped_count = len(seen_slugs)
    active_count = sum(
        1
        for t in tasks
        if t.state == "pending" and slug_from_title(t.title) in seen_slugs
    )
    completed_count = deduped_count - active_count
    actions.insert(
        0,
        f"Split {deduped_count} tasks ({active_count} active, {completed_count} completed)",
    )
    return actions


def create_task_file(
    task_dir: Path,
    *,
    title: str,
    role: str,
    section: str,
    priority: str = "medium",
    description: str = "",
    context: str = "",
    files: list[str] | None = None,
    dependencies: list[str] | None = None,
) -> Path:
    """Create a new task file in active/.

    Assigns the next available T### ID.
    """
    # Determine next ID
    main_root = find_main_repo_root()
    index_path = main_root / ".tasks.json"
    next_id = 1
    if index_path.exists():
        try:
            data = json.loads(index_path.read_text())
            next_id = data.get("next_id", 1)
        except (json.JSONDecodeError, OSError):
            pass

    # Also scan existing task files for highest ID
    for subdir in ["active", "completed"]:
        d = task_dir / subdir
        if not d.is_dir():
            continue
        for f in d.glob("*.md"):
            content = f.read_text()
            fm = _parse_task_frontmatter(content)
            tid = fm.get("id", "")
            if tid.startswith("T") and tid[1:].isdigit():
                num = int(tid[1:])
                if num >= next_id:
                    next_id = num + 1

    task_id = f"T{next_id:03d}"

    roles = [r.strip() for r in role.split("+") if r.strip()]

    task = TaskEntry(
        id=task_id,
        state="pending",
        roles=roles,
        title=title,
        description=description,
        context=context,
        files=files or [],
        priority=priority,
        dependencies=dependencies or [],
        section=section,
    )

    active_dir = task_dir / "active"
    active_dir.mkdir(parents=True, exist_ok=True)
    filepath = _write_task_file(task, active_dir)

    # Update next_id counter
    index_data = {}
    if index_path.exists():
        with contextlib.suppress(json.JSONDecodeError, OSError):
            index_data = json.loads(index_path.read_text())
    index_data["next_id"] = next_id + 1
    index_path.write_text(json.dumps(index_data, indent=2) + "\n")

    return filepath


def complete_task_file(
    task_dir: Path,
    slug: str,
    *,
    sprint: str,
    summary: str = "",
    completed_date: str = "",
) -> Path | None:
    """Mark a task complete and move it from active/ to completed/.

    Returns the new filepath, or None if not found.
    """
    active_dir = task_dir / "active"
    completed_dir = task_dir / "completed"
    completed_dir.mkdir(parents=True, exist_ok=True)

    source = active_dir / f"{slug}.md"
    if not source.exists():
        return None

    content = source.read_text()
    fm = _parse_task_frontmatter(content)
    body = _extract_task_body(content)

    if not completed_date:
        completed_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    # Rebuild frontmatter with completion data
    fm["status"] = "completed"
    fm["sprint"] = sprint
    fm["completed_date"] = completed_date
    if summary:
        fm["completed_summary"] = summary

    # Reconstruct file
    fm_lines = ["---"]
    for key in _FRONTMATTER_FIELDS:
        value = fm.get(key, "")
        fm_lines.append(f"{key}: {value}")
    fm_lines.append("---")

    new_content = "\n".join(fm_lines) + "\n\n" + body
    new_content = new_content.rstrip("\n") + "\n"

    dest = completed_dir / f"{slug}.md"
    dest.write_text(new_content)
    source.unlink()

    return dest


# --- CLI ---


def _load_tasks(args: argparse.Namespace) -> list[TaskEntry]:
    """Load tasks from per-task files or NEXT-STEPS.md (auto-detect).

    If the user explicitly specified a file via -f, use that file directly.
    Otherwise, check for per-task files first and fall back to NEXT-STEPS.md.
    """
    filepath = Path(args.file)
    default_path = find_repo_root() / "NEXT-STEPS.md"
    # If -f was explicitly specified (path differs from default), use the file directly
    if filepath.resolve() != default_path.resolve():
        return parse_tasks(filepath)
    # Auto-detect: prefer per-task files if they exist
    if _has_task_files():
        return _load_task_files()
    return parse_tasks(filepath)


def cmd_parse(args: argparse.Namespace) -> None:
    """Parse tasks and output JSON."""
    tasks = _load_tasks(args)
    output = [_task_to_dict(t) for t in tasks]
    print(json.dumps(output, indent=2))


def cmd_validate(args: argparse.Namespace) -> None:
    """Validate task format compliance."""
    tasks = _load_tasks(args)
    report = validate_tasks(tasks)

    # Print report
    print("=" * 50)
    print("        TASK FORMAT VALIDATION")
    print("=" * 50)
    print()
    print(
        f"Tasks: {report.task_count} total "
        f"({report.pending_count} pending, "
        f"{report.completed_count} completed)"
    )
    print(f"Score: {report.score}/100")
    print()

    if not report.issues:
        print("No issues found.")
        return

    print("-" * 50)
    print("ISSUES")
    print("-" * 50)

    for issue in sorted(
        report.issues,
        key=lambda i: (
            {"error": 0, "warning": 1, "info": 2}[i.severity],
            i.line_number,
        ),
    ):
        icon = {"error": "E", "warning": "W", "info": "I"}[issue.severity]
        fix = " [fixable]" if issue.fix_available else ""
        print(f"  {icon} L{issue.line_number} [{issue.category}] {issue.message}{fix}")

    print()
    errors = sum(1 for i in report.issues if i.severity == "error")
    warnings = sum(1 for i in report.issues if i.severity == "warning")
    infos = sum(1 for i in report.issues if i.severity == "info")
    print(f"Summary: {errors} errors, {warnings} warnings, {infos} info")

    if errors > 0:
        sys.exit(1)


def cmd_normalize(args: argparse.Namespace) -> None:
    """Normalize NEXT-STEPS.md formatting."""
    filepath = Path(args.file)
    changes = normalize_file(filepath, dry_run=args.dry_run)

    if not changes:
        print("No changes needed.")
        return

    for change in changes:
        print(f"  {change}")

    if args.dry_run:
        print(f"\n{len(changes)} changes would be made (dry run).")
    else:
        print(f"\n{len(changes)} changes applied.")


def cmd_index(args: argparse.Namespace) -> None:
    """Generate .tasks.json sidecar."""
    filepath = Path(args.file)
    index = generate_index(filepath)
    main_root = find_main_repo_root()
    index_path = main_root / ".tasks.json"
    print(f"Index written to {index_path}")
    print(
        f"  Tasks: {index['task_count']} "
        f"({index['pending_count']} pending, "
        f"{index['completed_count']} completed)"
    )
    print(f"  Next ID: T{index['next_id']:03d}")


def cmd_assign_ids(args: argparse.Namespace) -> None:
    """Assign T### IDs to tasks that lack them."""
    filepath = Path(args.file)
    changes = assign_ids(filepath, dry_run=args.dry_run)

    if not changes:
        print("All tasks already have IDs.")
        return

    for change in changes:
        print(f"  {change}")

    if args.dry_run:
        print(f"\n{len(changes)} IDs would be assigned (dry run).")
    else:
        print(f"\n{len(changes)} IDs assigned.")


def cmd_lookup(args: argparse.Namespace) -> None:
    """Look up a task by ID or title substring."""
    tasks = _load_tasks(args)

    # Try exact ID match first
    if re.match(r"^T\d{3,}$", args.query):
        matches = [t for t in tasks if t.id == args.query]
    else:
        query_lower = args.query.lower()
        matches = [t for t in tasks if query_lower in t.title.lower()]

    if not matches:
        print(f"No task found matching '{args.query}'", file=sys.stderr)
        sys.exit(1)

    if len(matches) > 1:
        print(
            f"Warning: {len(matches)} tasks match '{args.query}', returning first match",
            file=sys.stderr,
        )

    result = _task_to_dict(matches[0])
    print(json.dumps(result, indent=2))


def cmd_review_freshness(args: argparse.Namespace) -> None:
    """Check staleness of .claude/reviews/ files."""
    repo_root = find_repo_root()
    results = check_review_freshness(repo_root)

    if not results:
        print("No reviews found in .claude/reviews/")
        return

    print("=" * 50)
    print("      REVIEW FRESHNESS CHECK")
    print("=" * 50)
    print()

    for r in results:
        icon = {"fresh": "+", "stale": "~", "orphaned": "?"}[r["status"]]
        task_id = r.get("task_id", "???")
        title = r.get("task_title", r["file"])
        print(f"  {icon} {task_id} {title} [{r['status']}]")

        if r["stale_files"]:
            for sf in r["stale_files"]:
                print(f"      {sf['file']}: {sf['reason']}")

    print()
    fresh = sum(1 for r in results if r["status"] == "fresh")
    stale = sum(1 for r in results if r["status"] == "stale")
    orphaned = sum(1 for r in results if r["status"] == "orphaned")
    print(f"Summary: {fresh} fresh, {stale} stale, {orphaned} orphaned")

    if args.json:
        print()
        print(json.dumps(results, indent=2))


def cmd_list_unreviewed(args: argparse.Namespace) -> None:
    """List pending tasks without review artifacts."""
    repo_root = find_repo_root()

    if _has_task_files():
        # Use task files directly
        tasks = _load_task_files()
        main_root = find_main_repo_root()
        reviews_dir = main_root / ".claude" / "reviews"
        reviewed_dir = main_root / ".claude" / "work-queue" / "reviewed"

        priority_order = {"high": 0, "medium": 1, "low": 2}
        pending = [t for t in tasks if t.state == "pending"]
        pending.sort(key=lambda t: priority_order.get((t.priority or "low").lower(), 2))

        unreviewed = []
        for task in pending:
            slug = slug_from_title(task.title)
            review_path = reviews_dir / f"{slug}.md"
            reviewed_marker = reviewed_dir / f"{slug}.json"
            if not review_path.exists() and not reviewed_marker.exists():
                unreviewed.append(_task_to_dict(task))
                if len(unreviewed) >= args.limit:
                    break

        if not unreviewed:
            print("No unreviewed tasks found.")
            return
        print(json.dumps(unreviewed, indent=2))
    else:
        results = list_unreviewed_tasks(repo_root, limit=args.limit)
        if not results:
            print("No unreviewed tasks found.")
            return
        print(json.dumps(results, indent=2))


def cmd_stats(args: argparse.Namespace) -> None:
    """Print summary statistics."""
    tasks = _load_tasks(args)
    stats = compute_stats(tasks)

    print("=" * 50)
    print("        TASK STATISTICS")
    print("=" * 50)
    print()
    print(f"Total:     {stats['total']}")
    print(f"Pending:   {stats['pending']}")
    print(f"Completed: {stats['completed']}")
    print(f"With IDs:  {stats['with_ids']}")
    print(f"No ID:     {stats['without_ids']}")
    print()

    if stats["by_section"]:
        print("By Section:")
        for section, count in stats["by_section"].items():
            print(f"  {section}: {count}")
        print()

    if stats["by_role"]:
        print("By Role:")
        for role, count in stats["by_role"].items():
            print(f"  {role}: {count}")
        print()

    if stats["by_priority"]:
        print("By Priority:")
        for priority, count in stats["by_priority"].items():
            print(f"  {priority}: {count}")

    if args.json:
        print()
        print(json.dumps(stats, indent=2))


def cmd_render(args: argparse.Namespace) -> None:
    """Generate NEXT-STEPS.md from per-task files."""
    task_dir = _task_files_dir()
    if not task_dir.is_dir():
        print(
            "Error: next-steps/ directory not found. Run 'split' first.",
            file=sys.stderr,
        )
        sys.exit(1)

    content = render_next_steps(task_dir)
    repo_root = find_repo_root()
    out_path = repo_root / "NEXT-STEPS.md"

    if args.check:
        # Compare generated content with committed file
        if out_path.exists():
            existing = out_path.read_text()
            if existing == content:
                print("NEXT-STEPS.md is up to date.")
            else:
                print(
                    "NEXT-STEPS.md is out of date. Run 'scripts/task-format.py render' to regenerate.",
                    file=sys.stderr,
                )
                sys.exit(1)
        else:
            print("NEXT-STEPS.md does not exist.", file=sys.stderr)
            sys.exit(1)
        return

    out_path.write_text(content)
    pending = content.count("- [ ] **")
    completed = content.count("- [x] **")
    print(f"Generated NEXT-STEPS.md ({pending} pending, {completed} completed)")


def cmd_split(args: argparse.Namespace) -> None:
    """Split NEXT-STEPS.md into per-task files."""
    filepath = Path(args.file)
    task_dir = _task_files_dir()

    if task_dir.is_dir() and not args.force:
        print(
            f"Error: {task_dir} already exists. Use --force to overwrite.",
            file=sys.stderr,
        )
        sys.exit(1)

    actions = split_next_steps(filepath, task_dir, dry_run=args.dry_run)

    for action in actions:
        print(action)

    if args.dry_run:
        print("\nDry run — no files written.")
    else:
        print(f"\nTask files written to {task_dir}/")


def cmd_create_task(args: argparse.Namespace) -> None:
    """Create a new task file."""
    task_dir = _task_files_dir()
    if not task_dir.is_dir():
        print(
            "Error: next-steps/ directory not found. Run 'split' first.",
            file=sys.stderr,
        )
        sys.exit(1)

    filepath = create_task_file(
        task_dir,
        title=args.title,
        role=args.role,
        section=args.section,
        priority=args.priority,
        description=args.body or "",
        context=args.context or "",
        files=args.files.split(",") if args.files else None,
        dependencies=args.deps.split(",") if args.deps else None,
    )
    print(f"Created {filepath.relative_to(find_repo_root())}")


def cmd_complete_task(args: argparse.Namespace) -> None:
    """Mark a task as complete and move to completed/."""
    task_dir = _task_files_dir()
    if not task_dir.is_dir():
        print(
            "Error: next-steps/ directory not found. Run 'split' first.",
            file=sys.stderr,
        )
        sys.exit(1)

    result = complete_task_file(
        task_dir,
        args.slug,
        sprint=args.sprint,
        summary=args.summary or "",
        completed_date=args.date or "",
    )

    if result is None:
        print(
            f"Error: No active task file found for slug '{args.slug}'", file=sys.stderr
        )
        sys.exit(1)

    print(f"Completed: {result.relative_to(find_repo_root())}")


def main() -> None:
    """Entry point."""
    parser = argparse.ArgumentParser(
        description="Task format tooling for NEXT-STEPS.md",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )

    # Global args
    parser.add_argument(
        "--file",
        "-f",
        default="NEXT-STEPS.md",
        help="Path to NEXT-STEPS.md (default: NEXT-STEPS.md)",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    # parse
    subparsers.add_parser("parse", help="Parse NEXT-STEPS.md → JSON")

    # validate
    subparsers.add_parser("validate", help="Format compliance report")

    # normalize
    norm_parser = subparsers.add_parser("normalize", help="Fix formatting in-place")
    norm_parser.add_argument(
        "--dry-run", action="store_true", help="Show changes without applying"
    )

    # index
    subparsers.add_parser("index", help="Generate .tasks.json sidecar")

    # assign-ids
    aid_parser = subparsers.add_parser(
        "assign-ids", help="Add T### IDs to tasks that lack them"
    )
    aid_parser.add_argument(
        "--dry-run", action="store_true", help="Show changes without applying"
    )

    # lookup
    lookup_parser = subparsers.add_parser(
        "lookup", help="Print task details by ID or title"
    )
    lookup_parser.add_argument("query", help="Task ID (T047) or title substring")

    # review-freshness
    rf_parser = subparsers.add_parser(
        "review-freshness", help="Check staleness of .claude/reviews/"
    )
    rf_parser.add_argument("--json", action="store_true", help="Also output JSON")

    # list-unreviewed
    lu_parser = subparsers.add_parser(
        "list-unreviewed", help="List pending tasks without reviews"
    )
    lu_parser.add_argument(
        "--limit",
        type=int,
        default=1,
        help="Max number of unreviewed tasks to return (default: 1)",
    )

    # stats
    stats_parser = subparsers.add_parser("stats", help="Summary statistics")
    stats_parser.add_argument("--json", action="store_true", help="Also output JSON")

    # render
    render_parser = subparsers.add_parser(
        "render", help="Generate NEXT-STEPS.md from per-task files"
    )
    render_parser.add_argument(
        "--check",
        action="store_true",
        help="Check if NEXT-STEPS.md is up to date (exit 1 if not)",
    )

    # split
    split_parser = subparsers.add_parser(
        "split", help="Migrate NEXT-STEPS.md → per-task files"
    )
    split_parser.add_argument(
        "--dry-run", action="store_true", help="Show what would be created"
    )
    split_parser.add_argument(
        "--force", action="store_true", help="Overwrite existing next-steps/ directory"
    )

    # create-task
    ct_parser = subparsers.add_parser(
        "create-task", help="Create a new task file in active/"
    )
    ct_parser.add_argument("--title", required=True, help="Task title")
    ct_parser.add_argument(
        "--role", required=True, help="Role tag (e.g. dev, docs+test)"
    )
    ct_parser.add_argument("--section", required=True, help="Section ID")
    ct_parser.add_argument(
        "--priority", default="medium", help="Priority (high/medium/low)"
    )
    ct_parser.add_argument("--body", help="Task description")
    ct_parser.add_argument("--context", help="Context/reason for the task")
    ct_parser.add_argument("--files", help="Comma-separated file paths")
    ct_parser.add_argument(
        "--deps", help="Comma-separated dependency task titles or IDs"
    )

    # complete-task
    cpt_parser = subparsers.add_parser(
        "complete-task", help="Mark a task complete (move to completed/)"
    )
    cpt_parser.add_argument("slug", help="Task slug (filename without .md)")
    cpt_parser.add_argument("--sprint", required=True, help="Sprint number")
    cpt_parser.add_argument("--summary", help="Completion summary")
    cpt_parser.add_argument("--date", help="Completion date (default: today)")

    args = parser.parse_args()

    commands = {
        "parse": cmd_parse,
        "validate": cmd_validate,
        "normalize": cmd_normalize,
        "index": cmd_index,
        "assign-ids": cmd_assign_ids,
        "lookup": cmd_lookup,
        "review-freshness": cmd_review_freshness,
        "list-unreviewed": cmd_list_unreviewed,
        "stats": cmd_stats,
        "render": cmd_render,
        "split": cmd_split,
        "create-task": cmd_create_task,
        "complete-task": cmd_complete_task,
    }

    commands[args.command](args)


if __name__ == "__main__":
    main()
