"""Spacing-multiplier candidate generation with hard bounds rejection.

The trained center stays fixed; the two equifinal candidates move linearly
away from it. A multiplier whose scaled vector violates any explicit v1
parameter bound is rejected outright — values are never truncated.
"""

from __future__ import annotations

from typing import Mapping

import pandas as pd

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES, V1_PARAMETER_BOUNDS

CENTER_PARAMETER_ID = "trained_center"
SCALED_PARAMETER_IDS = ("equifinal_diverse_1", "equifinal_diverse_2")


def scale_parameter_vector(
    center: Mapping[str, float], vector: Mapping[str, float], multiplier: float
) -> dict[str, float]:
    """Return center + multiplier * (vector - center) for every parameter."""

    scale = float(multiplier)
    if not scale > 0.0:
        raise ValueError("multiplier must be positive")
    return {
        name: float(center[name]) + scale * (float(vector[name]) - float(center[name]))
        for name in PARAMETER_NAMES
    }


def _validate_within_bounds(parameter_id: str, values: Mapping[str, float], multiplier: float) -> None:
    violations = [
        f"{name}={values[name]!r} outside [{lower}, {upper}]"
        for name, (lower, upper) in V1_PARAMETER_BOUNDS.items()
        if values[name] < lower or values[name] > upper
    ]
    if violations:
        raise ValueError(
            f"multiplier {multiplier!r} rejected for {parameter_id!r}: "
            + "; ".join(violations)
        )


def build_scaled_parameter_table(base_rows: pd.DataFrame, multiplier: float) -> pd.DataFrame:
    """Three-row candidate table at one spacing multiplier, bounds-validated."""

    expected_ids = (SCALED_PARAMETER_IDS[0], CENTER_PARAMETER_ID, SCALED_PARAMETER_IDS[1])
    ids = tuple(str(value) for value in base_rows["parameter_id"])
    if sorted(ids) != sorted(expected_ids):
        raise ValueError(f"base rows must contain exactly {expected_ids}")
    basins = set(str(value) for value in base_rows["basin_id"])
    if len(basins) != 1:
        raise ValueError("base rows must come from exactly one basin")
    center_row = base_rows.loc[base_rows["parameter_id"] == CENTER_PARAMETER_ID].iloc[0]
    center = {name: float(center_row[name]) for name in PARAMETER_NAMES}
    _validate_within_bounds(CENTER_PARAMETER_ID, center, multiplier)

    rows = []
    for parameter_id in expected_ids:
        source = base_rows.loc[base_rows["parameter_id"] == parameter_id].iloc[0]
        vector = {name: float(source[name]) for name in PARAMETER_NAMES}
        if parameter_id != CENTER_PARAMETER_ID:
            vector = scale_parameter_vector(center, vector, multiplier)
            _validate_within_bounds(parameter_id, vector, multiplier)
        rows.append(
            {
                "basin_id": str(source["basin_id"]),
                "parameter_id": parameter_id,
                "spacing_multiplier": float(multiplier),
                **vector,
            }
        )
    return pd.DataFrame(rows, columns=["basin_id", "parameter_id", "spacing_multiplier", *PARAMETER_NAMES])
