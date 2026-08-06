"""Closed production entry for the post-training independent replay audit.

`audit_strict_run_v09` had no production caller, so the sealed seed-100 run could be produced
but never externally replayed. This entry runs that replay and nothing else: it cannot train,
authorize, predict, or score, and it writes its report outside the sealed run directory.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

from artifact_v09 import assert_no_reparse_components
from audit_strict_formal_v09 import audit_strict_run_v09
from formal_action_runtime_v09 import _audit_formal_action_resources_under_lease_v09
from formal_training_data_v09 import load_sealed_training_inputs_v09
from formal_v09_protocol import load_protocol_v09
from memory_safety_v09 import exclusive_high_load_lease_v09
from run_formal_strict_stage_v09 import StrictStagePathsV09, strict_stage_paths_v09

_SCOPE = "R09-NEST-S100"
_DEVICE = "cuda:0"
_VARIANT = "strict_nesting_pair"
_REPORT_NAME = "R09-NEST-S100.strict_nesting_external_audit.json"


def _production_worktree_root_v09() -> Path:
    return Path(os.path.abspath(Path(__file__).parents[2]))


def _strict_audit_report_path_v09(paths: StrictStagePathsV09) -> Path:
    """Keep the external report beside the other formal evidence, never inside the run."""
    return paths.input_root.parent / _REPORT_NAME


def audit_formal_strict_stage_v09() -> dict:
    """Replay the sealed seed-100 strict run; this function intentionally has no arguments."""
    worktree_root = _production_worktree_root_v09()
    paths = strict_stage_paths_v09(worktree_root)
    if not paths.consumption.is_file():
        raise FileNotFoundError(f"strict authorization consumption receipt is absent: {paths.consumption}")
    if not paths.output_root.is_dir():
        raise FileNotFoundError(f"strict formal run directory is absent: {paths.output_root}")
    seal_path = paths.output_root / "seal.json"
    if not seal_path.is_file():
        raise FileNotFoundError(f"strict formal run seal is absent: {seal_path}")
    report_path = _strict_audit_report_path_v09(paths)
    assert_no_reparse_components(worktree_root, report_path)
    if report_path.exists():
        raise FileExistsError(f"strict external audit report already exists: {report_path}")
    protocol = load_protocol_v09(paths.protocol)
    # The replay streams the same batches as training, so gate it with the same conservative
    # training estimate rather than inventing an unregistered peak method.
    with exclusive_high_load_lease_v09() as lease:
        resource = _audit_formal_action_resources_under_lease_v09(
            protocol,
            action="training",
            variant=_VARIANT,
            lease=lease,
        )
        if resource.get("status") != "resource_preflight_passed":
            raise ValueError("strict external audit resource preflight drift")
        inputs = load_sealed_training_inputs_v09(
            paths.input_root,
            paths.protocol,
            worktree_root=worktree_root,
            external_audit_path=paths.input_external_audit,
            trusted_source_audit_path=paths.trusted_source_audit,
        )
        report = audit_strict_run_v09(
            paths.output_root,
            inputs=inputs,
            device=_DEVICE,
            report_path=report_path,
        )
    return {
        "schema": "historical_multiscale_formal_v09_strict_stage_audit_entry_v1",
        "status": "strict_nesting_external_audit_complete",
        "scope": _SCOPE,
        "report_path": str(report_path),
        "report": report,
        "formal_prediction_generation_authorized": False,
        "official_scoring_authorized": False,
    }


def main() -> None:
    print(json.dumps(audit_formal_strict_stage_v09(), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
