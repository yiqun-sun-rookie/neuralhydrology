from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from camels_switch_confirmation.diagnose_parameter_likelihood import (
    decompose_gaussian_log_odds,
    replay_task,
    select_extreme_tasks,
    verify_content_manifest,
    write_npz_exclusive,
)


REPO_ROOT = Path(__file__).resolve().parents[1]
PARENT_CONFIG = REPO_ROOT / (
    "src/camels_switch_confirmation/configs/"
    "camels_parfc_state_interaction_design90_01b.json"
)
REFERENCE_TASK = REPO_ROOT / (
    "results/23_camels_switch_confirmation/"
    "camels_parfc_state_interaction_01b_design90_s01_20260810_local/"
    "arms/C/probs/05501000_s1.npz"
)


def _selection_frame():
    return pd.DataFrame(
        [
            {"arm_id": "A", "basin_id": "00000001", "seed": 0,
             "true_negative_log_probability": 9000.0},
            {"arm_id": "C", "basin_id": "00000002", "seed": 0,
             "true_negative_log_probability": 1000.0},
            {"arm_id": "C", "basin_id": "00000003", "seed": 0,
             "true_negative_log_probability": 1000.1},
            {"arm_id": "C", "basin_id": "00000004", "seed": 1,
             "true_negative_log_probability": 2000.0},
        ]
    )


def test_select_extreme_tasks_uses_strict_threshold_and_c_arm_only():
    selected = select_extreme_tasks(_selection_frame(), threshold=1000.0)

    assert selected[["basin_id", "seed"]].to_records(index=False).tolist() == [
        ("00000004", 1),
        ("00000003", 0),
    ]


def test_select_extreme_tasks_rejects_reserved_seed():
    frame = _selection_frame()
    frame.loc[len(frame)] = {
        "arm_id": "C",
        "basin_id": "00000005",
        "seed": 2,
        "true_negative_log_probability": 3000.0,
    }

    with pytest.raises(ValueError, match="design seeds"):
        select_extreme_tasks(frame, threshold=1000.0)


def test_select_extreme_tasks_rejects_duplicate_task():
    frame = _selection_frame()
    frame.loc[len(frame)] = frame.iloc[-1]

    with pytest.raises(ValueError, match="duplicate"):
        select_extreme_tasks(frame, threshold=1000.0)


def test_decompose_gaussian_log_odds_closes_exactly():
    result = decompose_gaussian_log_odds(
        winner_prior_probability=0.30,
        true_prior_probability=0.20,
        winner_innovation=1.5,
        true_innovation=3.0,
        winner_innovation_variance=2.0,
        true_innovation_variance=4.0,
    )

    expected_prior = np.log(0.30 / 0.20)
    expected_residual = -0.5 * (1.5**2 / 2.0 - 3.0**2 / 4.0)
    expected_log_variance = -0.5 * np.log(2.0 / 4.0)
    assert result["prior_log_odds"] == pytest.approx(expected_prior)
    assert result["residual_contribution"] == pytest.approx(expected_residual)
    assert result["log_variance_contribution"] == pytest.approx(
        expected_log_variance
    )
    assert result["posterior_log_odds"] == pytest.approx(
        expected_prior + expected_residual + expected_log_variance
    )
    assert result["closure_error"] <= 1e-12


@pytest.mark.parametrize(
    "keyword,value",
    [
        ("winner_prior_probability", 0.0),
        ("true_prior_probability", -0.1),
        ("winner_innovation_variance", 0.0),
        ("true_innovation_variance", -1.0),
    ],
)
def test_decompose_gaussian_log_odds_rejects_nonpositive_inputs(keyword, value):
    arguments = {
        "winner_prior_probability": 0.3,
        "true_prior_probability": 0.2,
        "winner_innovation": 1.5,
        "true_innovation": 3.0,
        "winner_innovation_variance": 2.0,
        "true_innovation_variance": 4.0,
    }
    arguments[keyword] = value

    with pytest.raises(ValueError, match="positive"):
        decompose_gaussian_log_odds(**arguments)


def test_replay_task_matches_registered_parent_for_initial_days():
    trace = replay_task(
        repo_root=REPO_ROOT,
        parent_config_path=PARENT_CONFIG,
        basin_id="05501000",
        seed=1,
        reference_probability_path=REFERENCE_TASK,
        maximum_days=12,
    )

    assert int(trace["n_days_traced"]) == 12
    assert float(trace["truth_maximum_absolute_difference"]) == 0.0
    assert float(trace["observation_maximum_absolute_difference"]) == 0.0
    assert float(trace["probability_maximum_absolute_difference"]) <= 1e-12
    assert float(trace["log_probability_maximum_absolute_difference"]) <= 1e-12
    assert trace["predicted_observation"].shape == (12, 3)
    assert trace["pre_interaction_state"].shape == (12, 3, 15)
    assert trace["mixed_covariance_diagonal"].shape == (12, 3, 15)
    assert np.all(trace["innovation_variance"] > 0.0)


def test_write_npz_exclusive_refuses_existing_target(tmp_path):
    target = tmp_path / "trace.npz"
    write_npz_exclusive(target, values=np.array([1.0]))

    with pytest.raises(FileExistsError, match="already exists"):
        write_npz_exclusive(target, values=np.array([2.0]))


def test_verify_content_manifest_rehashes_registered_files(tmp_path):
    first = tmp_path / "first.txt"
    second = tmp_path / "second.txt"
    first.write_text("first\n", encoding="utf-8")
    second.write_text("second\n", encoding="utf-8")
    import hashlib

    rows = []
    for path in (first, second):
        rows.append(
            {
                "relative_path": path.relative_to(tmp_path).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            }
        )
    manifest = tmp_path / "manifest.csv"
    pd.DataFrame(rows).to_csv(manifest, index=False)

    assert verify_content_manifest(tmp_path, manifest) == 2
    second.write_text("changed\n", encoding="utf-8")
    with pytest.raises(ValueError, match="content manifest mismatch"):
        verify_content_manifest(tmp_path, manifest)
