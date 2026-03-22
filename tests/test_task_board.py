"""Tests for scripts/task-board.py — task board display and dependency resolution."""

from __future__ import annotations

import importlib
import sys
from pathlib import Path

# Import the modules under test
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
task_format = importlib.import_module("task-format")
task_board = importlib.import_module("task-board")

TaskEntry = task_format.TaskEntry
resolve_tasks = task_board.resolve_tasks
_build_pending_id_map = task_board._build_pending_id_map


def _make_task(
    title: str,
    *,
    id: str | None = None,
    dependencies: list[str] | None = None,
    state: str = "pending",
) -> TaskEntry:
    return TaskEntry(
        id=id,
        title=title,
        state=state,
        dependencies=dependencies or [],
        roles=["dev"],
        section="test",
        priority="medium",
    )


class TestDependencyResolution:
    """Tests for resolve_tasks dependency checking."""

    def test_parenthetical_annotation_stripped(self):
        """Dependencies with phase labels like (M1.1) match completed tasks."""
        completed = _make_task(
            "Extend BuildManifest with per-file SHA-256 hashes",
            id="T1165",
            state="completed",
        )
        pending = _make_task(
            "Build package builder",
            id="T1169",
            dependencies=[
                "Extend BuildManifest with per-file SHA-256 hashes (M1.1) "
                "— packages include the manifest"
            ],
        )
        completed_ids = {
            completed.id,
            completed.title,
            task_format.slug_from_title(completed.title),
        }
        board = resolve_tasks(
            [pending], claims={}, inflight=set(), completed_ids=completed_ids
        )
        assert board[0].status == "available"
        assert board[0].blocked_by == []

    def test_em_dash_description_stripped(self):
        """Dependencies with em-dash descriptions are resolved correctly."""
        completed_ids = {"Do the thing"}
        pending = _make_task(
            "Next task",
            id="T200",
            dependencies=["Do the thing — some explanation"],
        )
        board = resolve_tasks(
            [pending], claims={}, inflight=set(), completed_ids=completed_ids
        )
        assert board[0].status == "available"

    def test_double_dash_description_stripped(self):
        """Dependencies with double-dash descriptions are resolved correctly."""
        completed_ids = {"Do the thing"}
        pending = _make_task(
            "Next task",
            id="T200",
            dependencies=["Do the thing -- some explanation"],
        )
        board = resolve_tasks(
            [pending], claims={}, inflight=set(), completed_ids=completed_ids
        )
        assert board[0].status == "available"

    def test_unresolved_dependency_blocks(self):
        """A task with an unresolved dependency is blocked."""
        pending = _make_task(
            "Next task",
            id="T200",
            dependencies=["Some prerequisite that does not exist"],
        )
        board = resolve_tasks([pending], claims={}, inflight=set(), completed_ids=set())
        assert board[0].status == "blocked"
        assert len(board[0].blocked_by) == 1

    def test_none_dependency_skipped(self):
        """Dependencies starting with 'None' or 'No dependency' are ignored."""
        pending = _make_task(
            "Independent task",
            id="T300",
            dependencies=["None", "No dependency on other tasks"],
        )
        board = resolve_tasks([pending], claims={}, inflight=set(), completed_ids=set())
        assert board[0].status == "available"
        assert board[0].blocked_by == []

    def test_parenthetical_only_no_description(self):
        """Phase label without em-dash description is also stripped."""
        completed_ids = {"Build the widget"}
        pending = _make_task(
            "Use the widget",
            id="T400",
            dependencies=["Build the widget (Phase 1)"],
        )
        board = resolve_tasks(
            [pending], claims={}, inflight=set(), completed_ids=completed_ids
        )
        assert board[0].status == "available"


class TestBlockedByIdResolution:
    """Tests that blocked_by entries resolve to task IDs when possible."""

    def test_blocked_by_shows_task_id(self):
        """When a blocker is a pending task with an ID, blocked_by stores the ID."""
        blocker = _make_task("Build the thing", id="T100")
        dependent = _make_task(
            "Use the thing",
            id="T200",
            dependencies=["Build the thing"],
        )
        board = resolve_tasks(
            [blocker, dependent], claims={}, inflight=set(), completed_ids=set()
        )
        dependent_bt = next(bt for bt in board if bt.id == "T200")
        assert dependent_bt.status == "blocked"
        assert dependent_bt.blocked_by == ["T100"]

    def test_blocked_by_shows_task_id_with_annotation(self):
        """Phase-annotated deps that match pending tasks resolve to task IDs."""
        blocker = _make_task("Build the thing", id="T100")
        dependent = _make_task(
            "Use the thing",
            id="T200",
            dependencies=["Build the thing (M2.1) — needs the output"],
        )
        board = resolve_tasks(
            [blocker, dependent], claims={}, inflight=set(), completed_ids=set()
        )
        dependent_bt = next(bt for bt in board if bt.id == "T200")
        assert dependent_bt.status == "blocked"
        assert dependent_bt.blocked_by == ["T100"]

    def test_unresolvable_dep_keeps_raw_text(self):
        """When no pending task matches, blocked_by keeps the raw dependency text."""
        dependent = _make_task(
            "Use the thing",
            id="T200",
            dependencies=["Something unknown"],
        )
        board = resolve_tasks(
            [dependent], claims={}, inflight=set(), completed_ids=set()
        )
        assert board[0].blocked_by == ["Something unknown"]


class TestBuildPendingIdMap:
    """Tests for _build_pending_id_map helper."""

    def test_maps_title_and_slug(self):
        tasks = [_make_task("Build the Widget", id="T100")]
        id_map = _build_pending_id_map(tasks)
        assert id_map["Build the Widget"] == "T100"
        assert id_map["build-the-widget"] == "T100"

    def test_skips_tasks_without_id(self):
        tasks = [_make_task("No ID task")]
        id_map = _build_pending_id_map(tasks)
        assert len(id_map) == 0
