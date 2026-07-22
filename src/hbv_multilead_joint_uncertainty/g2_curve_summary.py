"""Frozen reduction rules for the G2 identification-time curve.

Identification time T = adaptation days + first stable cumulative rank-one
scoring day, censored (NaN) when the true candidate never becomes stably
top-ranked. Boundary cells per budget row are the smallest passing and the
largest failing multiplier; monotonicity violations are reported, never
smoothed away.
"""

from __future__ import annotations

import numpy as np


def identification_time_cycles(first_stable_days, adaptation_days: int) -> np.ndarray:
    """Cycles after the switch until stable top rank; NaN where censored (-1)."""

    values = np.asarray(first_stable_days, dtype=np.int64)
    adaptation = int(adaptation_days)
    if adaptation < 0:
        raise ValueError("adaptation_days must be nonnegative")
    valid = (values >= 1) | (values == -1)
    if not np.all(valid):
        raise ValueError("first_stable_days must be -1 (censored) or >= 1")
    result = np.where(values == -1, np.nan, values + adaptation).astype(np.float64)
    return result


def summarize_identification_times(values) -> dict:
    """Quantile summary over non-censored times with censoring reported."""

    array = np.asarray(values, dtype=np.float64).reshape(-1)
    observed = array[np.isfinite(array)]
    result = {
        "n_total": int(array.size),
        "n_censored": int(array.size - observed.size),
        "censored_fraction": (
            float((array.size - observed.size) / array.size) if array.size else None
        ),
        "min": None,
        "q25": None,
        "median": None,
        "q75": None,
        "max": None,
    }
    if observed.size:
        result["min"] = float(observed.min())
        result["q25"] = float(np.quantile(observed, 0.25))
        result["median"] = float(np.quantile(observed, 0.5))
        result["q75"] = float(np.quantile(observed, 0.75))
        result["max"] = float(observed.max())
    return result


def _sorted_row(row) -> list[dict]:
    cells = [
        {"multiplier": float(cell["multiplier"]), "passed": bool(cell["passed"])}
        for cell in row
    ]
    if len({cell["multiplier"] for cell in cells}) != len(cells) or not cells:
        raise ValueError("row must contain unique multipliers")
    return sorted(cells, key=lambda cell: cell["multiplier"])


def select_boundary_cells(row) -> dict:
    """Deterministic confirmation targets: smallest pass and largest fail."""

    cells = _sorted_row(row)
    passing = [cell["multiplier"] for cell in cells if cell["passed"]]
    failing = [cell["multiplier"] for cell in cells if not cell["passed"]]
    return {
        "smallest_passing_multiplier": min(passing) if passing else None,
        "largest_failing_multiplier": max(failing) if failing else None,
    }


def monotonicity_violations(row) -> list[dict]:
    """Adjacent pass→fail transitions as multiplier increases."""

    cells = _sorted_row(row)
    return [
        {
            "from_multiplier": earlier["multiplier"],
            "to_multiplier": later["multiplier"],
        }
        for earlier, later in zip(cells, cells[1:])
        if earlier["passed"] and not later["passed"]
    ]
