import json

import pytest

from hbv_multilead_joint_uncertainty.scripts.run_g3_deterministic_unique_state_forecast_attribution import (
    _validate_config,
)


def _config():
    return {
        "experiment_id": "g3_deterministic_unique_state_forecast_attribution_v01",
        "assimilation_days": 540,
        "lead_days": list(range(1, 8)),
        "state_sources": [
            "posterior_all_states",
            "truth_all_states",
            "posterior_hydrologic_truth_routing",
            "truth_hydrologic_posterior_routing",
        ],
        "parameter_sources": [
            "true_stage_parameters",
            "posterior_weighted_parameters",
            "maximum_posterior_parameters",
        ],
        "bootstrap": {
            "replicates": 20000,
            "seed": 20260731,
            "unit": "matched_block",
        },
        "cross_switch_policy": "diagnostic_only",
        "resource_limits": {"sequential_method_processing": True},
    }


def test_frozen_config_is_accepted():
    _validate_config(_config())


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("assimilation_days", 539),
        ("lead_days", [1, 3, 7]),
        ("cross_switch_policy", "include"),
    ],
)
def test_contract_drift_is_rejected(field, value):
    config = json.loads(json.dumps(_config()))
    config[field] = value
    with pytest.raises(ValueError):
        _validate_config(config)


def test_covariance_is_not_part_of_the_frozen_config():
    config = _config()
    assert "covariance" not in json.dumps(config).lower()
