from pathlib import Path
import hashlib
import json
import sys

import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from compose_seed_ensemble_v06 import (
    compose_prediction_frames_v06,
    validate_seed_ensemble_config_v06,
)
from compose_three_seed_ensemble_v06 import validate_three_seed_ensemble_config_v06


def _frame(first: float, second: float) -> pd.DataFrame:
    return pd.DataFrame({
        "basin": ["a", "a"],
        "date": ["2007-01-01", "2007-01-02"],
        "qobs": [1.0, 2.0],
        "qsim": [first, second],
    })


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_v06_seed_ensemble_is_exact_rowwise_equal_weight_mean():
    result = compose_prediction_frames_v06(
        [_frame(1.0, 2.0), _frame(3.0, 4.0)],
        weights=[0.5, 0.5],
    )

    assert result.to_dict("list") == {
        "basin": ["a", "a"],
        "date": ["2007-01-01", "2007-01-02"],
        "qobs": [1.0, 2.0],
        "qsim": [2.0, 3.0],
    }


def test_v06_seed_ensemble_rejects_weight_or_target_drift():
    with pytest.raises(ValueError, match="sum to one"):
        compose_prediction_frames_v06(
            [_frame(1.0, 2.0), _frame(3.0, 4.0)],
            weights=[0.4, 0.5],
        )
    changed = _frame(3.0, 4.0)
    changed.loc[0, "qobs"] = 1.1
    with pytest.raises(ValueError, match="observations"):
        compose_prediction_frames_v06(
            [_frame(1.0, 2.0), changed],
            weights=[0.5, 0.5],
        )


def test_v06_real_seed_ensemble_config_is_valid_and_all_inputs_match_hashes():
    idea = Path(__file__).resolve().parents[1]
    repo = idea.parents[1]
    config = json.loads(
        (idea / "configs/late_concat_seed_ensemble_i04_v06.json").read_text(encoding="utf-8")
    )

    validate_seed_ensemble_config_v06(config)
    assert _sha256(repo / config["iteration_three_summary"]) == (
        config["iteration_three_summary_sha256"]
    )
    for group in ("candidate_members", "classic_members", "capacity_members"):
        for member in config[group]:
            assert _sha256(repo / member["predictions"]) == member["sha256"]
    assert _sha256(repo / config["legacy_late_concat_predictions"]) == (
        config["legacy_late_concat_predictions_sha256"]
    )


def test_v06_real_three_seed_ensemble_config_is_valid_and_all_inputs_match_hashes():
    idea = Path(__file__).resolve().parents[1]
    repo = idea.parents[1]
    config = json.loads(
        (idea / "configs/late_concat_three_seed_ensemble_i05_v06.json").read_text(
            encoding="utf-8"
        )
    )

    validate_three_seed_ensemble_config_v06(config)
    assert _sha256(repo / config["iteration_four_summary"]) == (
        config["iteration_four_summary_sha256"]
    )
    for group in ("candidate_members", "classic_members", "capacity_members"):
        for member in config[group]:
            assert _sha256(repo / member["predictions"]) == member["sha256"]


@pytest.mark.parametrize(
    ("key", "value"),
    [
        ("candidate_iteration", 3),
        ("ensemble_operation", "median"),
        ("member_seeds", [100, 200]),
        ("member_weights", [0.25, 0.75]),
        ("discovery_seed_excluded", 200),
        ("formal_evaluation_access", True),
    ],
)
def test_v06_seed_ensemble_config_rejects_protocol_drift(key, value):
    idea = Path(__file__).resolve().parents[1]
    config = json.loads(
        (idea / "configs/late_concat_seed_ensemble_i04_v06.json").read_text(encoding="utf-8")
    )
    config[key] = value
    with pytest.raises(ValueError, match=key):
        validate_seed_ensemble_config_v06(config)
