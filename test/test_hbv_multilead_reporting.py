import sys
from pathlib import Path

import pandas as pd
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.reporting import paired_method_comparisons  # noqa: E402


def test_paired_method_table_reports_exact_lead_specific_medians_and_win_counts():
    rows = []
    values = {
        "00000001": {"open_loop": 4.0, "fixed_filter": 3.0, "parameter_only": 2.8, "noise_only": 2.7, "joint": 2.0},
        "00000002": {"open_loop": 5.0, "fixed_filter": 4.0, "parameter_only": 4.1, "noise_only": 3.9, "joint": 3.0},
    }
    for basin_id, methods in values.items():
        for method, rmse in methods.items():
            rows.append(
                {
                    "basin_id": basin_id,
                    "method": method,
                    "lead_days": 1,
                    "rmse": rmse,
                    "mae": rmse / 2.0,
                    "nse": 1.0 - rmse / 10.0,
                }
            )

    table = paired_method_comparisons(pd.DataFrame(rows))
    row = table.loc[table["comparison_id"] == "joint_vs_fixed_filter"].iloc[0]

    assert row["basin_count"] == 2
    assert row["median_rmse_difference"] == -1.0
    assert row["median_rmse_change_percent"] == pytest.approx(-29.166666666666664)
    assert row["rmse_win_count"] == 2
    assert row["median_nse_difference"] == pytest.approx(0.1)
