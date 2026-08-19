import sys
from pathlib import Path

import pandas as pd
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from camels_switch_confirmation.register_parameter_interaction_design90 import (  # noqa: E402
    select_design90_basins,
    write_csv_exclusive,
)


def _synthetic_531_tables():
    cell_sizes = {
        (1, False): 77,
        (1, True): 100,
        (2, False): 31,
        (2, True): 146,
        (3, False): 9,
        (3, True): 168,
    }
    precheck_rows = []
    parameter_rows = []
    basin_number = 1
    global_rank = 0
    for tertile in (1, 2, 3):
        for overflow in (False, True):
            for _ in range(cell_sizes[(tertile, overflow)]):
                basin_id = f"{basin_number:08d}"
                precheck_rows.append(
                    {
                        "basin_id": basin_id,
                        "run_status": "success",
                        "r_min": float(global_rank),
                        "fc_member2": 1.0,
                        "fc_clipped_any": False,
                        "predicted_identifiable": global_rank >= 177,
                        "feasible_zero_clipping": True,
                        "n_forcing_days": 1260,
                        "events_passed": global_rank % 7,
                    }
                )
                parameter_rows.append(
                    {
                        "basin_id": basin_id,
                        "state_SM": 2.0 if overflow else 0.5,
                    }
                )
                basin_number += 1
                global_rank += 1
    return pd.DataFrame(precheck_rows), pd.DataFrame(parameter_rows)


def test_select_design90_uses_maximum_balanced_unique_allocation():
    precheck, parameters = _synthetic_531_tables()

    selected = select_design90_basins(precheck, parameters)

    assert len(selected) == 90
    assert selected["basin_id"].nunique() == 90
    counts = selected.groupby(
        ["rmin_tertile", "initial_half_capacity_overflow"],
        sort=True,
    ).size().to_dict()
    assert counts == {
        (1, False): 16,
        (1, True): 16,
        (2, False): 16,
        (2, True): 16,
        (3, False): 9,
        (3, True): 17,
    }
    rare = selected[
        (selected["rmin_tertile"] == 3)
        & ~selected["initial_half_capacity_overflow"]
    ]
    assert rare["within_cell_index_zero_based"].tolist() == list(range(9))


def test_select_design90_does_not_depend_on_existing_outcome_column():
    precheck, parameters = _synthetic_531_tables()
    first = select_design90_basins(precheck, parameters)
    precheck["events_passed"] = list(reversed(precheck["events_passed"].tolist()))

    second = select_design90_basins(precheck, parameters)

    assert second["basin_id"].tolist() == first["basin_id"].tolist()


def test_write_csv_exclusive_refuses_existing_target(tmp_path):
    target = tmp_path / "registered.csv"
    target.write_text("existing\n", encoding="utf-8")

    with pytest.raises(FileExistsError, match="registered artifact already exists"):
        write_csv_exclusive(pd.DataFrame({"value": [1]}), target)
