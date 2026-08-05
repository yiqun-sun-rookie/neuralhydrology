from __future__ import annotations

import csv
import hashlib
import importlib.util
import json
from pathlib import Path

import numpy as np
import pytest


PROJECT_ROOT = Path(__file__).resolve().parents[1]
VERIFIER_PATH = (
    PROJECT_ROOT
    / "src"
    / "hbv_multilead_joint_uncertainty"
    / "scripts"
    / "verify_g3_state_domain_consistent_parameter_switch_confirmation.py"
)


def _verifier():
    specification = importlib.util.spec_from_file_location(
        "parameter_switch_verifier", VERIFIER_PATH
    )
    module = importlib.util.module_from_spec(specification)
    assert specification.loader is not None
    specification.loader.exec_module(module)
    return module


def test_verifier_does_not_import_production_experiment_or_runner():
    source = VERIFIER_PATH.read_text(encoding="utf-8")
    assert (
        "from hbv_multilead_joint_uncertainty.state_domain_consistent_parameter_switch_confirmation"
        not in source
    )
    assert "run_g3_state_domain_consistent_parameter_switch_confirmation import" not in source


def test_independent_clear_run_rejects_near_tie():
    verifier = _verifier()
    weak = np.tile(np.asarray([0.34, 0.33, 0.33]), (30, 1))
    strong = np.tile(np.asarray([0.2, 0.2, 0.6]), (30, 1))
    assert verifier.independent_first_clear_run(weak, 0, 5, 30, 0.5, 0.1) is None
    assert verifier.independent_first_clear_run(strong, 2, 5, 30, 0.5, 0.1) == 0


def test_independent_exact_interval_matches_thirteen_of_sixteen():
    verifier = _verifier()
    lower, upper = verifier._exact_interval(13, 16)
    assert lower == pytest.approx(0.5435434537683882)
    assert upper == pytest.approx(0.9595262660940541)


def test_verification_path_guard_rejects_existing_directory(tmp_path):
    verifier = _verifier()
    target = tmp_path / "verification"
    verifier.assert_verification_path_absent(target)
    target.mkdir()
    with pytest.raises(FileExistsError, match="already exists"):
        verifier.assert_verification_path_absent(target)


def test_artifact_checksum_verifier_checks_complete_file_set(tmp_path):
    verifier = _verifier()
    artifact = tmp_path / "artifact.txt"
    artifact.write_text("sealed\n", encoding="utf-8")
    digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
    (tmp_path / "checksums.json").write_text(
        json.dumps({"artifact.txt": digest}) + "\n", encoding="utf-8"
    )
    checks = verifier.verify_artifact_checksums(tmp_path)
    assert all(checks.values())
    (tmp_path / "extra.txt").write_text("extra\n", encoding="utf-8")
    checks = verifier.verify_artifact_checksums(tmp_path)
    assert checks["__file_set__"] is False


def test_combine_numeric_and_visual_requires_both_gates():
    verifier = _verifier()
    config = json.loads(verifier.FROZEN_CONFIG.read_text(encoding="utf-8"))
    identifiers = [row["parameter_id"] for row in config["parameter_candidates"]]
    transitions = [
        (identifiers[0], identifiers[1]),
        (identifiers[1], identifiers[2]),
        (identifiers[2], identifiers[0]),
    ]
    numeric = []
    visual = []
    event_index = 0
    for old_identifier, new_identifier in transitions:
        for position in range(16):
            event_index += 1
            event_id = f"event_{event_index:02d}"
            numerical_success = position < 15
            numeric.append(
                {
                    "event_id": event_id,
                    "old_parameter_id": old_identifier,
                    "new_parameter_id": new_identifier,
                    "numerical_success": numerical_success,
                }
            )
            visual.append(
                {
                    "review_id": f"review_{event_index:03d}",
                    "event_id": event_id,
                    "visual_label": "clear_success" if position < 14 else "ambiguous",
                    "visible_reason": "clear sustained separation" if position < 14 else "near tie",
                }
            )
    combined, summaries = verifier.combine_numeric_and_visual_events(
        numeric, visual, config
    )
    assert len(combined) == 48
    assert [row["final_successful_event_count"] for row in summaries] == [14, 14, 14]
    assert all(row["criterion_passed"] for row in summaries)


def test_csv_comparison_handles_none_boolean_and_numbers(tmp_path):
    verifier = _verifier()
    path = tmp_path / "rows.csv"
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=("name", "count", "passed", "missing"))
        writer.writeheader()
        writer.writerow({"name": "a", "count": 3, "passed": True, "missing": ""})
    assert verifier._compare_csv(
        path,
        [{"name": "a", "count": 3, "passed": True, "missing": None}],
        1e-12,
    )
