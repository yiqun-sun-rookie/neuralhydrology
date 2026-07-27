"""Runner contract tests for the formal post-switch confirmation."""

from __future__ import annotations

import importlib

import numpy as np
import pytest


RUNNER_MODULE = (
    "hbv_multilead_joint_uncertainty.scripts."
    "run_g3_post_switch_forecast_confirmation"
)


def _config():
    return {
        "forecast_contract": {
            "model_transition_during_forecast": "identity",
            "candidate_probabilities_during_forecast": (
                "fixed_at_origin_assimilation_posterior"
            ),
            "cross_candidate_state_mixing_during_forecast": False,
        },
        "comparison_methods": [
            "full",
            "none",
            "uniform_independent",
        ],
        "lead_days": [1, 3, 7],
        "switch_days": [180, 360],
        "post_switch_offsets": [0, 1, 2, 3, 4, 5, 6],
        "crosscheck_origin": 539,
        "matched_block_generation": {
            "count": 96,
            "block_id_prefix": "g3_post_switch_confirmation_block_",
            "forcing_seed_start": 8811001,
            "process_noise_seed_start": 8812001,
            "observation_noise_seed_start": 8813001,
        },
        "bootstrap": {
            "unit": "matched_block",
            "replicates": 20000,
            "seed": 8814001,
            "shared_resample_indices_across_leads": True,
        },
        "retention_thresholds": {
            "minimum_meaningful_rmse_fraction": 0.01,
        },
    }


def test_generated_blocks_expand_exact_fresh_seed_contract():
    runner = importlib.import_module(RUNNER_MODULE)
    config = _config()

    blocks = runner._generated_blocks(config)

    assert len(blocks) == 96
    assert blocks[0] == {
        "block_id": "g3_post_switch_confirmation_block_001",
        "forcing_seed": 8811001,
        "process_noise_seed": 8812001,
        "observation_noise_seed": 8813001,
    }
    assert blocks[-1]["forcing_seed"] == 8811096
    all_seeds = [
        int(block[key])
        for block in blocks
        for key in (
            "forcing_seed",
            "process_noise_seed",
            "observation_noise_seed",
        )
    ]
    assert len(all_seeds) == len(set(all_seeds))


@pytest.mark.parametrize(
    ("mutation", "match"),
    [
        (
            lambda config: config["matched_block_generation"].__setitem__(
                "count", 95
            ),
            "count",
        ),
        (
            lambda config: config["post_switch_offsets"].append(7),
            "offsets",
        ),
        (
            lambda config: config["comparison_methods"].remove(
                "uniform_independent"
            ),
            "comparison methods",
        ),
        (
            lambda config: config["bootstrap"].__setitem__(
                "replicates", 19999
            ),
            "20000",
        ),
        (
            lambda config: config["retention_thresholds"].__setitem__(
                "minimum_meaningful_rmse_fraction", 0.0
            ),
            "retention thresholds",
        ),
    ],
)
def test_formal_contract_rejects_drift(mutation, match):
    runner = importlib.import_module(RUNNER_MODULE)
    config = _config()
    mutation(config)

    with pytest.raises(ValueError, match=match):
        runner._validate_config_contract(config)


def test_result_summary_preserves_all_paired_fields():
    runner = importlib.import_module(RUNNER_MODULE)
    comparison = {
        key: np.asarray([1.0, 2.0, 3.0])
        for key in (
            "mean",
            "ci_low",
            "ci_high",
            "baseline_mse",
            "meaningful_improvement_boundary",
        )
    }
    comparison["materially_improves"] = np.asarray([True, True, True])
    statistics = {
        "lead_days": np.asarray([1, 3, 7]),
        "rmse": {
            method: np.asarray([1.0, 2.0, 3.0])
            for method in ("full", "none", "uniform_independent")
        },
        "per_origin_rmse": {
            method: np.ones((14, 3))
            for method in ("full", "none", "uniform_independent")
        },
        "paired": {
            "full_minus_none": comparison,
            "full_minus_uniform_independent": comparison,
        },
        "retention_gates": {
            "full_materially_improves_none_all_leads": True,
            (
                "full_materially_improves_"
                "uniform_independent_all_leads"
            ): True,
            "retain": True,
        },
    }

    result = runner._result_summary(statistics)

    assert result["retention_gates"]["retain"] is True
    assert set(result["paired"]["full_minus_none"]) == {
        "mean",
        "ci_low",
        "ci_high",
        "baseline_mse",
        "meaningful_improvement_boundary",
        "materially_improves",
    }
    assert len(result["per_origin_rmse"]["full"]) == 14
