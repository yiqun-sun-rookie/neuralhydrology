from pathlib import Path
import sys

import pytest
import torch

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def test_checkpoint_bridge_requires_six_exact_active_tensors_and_three_equal_models():
    from audit_legacy_checkpoint_bridge_v09 import assert_legacy_checkpoint_bridge_v09
    from models_formal_v09 import build_model_v09

    source = build_model_v09("classic_lstm_256_clean", 100)
    state = source.state_dict()
    dynamic = {"recent": torch.zeros(2, 12, 5)}
    statics = torch.zeros(2, 27)

    report = assert_legacy_checkpoint_bridge_v09(
        state,
        seed=100,
        panels=((dynamic, statics),),
    )
    assert report["tensor_count"] == 6
    assert report["panel_count"] == 1
    assert report["maximum_prediction_difference"] == 0.0

    drift = dict(state)
    drift.pop("head.net.0.bias")
    with pytest.raises(ValueError, match="six|tensor"):
        assert_legacy_checkpoint_bridge_v09(
            drift,
            seed=100,
            panels=((dynamic, statics),),
        )


def test_legacy_bridge_report_path_rejects_every_protected_root(tmp_path):
    from audit_legacy_checkpoint_bridge_v09 import _assert_report_outside_protected_paths

    legacy = tmp_path / "legacy"
    inputs = tmp_path / "inputs"
    formal_run = tmp_path / "formal-run"
    for root in (legacy, inputs, formal_run):
        root.mkdir()
        with pytest.raises(ValueError, match="outside protected"):
            _assert_report_outside_protected_paths(root / "report.json", (legacy, inputs, formal_run))

    external = tmp_path / "audits" / "report.json"
    assert _assert_report_outside_protected_paths(external, (legacy, inputs, formal_run)) == external.resolve()


def test_legacy_bridge_report_rejects_reparse_parent_before_resolve(tmp_path, monkeypatch):
    import artifact_v09
    from audit_legacy_checkpoint_bridge_v09 import _assert_report_outside_protected_paths

    protected = tmp_path / "legacy"
    protected.mkdir()
    report_parent = tmp_path / "audits"
    report_parent.mkdir()
    original = artifact_v09.is_reparse_point
    monkeypatch.setattr(
        artifact_v09,
        "is_reparse_point",
        lambda path: Path(path) == report_parent or original(path),
    )
    with pytest.raises(ValueError, match="reparse point"):
        _assert_report_outside_protected_paths(report_parent / "report.json", (protected,))
