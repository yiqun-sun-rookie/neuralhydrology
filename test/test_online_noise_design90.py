"""Contract tests for the stage-2 A2f99 design-90 module (no filter runs)."""

import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from camels_switch_confirmation.run_online_noise_design90 import (  # noqa: E402
    PILOT_BASINS,
    design90_identities,
    design90_tasks,
    generalization_mask,
)


def test_identity_and_task_counts():
    identities = design90_identities()
    assert len(identities) == 180
    tasks = design90_tasks()
    assert len(tasks) == 360
    assert len(set(tasks)) == 360


def test_pilot_basins_inside_design90_and_generalization_split():
    identities = design90_identities()
    basins = {basin for basin, _ in identities}
    assert PILOT_BASINS <= basins
    frame = pd.DataFrame(
        [{"basin_id": basin, "seed": seed} for basin, seed in identities]
    )
    mask = generalization_mask(frame)
    assert int(mask.sum()) == 180 - 8
    assert not frame[~mask]["basin_id"].isin(basins - PILOT_BASINS).any()
