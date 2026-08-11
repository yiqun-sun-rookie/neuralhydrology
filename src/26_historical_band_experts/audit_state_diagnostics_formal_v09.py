"""Second-process byte-exact replay audit of formal version-09 state diagnostics."""
from __future__ import annotations

from collections.abc import Mapping
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import sys

import numpy as np

IDEA_ROOT = Path(__file__).resolve().parent
if str(IDEA_ROOT) not in sys.path:
    sys.path.insert(0, str(IDEA_ROOT))

from artifact_v09 import assert_no_reparse_tree, canonical_sha256, sha256_file, write_json_atomic  # noqa: E402
import state_diagnostics_formal_v09 as diagnostics  # noqa: E402

_ROOT_SCHEMA = "historical_multiscale_formal_v09_state_diagnostics_root_v1"
_SEED_SCHEMA = "historical_multiscale_formal_v09_state_diagnostics_manifest_v1"
_AUDIT_SCHEMA = "historical_multiscale_formal_v09_state_diagnostics_external_audit_v1"
_EPOCHS = (10, 20, 30)
_EXPECTED_SEEDS = tuple(range(100, 801, 100))
_EXPECTED_FILES = {
    "epoch010_panel_keys.int32.npy",
    "epoch010_panel_state_norms.float32.npy",
    "epoch020_panel_keys.int32.npy",
    "epoch020_panel_state_norms.float32.npy",
    "epoch030_panel_keys.int32.npy",
    "epoch030_panel_state_norms.float32.npy",
    "epoch030_all_training_keys.int32.npy",
    "epoch030_all_training_state_norms.float32.npy",
    "summary.json",
    "manifest.json",
}
_ARRAY_LAYOUT = {
    "epoch010_panel_keys": ("epoch010_panel_keys.int32.npy", "<i4", "panel_keys"),
    "epoch010_panel_state_norms": ("epoch010_panel_state_norms.float32.npy", "<f4", "panel_states"),
    "epoch020_panel_keys": ("epoch020_panel_keys.int32.npy", "<i4", "panel_keys"),
    "epoch020_panel_state_norms": ("epoch020_panel_state_norms.float32.npy", "<f4", "panel_states"),
    "epoch030_panel_keys": ("epoch030_panel_keys.int32.npy", "<i4", "panel_keys"),
    "epoch030_panel_state_norms": ("epoch030_panel_state_norms.float32.npy", "<f4", "panel_states"),
    "epoch030_all_training_keys": ("epoch030_all_training_keys.int32.npy", "<i4", "all_keys"),
    "epoch030_all_training_state_norms": (
        "epoch030_all_training_state_norms.float32.npy",
        "<f4",
        "all_states",
    ),
}


class StateDiagnosticsAuditError(ValueError):
    """Raised when independent state replay cannot reproduce the sealed diagnostics."""


def _load_json(path: Path) -> dict:
    def reject_constant(value: str):
        raise StateDiagnosticsAuditError(f"non-finite JSON constant is forbidden: {value}")

    try:
        value = json.loads(path.read_text(encoding="utf-8"), parse_constant=reject_constant)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise StateDiagnosticsAuditError(f"invalid state diagnostic JSON: {path}") from exc
    if not isinstance(value, dict):
        raise StateDiagnosticsAuditError(f"state diagnostic JSON root must be an object: {path}")
    return value


def _raw_sha256(array: np.ndarray) -> str:
    return hashlib.sha256(array.tobytes(order="C")).hexdigest()


def _npy_bytes_sha256(array: np.ndarray) -> str:
    buffer = io.BytesIO()
    np.save(buffer, array, allow_pickle=False)
    return hashlib.sha256(buffer.getvalue()).hexdigest()


def _validate_root_manifest(
    diagnostic_root: Path,
    formal_root: Path,
    specs,
    environment: Mapping,
) -> tuple[dict, dict[int, dict]]:
    manifest_path = diagnostic_root / "manifest.json"
    manifest = _load_json(manifest_path)
    if manifest.get("schema") != _ROOT_SCHEMA or manifest.get("status") != "state_diagnostics_complete":
        raise StateDiagnosticsAuditError("state diagnostic root schema or status drift")
    if manifest.get("seed_count") != 8 or manifest.get("seeds") != list(_EXPECTED_SEEDS):
        raise StateDiagnosticsAuditError("state diagnostic root seed coverage drift")
    prohibited = {
        "training_target_reads": 0,
        "formal_evaluation_observation_reads": 0,
        "recent_path_executed": False,
        "flow_head_executed": False,
        "formal_period_predictions_generated": False,
        "official_score_called": False,
    }
    for key, expected in prohibited.items():
        if type(manifest.get(key)) is not type(expected) or manifest.get(key) != expected:
            raise StateDiagnosticsAuditError(f"state diagnostic prohibited activity drift: {key}")
    if manifest.get("environment") != dict(environment):
        raise StateDiagnosticsAuditError("state diagnostic replay environment differs")
    if manifest.get("environment_sha256") != canonical_sha256(environment):
        raise StateDiagnosticsAuditError("state diagnostic environment SHA-256 drift")
    diagnostic_source = diagnostics._diagnostic_source_context_v09()
    if manifest.get("diagnostic_source") != diagnostic_source:
        raise StateDiagnosticsAuditError("state diagnostic executable source differs")
    if manifest.get("diagnostic_source_sha256") != canonical_sha256(diagnostic_source):
        raise StateDiagnosticsAuditError("state diagnostic executable source SHA-256 drift")
    run_order_sha256 = diagnostics._run_order_binding_v09(specs)
    if manifest.get("run_order_canonical_sha256") != run_order_sha256:
        raise StateDiagnosticsAuditError("state diagnostic run-order binding drift")
    preregistration_sha256 = sha256_file(diagnostics._preregistration_path_v09())
    if manifest.get("state_diagnostics_preregistration_sha256") != preregistration_sha256:
        raise StateDiagnosticsAuditError("state diagnostic pre-registration binding drift")
    training_audit_path = formal_root / "training_external_audit.json"
    if manifest.get("training_external_audit_sha256") != sha256_file(training_audit_path):
        raise StateDiagnosticsAuditError("state diagnostic training-audit binding drift")
    children = manifest.get("children")
    if not isinstance(children, list) or len(children) != 8:
        raise StateDiagnosticsAuditError("state diagnostic child inventory drift")
    by_seed = {entry.get("seed"): dict(entry) for entry in children if isinstance(entry, Mapping)}
    if set(by_seed) != set(_EXPECTED_SEEDS) or len(by_seed) != 8:
        raise StateDiagnosticsAuditError("state diagnostic child seed inventory drift")
    expected_names = {"manifest.json", *(f"E09-CONTINUOUS_s{seed}" for seed in _EXPECTED_SEEDS)}
    actual_names = {path.name for path in diagnostic_root.iterdir()}
    if actual_names != expected_names:
        raise StateDiagnosticsAuditError("state diagnostic root directory inventory drift")
    return manifest, by_seed


def _validate_seed_directory(
    child_root: Path,
    child_record: Mapping,
    *,
    seed: int,
    expected_provenance: Mapping,
) -> tuple[dict, dict, dict[str, np.ndarray]]:
    if child_record.get("relative_path") != child_root.name or child_record.get("seed") != seed:
        raise StateDiagnosticsAuditError(f"state diagnostic child identity drift for seed {seed}")
    if not child_root.is_dir():
        raise StateDiagnosticsAuditError(f"state diagnostic seed directory is missing for seed {seed}")
    assert_no_reparse_tree(child_root)
    actual_files = {path.name for path in child_root.iterdir() if path.is_file()}
    if actual_files != _EXPECTED_FILES:
        raise StateDiagnosticsAuditError(f"state diagnostic seed file inventory drift for seed {seed}")
    binding = diagnostics._directory_binding_v09(child_root)
    if (child_record.get("directory_file_count") != binding["file_count"] or
            child_record.get("directory_files_sha256") != binding["files_sha256"]):
        raise StateDiagnosticsAuditError(f"state diagnostic directory hash drift for seed {seed}")
    manifest_path = child_root / "manifest.json"
    if child_record.get("manifest_sha256") != sha256_file(manifest_path):
        raise StateDiagnosticsAuditError(f"state diagnostic manifest hash drift for seed {seed}")
    manifest = _load_json(manifest_path)
    if (manifest.get("schema") != _SEED_SCHEMA or manifest.get("status") != "state_diagnostics_complete" or
            manifest.get("seed") != seed):
        raise StateDiagnosticsAuditError(f"state diagnostic seed manifest identity drift for seed {seed}")
    if manifest.get("provenance") != dict(expected_provenance):
        raise StateDiagnosticsAuditError(f"state diagnostic provenance drift for seed {seed}")
    if (manifest.get("training_target_reads") != 0 or
            manifest.get("formal_evaluation_observation_reads") != 0 or
            manifest.get("recent_path_executed") is not False or
            manifest.get("flow_head_executed") is not False):
        raise StateDiagnosticsAuditError(f"state diagnostic prohibited activity for seed {seed}")
    arrays = manifest.get("arrays")
    if not isinstance(arrays, Mapping) or set(arrays) != set(_ARRAY_LAYOUT):
        raise StateDiagnosticsAuditError(f"state diagnostic array inventory drift for seed {seed}")
    loaded = {}
    for name, (filename, dtype, _role) in _ARRAY_LAYOUT.items():
        record = arrays[name]
        if not isinstance(record, Mapping) or record.get("relative_path") != filename:
            raise StateDiagnosticsAuditError(f"state diagnostic array path drift: seed {seed}, {name}")
        path = child_root / filename
        array = np.load(path, mmap_mode="r", allow_pickle=False)
        if array.dtype.str != dtype or not array.flags.c_contiguous or list(array.shape) != record.get("shape"):
            raise StateDiagnosticsAuditError(f"state diagnostic array layout drift: seed {seed}, {name}")
        if record.get("dtype") != dtype or record.get("c_contiguous") is not True:
            raise StateDiagnosticsAuditError(f"state diagnostic recorded layout drift: seed {seed}, {name}")
        if record.get("raw_bytes_sha256") != _raw_sha256(array):
            raise StateDiagnosticsAuditError(f"state diagnostic raw hash drift: seed {seed}, {name}")
        if record.get("file_sha256") != sha256_file(path):
            raise StateDiagnosticsAuditError(f"state diagnostic file hash drift: seed {seed}, {name}")
        loaded[name] = array
    summary = _load_json(child_root / "summary.json")
    return manifest, summary, loaded


def _assert_replay_array(
    stored: np.ndarray,
    replay: np.ndarray,
    *,
    seed: int,
    name: str,
    stored_file_sha256: str,
) -> None:
    if stored.dtype.str != replay.dtype.str or stored.shape != replay.shape or not replay.flags.c_contiguous:
        raise StateDiagnosticsAuditError(f"state diagnostic replay layout differs: seed {seed}, {name}")
    if _raw_sha256(stored) != _raw_sha256(replay):
        raise StateDiagnosticsAuditError(f"state diagnostic replay raw bytes differ: seed {seed}, {name}")
    if _npy_bytes_sha256(replay) != stored_file_sha256:
        raise StateDiagnosticsAuditError(f"state diagnostic replay NumPy file differs: seed {seed}, {name}")


def _expected_provenance(
    root_manifest: Mapping,
    training_audit: Mapping,
    run_record: Mapping,
    spec,
    checkpoint_hashes: Mapping,
) -> dict:
    return {
        **dict(root_manifest["input_bindings"]),
        "training_external_audit_sha256": root_manifest["training_external_audit_sha256"],
        "training_source_context_sha256": training_audit["source_context_sha256"],
        "run_order_canonical_sha256": root_manifest["run_order_canonical_sha256"],
        "state_diagnostics_preregistration_sha256": root_manifest[
            "state_diagnostics_preregistration_sha256"],
        "diagnostic_environment_sha256": root_manifest["environment_sha256"],
        "diagnostic_source_tree_sha256": root_manifest["diagnostic_source"]["tree_sha256"],
        "run_id": spec.run_id,
        "run_seal_sha256": run_record["run_seal_sha256"],
        "checkpoint_sha256": dict(checkpoint_hashes),
    }


def audit_history_state_diagnostics_v09(
    input_root: str | Path,
    formal_root: str | Path,
    run_order,
    diagnostic_root: str | Path,
    report_path: str | Path,
    device,
    *,
    require_formal_geometry: bool = True,
) -> dict:
    """Recompute every state array and compare raw and complete NumPy bytes exactly."""
    formal_root = Path(os.path.abspath(formal_root)).resolve()
    input_root = Path(os.path.abspath(input_root)).resolve()
    diagnostic_root = Path(os.path.abspath(diagnostic_root)).resolve()
    report_path = Path(os.path.abspath(report_path)).resolve()
    if diagnostic_root != formal_root / "state_diagnostics":
        raise StateDiagnosticsAuditError("state diagnostic root must use the fixed formal path")
    if report_path.parent != formal_root or diagnostic_root == report_path or diagnostic_root in report_path.parents:
        raise StateDiagnosticsAuditError("state diagnostic external audit must be outside the diagnostic tree")
    if report_path.name != "state_diagnostics_external_audit.json":
        raise StateDiagnosticsAuditError("state diagnostic external audit filename drift")
    if report_path.exists():
        raise FileExistsError(f"state diagnostic external audit already exists: {report_path}")
    if not diagnostic_root.is_dir():
        raise FileNotFoundError(f"state diagnostic root is missing: {diagnostic_root}")
    assert_no_reparse_tree(diagnostic_root)
    specs = diagnostics._resolve_run_order_v09(run_order)
    continuous = [spec for spec in specs if spec.variant == "continuous_multiscale_history"]
    if len(continuous) != 8 or tuple(spec.seed for spec in continuous) != _EXPECTED_SEEDS:
        raise StateDiagnosticsAuditError("state diagnostic replay requires the eight frozen continuous runs")
    environment = diagnostics._deterministic_environment_v09(device)
    root_manifest, children = _validate_root_manifest(diagnostic_root, formal_root, specs, environment)
    training_audit, audited_runs = diagnostics._load_training_audit_v09(formal_root)
    if root_manifest.get("input_bindings") != training_audit.get("input_bindings"):
        raise StateDiagnosticsAuditError("state diagnostic input binding differs from training audit")
    if root_manifest.get("training_source_context_sha256") != training_audit.get("source_context_sha256"):
        raise StateDiagnosticsAuditError("state diagnostic source binding differs from training audit")
    inputs = diagnostics._load_diagnostic_inputs_v09(input_root, formal_root)
    if hasattr(inputs, "targets"):
        raise StateDiagnosticsAuditError("state diagnostic replay refuses an input object exposing targets")
    actual_input_bindings = {
        "input_seal_sha256": inputs.input_seal_sha256,
        "input_external_audit_sha256": inputs.external_audit_sha256,
        "trusted_source_audit_sha256": inputs.trusted_source_audit_sha256,
    }
    if root_manifest.get("input_bindings") != actual_input_bindings:
        raise StateDiagnosticsAuditError("state diagnostic replay input hash drift")
    basin_count = len(inputs.basins)
    if require_formal_geometry and basin_count != 531:
        raise StateDiagnosticsAuditError("state diagnostic replay basin count drift")
    panel_keys = diagnostics.panel_keys_v09(basin_count)
    all_keys = diagnostics.all_training_keys_v09(basin_count)
    if require_formal_geometry and (panel_keys.shape != (6_372, 2) or all_keys.shape != (1_745_928, 2)):
        raise StateDiagnosticsAuditError("state diagnostic replay key coverage drift")
    diagnostics.verify_sealed_bridge_inputs_unchanged_v09(inputs)
    seed_reports = []
    raw_matches = 0
    file_matches = 0
    for spec in continuous:
        run_record = audited_runs.get(spec.run_id)
        if not isinstance(run_record, Mapping):
            raise StateDiagnosticsAuditError(f"training audit is missing {spec.run_id}")
        checkpoint_entries = {
            str(epoch): diagnostics._validate_diagnostic_checkpoint_record_v09(run_record, spec, epoch)["sha256"]
            for epoch in _EPOCHS
        }
        child_record = children[spec.seed]
        if child_record.get("run_id") != spec.run_id or child_record.get("checkpoint_sha256") != checkpoint_entries:
            raise StateDiagnosticsAuditError(f"state diagnostic root checkpoint binding drift for seed {spec.seed}")
        provenance = _expected_provenance(
            root_manifest,
            training_audit,
            run_record,
            spec,
            checkpoint_entries,
        )
        child_root = diagnostic_root / f"E09-CONTINUOUS_s{spec.seed}"
        stored_manifest, stored_summary, stored_arrays = _validate_seed_directory(
            child_root,
            child_record,
            seed=spec.seed,
            expected_provenance=provenance,
        )
        replay_summary = {"seed": spec.seed, "checkpoints": {}}
        run_dir = formal_root / Path(spec.results_root).name / f"seed_{spec.seed}"
        for epoch in _EPOCHS:
            checkpoint_name = f"checkpoint_epoch{epoch:03d}.pt"
            model = diagnostics._load_diagnostic_model_v09(
                run_dir / checkpoint_name,
                spec,
                epoch,
                checkpoint_entries[str(epoch)],
                device,
            )
            panel_states = diagnostics.state_norms_for_keys_v09(inputs, model, panel_keys, device=device)
            replay_arrays = {
                f"epoch{epoch:03d}_panel_keys": panel_keys,
                f"epoch{epoch:03d}_panel_state_norms": panel_states,
            }
            replay_summary["checkpoints"][str(epoch)] = {
                "gates": diagnostics.gate_summary_v09(model),
                "panel": diagnostics.column_summary_v09(panel_states),
            }
            if epoch == 30:
                all_states = diagnostics.state_norms_for_keys_v09(inputs, model, all_keys, device=device)
                replay_arrays["epoch030_all_training_keys"] = all_keys
                replay_arrays["epoch030_all_training_state_norms"] = all_states
                replay_summary["checkpoints"]["30"]["all_training_keys"] = diagnostics.column_summary_v09(all_states)
            for name, replay in replay_arrays.items():
                _assert_replay_array(
                    stored_arrays[name],
                    replay,
                    seed=spec.seed,
                    name=name,
                    stored_file_sha256=stored_manifest["arrays"][name]["file_sha256"],
                )
                raw_matches += 1
                file_matches += 1
            del model
        if stored_summary != replay_summary:
            raise StateDiagnosticsAuditError(f"state diagnostic replay summary differs for seed {spec.seed}")
        seed_reports.append({
            "seed": spec.seed,
            "run_id": spec.run_id,
            "array_count": 8,
            "raw_array_sha256_matches": 8,
            "npy_file_sha256_matches": 8,
            "summary_identical": True,
        })
    diagnostics.verify_sealed_bridge_inputs_unchanged_v09(inputs)
    report = {
        "schema": _AUDIT_SCHEMA,
        "status": "state_diagnostics_external_audit_passed",
        "diagnostic_root": str(diagnostic_root),
        "diagnostic_root_manifest_sha256": sha256_file(diagnostic_root / "manifest.json"),
        "training_external_audit_sha256": sha256_file(formal_root / "training_external_audit.json"),
        "run_order_canonical_sha256": diagnostics._run_order_binding_v09(specs),
        "state_diagnostics_preregistration_sha256": sha256_file(diagnostics._preregistration_path_v09()),
        "environment": dict(environment),
        "environment_sha256": canonical_sha256(environment),
        "diagnostic_source": root_manifest["diagnostic_source"],
        "diagnostic_source_sha256": root_manifest["diagnostic_source_sha256"],
        "seed_count": len(seed_reports),
        "array_count": raw_matches,
        "raw_array_sha256_matches": raw_matches,
        "npy_file_sha256_matches": file_matches,
        "seeds": seed_reports,
        "training_target_reads": 0,
        "formal_evaluation_observation_reads": 0,
        "recent_path_executed": False,
        "flow_head_executed": False,
        "formal_period_predictions_generated": False,
        "official_score_called": False,
        "persistent_replay_output_written": False,
    }
    write_json_atomic(report_path, report)
    return report


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="audit formal version-09 history-state diagnostics")
    parser.add_argument("--input-root", required=True)
    parser.add_argument("--formal-root", required=True)
    parser.add_argument("--run-order", required=True)
    parser.add_argument("--diagnostic-root", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--device", default="cuda:0")
    args = parser.parse_args(argv)
    report = audit_history_state_diagnostics_v09(
        args.input_root,
        args.formal_root,
        args.run_order,
        args.diagnostic_root,
        args.report,
        args.device,
    )
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
