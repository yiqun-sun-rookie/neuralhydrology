"""Only production entry for the authorized version-09 strict-nesting run."""
from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
import subprocess

from artifact_v09 import assert_no_reparse_components, canonical_sha256, sha256_file
from formal_action_runtime_v09 import _run_authorized_formal_action_v09
from formal_training_data_v09 import load_sealed_training_inputs_v09
from formal_v09_protocol import load_protocol_v09
from stage_authorization_v09 import stage_authorization_paths_v09
from train_strict_formal_v09 import run_strict_training_v09

_SCOPE = "R09-NEST-S100"
_RUN_ID = "R09-NEST-S100"
_SEED = 100
_VARIANT = "strict_nesting_pair"
_FORMAL_ROOT = Path("results/26_historical_band_experts/formal_v09")
_EXECUTABLE_FILES = (
    "src/26_historical_band_experts/artifact_v09.py",
    "src/26_historical_band_experts/bands_formal_v09.py",
    "src/26_historical_band_experts/formal_action_resources_v09.py",
    "src/26_historical_band_experts/formal_action_runtime_v09.py",
    "src/26_historical_band_experts/formal_training_data_v09.py",
    "src/26_historical_band_experts/formal_v09_protocol.py",
    "src/26_historical_band_experts/launch_gate_v09.py",
    "src/26_historical_band_experts/memory_safety_v09.py",
    "src/26_historical_band_experts/models_formal_v09.py",
    "src/26_historical_band_experts/models_v03.py",
    "src/26_historical_band_experts/run_formal_strict_stage_v09.py",
    "src/26_historical_band_experts/stage_authorization_v09.py",
    "src/26_historical_band_experts/strict_nesting_formal_v09.py",
    "src/26_historical_band_experts/train_strict_formal_v09.py",
    "src/26_historical_band_experts/train_strict_v06.py",
    "src/fair_benchmark/task_memory_v09.py",
    "neuralhydrology/modelzoo/head.py",
)


@dataclass(frozen=True)
class StrictStagePathsV09:
    worktree_root: Path
    protocol: Path
    input_root: Path
    input_external_audit: Path
    trusted_source_audit: Path
    legacy_bridge_audit: Path
    resource_preflight_audit: Path
    authorization: Path
    consumption: Path
    output_root: Path


def strict_stage_paths_v09(worktree_root: str | Path) -> StrictStagePathsV09:
    root = Path(os.path.abspath(worktree_root))
    assert_no_reparse_components(root, root)
    formal_root = root / _FORMAL_ROOT
    authorization, consumption = stage_authorization_paths_v09(_SCOPE, worktree_root=root)
    paths = StrictStagePathsV09(
        worktree_root=root,
        protocol=root / "src/26_historical_band_experts/configs/formal_v09_protocol.json",
        input_root=formal_root / "input_attempt_01",
        input_external_audit=formal_root / "input_attempt_01.external_audit.json",
        trusted_source_audit=formal_root / "input_attempt_01.trusted_source_external_audit.json",
        legacy_bridge_audit=formal_root / "R09-NEST-S100.legacy_checkpoint_bridge_external_audit.json",
        resource_preflight_audit=formal_root / "R09-NEST-S100.training_resource_preflight_external_audit.json",
        authorization=authorization,
        consumption=consumption,
        output_root=formal_root / "strict_nesting/R09-NEST-S100",
    )
    for path in (
            paths.protocol,
            paths.input_root,
            paths.input_external_audit,
            paths.trusted_source_audit,
            paths.legacy_bridge_audit,
            paths.resource_preflight_audit,
            paths.authorization,
            paths.consumption,
            paths.output_root,
    ):
        assert_no_reparse_components(root, path)
    return paths


def strict_executable_tree_v09(worktree_root: str | Path) -> dict:
    root = Path(os.path.abspath(worktree_root))
    assert_no_reparse_components(root, root)
    files = []
    for relative_path in _EXECUTABLE_FILES:
        path = root / relative_path
        assert_no_reparse_components(root, path)
        if not path.is_file():
            raise FileNotFoundError(f"strict executable is missing: {relative_path}")
        files.append({
            "relative_path": relative_path,
            "size_bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        })
    return {
        "schema": "historical_multiscale_formal_v09_strict_executable_tree_v1",
        "files": files,
        "tree_sha256": canonical_sha256(files),
    }


def _load_json_status(path: Path, expected_status: str) -> dict:
    if not path.is_file():
        raise FileNotFoundError(f"strict prerequisite is missing: {path}")
    report = json.loads(path.read_text(encoding="utf-8"))
    if report.get("status") != expected_status:
        raise ValueError(f"strict prerequisite status drift: {path.name}")
    return report


def _validate_legacy_bridge_report_v09(legacy: dict, protocol: dict, *, device: str) -> None:
    from audit_legacy_checkpoint_bridge_v09 import _environment_binding_v09, _source_bindings_v09

    if legacy.get("protocol_canonical_sha256") != canonical_sha256(protocol):
        raise ValueError("legacy bridge protocol binding drift")
    if legacy.get("source_bindings") != _source_bindings_v09():
        raise ValueError("legacy bridge source binding drift")
    if legacy.get("environment_binding") != _environment_binding_v09(device):
        raise ValueError("legacy bridge environment binding drift")
    registered_runs = protocol.get("legacy_reference", {}).get("runs")
    if not isinstance(registered_runs, list) or len(registered_runs) != 8:
        raise ValueError("legacy bridge registered run geometry drift")
    rows_per_run = int(protocol["basin_count"]) * 12
    expected_runs = [{
        "seed": run["seed"],
        "run_id": run["run_id"],
        "config_sha256": run["config_sha256"],
        "checkpoint_sha256": run["checkpoint_epoch030_sha256"],
        "real_panel_rows": rows_per_run,
    } for run in registered_runs]
    expected_identity = {
        "verified": True,
        "run_count": 8,
        "file_count": 16,
        "seeds": [run["seed"] for run in registered_runs],
        "recorded_code_commit_prefix": protocol["legacy_reference"]["recorded_code_commit_prefix"],
    }
    fixed = {
        "verified_identity": expected_identity,
        "runs": expected_runs,
        "run_count": 8,
        "synthetic_panel_rows_per_run": 2,
        "real_panel_rows_per_run": rows_per_run,
        "real_panel_rows_total": rows_per_run * 8,
        "maximum_prediction_difference": 0.0,
        "training_target_value_reads": 0,
        "formal_evaluation_observation_reads": 0,
    }
    for key, expected in fixed.items():
        if legacy.get(key) != expected:
            raise ValueError(f"legacy bridge report geometry drift: {key}")


def strict_prerequisite_hashes_v09(
    paths: StrictStagePathsV09,
    protocol: dict,
    *,
    device: str = "cuda:0",
) -> dict[str, str]:
    seal = _load_json_status(paths.input_root / "seal.json", "sealed")
    del seal
    _load_json_status(paths.input_external_audit, "complete_input_audit_passed")
    _load_json_status(paths.trusted_source_audit, "complete_trusted_training_target_audit")
    legacy = _load_json_status(paths.legacy_bridge_audit, "legacy_checkpoint_bridge_external_audit_passed")
    resource = _load_json_status(paths.resource_preflight_audit, "resource_preflight_passed")
    _validate_legacy_bridge_report_v09(legacy, protocol, device=device)
    if resource.get("action") != "training" or resource.get("variant") != _VARIANT:
        raise ValueError("strict training resource preflight binding drift")
    return {
        "input_seal": sha256_file(paths.input_root / "seal.json"),
        "input_artifact_external_audit": sha256_file(paths.input_external_audit),
        "trusted_target_external_audit": sha256_file(paths.trusted_source_audit),
        "legacy_checkpoint_bridge_external_audit": sha256_file(paths.legacy_bridge_audit),
        "training_resource_preflight_external_audit": sha256_file(paths.resource_preflight_audit),
    }


def _require_clean_bound_git_v09(worktree_root: Path, expected_commit: str) -> None:
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
    if head != expected_commit:
        raise ValueError("strict authorization Git commit drift")
    if status:
        raise ValueError("strict formal launch requires a clean Git worktree")


def run_formal_strict_stage_v09() -> dict:
    """Execute exactly one fixed run; this function intentionally has no arguments."""
    worktree_root = Path(os.path.abspath(Path(__file__).parents[2]))
    paths = strict_stage_paths_v09(worktree_root)
    if not paths.authorization.is_file():
        raise FileNotFoundError("strict one-use authorization is absent")
    if paths.consumption.exists():
        raise FileExistsError("strict one-use authorization was already consumed")
    if paths.output_root.exists():
        raise FileExistsError("strict formal output root already exists")
    protocol = load_protocol_v09(paths.protocol)
    prerequisites = strict_prerequisite_hashes_v09(paths, protocol)
    executable_tree = strict_executable_tree_v09(worktree_root)
    receipt = json.loads(paths.authorization.read_text(encoding="utf-8"))
    _require_clean_bound_git_v09(worktree_root, receipt.get("git_commit"))
    inputs = load_sealed_training_inputs_v09(
        paths.input_root,
        paths.protocol,
        worktree_root=worktree_root,
        external_audit_path=paths.input_external_audit,
        trusted_source_audit_path=paths.trusted_source_audit,
    )
    output_root = str(paths.output_root.resolve())
    bindings = {
        "protocol_sha256": canonical_sha256(protocol),
        "prerequisite_sha256": prerequisites,
        "executable_tree_sha256": executable_tree["tree_sha256"],
        "worktree_root": str(worktree_root.resolve()),
        "output_root": output_root,
    }
    claim = {
        "run_id": _RUN_ID,
        "seed": _SEED,
        "variant": _VARIANT,
        "output_root": output_root,
    }
    return _run_authorized_formal_action_v09(
        protocol,
        action="training",
        variant=_VARIANT,
        callback=run_strict_training_v09,
        authorization_scope=_SCOPE,
        stage_bindings=bindings,
        stage_worktree_root=worktree_root,
        run_claim=claim,
        callback_kwargs={
            "inputs": inputs,
            "protocol": protocol,
            "output_dir": paths.output_root,
            "device": "cuda:0",
        },
    )


def main() -> None:
    print(json.dumps(run_formal_strict_stage_v09(), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
