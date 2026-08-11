"""Independent replay tests for formal version-09 history-state diagnostics."""
import json
from pathlib import Path
from types import SimpleNamespace
import sys

import numpy as np
import pytest

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def _write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _training_audit(specs):
    runs = []
    for position, spec in enumerate(specs, start=1):
        checkpoints = [
            {
                "epoch": epoch,
                "relative_path": f"checkpoint_epoch{epoch:03d}.pt",
                "sha256": f"{position * 100 + epoch:064x}",
                "size_bytes": 1,
                "finite_tensor_count": 1,
                "not_eligible_for_formal_prediction": epoch != 30,
                "eligible_for_formal_prediction": epoch == 30,
            }
            for epoch in (10, 20, 30)
        ]
        runs.append({
            "position": spec.position,
            "run_id": spec.run_id,
            "family": spec.family,
            "variant": spec.variant,
            "seed": spec.seed,
            "run_root": str(Path(spec.results_root) / f"seed_{spec.seed}"),
            "run_seal_sha256": f"{position:064x}",
            "checkpoints": checkpoints,
        })
    return {
        "schema": "historical_multiscale_formal_v09_training_external_audit_v1",
        "status": "complete_training_audit",
        "source_context_sha256": "a" * 64,
        "input_bindings": {
            "input_seal_sha256": "b" * 64,
            "input_external_audit_sha256": "c" * 64,
            "trusted_source_audit_sha256": "d" * 64,
        },
        "coverage": {"expected_runs": 24, "audited_runs": 24, "passed_runs": 24},
        "runs": runs,
        "formal_evaluation_observation_reads": 0,
        "formal_period_predictions_generated": False,
        "official_score_called": False,
    }


def _build_case(tmp_path, monkeypatch):
    import audit_state_diagnostics_formal_v09 as auditor
    import state_diagnostics_formal_v09 as diagnostics
    from artifact_v09 import canonical_sha256, sha256_file, write_json_atomic
    from train_formal_v09 import load_run_order_v09

    specs = load_run_order_v09(IDEA_ROOT / "configs/formal_v09_run_order.json")
    formal_root = tmp_path / "formal_v09"
    formal_root.mkdir()
    training_audit = _training_audit(specs)
    training_audit_path = formal_root / "training_external_audit.json"
    _write_json(training_audit_path, training_audit)
    training_audit_sha256 = sha256_file(training_audit_path)
    environment = {
        "device": "cpu",
        "device_name": None,
        "torch": "test",
        "cuda": None,
        "cudnn": None,
        "deterministic_algorithms": True,
        "cudnn_benchmark": False,
        "cudnn_deterministic": True,
        "cuda_matmul_allow_tf32": False,
        "cudnn_allow_tf32": False,
        "cublas_workspace_config": None,
    }
    environment_sha256 = canonical_sha256(environment)
    diagnostic_source = diagnostics._diagnostic_source_context_v09()
    run_order_sha256 = diagnostics._run_order_binding_v09(specs)
    prereg_sha256 = sha256_file(diagnostics._preregistration_path_v09())
    audit_by_id = {row["run_id"]: row for row in training_audit["runs"]}
    panel_keys = np.ascontiguousarray(np.array([[0, 0], [1, 1]], dtype="<i4"))
    all_keys = np.ascontiguousarray(np.array([[0, 0], [0, 1], [1, 0], [1, 1]], dtype="<i4"))
    diagnostic_root = formal_root / "state_diagnostics"
    diagnostic_root.mkdir()
    children = []
    for spec in [value for value in specs if value.variant == "continuous_multiscale_history"]:
        run_record = audit_by_id[spec.run_id]
        checkpoint_hashes = {str(entry["epoch"]): entry["sha256"] for entry in run_record["checkpoints"]}
        checkpoints = {}
        for epoch in (10, 20, 30):
            panel_states = np.ascontiguousarray(
                np.full((len(panel_keys), 5), spec.seed + epoch, dtype="<f4"))
            payload = {
                "panel_keys": panel_keys,
                "panel_states": panel_states,
                "gates": {"hidden_gate": {"seed": spec.seed, "epoch": epoch}},
            }
            if epoch == 30:
                payload["all_keys"] = all_keys
                payload["all_states"] = np.ascontiguousarray(
                    np.full((len(all_keys), 5), spec.seed + epoch, dtype="<f4"))
            checkpoints[epoch] = payload
        provenance = {
            "input_seal_sha256": "b" * 64,
            "input_external_audit_sha256": "c" * 64,
            "trusted_source_audit_sha256": "d" * 64,
            "training_external_audit_sha256": training_audit_sha256,
            "training_source_context_sha256": "a" * 64,
            "run_order_canonical_sha256": run_order_sha256,
            "state_diagnostics_preregistration_sha256": prereg_sha256,
            "diagnostic_environment_sha256": environment_sha256,
            "diagnostic_source_tree_sha256": diagnostic_source["tree_sha256"],
            "run_id": spec.run_id,
            "run_seal_sha256": run_record["run_seal_sha256"],
            "checkpoint_sha256": checkpoint_hashes,
        }
        child_name = f"E09-CONTINUOUS_s{spec.seed}"
        child_root = diagnostic_root / child_name
        manifest = diagnostics.write_seed_diagnostics_v09(
            child_root,
            seed=spec.seed,
            checkpoints=checkpoints,
            provenance=provenance,
        )
        binding = diagnostics._directory_binding_v09(child_root)
        children.append({
            "seed": spec.seed,
            "run_id": spec.run_id,
            "relative_path": child_name,
            "manifest_sha256": sha256_file(child_root / "manifest.json"),
            "directory_file_count": binding["file_count"],
            "directory_files_sha256": binding["files_sha256"],
            "array_count": len(manifest["arrays"]),
            "checkpoint_sha256": checkpoint_hashes,
        })
    root_manifest = {
        "schema": "historical_multiscale_formal_v09_state_diagnostics_root_v1",
        "status": "state_diagnostics_complete",
        "seed_count": 8,
        "seeds": list(range(100, 801, 100)),
        "children": children,
        "input_bindings": training_audit["input_bindings"],
        "training_external_audit_sha256": training_audit_sha256,
        "training_source_context_sha256": "a" * 64,
        "run_order_canonical_sha256": run_order_sha256,
        "state_diagnostics_preregistration_sha256": prereg_sha256,
        "environment": environment,
        "environment_sha256": environment_sha256,
        "diagnostic_source": diagnostic_source,
        "diagnostic_source_sha256": canonical_sha256(diagnostic_source),
        "training_target_reads": 0,
        "formal_evaluation_observation_reads": 0,
        "recent_path_executed": False,
        "flow_head_executed": False,
        "formal_period_predictions_generated": False,
        "official_score_called": False,
    }
    write_json_atomic(diagnostic_root / "manifest.json", root_manifest)
    inputs = SimpleNamespace(
        basins=("a", "b"),
        input_seal_sha256="b" * 64,
        external_audit_sha256="c" * 64,
        trusted_source_audit_sha256="d" * 64,
    )
    verifier_calls = []
    monkeypatch.setattr(diagnostics, "_deterministic_environment_v09", lambda _device: environment)
    monkeypatch.setattr(diagnostics, "_load_diagnostic_inputs_v09", lambda *_args: inputs)
    monkeypatch.setattr(
        diagnostics,
        "verify_sealed_bridge_inputs_unchanged_v09",
        lambda value: verifier_calls.append(value),
    )
    monkeypatch.setattr(
        diagnostics,
        "_load_diagnostic_model_v09",
        lambda _path, spec, epoch, _sha, _device: SimpleNamespace(seed=spec.seed, epoch=epoch),
    )
    monkeypatch.setattr(diagnostics, "panel_keys_v09", lambda _count: panel_keys)
    monkeypatch.setattr(diagnostics, "all_training_keys_v09", lambda _count: all_keys)
    monkeypatch.setattr(
        diagnostics,
        "state_norms_for_keys_v09",
        lambda _inputs, model, keys, *, device: np.ascontiguousarray(
            np.full((len(keys), 5), model.seed + model.epoch, dtype="<f4")),
    )
    monkeypatch.setattr(
        diagnostics,
        "gate_summary_v09",
        lambda model: {"hidden_gate": {"seed": model.seed, "epoch": model.epoch}},
    )
    return SimpleNamespace(
        auditor=auditor,
        diagnostics=diagnostics,
        formal_root=formal_root,
        diagnostic_root=diagnostic_root,
        input_root=tmp_path / "input_attempt_01",
        specs=specs,
        report_path=formal_root / "state_diagnostics_external_audit.json",
        inputs=inputs,
        verifier_calls=verifier_calls,
    )


def test_independent_replay_matches_all_64_arrays_without_a_replay_tree(tmp_path, monkeypatch):
    case = _build_case(tmp_path, monkeypatch)
    report = case.auditor.audit_history_state_diagnostics_v09(
        case.input_root,
        case.formal_root,
        case.specs,
        case.diagnostic_root,
        case.report_path,
        "cpu",
        require_formal_geometry=False,
    )
    assert report["status"] == "state_diagnostics_external_audit_passed"
    assert report["seed_count"] == 8
    assert report["array_count"] == 64
    assert report["raw_array_sha256_matches"] == 64
    assert report["npy_file_sha256_matches"] == 64
    assert report["training_target_reads"] == 0
    assert report["formal_evaluation_observation_reads"] == 0
    assert len(case.verifier_calls) == 2
    assert not list(case.formal_root.rglob("*replay*"))


def test_replay_rejects_a_changed_stored_array_before_writing_report(tmp_path, monkeypatch):
    case = _build_case(tmp_path, monkeypatch)
    path = case.diagnostic_root / "E09-CONTINUOUS_s100/epoch010_panel_state_norms.float32.npy"
    values = np.load(path, allow_pickle=False)
    values[0, 0] += np.float32(1.0)
    np.save(path, values, allow_pickle=False)
    with pytest.raises(ValueError, match="hash|drift|differs"):
        case.auditor.audit_history_state_diagnostics_v09(
            case.input_root,
            case.formal_root,
            case.specs,
            case.diagnostic_root,
            case.report_path,
            "cpu",
            require_formal_geometry=False,
        )
    assert not case.report_path.exists()


def test_replay_rejects_environment_drift(tmp_path, monkeypatch):
    case = _build_case(tmp_path, monkeypatch)
    changed = dict(case.diagnostics._deterministic_environment_v09("cpu"))
    changed["torch"] = "different"
    monkeypatch.setattr(case.diagnostics, "_deterministic_environment_v09", lambda _device: changed)
    with pytest.raises(ValueError, match="environment"):
        case.auditor.audit_history_state_diagnostics_v09(
            case.input_root,
            case.formal_root,
            case.specs,
            case.diagnostic_root,
            case.report_path,
            "cpu",
            require_formal_geometry=False,
        )


def test_replay_refuses_an_input_object_that_exposes_targets(tmp_path, monkeypatch):
    case = _build_case(tmp_path, monkeypatch)
    unsafe = SimpleNamespace(**vars(case.inputs), targets=np.zeros((2, 2), dtype=np.float32))
    monkeypatch.setattr(case.diagnostics, "_load_diagnostic_inputs_v09", lambda *_args: unsafe)
    with pytest.raises(ValueError, match="target"):
        case.auditor.audit_history_state_diagnostics_v09(
            case.input_root,
            case.formal_root,
            case.specs,
            case.diagnostic_root,
            case.report_path,
            "cpu",
            require_formal_geometry=False,
        )


def test_replay_report_must_be_outside_the_diagnostic_tree(tmp_path, monkeypatch):
    case = _build_case(tmp_path, monkeypatch)
    report_path = case.diagnostic_root / "audit.json"
    with pytest.raises(ValueError, match="outside"):
        case.auditor.audit_history_state_diagnostics_v09(
            case.input_root,
            case.formal_root,
            case.specs,
            case.diagnostic_root,
            report_path,
            "cpu",
            require_formal_geometry=False,
        )
