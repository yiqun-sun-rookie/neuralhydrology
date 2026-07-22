import json
import sys
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.registry import RunRegistry  # noqa: E402


def test_run_identifier_is_reserved_once_and_retains_failure_history(tmp_path):
    registry = RunRegistry(tmp_path, "formal_v01")
    registry.reserve("frozen_evaluation", contract_id="contract_v01")
    registry.update("failed", message="resource gate")

    with pytest.raises(FileExistsError):
        RunRegistry(tmp_path, "formal_v01").reserve("frozen_evaluation")

    record = json.loads((tmp_path / "registry" / "formal_v01.json").read_text(encoding="utf-8"))
    assert record["status"] == "failed"
    assert [row["status"] for row in record["history"]] == ["running", "failed"]


def test_registry_supports_explicit_superseded_status_without_reusing_the_identifier(tmp_path):
    registry = RunRegistry(tmp_path, "pilot_v01")
    registry.reserve("calibration_contract")
    registry.update("superseded", replacement_id="pilot_v02")

    record = json.loads(registry.path.read_text(encoding="utf-8"))
    assert record["status"] == "superseded"
    assert record["history"][-1]["replacement_id"] == "pilot_v02"
