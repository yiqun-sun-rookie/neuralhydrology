import numpy as np
import pytest

from hbv_multilead_joint_uncertainty.fixed_process_parameter_candidate_forecast import (
    CONTROLLED_METHOD_ROLES,
    CONTROLLED_METHODS,
    summarize_controlled_forecasts,
    validate_common_forecast_parameters,
    validate_controlled_candidate_contract,
)


def _sealed_candidate_arrays():
    method_names = np.asarray(
        ("open_loop", "fixed_filter", "parameter_only", "noise_only", "joint")
    )
    candidate_counts = np.asarray((1, 1, 3, 3, 9), dtype=np.int64)
    candidate_ids = np.full((5, 9), "", dtype="U96")
    candidate_ids[0, 0] = "trained_center_open_loop"
    candidate_ids[1, 0] = "trained_center__process_2"
    candidate_ids[2, :3] = (
        "equifinal_diverse_1__process_2",
        "trained_center__process_2",
        "equifinal_diverse_2__process_2",
    )
    candidate_ids[3, :3] = (
        "trained_center__process_0",
        "trained_center__process_1",
        "trained_center__process_2",
    )
    candidate_ids[4] = tuple(
        f"{parameter}__{process}"
        for parameter in (
            "equifinal_diverse_1",
            "trained_center",
            "equifinal_diverse_2",
        )
        for process in ("process_0", "process_1", "process_2")
    )
    return method_names, candidate_ids, candidate_counts


def test_candidate_contract_matches_single_filter_and_full_imm_sources():
    method_names, candidate_ids, candidate_counts = _sealed_candidate_arrays()
    contract = validate_controlled_candidate_contract(
        method_names, candidate_ids, candidate_counts
    )
    assert contract.output_method_names == CONTROLLED_METHODS
    assert CONTROLLED_METHOD_ROLES[CONTROLLED_METHODS[1]] == (
        "fully_interacting_multiple_model_global_posterior_state"
    )
    assert contract.fixed_filter_candidates == ("trained_center__process_2",)
    assert contract.parameter_candidate_parameter_ids == (
        "equifinal_diverse_1",
        "trained_center",
        "equifinal_diverse_2",
    )
    assert contract.parameter_candidate_process_ids == ("process_2",) * 3
    assert contract.fixed_process_id == "process_2"


def test_candidate_contract_rejects_a_second_process_covariance():
    method_names, candidate_ids, candidate_counts = _sealed_candidate_arrays()
    candidate_ids[2, 2] = "equifinal_diverse_2__process_1"
    with pytest.raises(ValueError, match="same process_2 process covariance"):
        validate_controlled_candidate_contract(
            method_names, candidate_ids, candidate_counts
        )


def test_common_forecast_parameter_must_be_identical_for_both_methods():
    trained_center = np.arange(13, dtype=np.float64)
    selected = validate_common_forecast_parameters(
        trained_center.copy(), trained_center.copy(), trained_center
    )
    np.testing.assert_array_equal(selected, trained_center)
    assert not selected.flags.writeable
    with pytest.raises(ValueError, match="same trained_center forecast parameters"):
        validate_common_forecast_parameters(
            trained_center, trained_center + 1.0, trained_center
        )


def test_summary_uses_matched_blocks_same_stage_mask_and_frozen_decision_rule():
    truth = np.zeros((2, 1, 3, 2), dtype=np.float64)
    single = np.empty_like(truth)
    three = np.empty_like(truth)
    single[0] = 2.0
    single[1] = 4.0
    three[0] = 1.0
    three[1] = 2.0
    mask = np.asarray([[[True, True], [True, False], [False, True]]])
    stage_indices = np.asarray([[0, 1, 2]], dtype=np.int64)
    bootstrap = np.asarray([[0, 0], [0, 1], [1, 1]], dtype=np.int64)

    result = summarize_controlled_forecasts(
        {
            CONTROLLED_METHODS[0]: single,
            CONTROLLED_METHODS[1]: three,
        },
        truth,
        mask,
        stage_indices,
        ("stage_0", "stage_1", "stage_2"),
        bootstrap,
        minimum_relative_rmse_reduction=0.01,
    )

    np.testing.assert_allclose(
        result["rmse"][CONTROLLED_METHODS[0]], np.sqrt(10.0)
    )
    np.testing.assert_allclose(
        result["rmse"][CONTROLLED_METHODS[1]], np.sqrt(2.5)
    )
    np.testing.assert_allclose(result["relative_rmse_fraction"], -0.5)
    np.testing.assert_allclose(result["block_mse_difference"], [[-3, -3], [-12, -12]])
    assert np.all(result["improvement_decision"])
    np.testing.assert_array_equal(result["same_stage_sample_count_per_block"], [2, 2])
    assert result["stage_rmse"].shape == (2, 3, 2)


def test_summary_rejects_unmatched_forecast_shapes():
    truth = np.zeros((2, 1, 3, 2), dtype=np.float64)
    with pytest.raises(ValueError, match="match truth"):
        summarize_controlled_forecasts(
            {
                CONTROLLED_METHODS[0]: np.zeros((2, 1, 3, 1)),
                CONTROLLED_METHODS[1]: truth.copy(),
            },
            truth,
            np.ones((1, 3, 2), dtype=bool),
            np.asarray([[0, 1, 2]], dtype=np.int64),
            ("stage_0", "stage_1", "stage_2"),
            np.asarray([[0, 1]], dtype=np.int64),
            minimum_relative_rmse_reduction=0.01,
        )
