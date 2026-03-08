from dataclasses import dataclass, field
from typing import Dict, Optional

import numpy as np

from src.hbv_camels_us_531.structure import build_fixed_hbv_structure
from src.hydroagent.data_loading import load_camels_basin
from src.hydroagent.environment import SuperflexEnv

from src.hbv_camels_us_531.config import (
    TEST_END_DATE,
    TEST_START_DATE,
    TRAIN_END_DATE,
    TRAIN_START_DATE,
    VALIDATION_END_DATE,
    VALIDATION_START_DATE,
)


@dataclass
class BasinRunResult:
    basin_id: str
    train_nse: Optional[float] = None
    validation_nse: Optional[float] = None
    test_nse: Optional[float] = None
    status: str = "ok"
    error: str = ""
    best_params: Dict[str, float] = field(default_factory=dict)


def split_periods() -> Dict[str, tuple[str, str]]:
    return {
        "train": (TRAIN_START_DATE, TRAIN_END_DATE),
        "validation": (VALIDATION_START_DATE, VALIDATION_END_DATE),
        "test": (TEST_START_DATE, TEST_END_DATE),
    }


def _compute_nse(obs, sim) -> float:
    obs_values = np.asarray(obs, dtype=float)
    sim_values = np.asarray(sim, dtype=float)
    denominator = np.sum((obs_values - np.mean(obs_values)) ** 2)
    if denominator == 0:
        return float("nan")
    numerator = np.sum((sim_values - obs_values) ** 2)
    return float(1.0 - numerator / denominator)


def run_single_basin(basin_id: str, data_root=None) -> BasinRunResult:
    periods = split_periods()
    structure = build_fixed_hbv_structure()
    env = SuperflexEnv()
    env.parse_structure(structure)

    train_forcing, train_obs, _ = load_camels_basin(
        basin_id, data_root=data_root, start_date=periods["train"][0], end_date=periods["train"][1]
    )
    train_result = env.auto_calibrate(train_forcing, train_obs)
    best_params = train_result["optimized_params"]

    validation_forcing, validation_obs, _ = load_camels_basin(
        basin_id, data_root=data_root, start_date=periods["validation"][0], end_date=periods["validation"][1]
    )
    validation_sim = env.run_simulation(validation_forcing, params=best_params)

    test_forcing, test_obs, _ = load_camels_basin(
        basin_id, data_root=data_root, start_date=periods["test"][0], end_date=periods["test"][1]
    )
    test_sim = env.run_simulation(test_forcing, params=best_params)

    return BasinRunResult(
        basin_id=basin_id,
        train_nse=float(train_result["nse"]),
        validation_nse=_compute_nse(validation_obs, validation_sim),
        test_nse=_compute_nse(test_obs, test_sim),
        best_params=best_params,
    )
