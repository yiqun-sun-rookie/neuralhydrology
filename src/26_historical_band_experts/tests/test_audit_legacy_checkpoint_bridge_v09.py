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


def test_legacy_bridge_rejects_registered_checkpoint_reparse_before_loading(tmp_path, monkeypatch):
    import artifact_v09
    from audit_legacy_checkpoint_bridge_v09 import audit_legacy_checkpoint_bridge_v09
    from formal_v09_protocol import load_protocol_v09
    from test_train_strict_formal_v09 import _inputs

    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    legacy_root = tmp_path / "legacy"
    first_run = legacy_root / protocol["legacy_reference"]["runs"][0]["run_id"]
    first_run.mkdir(parents=True)
    checkpoint = first_run / "model_epoch030.pt"
    original = artifact_v09.is_reparse_point
    monkeypatch.setattr(
        artifact_v09,
        "is_reparse_point",
        lambda path: Path(path) == checkpoint or original(path),
    )

    with pytest.raises(ValueError, match="reparse point"):
        audit_legacy_checkpoint_bridge_v09(
            protocol,
            legacy_results_root=legacy_root,
            inputs=_inputs(),
            report_path=tmp_path / "bridge.json",
            device="cpu",
        )


def test_legacy_bridge_rechecks_registered_files_after_identity_verification(tmp_path, monkeypatch):
    import artifact_v09
    import audit_legacy_checkpoint_bridge_v09 as module
    from formal_v09_protocol import load_protocol_v09
    from test_train_strict_formal_v09 import _inputs

    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    legacy_root = tmp_path / "legacy"
    first_run = legacy_root / protocol["legacy_reference"]["runs"][0]["run_id"]
    first_run.mkdir(parents=True)
    config_path = first_run / "config.yml"
    after_verification = {"value": False}
    original = artifact_v09.is_reparse_point

    def verify(*args, **kwargs):
        after_verification["value"] = True
        return {
            "verified": True,
            "run_count": 8,
            "file_count": 16,
            "seeds": [run["seed"] for run in protocol["legacy_reference"]["runs"]],
            "recorded_code_commit_prefix": protocol["legacy_reference"]["recorded_code_commit_prefix"],
        }

    monkeypatch.setattr(module, "verify_legacy_reference_v09", verify)
    monkeypatch.setattr(
        artifact_v09,
        "is_reparse_point",
        lambda path: (after_verification["value"] and Path(path) == config_path) or original(path),
    )
    monkeypatch.setattr(module.torch, "load", lambda *args, **kwargs: pytest.fail("must reject before torch.load"))

    with pytest.raises(ValueError, match="reparse point"):
        module.audit_legacy_checkpoint_bridge_v09(
            protocol,
            legacy_results_root=legacy_root,
            inputs=_inputs(),
            report_path=tmp_path / "bridge.json",
            device="cpu",
        )
