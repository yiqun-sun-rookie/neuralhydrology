import json
import sys
from pathlib import Path

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES  # noqa: E402
from hbv_multilead_joint_uncertainty.preparation import (  # noqa: E402
    _center_parameters,
    _method_contract_parts,
    _parameter_pool_from_config,
    evaluate_parameter_pool,
    evaluate_single_filter_noise_grid,
)
from hbv_multilead_joint_uncertainty.methods import (  # noqa: E402
    LEGACY_PARAMETER_ORDER,
    PARAMETER_ORDER,
)
from hbv_multilead_joint_uncertainty.contracts import load_base_config  # noqa: E402
from hbv_multilead_joint_uncertainty.selection import generate_local_parameter_pool  # noqa: E402


CENTER = {
    "parTT": 0.0,
    "parCFMAX": 3.0,
    "parCFR": 0.05,
    "parCWH": 0.1,
    "parFC": 200.0,
    "parBETA": 2.0,
    "parLP": 0.8,
    "parK0": 0.2,
    "parK1": 0.1,
    "parUZL": 20.0,
    "parPERC": 1.0,
    "parK2": 0.05,
    "lag_time": 2.0,
}


def _forcing(days):
    x = np.arange(days, dtype=np.float64)
    return np.column_stack((2.0 + np.sin(x / 3.0), np.full(days, 1.0), 5.0 + np.cos(x / 7.0)))


def test_parameter_pool_evaluation_returns_one_finite_score_and_mean_per_complete_vector():
    candidates = generate_local_parameter_pool(CENTER, count=4, fraction=0.1, seed=3)
    warmup = _forcing(20)
    development = _forcing(30)
    observations = np.linspace(0.1, 2.0, 30)

    result = evaluate_parameter_pool(CENTER, candidates, warmup, development, observations)

    assert result["candidate_nse"].shape == (4,)
    assert result["candidate_mean_discharge"].shape == (4,)
    assert np.all(np.isfinite(result["candidate_nse"]))
    assert np.all(np.isfinite(result["candidate_mean_discharge"]))
    assert np.isfinite(result["center_nse"])
    assert set(result["center_parameters"]) == set(PARAMETER_NAMES)
    assert result["center_predictions"].shape == observations.shape


def test_current_parameter_pool_config_builds_four_fixed_scales_with_candidate_provenance():
    config = {
        "schema_version": 3,
        "pool_size": 16,
        "candidates_per_scale": 4,
        "local_fractions": [0.1, 0.05, 0.025, 0.0125],
    }

    pool, provenance, outer_fraction = _parameter_pool_from_config(
        CENTER, config, seed=7
    )

    assert len(pool) == 16
    assert [row["candidate_index"] for row in provenance] == list(range(16))
    assert [row["local_fraction"] for row in provenance[::4]] == [
        0.1,
        0.05,
        0.025,
        0.0125,
    ]
    assert outer_fraction == 0.1


def test_noise_grid_uses_one_fixed_absolute_process_covariance_per_scale():
    warmup = _forcing(20)
    development = _forcing(12)
    observations = np.linspace(0.2, 1.2, 12)
    process_scales = np.array([1e-8, 1e-7, 1e-6])
    observation_stds = np.array([0.1, 0.2])

    result = evaluate_single_filter_noise_grid(
        center_parameters=CENTER,
        warmup_forcing=warmup,
        development_forcing=development,
        development_observations=observations,
        process_scales=process_scales,
        observation_standard_deviations=observation_stds,
        initial_covariance_fraction=0.001,
    )

    assert result["mean_log_likelihoods"].shape == (3, 2)
    assert result["process_covariance_diagonals"].shape == (3, 15)
    assert np.all(np.isfinite(result["mean_log_likelihoods"]))
    assert np.all(result["process_covariance_diagonals"][:, :5] > 0.0)
    assert np.count_nonzero(result["process_covariance_diagonals"][:, 5:]) == 0
    np.testing.assert_allclose(
        result["process_covariance_diagonals"][1],
        10 * result["process_covariance_diagonals"][0],
    )


def test_center_parameter_source_rejects_changed_metadata_even_when_parameter_projection_matches():
    config = load_base_config(REPO_ROOT)
    config["parameter_source"]["metadata_sha256"] = "0" * 64

    with pytest.raises(ValueError, match="metadata checksum"):
        _center_parameters(REPO_ROOT, "04015330", config)


@pytest.mark.parametrize("parameter_order", [PARAMETER_ORDER, LEGACY_PARAMETER_ORDER])
def test_method_contract_loader_restores_frozen_parameter_order_after_sorted_json_round_trip(
    parameter_order,
):
    contract = {
        "parameter_vectors": {
            parameter_id: {"parameters": {**CENTER, "parTT": float(index)}}
            for index, parameter_id in enumerate(parameter_order)
        },
        "process_noise": {
            "candidates": [
                {
                    "process_id": "process_0",
                    "variance_scale": 1e-6,
                    "covariance_matrix": [[1.0]],
                }
            ]
        },
    }
    sorted_round_trip = json.loads(json.dumps(contract, sort_keys=True))
    assert tuple(sorted_round_trip["parameter_vectors"]) != parameter_order

    parameter_vectors, process_scales, process_covariances = _method_contract_parts(
        sorted_round_trip
    )

    assert tuple(parameter_vectors) == parameter_order
    assert tuple(process_scales) == ("process_0",)
    assert tuple(process_covariances) == ("process_0",)
