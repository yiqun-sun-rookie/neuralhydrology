"""Closed production entry that mints the one-use strict-nesting training receipt.

`run_formal_strict_stage_v09` consumes an `A09-NEST-01` receipt but never creates one, and
`create_stage_authorization_v09` had no production caller. This entry closes that gap and
nothing else: it cannot train, predict, score, or consume the receipt it writes.
"""
from __future__ import annotations

import datetime as dt
import json
import os
from pathlib import Path
import subprocess

from artifact_v09 import assert_no_reparse_components, canonical_sha256, sha256_file, write_json_atomic
from formal_v09_protocol import load_protocol_v09
from run_formal_strict_stage_v09 import (
    StrictStagePathsV09,
    strict_executable_tree_v09,
    strict_prerequisite_hashes_v09,
    strict_stage_paths_v09,
)
from stage_authorization_v09 import (
    STRICT_NESTING_APPROVAL_TEXT,
    create_stage_authorization_v09,
    validate_stage_authorization_v09,
)

_SCOPE = "R09-NEST-S100"
_ACTION = "training"


def _production_worktree_root_v09() -> Path:
    return Path(os.path.abspath(Path(__file__).parents[2]))


def _require_clean_worktree_v09(worktree_root: Path) -> str:
    head = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=worktree_root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    status = subprocess.run(
        ["git", "status", "--porcelain=v1", "--untracked-files=all"],
        cwd=worktree_root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if len(head) != 40 or status:
        raise ValueError("strict training authorization requires a clean Git worktree")
    return head


def _assert_unused_stage_state_v09(paths: StrictStagePathsV09) -> None:
    """Refuse to mint a receipt for a stage that already has one, or that already ran."""
    blocked = (
        (paths.authorization, "authorization"),
        (paths.consumption, "consumption"),
        (paths.output_root, "output"),
    )
    for path, label in blocked:
        assert_no_reparse_components(paths.worktree_root, path)
        if path.exists():
            raise FileExistsError(f"strict stage {label} already exists: {path}")


def _created_utc_v09() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def create_formal_strict_authorization_v09() -> dict:
    """Create exactly one A09-NEST-01 receipt; this function intentionally has no arguments."""
    worktree_root = _production_worktree_root_v09()
    paths = strict_stage_paths_v09(worktree_root)
    head = _require_clean_worktree_v09(worktree_root)
    _assert_unused_stage_state_v09(paths)
    protocol = load_protocol_v09(paths.protocol)
    prerequisites = strict_prerequisite_hashes_v09(paths, protocol)
    executable_tree = strict_executable_tree_v09(worktree_root)
    protocol_sha256 = canonical_sha256(protocol)
    output_root = str(paths.output_root)
    bindings = {
        "action": _ACTION,
        "scope": _SCOPE,
        "protocol_sha256": protocol_sha256,
        "prerequisite_sha256": prerequisites,
        "executable_tree_sha256": executable_tree["tree_sha256"],
        "worktree_root": worktree_root,
        "output_root": output_root,
    }
    receipt = create_stage_authorization_v09(
        approval_text=STRICT_NESTING_APPROVAL_TEXT,
        scope=_SCOPE,
        protocol_sha256=protocol_sha256,
        prerequisite_sha256=prerequisites,
        executable_tree_sha256=executable_tree["tree_sha256"],
        git_commit=head,
        worktree_root=worktree_root,
        output_root=output_root,
        created_utc=_created_utc_v09(),
    )
    validate_stage_authorization_v09(receipt, **bindings)
    _assert_unused_stage_state_v09(paths)
    paths.authorization.parent.mkdir(parents=True, exist_ok=True)
    write_json_atomic(paths.authorization, receipt)
    persisted = json.loads(paths.authorization.read_text(encoding="utf-8"))
    if persisted != receipt:
        raise ValueError("strict training authorization file drift")
    validate_stage_authorization_v09(persisted, **bindings)
    return {
        "schema": "historical_multiscale_formal_v09_strict_authorization_creation_v1",
        "status": "strict_training_authorization_created",
        "scope": _SCOPE,
        "receipt_id": receipt["receipt_id"],
        "authorization_path": str(paths.authorization),
        "authorization_file_sha256": sha256_file(paths.authorization),
        "authorization_canonical_sha256": canonical_sha256(receipt),
        "git_commit": head,
        "prerequisite_sha256": dict(prerequisites),
        "executable_tree_sha256": executable_tree["tree_sha256"],
        "formal_training_started": False,
        "formal_prediction_generation_authorized": False,
        "official_scoring_authorized": False,
    }


def main() -> None:
    print(json.dumps(create_formal_strict_authorization_v09(), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
