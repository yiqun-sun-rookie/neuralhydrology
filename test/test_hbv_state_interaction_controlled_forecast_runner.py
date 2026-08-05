import json
from pathlib import Path

import numpy as np
import pytest

from hbv_multilead_joint_uncertainty.scripts.run_g3_fixed_process_state_interaction_controlled_forecast import (
    _build_truth_forecasts,
    _require_unused_output,
    _select_source_states,
    _validate_config,
)


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = (
    PROJECT_ROOT
    / "src/hbv_multilead_joint_uncertainty/configs/"
    "g3_fixed_process_state_interaction_controlled_forecast_v01.json"
)


def test_config_is_a_single_factor_hbv_forecast_control():
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    assert config["model_family"] == "HBV"
    assert config["state_methods"] == [
        "fully_interacting_global_posterior_state",
        "noninteracting_global_posterior_state",
    ]
    assert (
        config["only_changed_factor"]
        == "assimilation state and covariance interaction"
    )
    assert config["fixed_process_id"] == "process_2"
    assert config["fixed_forecast_parameter_id"] == "trained_center"
    assert config["lead_days"] == list(range(1, 8))
    assert config["cross_switch_policy"] == "exclude_from_primary_metrics"
    assert config["future_discharge_observations_used"] is False
    assert config["forecast_state_count"] == 1
    assert config["forecast_trajectory_count"] == 1
    assert config["forecast_covariance_used"] is False
    assert config["candidate_forecast_trajectories_used"] is False
    assert config["bootstrap"] == {
        "replicates": 20000,
        "seed": 20260801,
        "unit": "matched_block",
    }
    assert config["numerical_tolerance"] == 1e-10
    assert len(config["sealed_state_audit_evidence"]["sha256"]) == 64
    assert len(config["sealed_ideal_evidence"]["sha256"]) == 64
    _validate_config(config)


def test_runner_selects_exact_full_and_no_interaction_global_states():
    sealed_names = np.asarray(
        [
            "fully_interacting_multiple_model_global_posterior_state",
            "noninteracting_multiple_filter_global_posterior_state_control",
        ]
    )
    values = np.arange(2 * 2 * 1 * 3 * 15, dtype=np.float64).reshape(
        2, 1, 2, 3, 15
    )
    selected, indices = _select_source_states(sealed_names, values)
    assert indices == (0, 1)
    np.testing.assert_array_equal(
        selected["fully_interacting_global_posterior_state"], values[:, :, 0]
    )
    np.testing.assert_array_equal(
        selected["noninteracting_global_posterior_state"], values[:, :, 1]
    )


def test_existing_output_directory_is_rejected_before_execution(tmp_path):
    output = tmp_path / "already_exists"
    output.mkdir()
    with pytest.raises(FileExistsError, match="already exists"):
        _require_unused_output(output)


def test_truth_forecasts_use_exact_future_target_indices():
    truth = np.arange(20, dtype=np.float64).reshape(1, 2, 10)
    targets = np.asarray([[1, 3], [4, 7]], dtype=np.int64)
    selected = _build_truth_forecasts(truth, targets)
    assert selected.shape == (1, 2, 2, 2)
    np.testing.assert_array_equal(selected[0, 0], [[1.0, 3.0], [4.0, 7.0]])
    np.testing.assert_array_equal(selected[0, 1], [[11.0, 13.0], [14.0, 17.0]])


def test_runner_forbids_candidate_trajectory_and_covariance_forecasts():
    runner_path = (
        PROJECT_ROOT
        / "src/hbv_multilead_joint_uncertainty/scripts/"
        "run_g3_fixed_process_state_interaction_controlled_forecast.py"
    )
    runner_source = runner_path.read_text(encoding="utf-8")
    assert "model_conditioned_forecast" not in runner_source
    assert 'candidate_forecast_trajectories_used": True' not in runner_source
    assert '"forecast_trajectory_count": 1' in runner_source
    assert '"forecast_covariance_used": False' in runner_source
