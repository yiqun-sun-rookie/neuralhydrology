import json
import sys
from pathlib import Path

import pandas as pd


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.scripts.run_assimilation_duration_boundary import (  # noqa: E402
    run,
)


def test_boundary_packager_recalculates_identification_and_exact_prefixes(tmp_path):
    config_path = (
        REPO_ROOT
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "configs"
        / "joint_method_assimilation_duration_boundary_v01.json"
    )
    output = tmp_path / "joint_method_assimilation_duration_boundary_v01"

    summary = run(REPO_ROOT, config_path, output)

    assert summary["status"] == "passed"
    assert summary["all_input_evidence_verified"] is True
    assert summary["all_matched_prefixes_exact"] is True
    decision = json.loads((output / "decision.json").read_text(encoding="utf-8"))
    assert decision["identification_sufficient_within_tested_range"] is False
    assert decision["longest_tested_assimilation_days"] == 45
    assert decision["untested_longer_durations_remain_unknown"] is True
    table = pd.read_csv(output / "duration_identification.csv")
    assert table["assimilation_days"].tolist() == [7, 21, 45]
    assert table["identification_effective"].tolist() == [False, False, False]
    prefix = json.loads((output / "prefix_integrity.json").read_text(encoding="utf-8"))
    assert prefix["all_exact"] is True
    assert prefix["comparisons_checked"] == 18
    resource = json.loads((output / "resource_preflight.json").read_text(encoding="utf-8"))
    assert resource["safe_to_run"] is True
    assert resource["execution_parallelism"] == 1
