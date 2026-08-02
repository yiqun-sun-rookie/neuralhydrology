from pathlib import Path
import inspect
import json
import sys

import pytest

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def _valid_legacy_report(protocol):
    from artifact_v09 import canonical_sha256
    from audit_legacy_checkpoint_bridge_v09 import _environment_binding_v09, _source_bindings_v09

    rows = protocol["basin_count"] * 12
    runs = protocol["legacy_reference"]["runs"]
    return {
        "status": "legacy_checkpoint_bridge_external_audit_passed",
        "protocol_canonical_sha256": canonical_sha256(protocol),
        "source_bindings": _source_bindings_v09(),
        "environment_binding": _environment_binding_v09("cuda:0"),
        "verified_identity": {
            "verified": True,
            "run_count": 8,
            "file_count": 16,
            "seeds": [run["seed"] for run in runs],
            "recorded_code_commit_prefix": protocol["legacy_reference"]["recorded_code_commit_prefix"],
        },
        "runs": [{
            "seed": run["seed"],
            "run_id": run["run_id"],
            "config_sha256": run["config_sha256"],
            "checkpoint_sha256": run["checkpoint_epoch030_sha256"],
            "real_panel_rows": rows,
        } for run in runs],
        "run_count": 8,
        "synthetic_panel_rows_per_run": 2,
        "real_panel_rows_per_run": rows,
        "real_panel_rows_total": rows * 8,
        "maximum_prediction_difference": 0.0,
        "training_target_value_reads": 0,
        "formal_evaluation_observation_reads": 0,
    }


def test_production_strict_entry_has_no_runtime_arguments_and_fixed_claim_paths():
    from run_formal_strict_stage_v09 import run_formal_strict_stage_v09, strict_stage_paths_v09

    assert not inspect.signature(run_formal_strict_stage_v09).parameters
    paths = strict_stage_paths_v09(IDEA_ROOT.parents[1])
    assert paths.output_root.name == "R09-NEST-S100"
    assert paths.authorization.name == "A09-NEST-01.authorization.json"
    assert paths.consumption.name == "A09-NEST-01.consumption.json"


def test_strict_prerequisite_hashes_reject_wrong_resource_variant(tmp_path):
    from formal_v09_protocol import load_protocol_v09
    from run_formal_strict_stage_v09 import StrictStagePathsV09, strict_prerequisite_hashes_v09

    input_root = tmp_path / "input"
    input_root.mkdir()
    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    files = {
        input_root / "seal.json": {
            "status": "sealed"
        },
        tmp_path / "input.audit.json": {
            "status": "complete_input_audit_passed"
        },
        tmp_path / "trusted.audit.json": {
            "status": "complete_trusted_training_target_audit"
        },
        tmp_path / "legacy.audit.json": _valid_legacy_report(protocol),
        tmp_path / "resource.audit.json": {
            "status": "resource_preflight_passed",
            "action": "training",
            "variant": "classic_lstm_256_clean",
        },
    }
    for path, payload in files.items():
        path.write_text(json.dumps(payload), encoding="utf-8")
    paths = StrictStagePathsV09(
        worktree_root=tmp_path,
        protocol=tmp_path / "protocol.json",
        input_root=input_root,
        input_external_audit=tmp_path / "input.audit.json",
        trusted_source_audit=tmp_path / "trusted.audit.json",
        legacy_bridge_audit=tmp_path / "legacy.audit.json",
        resource_preflight_audit=tmp_path / "resource.audit.json",
        authorization=tmp_path / "authorization.json",
        consumption=tmp_path / "consumption.json",
        output_root=tmp_path / "output",
    )
    with pytest.raises(ValueError, match="resource preflight binding"):
        strict_prerequisite_hashes_v09(paths, protocol)


@pytest.mark.parametrize(
    ("field", "replacement", "message"),
    [
        ("protocol_canonical_sha256", "0" * 64, "protocol binding"),
        ("source_bindings", {}, "source binding"),
        ("environment_binding", {}, "environment binding"),
        ("run_count", 7, "report geometry"),
    ],
)
def test_legacy_bridge_report_is_recomputed_at_strict_launch(field, replacement, message):
    from formal_v09_protocol import load_protocol_v09
    from run_formal_strict_stage_v09 import _validate_legacy_bridge_report_v09

    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    report = _valid_legacy_report(protocol)
    report[field] = replacement
    with pytest.raises(ValueError, match=message):
        _validate_legacy_bridge_report_v09(report, protocol, device="cuda:0")


def test_strict_executable_tree_is_deterministic_and_binds_entry():
    from run_formal_strict_stage_v09 import strict_executable_tree_v09

    root = IDEA_ROOT.parents[1]
    first = strict_executable_tree_v09(root)
    second = strict_executable_tree_v09(root)
    assert first == second
    assert any(row["relative_path"].endswith("run_formal_strict_stage_v09.py") for row in first["files"])
    assert len(first["tree_sha256"]) == 64
