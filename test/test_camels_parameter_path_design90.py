from __future__ import annotations

import hashlib
from pathlib import Path

import pandas as pd
import pytest

from camels_switch_confirmation.run_parameter_path_design90 import (
    PLANNED_TASK_COUNT,
    SOURCE_TASK_COUNT,
    validate_design90_task_frame,
)


def _tasks() -> tuple[pd.DataFrame, list[str]]:
    basins = [f"{index:08d}" for index in range(1, 91)]
    rows = []
    for basin_id in basins:
        for seed in (0, 1):
            rows.append(
                {
                    "basin_id": basin_id,
                    "seed": seed,
                    "arm_id": "C",
                    "source_probability_path": f"source/{basin_id}_s{seed}.npz",
                    "source_probability_bytes": 1,
                    "source_probability_sha256": "0" * 64,
                }
            )
    return pd.DataFrame(rows), basins


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def test_design90_task_contract_accepts_exact_cross_product():
    tasks, basins = _tasks()
    verified = validate_design90_task_frame(tasks, basins)
    assert len(verified) == SOURCE_TASK_COUNT == 180
    assert PLANNED_TASK_COUNT == 360
    assert set(verified["seed"]) == {0, 1}
    assert verified["basin_id"].nunique() == 90


@pytest.mark.parametrize("removed_rows", [1, 2])
def test_design90_task_contract_rejects_wrong_count(removed_rows):
    tasks, basins = _tasks()
    with pytest.raises(ValueError, match="180"):
        validate_design90_task_frame(tasks.iloc[:-removed_rows], basins)


def test_design90_task_contract_rejects_reserved_seed():
    tasks, basins = _tasks()
    tasks.loc[0, "seed"] = 2
    with pytest.raises(ValueError, match="seeds"):
        validate_design90_task_frame(tasks, basins)


def test_design90_task_contract_rejects_duplicate_identity():
    tasks, basins = _tasks()
    tasks.loc[1, ["basin_id", "seed"]] = tasks.loc[0, ["basin_id", "seed"]]
    with pytest.raises(ValueError, match="unique"):
        validate_design90_task_frame(tasks, basins)


def test_design90_task_contract_rejects_basin_order_drift():
    tasks, basins = _tasks()
    reordered = list(reversed(basins))
    with pytest.raises(ValueError, match="order"):
        validate_design90_task_frame(tasks, reordered)


def test_completed_mechanism_entrypoints_remain_byte_identical():
    root = Path(__file__).resolve().parents[1]
    assert _sha256(
        root / "src/camels_switch_confirmation/run_parameter_path_mechanism.py"
    ) == "72a9965e441f7c9168bff681b6661c8901772e4d7d3b39ad15edeca57904f6b5"
    assert _sha256(
        root / "src/camels_switch_confirmation/verify_parameter_path_mechanism.py"
    ) == "6480c402b0bfa9b831713fda2681bc8eb5e0e52359b37cf51125e64ccfe668f1"
