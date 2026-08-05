from __future__ import annotations

import ast
import hashlib
import json
from pathlib import Path

import pytest

from hbv_multilead_joint_uncertainty.scripts.verify_g3_state_domain_consistent_process_noise_switch import (
    assert_verification_path_absent,
    independent_first_complete_top_ranked_run,
    verify_artifact_checksums,
)


def test_independent_run_detector_matches_frozen_complete_run_definition():
    assert (
        independent_first_complete_top_ranked_run(
            [False, True, True, True, True, True, False], 5, 6
        )
        == 1
    )
    assert (
        independent_first_complete_top_ranked_run(
            [False, False, True, True, True, True, True], 5, 6
        )
        is None
    )


def test_checksum_verifier_rejects_changed_artifact(tmp_path):
    artifact = tmp_path / "artifact.txt"
    artifact.write_text("sealed", encoding="utf-8")
    digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
    (tmp_path / "checksums.json").write_text(
        json.dumps({"artifact.txt": digest}), encoding="utf-8"
    )
    assert verify_artifact_checksums(tmp_path)["artifact.txt"] is True
    artifact.write_text("changed", encoding="utf-8")
    with pytest.raises(ValueError, match="artifact checksum mismatch"):
        verify_artifact_checksums(tmp_path)


def test_verification_path_must_be_absent(tmp_path):
    target = tmp_path / "verification"
    assert_verification_path_absent(target)
    target.mkdir()
    with pytest.raises(FileExistsError, match="verification path already exists"):
        assert_verification_path_absent(target)


def test_verifier_imports_neither_production_experiment_module_nor_forecast():
    source_path = Path(__file__).resolve().parents[1] / (
        "src/hbv_multilead_joint_uncertainty/scripts/"
        "verify_g3_state_domain_consistent_process_noise_switch.py"
    )
    tree = ast.parse(source_path.read_text(encoding="utf-8"))
    imported = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.extend(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.append(node.module)
    forbidden = {
        "hbv_multilead_joint_uncertainty.state_domain_consistent_process_noise_switch"
    }
    assert forbidden.isdisjoint(imported)
    assert not any("forecast" in name.lower() for name in imported)
