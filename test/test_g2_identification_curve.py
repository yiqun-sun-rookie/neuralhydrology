"""Tests for the G2 identification-time curve round (design doc 2026-07-22).

Frozen rules under test: multiplier scaling around the trained center with
hard bounds rejection (never truncation), identification time T = adaptation
days + first stable cumulative rank-one day with censoring, quantile summary,
the deterministic boundary-cell rule, preregistered monotonicity checking, and
the development seed layout (new segments, paired within a budget row).
"""

import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES, V1_PARAMETER_BOUNDS  # noqa: E402
from hbv_multilead_joint_uncertainty.g2_curve_design import (  # noqa: E402
    BUDGET_STAGE_LENGTHS,
    SPACING_MULTIPLIERS,
    development_block_seeds,
    development_experiment_id,
    grid_cells,
)
from hbv_multilead_joint_uncertainty.g2_curve_summary import (  # noqa: E402
    identification_time_cycles,
    monotonicity_violations,
    select_boundary_cells,
    summarize_identification_times,
)
from hbv_multilead_joint_uncertainty.g2_spacing_inputs import (  # noqa: E402
    build_scaled_parameter_table,
    scale_parameter_vector,
)


def _center() -> dict[str, float]:
    values = {name: 0.5 * (lower + upper) for name, (lower, upper) in V1_PARAMETER_BOUNDS.items()}
    values["parK2"] = 0.0221
    return values


def _diverse() -> dict[str, float]:
    values = dict(_center())
    values["parK2"] = 0.0201
    values["parFC"] = values["parFC"] + 50.0
    values["parTT"] = values["parTT"] - 0.25
    return values


class TestScaling:
    def test_multiplier_one_is_identity(self):
        center, vector = _center(), _diverse()
        scaled = scale_parameter_vector(center, vector, 1.0)
        assert scaled == pytest.approx(vector)

    def test_scaling_is_linear_around_the_center(self):
        center, vector = _center(), _diverse()
        scaled = scale_parameter_vector(center, vector, 4.0)
        for name in PARAMETER_NAMES:
            expected = center[name] + 4.0 * (vector[name] - center[name])
            assert scaled[name] == pytest.approx(expected)

    def test_center_row_is_never_scaled(self):
        table = pd.DataFrame(
            [
                {"basin_id": "12143600", "parameter_id": "equifinal_diverse_1", **_diverse()},
                {"basin_id": "12143600", "parameter_id": "trained_center", **_center()},
                {"basin_id": "12143600", "parameter_id": "equifinal_diverse_2", **_diverse()},
            ]
        )
        scaled = build_scaled_parameter_table(table, 2.0)
        center_row = scaled.loc[scaled["parameter_id"] == "trained_center"].iloc[0]
        for name in PARAMETER_NAMES:
            assert center_row[name] == pytest.approx(_center()[name])
        assert float(center_row["spacing_multiplier"]) == 2.0

    def test_out_of_bounds_multiplier_is_rejected_not_truncated(self):
        table = pd.DataFrame(
            [
                {"basin_id": "12143600", "parameter_id": "equifinal_diverse_1", **_diverse()},
                {"basin_id": "12143600", "parameter_id": "trained_center", **_center()},
                {"basin_id": "12143600", "parameter_id": "equifinal_diverse_2", **_diverse()},
            ]
        )
        with pytest.raises(ValueError, match="parK2"):
            build_scaled_parameter_table(table, 20.0)


class TestIdentificationTime:
    def test_adds_adaptation_days_and_censors_never_stable(self):
        first_stable = np.array([[1, 3], [-1, 10]], dtype=np.int64)
        result = identification_time_cycles(first_stable, adaptation_days=5)
        assert result[0, 0] == 6.0
        assert result[0, 1] == 8.0
        assert np.isnan(result[1, 0])
        assert result[1, 1] == 15.0

    def test_rejects_invalid_first_stable_values(self):
        with pytest.raises(ValueError):
            identification_time_cycles(np.array([0]), adaptation_days=5)

    def test_summary_reports_quantiles_and_censoring(self):
        values = np.array([6.0, np.nan, 8.0, 15.0])
        summary = summarize_identification_times(values)
        assert summary["n_total"] == 4
        assert summary["n_censored"] == 1
        assert summary["censored_fraction"] == pytest.approx(0.25)
        assert summary["median"] == pytest.approx(8.0)
        assert summary["min"] == 6.0
        assert summary["max"] == 15.0

    def test_summary_with_all_censored_has_no_quantiles(self):
        summary = summarize_identification_times(np.array([np.nan, np.nan]))
        assert summary["n_censored"] == 2
        assert summary["median"] is None


class TestBoundaryCells:
    def test_smallest_passing_and_largest_failing(self):
        row = [
            {"multiplier": 0.5, "passed": False},
            {"multiplier": 1.0, "passed": False},
            {"multiplier": 2.0, "passed": True},
            {"multiplier": 4.0, "passed": True},
            {"multiplier": 8.0, "passed": True},
        ]
        cells = select_boundary_cells(row)
        assert cells["smallest_passing_multiplier"] == 2.0
        assert cells["largest_failing_multiplier"] == 1.0

    def test_all_passing_row_has_no_failing_cell(self):
        row = [{"multiplier": m, "passed": True} for m in (0.5, 1.0)]
        cells = select_boundary_cells(row)
        assert cells["smallest_passing_multiplier"] == 0.5
        assert cells["largest_failing_multiplier"] is None

    def test_all_failing_row_has_no_passing_cell(self):
        row = [{"multiplier": m, "passed": False} for m in (0.5, 1.0)]
        cells = select_boundary_cells(row)
        assert cells["smallest_passing_multiplier"] is None
        assert cells["largest_failing_multiplier"] == 1.0

    def test_non_monotone_row_is_detected(self):
        row = [
            {"multiplier": 0.5, "passed": False},
            {"multiplier": 1.0, "passed": True},
            {"multiplier": 2.0, "passed": False},
            {"multiplier": 4.0, "passed": True},
        ]
        violations = monotonicity_violations(row)
        assert violations == [{"from_multiplier": 1.0, "to_multiplier": 2.0}]
        assert monotonicity_violations(
            [{"multiplier": 0.5, "passed": False}, {"multiplier": 1.0, "passed": True}]
        ) == []


class TestGridAndSeeds:
    def test_grid_is_five_multipliers_by_four_budgets_in_frozen_order(self):
        assert SPACING_MULTIPLIERS == (0.5, 1.0, 2.0, 4.0, 8.0)
        assert BUDGET_STAGE_LENGTHS == (15, 45, 90, 180)
        cells = grid_cells()
        assert len(cells) == 20
        assert cells[0] == {"cell_number": 1, "stage_length": 15, "multiplier": 0.5}
        assert cells[5] == {"cell_number": 6, "stage_length": 45, "multiplier": 0.5}
        assert cells[19] == {"cell_number": 20, "stage_length": 180, "multiplier": 8.0}

    def test_development_seeds_are_paired_within_a_budget_row(self):
        blocks = development_block_seeds(budget_row_index=2)
        assert len(blocks) == 12
        assert blocks[0]["forcing_seed"] == 3112001
        assert blocks[0]["process_noise_seed"] == 3122001
        assert blocks[0]["observation_noise_seed"] == 3132001
        assert blocks[11]["forcing_seed"] == 3112012
        assert development_block_seeds(budget_row_index=2) == blocks

    def test_development_seeds_avoid_previously_used_segments(self):
        used = set()
        for row_index in range(4):
            for block in development_block_seeds(row_index):
                for key in ("forcing_seed", "process_noise_seed", "observation_noise_seed"):
                    seed = block[key]
                    assert seed not in used
                    used.add(seed)
                    assert not 990001 <= seed <= 998012
                    assert not 3001001 <= seed <= 3002012

    def test_experiment_id_format(self):
        assert (
            development_experiment_id(multiplier=0.5, stage_length=15)
            == "g2_curve_param_switch_dev_m05_L015_v01"
        )
        assert (
            development_experiment_id(multiplier=8.0, stage_length=180)
            == "g2_curve_param_switch_dev_m80_L180_v01"
        )
