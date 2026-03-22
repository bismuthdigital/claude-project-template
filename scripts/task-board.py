#!/usr/bin/env python3
"""Task board — unified view of pending tasks, claims, and in-flight PRs.

Aggregates data from task files, the work queue, and GitHub PRs to show
the full state of the task backlog. Useful for planning, directing agent
claims, and understanding what's available.

Usage:
    scripts/task-board.py                    # Full board, grouped by section
    scripts/task-board.py --role dev          # Filter to dev tasks
    scripts/task-board.py --available-only   # Only claimable tasks
    scripts/task-board.py --clusters         # Show file-overlap clusters
    scripts/task-board.py --json             # Machine-readable output
    scripts/task-board.py --group-by role    # Group by role instead of section
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

# ---------------------------------------------------------------------------
# Import task-format.py as a module (it has a hyphen in the name)
# ---------------------------------------------------------------------------

_SCRIPTS_DIR = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location(
    "task_format", _SCRIPTS_DIR / "task-format.py"
)
assert _spec and _spec.loader
task_format = importlib.util.module_from_spec(_spec)
sys.modules["task_format"] = (
    task_format  # Register before exec to fix dataclass resolution
)
_spec.loader.exec_module(task_format)

TaskEntry = task_format.TaskEntry
slug_from_title = task_format.slug_from_title

# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------


@dataclass
class ClaimInfo:
    worktree: str
    state: str  # "claimed" or "shipped"
    age_minutes: int
    expired: bool
    pr_number: int | None = None


@dataclass
class BoardTask:
    slug: str
    id: str | None
    title: str
    roles: list[str]
    section: str
    priority: str | None
    status: str  # available, claimed, shipped, in-flight, blocked, expired-claim
    files: list[str]
    dependencies: list[str]
    blocked_by: list[str]
    claim: ClaimInfo | None = None
    cluster_id: int | None = None


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------


def load_tasks() -> list[TaskEntry]:
    """Load pending tasks from per-task files."""
    all_tasks = task_format._load_task_files()
    return [t for t in all_tasks if t.state == "pending"]


def load_completed_ids() -> set[str]:
    """Load IDs/titles of completed tasks for dependency resolution."""
    all_tasks = task_format._load_task_files()
    ids: set[str] = set()
    for t in all_tasks:
        if t.state == "completed":
            if t.id:
                ids.add(t.id)
            ids.add(t.title)
            ids.add(slug_from_title(t.title))
            if t.source_path:
                ids.add(t.source_path.stem)
    return ids


def load_sections() -> dict[str, dict]:
    """Load section metadata from _sections.toml."""
    sections_path = task_format.find_repo_root() / "next-steps" / "_sections.toml"
    if not sections_path.exists():
        return {}
    raw = task_format._parse_sections_toml(sections_path)
    return {s["id"]: s for s in raw if "id" in s}


@dataclass
class RefreshResult:
    refreshed: list[dict]
    stale: list[dict]
    orphaned: list[dict]


def refresh_active_claims() -> RefreshResult | None:
    """Refresh near-expired claims whose worktree shows recent activity."""
    try:
        result = subprocess.run(
            [str(_SCRIPTS_DIR / "work-queue.sh"), "refresh-active"],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        if result.returncode != 0:
            return None
        data = json.loads(result.stdout)
        return RefreshResult(
            refreshed=data.get("refreshed", []),
            stale=data.get("stale", []),
            orphaned=data.get("orphaned", []),
        )
    except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
        return None


def load_claims() -> dict[str, ClaimInfo]:
    """Load work queue claims via work-queue.sh list."""
    try:
        result = subprocess.run(
            [str(_SCRIPTS_DIR / "work-queue.sh"), "list"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        if result.returncode != 0:
            return {}
        data = json.loads(result.stdout)
        claims: dict[str, ClaimInfo] = {}
        for c in data.get("claims", []):
            claims[c["task_slug"]] = ClaimInfo(
                worktree=c.get("agent_worktree", ""),
                state=c.get("state", "claimed"),
                age_minutes=c.get("age_minutes", 0),
                expired=c.get("expired", False),
                pr_number=c.get("pr_number"),
            )
        return claims
    except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
        return {}


def load_inflight() -> set[str]:
    """Load task titles completed in open PRs."""
    try:
        result = subprocess.run(
            [str(_SCRIPTS_DIR / "work-queue.sh"), "inflight-tasks"],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        if result.returncode != 0:
            return set()
        titles = json.loads(result.stdout)
        return set(titles) if isinstance(titles, list) else set()
    except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
        return set()


# ---------------------------------------------------------------------------
# Status resolution
# ---------------------------------------------------------------------------


def _build_pending_id_map(tasks: list[TaskEntry]) -> dict[str, str]:
    """Build a map from title/slug to task ID for pending tasks."""
    id_map: dict[str, str] = {}
    for t in tasks:
        if t.id:
            id_map[t.title] = t.id
            id_map[slug_from_title(t.title)] = t.id
    return id_map


def resolve_tasks(  # noqa: PLR0912
    tasks: list[TaskEntry],
    claims: dict[str, ClaimInfo],
    inflight: set[str],
    completed_ids: set[str],
) -> list[BoardTask]:
    """Assign a status to each pending task."""
    pending_id_map = _build_pending_id_map(tasks)
    board: list[BoardTask] = []
    for t in tasks:
        slug = slug_from_title(t.title)

        # Resolve blocked dependencies
        blocked_by: list[str] = []
        for dep in t.dependencies:
            # Skip non-dependency lines (comments in the Dependencies section)
            dep_lower = dep.lower().strip()
            if dep_lower.startswith("no dependency") or dep_lower.startswith("none"):
                continue
            # Strip trailing description after em dash or double dash
            dep_key = dep.split(" — ")[0].split(" -- ")[0].strip()
            # Strip trailing parenthetical annotations like (M1.1), (M2.1)
            dep_key = re.sub(r"\s*\([^)]*\)\s*$", "", dep_key)
            # Check if dependency is satisfied (by ID, title, slug, or filename)
            if dep_key not in completed_ids and dep_key not in inflight:
                # Resolve to task ID for display (check title and slug)
                dep_slug = slug_from_title(dep_key)
                resolved_id = pending_id_map.get(dep_key) or pending_id_map.get(
                    dep_slug
                )
                if resolved_id:
                    blocked_by.append(resolved_id)
                else:
                    blocked_by.append(dep)

        # Status priority: in-flight > shipped > claimed > expired > blocked > available
        claim = claims.get(slug)
        if t.title in inflight:
            status = "in-flight"
        elif claim and claim.state == "shipped" and not claim.expired:
            status = "shipped"
        elif claim and claim.state == "claimed" and not claim.expired:
            status = "claimed"
        elif claim and claim.expired:
            status = "expired-claim"
        elif blocked_by:
            status = "blocked"
        else:
            status = "available"

        claim_info = None
        if claim:
            claim_info = claim

        board.append(
            BoardTask(
                slug=slug,
                id=t.id,
                title=t.title,
                roles=t.roles,
                section=t.section,
                priority=t.priority,
                status=status,
                files=t.files,
                dependencies=t.dependencies,
                blocked_by=blocked_by,
                claim=claim_info,
            )
        )
    return board


# ---------------------------------------------------------------------------
# Cluster computation (union-find)
# ---------------------------------------------------------------------------


class UnionFind:
    def __init__(self) -> None:
        self.parent: dict[str, str] = {}

    def find(self, x: str) -> str:
        if x not in self.parent:
            self.parent[x] = x
        while self.parent[x] != x:
            self.parent[x] = self.parent[self.parent[x]]
            x = self.parent[x]
        return x

    def union(self, x: str, y: str) -> None:
        self.parent[self.find(x)] = self.find(y)


def _dirs_for_files(files: list[str]) -> set[str]:
    """Extract parent directories from file paths."""
    dirs: set[str] = set()
    for f in files:
        p = Path(f)
        # If path ends with /, it's already a directory
        if f.endswith("/"):
            dirs.add(f.rstrip("/"))
        else:
            parent = str(p.parent)
            if parent != ".":
                dirs.add(parent)
    return dirs


def compute_clusters(board: list[BoardTask]) -> list[dict]:  # noqa: PLR0912
    """Group tasks by shared files/directories."""
    # Map each file/dir to list of task slugs that reference it
    resource_to_slugs: dict[str, list[str]] = defaultdict(list)

    for bt in board:
        for f in bt.files:
            resource_to_slugs[f].append(bt.slug)
        for d in _dirs_for_files(bt.files):
            resource_to_slugs[d].append(bt.slug)

    # Build union-find from shared resources
    uf = UnionFind()
    for slugs in resource_to_slugs.values():
        if len(slugs) > 1:
            for s in slugs[1:]:
                uf.union(slugs[0], s)

    # Ensure all tasks with files are in the UF
    for bt in board:
        if bt.files:
            uf.find(bt.slug)

    # Group by root
    groups: dict[str, list[str]] = defaultdict(list)
    for bt in board:
        if bt.files:
            root = uf.find(bt.slug)
            groups[root].append(bt.slug)

    slug_to_task = {bt.slug: bt for bt in board}
    clusters: list[dict] = []
    cluster_id = 1

    for _root, slugs in sorted(groups.items(), key=lambda x: -len(x[1])):
        tasks_in_cluster = [slug_to_task[s] for s in slugs]
        all_files: set[str] = set()
        all_dirs: set[str] = set()
        all_roles: set[str] = set()
        available = 0
        best_priority = "low"
        priority_rank = {"high": 0, "medium": 1, "low": 2}

        for bt in tasks_in_cluster:
            all_files.update(bt.files)
            all_dirs.update(_dirs_for_files(bt.files))
            all_roles.update(bt.roles)
            if bt.status == "available":
                available += 1
            if bt.priority and priority_rank.get(bt.priority, 2) < priority_rank.get(
                best_priority, 2
            ):
                best_priority = bt.priority

        # Assign cluster_id to tasks
        for bt in tasks_in_cluster:
            bt.cluster_id = cluster_id

        clusters.append(
            {
                "id": cluster_id,
                "dirs": sorted(all_dirs),
                "files": sorted(all_files),
                "task_count": len(slugs),
                "available_count": available,
                "priority": best_priority,
                "roles": sorted(all_roles),
                "task_slugs": sorted(slugs),
            }
        )
        cluster_id += 1

    # Sort: available count desc, then priority, then size
    clusters.sort(
        key=lambda c: (
            -c["available_count"],
            priority_rank.get(c["priority"], 2),
            -c["task_count"],
        )
    )
    # Re-number after sort
    for i, c in enumerate(clusters, 1):
        old_id = c["id"]
        c["id"] = i
        for bt in board:
            if bt.cluster_id == old_id:
                bt.cluster_id = i

    return clusters


# ---------------------------------------------------------------------------
# Summary statistics
# ---------------------------------------------------------------------------


def compute_summary(board: list[BoardTask], _sections: dict[str, dict]) -> dict:
    """Compute aggregate statistics."""
    by_role: dict[str, dict[str, int]] = defaultdict(
        lambda: {"total": 0, "available": 0}
    )
    by_section: dict[str, dict[str, int]] = defaultdict(
        lambda: {"total": 0, "available": 0}
    )
    by_priority: dict[str, dict[str, int]] = defaultdict(
        lambda: {"total": 0, "available": 0}
    )
    by_status: dict[str, int] = defaultdict(int)

    for bt in board:
        by_status[bt.status] += 1
        for role in bt.roles:
            by_role[role]["total"] += 1
            if bt.status == "available":
                by_role[role]["available"] += 1
        sec = bt.section or "(no section)"
        by_section[sec]["total"] += 1
        if bt.status == "available":
            by_section[sec]["available"] += 1
        pri = bt.priority or "medium"
        by_priority[pri]["total"] += 1
        if bt.status == "available":
            by_priority[pri]["available"] += 1

    return {
        "total_pending": len(board),
        "available": by_status.get("available", 0),
        "claimed": by_status.get("claimed", 0),
        "shipped": by_status.get("shipped", 0),
        "in_flight": by_status.get("in-flight", 0),
        "blocked": by_status.get("blocked", 0),
        "expired_claim": by_status.get("expired-claim", 0),
        "by_role": dict(sorted(by_role.items(), key=lambda x: -x[1]["total"])),
        "by_section": dict(sorted(by_section.items())),
        "by_priority": dict(by_priority),
    }


# ---------------------------------------------------------------------------
# Filtering
# ---------------------------------------------------------------------------


def apply_filters(
    board: list[BoardTask],
    *,
    roles: list[str] | None = None,
    section: str | None = None,
    priority: str | None = None,
    available_only: bool = False,
    blocked_only: bool = False,
) -> list[BoardTask]:
    """Filter board tasks by criteria."""
    result = board
    if roles:
        result = [bt for bt in result if any(r in bt.roles for r in roles)]
    if section:
        result = [bt for bt in result if bt.section == section]
    if priority:
        result = [bt for bt in result if bt.priority == priority]
    if available_only:
        result = [bt for bt in result if bt.status == "available"]
    if blocked_only:
        result = [bt for bt in result if bt.status == "blocked"]
    return result


# ---------------------------------------------------------------------------
# Terminal color support
# ---------------------------------------------------------------------------


def _use_color() -> bool:
    """Check if color output is supported and desired."""
    # Respect NO_COLOR convention (https://no-color.org/)
    if os.environ.get("NO_COLOR"):
        return False
    return sys.stdout.isatty()


class _Color:
    """ANSI color codes with graceful degradation."""

    def __init__(self, enabled: bool = True) -> None:
        self.enabled = enabled

    def _wrap(self, code: str, text: str) -> str:
        if not self.enabled:
            return text
        return f"\033[{code}m{text}\033[0m"

    # Foreground colors
    def red(self, text: str) -> str:
        return self._wrap("31", text)

    def green(self, text: str) -> str:
        return self._wrap("32", text)

    def yellow(self, text: str) -> str:
        return self._wrap("33", text)

    def blue(self, text: str) -> str:
        return self._wrap("34", text)

    def magenta(self, text: str) -> str:
        return self._wrap("35", text)

    def cyan(self, text: str) -> str:
        return self._wrap("36", text)

    def dim(self, text: str) -> str:
        return self._wrap("2", text)

    def bold(self, text: str) -> str:
        return self._wrap("1", text)

    def bold_red(self, text: str) -> str:
        return self._wrap("1;31", text)

    def bold_green(self, text: str) -> str:
        return self._wrap("1;32", text)

    def bold_yellow(self, text: str) -> str:
        return self._wrap("1;33", text)

    def bold_blue(self, text: str) -> str:
        return self._wrap("1;34", text)

    def bold_magenta(self, text: str) -> str:
        return self._wrap("1;35", text)

    def bold_cyan(self, text: str) -> str:
        return self._wrap("1;36", text)


# Module-level instance, configured in main()
C = _Color(enabled=False)

# Terminal width, configured in main()
TERM_WIDTH = 80


def _get_term_width() -> int:
    """Get terminal width, defaulting to 80."""
    try:
        return os.get_terminal_size().columns
    except (AttributeError, ValueError, OSError):
        return 80


def _truncate(text: str, max_len: int) -> str:
    """Truncate text with ellipsis if it exceeds max_len."""
    if len(text) <= max_len:
        return text
    return text[: max_len - 1] + "\u2026"  # …


# ---------------------------------------------------------------------------
# Human display
# ---------------------------------------------------------------------------

# Unicode status indicators (with fallback text for NO_COLOR / non-tty)
STATUS_INDICATORS_UNICODE = {
    "available": "\u25cb",  # ○
    "claimed": "\u25c9",  # ◉
    "shipped": "\u2713",  # ✓
    "in-flight": "\u25b6",  # ▶
    "blocked": "\u2298",  # ⊘
    "expired-claim": "\u2718",  # ✘
}

STATUS_INDICATORS_PLAIN = {
    "available": "[ ]",
    "claimed": "[C]",
    "shipped": "[S]",
    "in-flight": "[P]",
    "blocked": "[B]",
    "expired-claim": "[E]",
}

STATUS_COLORS = {
    "available": "green",
    "claimed": "cyan",
    "shipped": "blue",
    "in-flight": "magenta",
    "blocked": "red",
    "expired-claim": "dim",
}

PRIORITY_INDICATORS = {
    "high": ("!!!", "bold_red"),
    "medium": (" !!", "yellow"),
    "low": ("  !", "dim"),
}

# Single-character role badges with distinct colors
# Customize for your project's role taxonomy
ROLE_BADGES: dict[str, tuple[str, str]] = {
    "dev": ("D", "bold_cyan"),
    "design": ("G", "bold_magenta"),
    "docs": ("W", "bold_yellow"),
    "test": ("T", "bold_green"),
    "ops": ("O", "bold_blue"),
    "security": ("X", "bold_red"),
}

ROLE_BADGE_PLAIN: dict[str, str] = {
    "dev": "D",
    "design": "G",
    "docs": "W",
    "test": "T",
    "ops": "O",
    "security": "X",
}


def _status_indicator(status: str) -> str:
    """Get a colored status indicator."""
    if C.enabled:
        symbol = STATUS_INDICATORS_UNICODE.get(status, "?")
        color_name = STATUS_COLORS.get(status, "dim")
        color_fn = getattr(C, color_name, C.dim)
        return color_fn(symbol)
    return STATUS_INDICATORS_PLAIN.get(status, "[ ]")


def _status_indicator_width() -> int:
    """Visible character width of a status indicator."""
    return 1 if C.enabled else 3  # Unicode "○" vs plain "[X]"


def _priority_indicator(priority: str | None) -> str:
    """Get a colored priority indicator."""
    pri = priority or "medium"
    label, color_name = PRIORITY_INDICATORS.get(pri, (" !!", "yellow"))
    color_fn = getattr(C, color_name, C.dim)
    return color_fn(label)


def _role_badges(roles: list[str]) -> str:
    """Format roles as colored single-character badges (e.g., S D E)."""
    if not roles:
        if C.enabled:
            return C.dim("?")
        return "?"
    badges = []
    for role in roles:
        if C.enabled:
            char, color_name = ROLE_BADGES.get(role, (role[0].upper(), "dim"))
            color_fn = getattr(C, color_name, C.dim)
            badges.append(color_fn(char))
        else:
            badges.append(ROLE_BADGE_PLAIN.get(role, role[0].upper()))
    return " ".join(badges)


def _role_badges_width(roles: list[str]) -> int:
    """Visible character width of role badges."""
    n = max(len(roles), 1)
    return n + (n - 1)  # chars + spaces between them


def _bar_width() -> int:
    """Width for bar charts in summary, scaled to terminal."""
    if TERM_WIDTH >= 120:
        return 20
    if TERM_WIDTH >= 100:
        return 15
    if TERM_WIDTH >= 80:
        return 10
    return 6


def _format_task_compact(bt: BoardTask) -> str:
    """One-line compact task format, width-aware."""
    indicator = _status_indicator(bt.status)

    # Role badges: colored single chars, right-padded to 5 (max 3 roles = "S D E")
    badges = _role_badges(bt.roles)
    badges_w = _role_badges_width(bt.roles)
    max_badges_w = 5  # 3 chars + 2 spaces for max 3 roles
    badge_pad = " " * (max_badges_w - badges_w) if badges_w < max_badges_w else ""

    pri = _priority_indicator(bt.priority)

    # Compute suffix (claim/blocked info)
    suffix_plain = ""
    suffix_colored = ""
    if bt.claim and bt.status == "claimed":
        wt = bt.claim.worktree
        age = bt.claim.age_minutes
        suffix_plain = f" \u2190 {wt} ({age}m)"
        suffix_colored = " " + C.cyan(suffix_plain.lstrip())
    elif bt.claim and bt.status == "shipped" and bt.claim.pr_number:
        suffix_plain = f" PR #{bt.claim.pr_number}"
        suffix_colored = " " + C.blue(suffix_plain.lstrip())
    elif bt.blocked_by:
        deps = [
            d.split(" \u2014 ")[0].strip()[:30]
            for d in bt.blocked_by
            if not d.lower().startswith("none")
            and not d.lower().startswith("no dependency")
        ]
        if deps:
            if len(deps) <= 2:
                dep_text = f"\u2190 {', '.join(deps)}"
            else:
                dep_text = f"\u2190 {len(deps)} deps"
            suffix_plain = f" {dep_text}"
            suffix_colored = " " + C.red(dep_text)

    # Prepend task ID if available (e.g., "T1140")
    id_prefix = ""
    id_prefix_w = 0
    if bt.id:
        id_prefix = C.dim(bt.id) + " "
        id_prefix_w = len(bt.id) + 1

    ind_w = _status_indicator_width()
    prefix_w = 2 + ind_w + 1 + 3 + 1 + max_badges_w + 1 + id_prefix_w

    # Budget for title + suffix
    avail_w = TERM_WIDTH - prefix_w
    title = bt.title
    if suffix_plain:
        # Fit title + suffix within budget
        suffix_vis_len = len(suffix_plain)
        title_budget = avail_w - suffix_vis_len
        if title_budget < 20:
            # Suffix too long — drop it to a second line
            title = _truncate(title, avail_w)
            suffix_colored = ""
        elif len(title) > title_budget:
            title = _truncate(title, title_budget)
    else:
        title = _truncate(title, avail_w)

    return f"  {indicator} {pri} {badge_pad}{badges} {id_prefix}{title}{suffix_colored}"


def _print_legend() -> None:
    """Print a compact legend explaining status indicators, priority, and roles."""
    indicators = [
        (_status_indicator("available"), "avail"),
        (_status_indicator("claimed"), "claim"),
        (_status_indicator("shipped"), "ship"),
        (_status_indicator("in-flight"), "PR"),
        (_status_indicator("blocked"), "block"),
        (_status_indicator("expired-claim"), "expir"),
    ]
    legend_parts = [f"{sym} {label}" for sym, label in indicators]

    pri_parts = [
        f"{_priority_indicator('high')} hi",
        f"{_priority_indicator('medium')} md",
        f"{_priority_indicator('low')} lo",
    ]

    # Role badge legend
    role_parts = []
    for role, (char, color_name) in ROLE_BADGES.items():
        if C.enabled:
            color_fn = getattr(C, color_name, C.dim)
            role_parts.append(f"{color_fn(char)}{C.dim('=' + role[:3])}")
        else:
            role_parts.append(f"{char}={role[:3]}")

    status_line = C.dim(" ").join(legend_parts)
    pri_line = C.dim(" ").join(pri_parts)
    role_line = C.dim(" ").join(role_parts)

    # Layout: fit on as few lines as possible
    if TERM_WIDTH >= 110:
        print(
            C.dim("  ")
            + status_line
            + C.dim("  \u2502  ")
            + pri_line
            + C.dim("  \u2502  ")
            + role_line
        )
    elif TERM_WIDTH >= 90:
        print(C.dim("  ") + status_line + C.dim("  \u2502  ") + pri_line)
        print(C.dim("  ") + role_line)
    else:
        print(C.dim("  ") + status_line)
        print(C.dim("  ") + pri_line + C.dim("  \u2502  ") + role_line)


def _display_refresh(refresh: RefreshResult) -> None:
    """Show claim refresh activity (refreshed, stale, orphaned)."""
    if not refresh.refreshed and not refresh.stale and not refresh.orphaned:
        return
    items: list[str] = []
    if refresh.refreshed:
        owners = {r["owner"] for r in refresh.refreshed}
        items.append(
            C.green(f"\u21bb {len(refresh.refreshed)} refreshed")
            + C.dim(f" ({', '.join(sorted(owners))})")
        )
    if refresh.stale:
        owners = {s["owner"] for s in refresh.stale}
        items.append(
            C.yellow(f"\u23f8 {len(refresh.stale)} stale")
            + C.dim(f" ({', '.join(sorted(owners))})")
        )
    if refresh.orphaned:
        owners = {o["owner"] for o in refresh.orphaned}
        items.append(
            C.red(f"\u2620 {len(refresh.orphaned)} orphaned")
            + C.dim(f" ({', '.join(sorted(owners))})")
        )
    print(C.dim("Claims: ") + C.dim(" \u2502 ").join(items))


def display_human(
    board: list[BoardTask],
    summary: dict,
    sections: dict[str, dict],
    clusters: list[dict],
    *,
    group_by: str = "section",
    show_clusters: bool = False,
    refresh: RefreshResult | None = None,
) -> None:
    """Print human-readable task board."""
    w = min(TERM_WIDTH, 60)
    print(C.bold("\u2500" * w))
    print(C.bold("  TASK BOARD"))
    print(C.bold("\u2500" * w))

    # Summary bar with colored counts
    parts = [C.bold(f"{summary['total_pending']} pending")]
    if summary["available"]:
        parts.append(C.bold_green(f"{summary['available']} avail"))
    if summary["claimed"]:
        parts.append(C.bold_cyan(f"{summary['claimed']} claim"))
    if summary["shipped"]:
        parts.append(C.bold_blue(f"{summary['shipped']} ship"))
    if summary["in_flight"]:
        parts.append(C.bold_magenta(f"{summary['in_flight']} in-PR"))
    if summary["blocked"]:
        parts.append(C.bold_red(f"{summary['blocked']} block"))
    if summary.get("expired_claim"):
        parts.append(C.dim(f"{summary['expired_claim']} expir"))
    print(" \u2502 ".join(parts))

    # Show claim refresh activity
    if refresh:
        _display_refresh(refresh)

    _print_legend()
    print()

    if show_clusters:
        _display_clusters(board, clusters)
    elif group_by == "role":
        _display_by_role(board)
    elif group_by == "priority":
        _display_by_priority(board)
    else:
        _display_by_section(board, sections)

    print()
    _display_role_summary(summary)


def _section_header(title: str, count: int, status_parts: list[str]) -> str:
    """Format a section header, truncated to terminal width."""
    stats = ", ".join(status_parts)
    header_text = f"{title} ({count}: {stats})"
    max_w = TERM_WIDTH - 6  # "─── " + " ───"
    header_text = _truncate(header_text, max_w)
    return f"\u2500\u2500 {C.bold(header_text)} \u2500\u2500"


def _display_by_section(board: list[BoardTask], sections: dict[str, dict]) -> None:
    """Display tasks grouped by section."""
    # Group tasks
    groups: dict[str, list[BoardTask]] = defaultdict(list)
    for bt in board:
        groups[bt.section or "(no section)"].append(bt)

    # Sort sections using _sections.toml ordering
    priority_rank = {"high": 0, "medium": 1, "low": 2}

    def section_sort_key(section_id: str) -> tuple[int, int, str]:
        meta = sections.get(section_id, {})
        p = priority_rank.get(meta.get("priority", "medium"), 1)
        return (p, meta.get("sort_order", 99), section_id)

    for section_id in sorted(groups.keys(), key=section_sort_key):
        tasks = groups[section_id]
        meta = sections.get(section_id, {})
        title = meta.get("title", section_id)
        avail = sum(1 for t in tasks if t.status == "available")
        claimed = sum(1 for t in tasks if t.status in ("claimed", "shipped"))

        status_parts = []
        if avail:
            status_parts.append(C.green(f"{avail}a"))
        if claimed:
            status_parts.append(C.cyan(f"{claimed}c"))
        blocked = sum(1 for t in tasks if t.status == "blocked")
        if blocked:
            status_parts.append(C.red(f"{blocked}b"))

        print(_section_header(title, len(tasks), status_parts))
        for bt in sorted(
            tasks,
            key=lambda t: ({"available": 0, "blocked": 1}.get(t.status, 2), t.title),
        ):
            print(_format_task_compact(bt))
        print()


def _display_by_role(board: list[BoardTask]) -> None:
    """Display tasks grouped by role."""
    groups: dict[str, list[BoardTask]] = defaultdict(list)
    for bt in board:
        for role in bt.roles or ["(no role)"]:
            groups[role].append(bt)

    for role in sorted(groups.keys()):
        tasks = groups[role]
        avail = sum(1 for t in tasks if t.status == "available")
        print(_section_header(role, len(tasks), [C.green(f"{avail}a")]))
        for bt in sorted(tasks, key=lambda t: t.title):
            print(_format_task_compact(bt))
        print()


def _display_by_priority(board: list[BoardTask]) -> None:
    """Display tasks grouped by priority."""
    groups: dict[str, list[BoardTask]] = defaultdict(list)
    for bt in board:
        groups[bt.priority or "medium"].append(bt)

    for pri in ["high", "medium", "low"]:
        tasks = groups.get(pri, [])
        if not tasks:
            continue
        avail = sum(1 for t in tasks if t.status == "available")
        pri_ind = _priority_indicator(pri)
        print(
            f"\u2500\u2500 {pri_ind} {C.bold(pri.upper())} "
            f"({len(tasks)}: {C.green(f'{avail}a')}) \u2500\u2500"
        )
        for bt in sorted(tasks, key=lambda t: t.title):
            print(_format_task_compact(bt))
        print()


def _display_clusters(board: list[BoardTask], clusters: list[dict]) -> None:
    """Display file-overlap clusters."""
    slug_to_task = {bt.slug: bt for bt in board}
    unlinked = [bt for bt in board if bt.cluster_id is None]

    for cluster in clusters:
        avail = cluster["available_count"]
        total = cluster["task_count"]
        roles = ", ".join(cluster["roles"])
        dirs = cluster["dirs"][:3]
        dir_str = ", ".join(dirs)
        if len(cluster["dirs"]) > 3:
            dir_str += f" (+{len(cluster['dirs']) - 3})"

        print(
            _section_header(
                f"Cluster {cluster['id']} [{roles}]",
                total,
                [C.green(f"{avail}a")],
            )
        )
        dir_budget = TERM_WIDTH - 10
        print(f"    {C.dim('Dirs:')} {_truncate(dir_str, dir_budget)}")
        for slug in cluster["task_slugs"]:
            bt = slug_to_task.get(slug)
            if bt:
                print(_format_task_compact(bt))
        print()

    if unlinked:
        avail = sum(1 for bt in unlinked if bt.status == "available")
        print(
            _section_header(
                "Unlinked (no file refs)",
                len(unlinked),
                [C.green(f"{avail}a")],
            )
        )
        for bt in sorted(unlinked, key=lambda t: t.title):
            print(_format_task_compact(bt))
        print()


def _display_role_summary(summary: dict) -> None:
    """Print role summary table."""
    bw = _bar_width()
    print(C.bold("\u2500\u2500 ROLES \u2500\u2500"))
    by_role = summary.get("by_role", {})
    max_avail = max((c["available"] for c in by_role.values()), default=1) or 1
    rw = max((len(r) for r in by_role), default=8)
    for role, counts in by_role.items():
        avail = counts["available"]
        total = counts["total"]
        filled = round(avail / max_avail * bw) if avail else 0
        bar = C.green("\u2588" * filled) + C.dim("\u2591" * (bw - filled))
        avail_str = C.bold_green(f"{avail:2}") if avail else C.dim(f"{avail:2}")
        print(f"  {role:>{rw}} {total:2}/{avail_str} {bar}")
    print()
    print(C.bold("\u2500\u2500 PRIORITY \u2500\u2500"))
    by_pri = summary.get("by_priority", {})
    max_pri_avail = (
        max(
            (by_pri.get(p, {}).get("available", 0) for p in ["high", "medium", "low"]),
            default=1,
        )
        or 1
    )
    for pri in ["high", "medium", "low"]:
        counts = by_pri.get(pri, {"total": 0, "available": 0})
        avail = counts["available"]
        total = counts["total"]
        pri_ind = _priority_indicator(pri)
        filled = round(avail / max_pri_avail * bw) if avail else 0
        bar = C.green("\u2588" * filled) + C.dim("\u2591" * (bw - filled))
        avail_str = C.bold_green(f"{avail:2}") if avail else C.dim(f"{avail:2}")
        print(f"  {pri_ind} {pri:>6} {total:2}/{avail_str} {bar}")


# ---------------------------------------------------------------------------
# JSON output
# ---------------------------------------------------------------------------


def to_json(
    board: list[BoardTask],
    summary: dict,
    sections: dict[str, dict],
    clusters: list[dict],
) -> dict:
    """Build the full JSON output."""
    tasks_json = []
    for bt in board:
        claim_json = None
        if bt.claim:
            claim_json = {
                "worktree": bt.claim.worktree,
                "state": bt.claim.state,
                "age_minutes": bt.claim.age_minutes,
                "expired": bt.claim.expired,
                "pr_number": bt.claim.pr_number,
            }
        tasks_json.append(
            {
                "slug": bt.slug,
                "id": bt.id,
                "title": bt.title,
                "roles": bt.roles,
                "section": bt.section,
                "section_title": sections.get(bt.section, {}).get("title", bt.section),
                "priority": bt.priority,
                "status": bt.status,
                "files": bt.files,
                "dependencies": bt.dependencies,
                "blocked_by": bt.blocked_by,
                "claim": claim_json,
                "cluster_id": bt.cluster_id,
            }
        )

    sections_json = []
    # Gather section stats from summary
    for sid, meta in sorted(sections.items(), key=lambda x: x[1].get("sort_order", 99)):
        sec_stats = summary.get("by_section", {}).get(sid, {"total": 0, "available": 0})
        sections_json.append(
            {
                "id": sid,
                "title": meta.get("title", sid),
                "priority": meta.get("priority"),
                "sort_order": meta.get("sort_order", 99),
                "task_count": sec_stats["total"],
                "available_count": sec_stats["available"],
            }
        )

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "summary": summary,
        "tasks": tasks_json,
        "clusters": clusters,
        "sections": sections_json,
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Task board — unified view of pending tasks, claims, and in-flight PRs."
    )
    parser.add_argument(
        "--json", action="store_true", help="Machine-readable JSON output"
    )
    parser.add_argument(
        "--role",
        action="append",
        dest="roles",
        help="Filter to tasks with this role (repeatable)",
    )
    parser.add_argument("--section", help="Filter to tasks in this section")
    parser.add_argument(
        "--priority", choices=["high", "medium", "low"], help="Filter by priority"
    )
    parser.add_argument(
        "--available-only",
        action="store_true",
        help="Show only available (claimable) tasks",
    )
    parser.add_argument(
        "--blocked", action="store_true", help="Show only blocked tasks"
    )
    parser.add_argument(
        "--clusters",
        action="store_true",
        help="Group by file-overlap clusters instead of section",
    )
    parser.add_argument(
        "--group-by",
        choices=["section", "role", "priority"],
        default="section",
        help="Grouping mode (default: section)",
    )
    parser.add_argument(
        "--no-claims",
        action="store_true",
        help="Skip work-queue claim data (faster)",
    )
    parser.add_argument(
        "--no-prs",
        action="store_true",
        help="Skip in-flight PR data (faster)",
    )
    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable colored output",
    )
    parser.add_argument(
        "--width",
        type=int,
        default=0,
        help="Override terminal width (0 = auto-detect)",
    )

    args = parser.parse_args()

    # Configure color and terminal width
    global C, TERM_WIDTH  # noqa: PLW0603
    C = _Color(enabled=_use_color() and not args.no_color)
    TERM_WIDTH = args.width if args.width > 0 else _get_term_width()

    # Refresh near-expired claims before loading (unless --no-claims)
    refresh = None
    if not args.no_claims:
        refresh = refresh_active_claims()

    # Load data
    tasks = load_tasks()
    completed_ids = load_completed_ids()
    sections = load_sections()
    claims = {} if args.no_claims else load_claims()
    inflight = set() if args.no_prs else load_inflight()

    # Resolve statuses
    board = resolve_tasks(tasks, claims, inflight, completed_ids)

    # Compute clusters (always, for JSON; display respects --clusters flag)
    clusters = compute_clusters(board)

    # Apply filters
    filtered = apply_filters(
        board,
        roles=args.roles,
        section=args.section,
        priority=args.priority,
        available_only=args.available_only,
        blocked_only=args.blocked,
    )

    # Compute summary on filtered set
    summary = compute_summary(filtered, sections)

    if args.json:
        output = to_json(filtered, summary, sections, clusters)
        json.dump(output, sys.stdout, indent=2)
        print()
    else:
        display_human(
            filtered,
            summary,
            sections,
            clusters,
            group_by=args.group_by,
            show_clusters=args.clusters,
            refresh=refresh,
        )


if __name__ == "__main__":
    main()
