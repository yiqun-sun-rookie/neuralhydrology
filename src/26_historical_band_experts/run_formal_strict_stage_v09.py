"""Only production entry for the authorized version-09 strict-nesting run."""
from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile

from artifact_v09 import (
    assert_no_reparse_components,
    canonical_sha256,
    is_reparse_point,
    sha256_file,
)
from formal_action_resources_v09 import (
    AcceleratorMemorySnapshot,
    build_formal_action_peak_estimate_v09,
)
from formal_action_runtime_v09 import _run_authorized_formal_action_v09
from formal_input_contract_v09 import DYNAMIC_COLUMNS_V09
from formal_training_data_v09 import load_sealed_training_inputs_v09
from formal_v09_protocol import load_protocol_v09
from memory_safety_v09 import GIB, HostMemorySnapshot, MemorySafetyPolicy
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
    "src/26_historical_band_experts/create_formal_strict_authorization_v09.py",
    "src/26_historical_band_experts/formal_action_resources_v09.py",
    "src/26_historical_band_experts/formal_action_runtime_v09.py",
    "src/26_historical_band_experts/formal_training_data_v09.py",
    "src/26_historical_band_experts/formal_v09_protocol.py",
    "src/26_historical_band_experts/launch_gate_v09.py",
    "src/26_historical_band_experts/memory_safety_v09.py",
    "src/26_historical_band_experts/models_formal_v09.py",
    "src/26_historical_band_experts/models_v03.py",
    "src/26_historical_band_experts/prepare_formal_strict_stage_v09.py",
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


def _load_json_status_and_sha256(path: Path, expected_status: str) -> tuple[dict, str]:
    if not path.is_file() or is_reparse_point(path):
        raise FileNotFoundError(f"strict prerequisite is missing: {path}")
    payload = path.read_bytes()
    report = json.loads(payload.decode("utf-8"))
    if report.get("status") != expected_status:
        raise ValueError(f"strict prerequisite status drift: {path.name}")
    return report, hashlib.sha256(payload).hexdigest()


def _load_json_status(path: Path, expected_status: str) -> dict:
    report, _ = _load_json_status_and_sha256(path, expected_status)
    return report


def _require_exact_json_value(actual, expected, *, label: str) -> None:
    """Reject Python equality aliases such as ``False == 0`` in evidence JSON."""
    if type(actual) is not type(expected):
        raise ValueError(f"{label} type drift")
    if isinstance(expected, dict):
        if set(actual) != set(expected):
            raise ValueError(f"{label} schema drift")
        for key, expected_value in expected.items():
            _require_exact_json_value(actual[key], expected_value, label=f"{label}.{key}")
        return
    if isinstance(expected, list):
        if len(actual) != len(expected):
            raise ValueError(f"{label} length drift")
        for index, expected_value in enumerate(expected):
            _require_exact_json_value(actual[index], expected_value, label=f"{label}[{index}]")
        return
    if actual != expected:
        raise ValueError(f"{label} value drift")


def _validate_legacy_bridge_report_v09(
    legacy: dict,
    protocol: dict,
    *,
    device: str,
    input_bindings: Mapping,
) -> None:
    from audit_legacy_checkpoint_bridge_v09 import _environment_binding_v09, _source_bindings_v09

    expected_keys = {
        "schema",
        "status",
        "protocol_canonical_sha256",
        "source_bindings",
        "environment_binding",
        "input_bindings",
        "legacy_dynamic_input_names",
        "verified_identity",
        "runs",
        "run_count",
        "synthetic_panel_rows_per_run",
        "real_panel_rows_per_run",
        "real_panel_rows_total",
        "maximum_prediction_difference",
        "training_target_value_reads",
        "formal_evaluation_observation_reads",
    }
    if set(legacy) != expected_keys:
        raise ValueError("legacy bridge report schema drift")
    if legacy.get("schema") != "historical_multiscale_formal_v09_legacy_checkpoint_bridge_audit_v1":
        raise ValueError("legacy bridge report schema drift")
    if legacy.get("status") != "legacy_checkpoint_bridge_external_audit_passed":
        raise ValueError("legacy bridge report status drift")
    if legacy.get("protocol_canonical_sha256") != canonical_sha256(protocol):
        raise ValueError("legacy bridge protocol binding drift")
    if legacy.get("source_bindings") != _source_bindings_v09():
        raise ValueError("legacy bridge source binding drift")
    if legacy.get("environment_binding") != _environment_binding_v09(device):
        raise ValueError("legacy bridge environment binding drift")
    # The core key names live in the hash-bound legacy configs, not in the protocol, but the
    # sealed forcing columns were built from the same frozen tuple, so this binds by value.
    if len(DYNAMIC_COLUMNS_V09) != int(protocol["dynamic_input_count"]):
        raise ValueError("sealed forcing column contract disagrees with the protocol")
    _require_exact_json_value(
        legacy.get("legacy_dynamic_input_names"),
        list(DYNAMIC_COLUMNS_V09),
        label="legacy bridge report geometry.legacy_dynamic_input_names",
    )
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
        "input_bindings": dict(input_bindings),
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
        _require_exact_json_value(
            legacy.get(key),
            expected,
            label=f"legacy bridge report geometry.{key}",
        )


def _validate_resource_preflight_report_v09(resource: Mapping, protocol: Mapping) -> None:
    """Recompute every launch-relevant claim in one persisted resource report."""
    if not isinstance(resource, Mapping):
        raise ValueError("resource preflight report must be an object")
    expected_keys = {
        "status",
        "action",
        "variant",
        "authorization_checked",
        "estimate",
        "host_snapshot",
        "accelerator_snapshot",
        "host",
        "accelerator",
    }
    if set(resource) != expected_keys:
        raise ValueError("resource preflight report schema drift")
    fixed = {
        "status": "resource_preflight_passed",
        "action": "training",
        "variant": _VARIANT,
        "authorization_checked": False,
    }
    for key, expected in fixed.items():
        label = "authorization" if key == "authorization_checked" else "binding"
        _require_exact_json_value(
            resource.get(key),
            expected,
            label=f"resource preflight {label}.{key}",
        )
    expected_estimate = build_formal_action_peak_estimate_v09(
        protocol,
        "training",
        variant=_VARIANT,
    )
    _require_exact_json_value(
        resource.get("estimate"),
        expected_estimate,
        label="resource preflight estimate",
    )

    host_snapshot_payload = resource.get("host_snapshot")
    if not isinstance(host_snapshot_payload, Mapping) or set(host_snapshot_payload) != {
        "total_bytes",
        "available_bytes",
        "process_rss_bytes",
        "commit_headroom_bytes",
    }:
        raise ValueError("resource preflight host snapshot schema drift")
    if any(type(host_snapshot_payload[key]) is not int for key in host_snapshot_payload):
        raise ValueError("resource preflight host snapshot type drift")
    try:
        host_snapshot = HostMemorySnapshot(**host_snapshot_payload)
    except (TypeError, ValueError) as exc:
        raise ValueError("resource preflight host snapshot drift") from exc
    policy = MemorySafetyPolicy.from_total(host_snapshot.total_bytes, protocol["memory_safety"])
    host_peak = expected_estimate["estimated_peak_bytes"]
    guarded_host_peak = math.ceil(host_peak * policy.estimated_peak_safety_factor)
    host = resource.get("host")
    expected_host_keys = {
        "safe",
        "long_running",
        "method",
        "estimated_peak_bytes",
        "evidence_sha256",
        "guarded_estimated_peak_bytes",
        "available_after_guarded_peak_bytes",
        "commit_headroom_after_guarded_peak_bytes",
        "physical_reserve_bytes",
        "commit_headroom_reserve_bytes",
        "serial_lease",
    }
    if not isinstance(host, Mapping) or set(host) != expected_host_keys or host.get("safe") is not True:
        raise ValueError("resource preflight host safety drift")
    fixed_host = {
        "long_running": True,
        "method": expected_estimate["method"],
        "estimated_peak_bytes": host_peak,
        "evidence_sha256": expected_estimate["evidence_sha256"],
        "guarded_estimated_peak_bytes": guarded_host_peak,
        "available_after_guarded_peak_bytes": host_snapshot.available_bytes - guarded_host_peak,
        "commit_headroom_after_guarded_peak_bytes": host_snapshot.commit_headroom_bytes - guarded_host_peak,
        "physical_reserve_bytes": policy.physical_reserve_bytes,
        "commit_headroom_reserve_bytes": policy.commit_headroom_reserve_bytes,
    }
    for key, expected in fixed_host.items():
        try:
            _require_exact_json_value(host.get(key), expected, label=f"resource preflight host.{key}")
        except ValueError as exc:
            raise ValueError("resource preflight host arithmetic drift") from exc
    if host["available_after_guarded_peak_bytes"] < policy.physical_reserve_bytes:
        raise ValueError("resource preflight host physical reserve drift")
    if host["commit_headroom_after_guarded_peak_bytes"] < policy.commit_headroom_reserve_bytes:
        raise ValueError("resource preflight host commit reserve drift")
    lease = host.get("serial_lease")
    expected_lock = str(
        Path(tempfile.gettempdir(), "neuralhydrology_historical_multiscale_v09_high_load.lock")
    )
    if not isinstance(lease, Mapping) or set(lease) != {"held", "lock_path"}:
        raise ValueError("resource preflight serial lease drift")
    _require_exact_json_value(
        dict(lease),
        {"held": True, "lock_path": expected_lock},
        label="resource preflight serial lease",
    )

    accelerator_snapshot_payload = resource.get("accelerator_snapshot")
    if not isinstance(accelerator_snapshot_payload, Mapping) or set(accelerator_snapshot_payload) != {
        "device_index",
        "device_name",
        "total_bytes",
        "available_bytes",
    }:
        raise ValueError("resource preflight accelerator snapshot schema drift")
    if (
        type(accelerator_snapshot_payload["device_index"]) is not int
        or type(accelerator_snapshot_payload["device_name"]) is not str
        or type(accelerator_snapshot_payload["total_bytes"]) is not int
        or type(accelerator_snapshot_payload["available_bytes"]) is not int
    ):
        raise ValueError("resource preflight accelerator snapshot type drift")
    try:
        accelerator_snapshot = AcceleratorMemorySnapshot(**accelerator_snapshot_payload)
    except (TypeError, ValueError) as exc:
        raise ValueError("resource preflight accelerator snapshot drift") from exc
    if accelerator_snapshot.device_index != 0:
        raise ValueError("resource preflight accelerator device drift")
    accelerator = resource.get("accelerator")
    expected_accelerator_keys = {
        "required",
        "safe",
        "device_index",
        "device_name",
        "estimated_peak_bytes",
        "guarded_estimated_peak_bytes",
        "available_after_guarded_peak_bytes",
        "reserve_bytes",
    }
    if (
        not isinstance(accelerator, Mapping)
        or set(accelerator) != expected_accelerator_keys
        or accelerator.get("required") is not True
        or accelerator.get("safe") is not True
    ):
        raise ValueError("resource preflight accelerator safety drift")
    expected_accelerator_peak = expected_estimate["evidence"]["accelerator_estimated_peak_bytes"]
    resource_spec = protocol["formal_action_resources"]["training"]
    guarded_accelerator_peak = math.ceil(
        expected_accelerator_peak * float(resource_spec["accelerator_safety_factor"])
    )
    accelerator_reserve = math.ceil(float(resource_spec["accelerator_reserve_gib"]) * GIB)
    fixed_accelerator = {
        "device_index": accelerator_snapshot.device_index,
        "device_name": accelerator_snapshot.device_name,
        "estimated_peak_bytes": expected_accelerator_peak,
        "guarded_estimated_peak_bytes": guarded_accelerator_peak,
        "available_after_guarded_peak_bytes": accelerator_snapshot.available_bytes - guarded_accelerator_peak,
        "reserve_bytes": accelerator_reserve,
    }
    for key, expected in fixed_accelerator.items():
        try:
            _require_exact_json_value(
                accelerator.get(key),
                expected,
                label=f"resource preflight accelerator.{key}",
            )
        except ValueError as exc:
            raise ValueError("resource preflight accelerator arithmetic drift") from exc
    if accelerator["available_after_guarded_peak_bytes"] < accelerator_reserve:
        raise ValueError("resource preflight accelerator reserve drift")


def strict_input_bindings_v09(paths: StrictStagePathsV09) -> dict[str, str]:
    """Hash the three current sealed-input evidence files from their validated bytes."""
    _, seal_sha256 = _load_json_status_and_sha256(paths.input_root / "seal.json", "sealed")
    _, input_audit_sha256 = _load_json_status_and_sha256(
        paths.input_external_audit,
        "complete_input_audit_passed",
    )
    _, trusted_audit_sha256 = _load_json_status_and_sha256(
        paths.trusted_source_audit,
        "complete_trusted_training_target_audit",
    )
    return {
        "input_seal_sha256": seal_sha256,
        "complete_input_external_audit_sha256": input_audit_sha256,
        "trusted_source_external_audit_sha256": trusted_audit_sha256,
    }


def strict_prerequisite_hashes_v09(
    paths: StrictStagePathsV09,
    protocol: dict,
    *,
    device: str = "cuda:0",
) -> dict[str, str]:
    input_bindings = strict_input_bindings_v09(paths)
    legacy, legacy_sha256 = _load_json_status_and_sha256(
        paths.legacy_bridge_audit,
        "legacy_checkpoint_bridge_external_audit_passed",
    )
    resource, resource_sha256 = _load_json_status_and_sha256(
        paths.resource_preflight_audit,
        "resource_preflight_passed",
    )
    _validate_legacy_bridge_report_v09(
        legacy,
        protocol,
        device=device,
        input_bindings=input_bindings,
    )
    _validate_resource_preflight_report_v09(resource, protocol)
    return {
        "input_seal": input_bindings["input_seal_sha256"],
        "input_artifact_external_audit": input_bindings["complete_input_external_audit_sha256"],
        "trusted_target_external_audit": input_bindings["trusted_source_external_audit_sha256"],
        "legacy_checkpoint_bridge_external_audit": legacy_sha256,
        "training_resource_preflight_external_audit": resource_sha256,
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
