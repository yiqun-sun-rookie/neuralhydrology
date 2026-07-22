import json
import sys
from pathlib import Path

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES, V1_PARAMETER_BOUNDS  # noqa: E402
from hbv_multilead_joint_uncertainty.contracts import (  # noqa: E402
    INPUT_CONTRACT,
    PARAMETER_CONTRACT,
    load_base_config,
)
from hbv_multilead_joint_uncertainty.selection import (  # noqa: E402
    build_frozen_process_diagonals,
    generate_local_parameter_pool,
    generate_multiscale_parameter_pool,
    observation_standard_deviation_grid,
    robust_residual_scale,
    select_equifinal_parameters,
    select_noise_grid,
)


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


def test_input_contract_names_units_derivations_and_hindsight_availability():
    rows = {row["variable_id"]: row for row in INPUT_CONTRACT}

    assert set(rows) == {"precipitation", "mean_temperature", "potential_evapotranspiration", "streamflow"}
    assert rows["precipitation"]["model_unit"] == "mm/day"
    assert rows["mean_temperature"]["model_unit"] == "degree_Celsius"
    assert rows["potential_evapotranspiration"]["derivation"] == "Priestley-Taylor"
    assert rows["streamflow"]["derivation"] == "cubic_feet_per_second * 2.4466 / basin_area_km2"
    assert all(row["future_availability"] == "historical_hindsight_only" for row in INPUT_CONTRACT[:3])
    assert rows["streamflow"]["future_availability"] == "forbidden_after_origin"


def test_parameter_contract_covers_all_thirteen_values_with_units_and_v1_bounds():
    assert tuple(PARAMETER_CONTRACT) == PARAMETER_NAMES
    for name, row in PARAMETER_CONTRACT.items():
        assert row["unit"]
        assert tuple(row["bounds"]) == V1_PARAMETER_BOUNDS[name]
        assert row["meaning"]


def test_base_config_freezes_periods_leads_methods_and_resource_gates():
    config = load_base_config(REPO_ROOT)

    assert config["lead_days"] == [1, 3, 7]
    assert config["calibration_selection_start"] >= config["parameter_source"]["calibration_start"]
    assert config["calibration_selection_end"] <= config["parameter_source"]["calibration_end"]
    assert config["evaluation_start"] == "1989-10-01"
    assert config["evaluation_end"] == "1990-09-30"
    assert config["methods"] == ["open_loop", "fixed_filter", "parameter_only", "noise_only", "joint"]
    assert config["noise_selection"]["minimum_robust_residual_scale_mm_day"] == 0.05
    assert "minimum_observation_standard_deviation_mm_day" not in config["noise_selection"]
    assert config["parameter_selection"] == {
        "schema_version": 3,
        "strategy": "multiscale_global_maximin_normalized_parameter_distance",
        "pool_generator": "scrambled_sobol_restarted_per_scale",
        "pool_size": 1024,
        "candidates_per_scale": 256,
        "local_fractions": [0.1, 0.05, 0.025, 0.0125],
        "candidate_order": "local_fraction_config_order_then_scale_candidate_index",
        "maximum_nse_drop": 0.03,
        "normalization": "frozen_physical_bound_span",
        "distance": "euclidean",
        "objective": "maximize_the_minimum_of_both_center_distances_and_the_pair_distance",
        "tie_break": "candidate_index_ascending_lexicographic",
    }
    assert config["_loaded_config_path"].endswith("base_v02.json")
    assert config["resource"] == {
        "minimum_start_available_fraction": 0.25,
        "minimum_running_available_fraction": 0.20,
        "maximum_estimated_peak_fraction_of_available": 0.60,
        "minimum_free_disk_gib": 50.0,
        "minimum_output_space_multiplier": 3.0,
        "monitor_interval_seconds": 15.0,
        "maximum_resource_probe_seconds": 5.0,
        "reserved_logical_processors": 2,
    }
    json.dumps(config)


def test_readme_describes_the_active_four_scale_1024_candidate_parameter_pool():
    readme = (
        REPO_ROOT / "src" / "hbv_multilead_joint_uncertainty" / "README.md"
    ).read_text(encoding="utf-8")
    compact = "".join(readme.split())

    assert "10%、5%、2.5%和1.25%四个范围" in readme
    assert "每个范围生成256个" in readme
    assert "合计1,024个" in readme
    assert "每个范围都使用固定随机种子1，并重新启动同一条加扰索博尔低差异序列" in compact
    assert "候选编号按上述范围从大到小排列，每个范围内再按采样顺序排列" in readme
    assert "不超过0.03的候选" in readme
    assert "每个参数差值除以该参数的冻结物理边界跨度" in readme
    assert "穷举所有范围中的全部合格候选对" in readme
    assert "三个距离中最小值最大的" in readme
    assert "重新模拟中心及全部1,024个候选" in readme
    assert "10%范围内，用固定随机种子生成256个" not in readme


def test_local_parameter_pool_is_deterministic_finite_and_inside_the_ten_percent_envelope():
    first = generate_local_parameter_pool(CENTER, count=16, fraction=0.1, seed=7)
    second = generate_local_parameter_pool(CENTER, count=16, fraction=0.1, seed=7)

    assert len(first) == 16
    assert first == second
    assert len({tuple(row[name] for name in PARAMETER_NAMES) for row in first}) == 16
    for row in first:
        for name in PARAMETER_NAMES:
            lower, upper = V1_PARAMETER_BOUNDS[name]
            local_lower = CENTER[name] - 0.1 * (CENTER[name] - lower)
            local_upper = CENTER[name] + 0.1 * (upper - CENTER[name])
            assert local_lower <= row[name] <= local_upper


def test_multiscale_pool_is_an_auditable_concatenation_of_restarted_sobol_scales():
    fractions = (0.1, 0.05, 0.025, 0.0125)

    pool, audit = generate_multiscale_parameter_pool(
        CENTER,
        fractions=fractions,
        count_per_scale=4,
        seed=7,
    )

    assert len(pool) == 16
    assert len(audit) == 16
    for scale_index, fraction in enumerate(fractions):
        start = 4 * scale_index
        stop = start + 4
        assert pool[start:stop] == generate_local_parameter_pool(
            CENTER, count=4, fraction=fraction, seed=7
        )
        assert audit[start:stop] == [
            {
                "candidate_index": start + local_index,
                "scale_index": scale_index,
                "local_fraction": fraction,
                "scale_candidate_index": local_index,
            }
            for local_index in range(4)
        ]


@pytest.mark.parametrize("count", [0, 3, 12])
def test_local_parameter_pool_requires_a_positive_power_of_two(count):
    with pytest.raises(ValueError, match="power of two"):
        generate_local_parameter_pool(CENTER, count=count, fraction=0.1, seed=1)


def test_equifinal_selection_globally_maximizes_parameter_diversity_even_on_one_mean_flow_side():
    candidates = [
        {**CENTER, "parTT": -0.2},
        {**CENTER, "parTT": 0.2},
        {**CENTER, "parCFMAX": 3.5},
        {**CENTER, "parFC": 250.0},
    ]
    selected = select_equifinal_parameters(
        center=CENTER,
        candidates=candidates,
        center_nse=0.80,
        center_mean_discharge=1.8,
        candidate_nse=np.array([0.79, 0.785, 0.78, 0.70]),
        candidate_mean_discharge=np.array([2.0, 2.1, 2.2, 2.3]),
        maximum_nse_drop=0.03,
    )

    assert list(selected) == [
        "equifinal_diverse_1",
        "trained_center",
        "equifinal_diverse_2",
    ]
    assert selected["equifinal_diverse_1"]["candidate_index"] == 0
    assert selected["equifinal_diverse_2"]["candidate_index"] == 1
    assert selected["equifinal_diverse_1"]["development_mean_discharge"] > 1.8
    assert selected["equifinal_diverse_2"]["development_mean_discharge"] > 1.8
    assert selected["equifinal_diverse_1"]["development_nse"] == pytest.approx(0.79)
    assert selected["equifinal_diverse_2"]["development_nse"] == pytest.approx(0.785)
    assert selected["equifinal_diverse_1"]["selected_pair_minimum_distance"] == pytest.approx(
        selected["equifinal_diverse_2"]["selected_pair_minimum_distance"]
    )


def test_equifinal_selection_fails_instead_of_relaxing_the_rule_on_evaluation_data():
    with pytest.raises(ValueError, match="two distinct eligible"):
        select_equifinal_parameters(
            center=CENTER,
            candidates=[{**CENTER, "parTT": 0.1}, {**CENTER, "parTT": 0.2}],
            center_nse=0.8,
            center_mean_discharge=1.5,
            candidate_nse=np.array([0.79, 0.5]),
            candidate_mean_discharge=np.array([1.0, 2.0]),
            maximum_nse_drop=0.03,
        )


def test_equifinal_selection_is_bitwise_deterministic():
    candidates = [
        {**CENTER, "parTT": -0.2},
        {**CENTER, "parTT": 0.2},
        {**CENTER, "parCFMAX": 3.5},
    ]
    arguments = dict(
        center=CENTER,
        candidates=candidates,
        center_nse=0.8,
        center_mean_discharge=1.0,
        candidate_nse=np.array([0.8, 0.8, 0.8]),
        candidate_mean_discharge=np.array([2.0, 3.0, 4.0]),
        maximum_nse_drop=0.03,
    )

    assert select_equifinal_parameters(**arguments) == select_equifinal_parameters(**arguments)


def test_equifinal_selection_matches_an_independent_exhaustive_global_objective_within_one_e_minus_12():
    candidates = generate_local_parameter_pool(CENTER, count=16, fraction=0.1, seed=11)
    scores = np.linspace(0.80, 0.77, 16)
    selected = select_equifinal_parameters(
        center=CENTER,
        candidates=candidates,
        center_nse=0.80,
        center_mean_discharge=1.0,
        candidate_nse=scores,
        candidate_mean_discharge=np.linspace(2.0, 3.0, 16),
        maximum_nse_drop=0.03,
    )

    spans = np.array(
        [V1_PARAMETER_BOUNDS[name][1] - V1_PARAMETER_BOUNDS[name][0] for name in PARAMETER_NAMES]
    )
    center = np.array([CENTER[name] for name in PARAMETER_NAMES])
    normalized = [
        (np.array([candidate[name] for name in PARAMETER_NAMES]) - center) / spans
        for candidate in candidates
    ]
    independent_objectives = []
    for first in range(16):
        for second in range(first + 1, 16):
            independent_objectives.append(
                min(
                    np.linalg.norm(normalized[first]),
                    np.linalg.norm(normalized[second]),
                    np.linalg.norm(normalized[first] - normalized[second]),
                )
            )
    selected_objective = selected["equifinal_diverse_1"][
        "selected_pair_minimum_distance"
    ]

    assert abs(selected_objective - max(independent_objectives)) <= 1e-12


def test_robust_residual_scale_and_observation_grid_are_exact():
    residuals = np.array([-1.0, 0.0, 1.0, 100.0])
    scale = robust_residual_scale(residuals, minimum=0.05)

    assert scale == pytest.approx(1.4826)
    np.testing.assert_allclose(
        observation_standard_deviation_grid(residuals, multipliers=(0.25, 0.5, 1.0), minimum=0.05),
        np.array([0.37065, 0.7413, 1.4826]),
    )
    assert robust_residual_scale(np.zeros(5), minimum=0.05) == pytest.approx(0.05)


def test_noise_grid_selects_maximum_score_and_three_unique_neighboring_scales():
    process_scales = np.array([1e-8, 1e-7, 1e-6, 1e-5, 1e-4])
    observation_stds = np.array([0.1, 0.2, 0.4])
    scores = np.zeros((5, 3))
    scores[2, 1] = 10.0

    selected = select_noise_grid(process_scales, observation_stds, scores)

    assert selected["selected_process_scale"] == pytest.approx(1e-6)
    assert selected["selected_observation_standard_deviation"] == pytest.approx(0.2)
    np.testing.assert_array_equal(selected["candidate_process_scales"], np.array([1e-7, 1e-6, 1e-5]))


def test_noise_grid_uses_three_unique_values_at_a_boundary():
    process_scales = np.array([1e-8, 1e-7, 1e-6, 1e-5])
    scores = np.zeros((4, 1))
    scores[0, 0] = 1.0

    selected = select_noise_grid(process_scales, np.array([0.1]), scores)

    np.testing.assert_array_equal(selected["candidate_process_scales"], np.array([1e-8, 1e-7, 1e-6]))


def test_process_diagonals_are_built_once_from_center_and_reused_across_parameter_vectors():
    scales = np.array([1e-7, 1e-6, 1e-5])
    diagonals = build_frozen_process_diagonals(CENTER, scales)

    assert diagonals.shape == (3, 15)
    assert np.all(diagonals[:, :5] > 0.0)
    assert np.count_nonzero(diagonals[:, 5:]) == 0
    np.testing.assert_allclose(diagonals[1], 10.0 * diagonals[0])
    np.testing.assert_allclose(diagonals[2], 10.0 * diagonals[1])
