from pathlib import Path
import inspect
import json
import sys

import pytest

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def test_production_strict_entry_has_no_runtime_arguments_and_fixed_claim_paths():
    from run_formal_strict_stage_v09 import run_formal_strict_stage_v09, strict_stage_paths_v09

    assert not inspect.signature(run_formal_strict_stage_v09).parameters
    paths = strict_stage_paths_v09(IDEA_ROOT.parents[1])
    assert paths.output_root.name == "R09-NEST-S100"
    assert paths.authorization.name == "A09-NEST-01.authorization.json"
    assert paths.consumption.name == "A09-NEST-01.consumption.json"


def test_strict_prerequisite_hashes_reject_wrong_resource_variant(tmp_path):
    from run_formal_strict_stage_v09 import StrictStagePathsV09, strict_prerequisite_hashes_v09

    input_root = tmp_path / "input"
    input_root.mkdir()
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
        tmp_path / "legacy.audit.json": {
            "status": "legacy_checkpoint_bridge_external_audit_passed",
            "formal_evaluation_observation_reads": 0,
        },
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
        strict_prerequisite_hashes_v09(paths)


def test_strict_executable_tree_is_deterministic_and_binds_entry():
    from run_formal_strict_stage_v09 import strict_executable_tree_v09

    root = IDEA_ROOT.parents[1]
    first = strict_executable_tree_v09(root)
    second = strict_executable_tree_v09(root)
    assert first == second
    assert any(row["relative_path"].endswith("run_formal_strict_stage_v09.py") for row in first["files"])
    assert len(first["tree_sha256"]) == 64
