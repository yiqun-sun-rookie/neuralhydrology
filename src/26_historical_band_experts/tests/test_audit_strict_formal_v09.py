from pathlib import Path
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

    assert report["status"] == "strict_nesting_external_audit_passed"
    assert report["maximum_reference_difference"] == 0.0
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
