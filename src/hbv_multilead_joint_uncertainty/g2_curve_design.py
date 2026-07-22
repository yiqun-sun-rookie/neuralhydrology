"""Frozen grid, seed layout, and naming for the G2 identification-time curve.

Every constant here is fixed by the design doc
``docs/plans/2026-07-22-g2-identification-time-curve-design.md`` and must not
change after the first development run is sealed.
"""

from __future__ import annotations

SPACING_MULTIPLIERS: tuple[float, ...] = (0.5, 1.0, 2.0, 4.0, 8.0)
BUDGET_STAGE_LENGTHS: tuple[int, ...] = (15, 45, 90, 180)
BLOCKS_PER_CELL = 12
ADAPTATION_DAYS = 5
WARMUP_DAYS = 45

_DEVELOPMENT_SEED_BASES = {
    "forcing_seed": 3110000,
    "process_noise_seed": 3120000,
    "observation_noise_seed": 3130000,
}
_CONFIRMATION_SEED_BASES = {
    "forcing_seed": 3210000,
    "process_noise_seed": 3220000,
    "observation_noise_seed": 3230000,
}
DEVELOPMENT_BOOTSTRAP_SEED_BASE = 3150000
CONFIRMATION_BOOTSTRAP_SEED_BASE = 3250000


def grid_cells() -> list[dict]:
    """All 20 cells in frozen order: stage length ascending, multiplier ascending."""

    cells = []
    for stage_length in BUDGET_STAGE_LENGTHS:
        for multiplier in SPACING_MULTIPLIERS:
            cells.append(
                {
                    "cell_number": len(cells) + 1,
                    "stage_length": stage_length,
                    "multiplier": multiplier,
                }
            )
    return cells


def _block_seeds(bases: dict[str, int], budget_row_index: int) -> list[dict]:
    row = int(budget_row_index)
    if row not in range(len(BUDGET_STAGE_LENGTHS)):
        raise ValueError("budget_row_index must index a frozen budget row")
    return [
        {
            "block_id": f"g2_curve_block_{block:02d}",
            **{key: base + 1000 * row + block for key, base in bases.items()},
        }
        for block in range(1, BLOCKS_PER_CELL + 1)
    ]


def development_block_seeds(budget_row_index: int) -> list[dict]:
    """Twelve paired block seed triplets shared by every multiplier in one row."""

    return _block_seeds(_DEVELOPMENT_SEED_BASES, budget_row_index)


def confirmation_block_seeds(budget_row_index: int) -> list[dict]:
    return _block_seeds(_CONFIRMATION_SEED_BASES, budget_row_index)


def _multiplier_token(multiplier: float) -> str:
    token = int(round(float(multiplier) * 10.0))
    if abs(token - float(multiplier) * 10.0) > 1e-9:
        raise ValueError("multiplier must be representable in tenths")
    return f"{token:02d}"


def development_experiment_id(multiplier: float, stage_length: int) -> str:
    return (
        "g2_curve_param_switch_dev_"
        f"m{_multiplier_token(multiplier)}_L{int(stage_length):03d}_v01"
    )


def confirmation_experiment_id(multiplier: float, stage_length: int) -> str:
    return (
        "g2_curve_param_switch_conf_"
        f"m{_multiplier_token(multiplier)}_L{int(stage_length):03d}_v01"
    )
