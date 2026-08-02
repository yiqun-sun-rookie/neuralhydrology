"""Closed production preparation for the version-09 strict-nesting stage."""
from __future__ import annotations

from collections.abc import Callable, Mapping
import json
import os
from pathlib import Path
import subprocess
import tempfile

from artifact_v09 import (
    assert_no_reparse_components,
    assert_no_reparse_tree,
    assert_no_embedded_seal_entries,
    write_json_atomic,
)
from audit_legacy_checkpoint_bridge_v09 import audit_legacy_checkpoint_bridge_v09
from formal_action_runtime_v09 import _audit_formal_action_resources_under_lease_v09
from formal_training_data_v09 import FormalBridgeInputsV09, load_sealed_bridge_inputs_v09
from formal_v09_protocol import load_protocol_v09
from memory_safety_v09 import exclusive_high_load_lease_v09
from run_formal_strict_stage_v09 import (
    StrictStagePathsV09,
    _load_json_status,
    _validate_legacy_bridge_report_v09,
    _validate_resource_preflight_report_v09,
    strict_input_bindings_v09,
    strict_prerequisite_hashes_v09,
    strict_stage_paths_v09,
)

_LEGACY_RESULTS_ROOT = Path("results/18_lstm_fair_531")
_DEVICE = "cuda:0"
_VARIANT = "strict_nesting_pair"
_PREPARATION_LOCK_NAME = "neuralhydrology_historical_multiscale_v09_strict_prerequisites.lock"


def _production_worktree_root_v09() -> Path:
    return Path(os.path.abspath(Path(__file__).parents[2]))


def _primary_repository_root_v09(worktree_root: Path) -> Path:
    completed = subprocess.run(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        cwd=worktree_root,
        check=True,
        capture_output=True,
        text=True,
    )
    common_dir = Path(os.path.abspath(completed.stdout.strip()))
    if common_dir.name != ".git" or not common_dir.is_dir():
        raise ValueError("strict prerequisite preparation cannot resolve the primary repository")
    repository_root = common_dir.parent
    assert_no_reparse_components(repository_root, repository_root)
    return repository_root


def _preparation_lock_path_v09() -> Path:
    return Path(tempfile.gettempdir(), _PREPARATION_LOCK_NAME)


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
        raise ValueError("strict prerequisite preparation requires a clean Git worktree")
    return head


def _assert_closed_stage_state_v09(paths: StrictStagePathsV09) -> None:
    blocked = (
        (paths.authorization, "authorization"),
        (paths.consumption, "consumption"),
        (paths.output_root, "output"),
    )
    for path, label in blocked:
        assert_no_reparse_components(paths.worktree_root, path)
        if path.exists():
            raise FileExistsError(f"strict stage {label} already exists: {path}")


def _assert_formal_preparation_inventory_v09(paths: StrictStagePathsV09) -> None:
    formal_root = paths.input_root.parent
    assert_no_reparse_components(paths.worktree_root, formal_root)
    assert_no_reparse_tree(formal_root)
    seal = json.loads((paths.input_root / "seal.json").read_text(encoding="utf-8"))
    sealed_files = seal.get("sealed_files")
    if not isinstance(sealed_files, list):
        raise ValueError("formal input seal file inventory is invalid")
    assert_no_embedded_seal_entries(sealed_files)
    input_files = {
        f"input_attempt_01/{item['relative_path'].replace(chr(92), '/')}"
        for item in sealed_files
    }
    expected_files = {
        "formal_input_seal_authorization_consumed.json",
        "input_attempt_01.external_audit.json",
        "input_attempt_01.trusted_source_external_audit.json",
        "authorizations/formal_input_seal_authorization.json",
        "inputs/training_targets.csv",
        "inputs/training_targets.manifest.json",
        "input_attempt_01/seal.json",
        *input_files,
    }
    for optional in (paths.legacy_bridge_audit, paths.resource_preflight_audit):
        if optional.exists():
            expected_files.add(optional.relative_to(formal_root).as_posix())
    actual_files = {
        path.relative_to(formal_root).as_posix()
        for path in formal_root.rglob("*")
        if path.is_file()
    }
    if actual_files != expected_files:
        raise ValueError(
            "formal preparation inventory drift: "
            f"missing={sorted(expected_files - actual_files)}, "
            f"unexpected={sorted(actual_files - expected_files)}"
        )
    expected_directories = {
        parent.as_posix()
        for relative in expected_files
        for parent in Path(relative).parents
        if parent != Path(".")
    }
    actual_directories = {
        path.relative_to(formal_root).as_posix()
        for path in formal_root.rglob("*")
        if path.is_dir()
    }
    if actual_directories != expected_directories:
        raise ValueError(
            "formal preparation directory inventory drift: "
            f"missing={sorted(expected_directories - actual_directories)}, "
            f"unexpected={sorted(actual_directories - expected_directories)}"
        )


def _load_and_validate_existing_v09(
    paths: StrictStagePathsV09,
    protocol: Mapping,
) -> tuple[dict | None, dict | None]:
    input_bindings = strict_input_bindings_v09(paths)
    legacy = None
    if paths.legacy_bridge_audit.exists():
        legacy = _load_json_status(
            paths.legacy_bridge_audit,
            "legacy_checkpoint_bridge_external_audit_passed",
        )
        _validate_legacy_bridge_report_v09(
            legacy,
            protocol,
            device=_DEVICE,
            input_bindings=input_bindings,
        )
    resource = None
    if paths.resource_preflight_audit.exists():
        resource = _load_json_status(
            paths.resource_preflight_audit,
            "resource_preflight_passed",
        )
        _validate_resource_preflight_report_v09(resource, protocol)
    return legacy, resource


def _prepare_strict_prerequisites_v09(
    paths: StrictStagePathsV09,
    *,
    protocol: Mapping,
    inputs_loader: Callable[[], FormalBridgeInputsV09 | object],
    legacy_results_root: str | Path,
    legacy_trusted_root: str | Path | None = None,
    bridge_auditor: Callable | None = None,
    resource_auditor: Callable | None = None,
    preparation_lock_path: str | Path | None = None,
    high_load_lock_path: str | Path | None = None,
) -> dict:
    """Prepare fixed reports; dependency injection is limited to synthetic tests."""
    if bridge_auditor is None:
        bridge_auditor = audit_legacy_checkpoint_bridge_v09
    if resource_auditor is None:
        resource_auditor = _audit_formal_action_resources_under_lease_v09
    lock_path = (
        Path(preparation_lock_path)
        if preparation_lock_path is not None
        else _preparation_lock_path_v09()
    )
    with exclusive_high_load_lease_v09(lock_path=lock_path) as preparation_lease:
        _assert_closed_stage_state_v09(paths)
        _assert_formal_preparation_inventory_v09(paths)
        legacy, resource = _load_and_validate_existing_v09(paths, protocol)

        raw_legacy_root = Path(os.path.abspath(legacy_results_root))
        raw_legacy_trusted_root = Path(os.path.abspath(
            legacy_trusted_root if legacy_trusted_root is not None else paths.worktree_root
        ))
        assert_no_reparse_components(raw_legacy_trusted_root, raw_legacy_root)
        if resource is None or legacy is None:
            with exclusive_high_load_lease_v09(lock_path=high_load_lock_path) as high_load_lease:
                live_resource = resource_auditor(
                    protocol,
                    action="training",
                    variant=_VARIANT,
                    lease=high_load_lease,
                )
                _validate_resource_preflight_report_v09(live_resource, protocol)
                if resource is None:
                    resource = live_resource
                    write_json_atomic(paths.resource_preflight_audit, resource)
                    resource = json.loads(paths.resource_preflight_audit.read_text(encoding="utf-8"))
                    _validate_resource_preflight_report_v09(resource, protocol)

                if legacy is None:
                    inputs = inputs_loader()
                    bridge_auditor(
                        protocol,
                        legacy_results_root=raw_legacy_root,
                        inputs=inputs,
                        report_path=paths.legacy_bridge_audit,
                        device=_DEVICE,
                        protected_run_roots=(paths.output_root,),
                    )
                    legacy = _load_json_status(
                        paths.legacy_bridge_audit,
                        "legacy_checkpoint_bridge_external_audit_passed",
                    )
                    _validate_legacy_bridge_report_v09(
                        legacy,
                        protocol,
                        device=_DEVICE,
                        input_bindings=strict_input_bindings_v09(paths),
                    )

        _assert_formal_preparation_inventory_v09(paths)
        prerequisites = strict_prerequisite_hashes_v09(
            paths,
            protocol,
            device=_DEVICE,
        )
        _assert_closed_stage_state_v09(paths)
        return {
            "schema": "historical_multiscale_formal_v09_strict_prerequisite_preparation_v1",
            "status": "strict_prerequisites_prepared",
            "scope": "R09-NEST-S100",
            "preparation_serial_lease": {
                "held": preparation_lease.is_valid(),
                "lock_path": preparation_lease.lock_path,
            },
            "prerequisite_sha256": prerequisites,
            "training_authorization_created": False,
            "formal_training_started": False,
            "formal_prediction_generation_authorized": False,
            "official_scoring_authorized": False,
        }


def prepare_formal_strict_stage_v09() -> dict:
    """Create only the two fixed pre-authorization reports for strict nesting."""
    worktree_root = _production_worktree_root_v09()
    paths = strict_stage_paths_v09(worktree_root)
    _require_clean_worktree_v09(worktree_root)
    _assert_closed_stage_state_v09(paths)
    _assert_formal_preparation_inventory_v09(paths)
    protocol = load_protocol_v09(paths.protocol)
    primary_repository_root = _primary_repository_root_v09(worktree_root)
    return _prepare_strict_prerequisites_v09(
        paths,
        protocol=protocol,
        inputs_loader=lambda: load_sealed_bridge_inputs_v09(
            paths.input_root,
            paths.protocol,
            worktree_root=worktree_root,
            external_audit_path=paths.input_external_audit,
            trusted_source_audit_path=paths.trusted_source_audit,
        ),
        legacy_results_root=primary_repository_root / _LEGACY_RESULTS_ROOT,
        legacy_trusted_root=primary_repository_root,
    )


def main() -> None:
    print(json.dumps(prepare_formal_strict_stage_v09(), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
