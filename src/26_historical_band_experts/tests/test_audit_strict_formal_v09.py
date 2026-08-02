from pathlib import Path
import json
import sys

import numpy as np
import pytest

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))

from test_train_strict_formal_v09 import _inputs, _tiny_builder


def _make_run(tmp_path):
    from train_strict_formal_v09 import StrictExecutionSpecV09, _run_strict_training_v09

    output = tmp_path / "strict"
    _run_strict_training_v09(
        _inputs(),
        protocol={"protocol_id": "synthetic"},
        output_dir=output,
        device="cpu",
        execution_spec=StrictExecutionSpecV09(1, 3, (1,), 8, 3),
        model_builder=_tiny_builder,
    )
    return output


def test_external_strict_audit_replays_final_checkpoint(tmp_path):
    from audit_strict_formal_v09 import audit_strict_run_v09

    run = _make_run(tmp_path)
    report_path = tmp_path / "strict.external_audit.json"
    report = audit_strict_run_v09(
        run,
        inputs=_inputs(),
        device="cpu",
        report_path=report_path,
        model_builder=_tiny_builder,
    )

    assert report["status"] == "strict_nesting_synthetic_checkpoint_prediction_replay_passed"
    assert report["maximum_reference_difference"] == 0.0
    assert report["permutation_hashes_recomputed"] == 1
    assert report_path.is_file()


def test_external_strict_audit_rejects_report_inside_run_and_prediction_drift(tmp_path):
    from audit_strict_formal_v09 import audit_strict_run_v09
    from strict_nesting_formal_v09 import IndependentReproductionMismatch

    run = _make_run(tmp_path)
    with pytest.raises(ValueError, match="outside"):
        audit_strict_run_v09(
            run,
            inputs=_inputs(),
            device="cpu",
            report_path=run / "external.json",
            model_builder=_tiny_builder,
        )

    prediction_path = run / "classic_training_predictions.float32.npy"
    predictions = np.load(prediction_path, mmap_mode="r+")
    predictions[0] += np.float32(1e-3)
    predictions.flush()
    with pytest.raises((ValueError, IndependentReproductionMismatch)):
        audit_strict_run_v09(
            run,
            inputs=_inputs(),
            device="cpu",
            report_path=tmp_path / "drift.external.json",
            model_builder=_tiny_builder,
        )


def test_external_strict_audit_rejects_nested_file_named_seal(tmp_path):
    from audit_strict_formal_v09 import audit_strict_run_v09

    run = _make_run(tmp_path)
    nested = run / "unexpected"
    nested.mkdir()
    (nested / "seal.json").write_text("{}", encoding="utf-8")

    with pytest.raises(ValueError, match="inventory drift"):
        audit_strict_run_v09(
            run,
            inputs=_inputs(),
            device="cpu",
            report_path=tmp_path / "nested-seal.external.json",
            model_builder=_tiny_builder,
        )


def test_external_strict_audit_rejects_registered_nested_seal(tmp_path):
    from artifact_v09 import canonical_sha256, sha256_file
    from audit_strict_formal_v09 import audit_strict_run_v09

    run = _make_run(tmp_path)
    nested = run / "unexpected"
    nested.mkdir()
    nested_seal = nested / "seal.json"
    nested_seal.write_text("{}", encoding="utf-8")
    root_seal = run / "seal.json"
    seal = json.loads(root_seal.read_text(encoding="utf-8"))
    seal["sealed_files"].append({
        "relative_path": "unexpected/seal.json",
        "size_bytes": nested_seal.stat().st_size,
        "sha256": sha256_file(nested_seal),
    })
    seal["sealed_files_sha256"] = canonical_sha256(seal["sealed_files"])
    root_seal.write_text(json.dumps(seal), encoding="utf-8")

    with pytest.raises(ValueError, match="cannot seal"):
        audit_strict_run_v09(
            run,
            inputs=_inputs(),
            device="cpu",
            report_path=tmp_path / "registered-nested-seal.external.json",
            model_builder=_tiny_builder,
        )


def test_formal_manifest_contract_rejects_wrong_geometry_and_missing_input_hash():
    from audit_strict_formal_v09 import _FORMAL_GEOMETRY, _validate_manifest_trajectory_v09

    manifest = {
        "schema": "historical_multiscale_formal_v09_strict_run_v1",
        "status": "strict_nesting_complete",
        "formal_execution": True,
        **_FORMAL_GEOMETRY,
        "protocol_canonical_sha256": "1" * 64,
        "input_bindings": {
            "input_seal_sha256": "2" * 64,
            "input_external_audit_sha256": "3" * 64,
            "trusted_source_audit_sha256": "4" * 64,
        },
        "formal_evaluation_observation_reads": 0,
        "epoch_trace": [],
    }
    wrong_batch = dict(manifest, batch_size=255)
    with pytest.raises(ValueError, match="batch_size drift"):
        _validate_manifest_trajectory_v09(wrong_batch)

    missing_hash = dict(manifest)
    missing_hash["input_bindings"] = dict(manifest["input_bindings"], input_seal_sha256=None)
    with pytest.raises(ValueError, match="input binding input_seal_sha256"):
        _validate_manifest_trajectory_v09(missing_hash)
