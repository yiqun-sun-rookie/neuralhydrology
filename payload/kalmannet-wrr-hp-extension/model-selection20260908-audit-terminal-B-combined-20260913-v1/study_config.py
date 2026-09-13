"""Immutable stage definitions for the approved neural-gain model-selection study."""
from __future__ import annotations

from typing import Any


REMOTE_FAMILY_ROOT = "/data1/home/sunyiq/kalmannet_wrr_model_selection_20260908"

A_CONFIGS = (
    (16, 1, 5, 0.01),
    (16, 1, 5, 0.02),
    (16, 1, 5, 0.05),
    (16, 1, 10, 0.05),
    (16, 2, 5, 0.01),
    (16, 2, 5, 0.02),
    (16, 2, 5, 0.05),
    (32, 1, 10, 0.02),
    (32, 1, 15, 0.01),
)
B_CONFIGS = (
    (128, 1, 15, 0.01),
    (64, 1, 20, 0.01),
    (128, 1, 20, 0.01),
    (64, 2, 15, 0.01),
    (64, 1, 15, 0.005),
    (64, 1, 15, 0.02),
    (64, 1, 15, 0.05),
)

STAGE_SEEDS = {"A": (43, 44), "B": (42, 43, 44)}
STAGE_ROLES = {"A": "repeated_existing_candidate", "B": "fixed_boundary_probe"}
COMBO_FIELDS = {
    "index", "run_id", "role", "lr", "hidden_size", "num_layers",
    "in_out_mult", "seed", "effective_seed", "stage",
}


def validate_stage(stage: str) -> str:
    if not isinstance(stage, str):
        raise TypeError("stage must be the exact string 'A' or 'B'")
    if stage not in STAGE_SEEDS:
        raise ValueError(f"stage must be 'A' or 'B'; stage C is not approved, got {stage!r}")
    return stage


def remote_stage_root(stage: str) -> str:
    return f"{REMOTE_FAMILY_ROOT}/stages/{validate_stage(stage)}"


def _validated_configurations(stage: str) -> tuple[tuple[int, int, int, float], ...]:
    stage = validate_stage(stage)
    configurations = A_CONFIGS if stage == "A" else B_CONFIGS
    seen: set[tuple[int, int, int, float]] = set()
    for position, config in enumerate(configurations):
        if not isinstance(config, tuple) or len(config) != 4:
            raise ValueError(f"stage {stage} config {position} is malformed")
        hidden_size, num_layers, in_out_mult, learning_rate = config
        if isinstance(hidden_size, bool) or not isinstance(hidden_size, int) or hidden_size <= 0:
            raise ValueError(f"stage {stage} config {position} hidden_size is malformed")
        if isinstance(num_layers, bool) or not isinstance(num_layers, int) or num_layers <= 0:
            raise ValueError(f"stage {stage} config {position} num_layers is malformed")
        if isinstance(in_out_mult, bool) or not isinstance(in_out_mult, int) or in_out_mult <= 0:
            raise ValueError(f"stage {stage} config {position} in_out_mult is malformed")
        if isinstance(learning_rate, bool) or not isinstance(learning_rate, (int, float)) or learning_rate <= 0:
            raise ValueError(f"stage {stage} config {position} lr is malformed")
        normalized = (hidden_size, num_layers, in_out_mult, float(learning_rate))
        if normalized in seen:
            raise ValueError(f"stage {stage} contains duplicate config {normalized}")
        seen.add(normalized)
    return configurations


def make_combos(stage: str) -> list[dict]:
    stage = validate_stage(stage)
    rows: list[dict] = []
    for hidden_size, num_layers, in_out_mult, learning_rate in _validated_configurations(stage):
        for seed in STAGE_SEEDS[stage]:
            index = len(rows)
            rows.append(
                {
                    "index": index,
                    "run_id": f"NGF-SELECT-20260908-{stage}{index + 1:02d}",
                    "role": STAGE_ROLES[stage],
                    "lr": learning_rate,
                    "hidden_size": hidden_size,
                    "num_layers": num_layers,
                    "in_out_mult": in_out_mult,
                    "seed": seed,
                    "effective_seed": seed,
                    "stage": stage,
                }
            )
    identities = {
        (r["hidden_size"], r["num_layers"], r["in_out_mult"], r["lr"], r["seed"])
        for r in rows
    }
    if len(identities) != len(rows):
        raise ValueError(f"stage {stage} expands to duplicate numerical configurations")
    return rows


def validate_index(stage: str, index: int) -> int:
    stage = validate_stage(stage)
    if isinstance(index, bool) or not isinstance(index, int):
        raise TypeError(f"index for stage {stage} must be an integer")
    count = len(make_combos(stage))
    if index < 0 or index >= count:
        raise ValueError(f"index for stage {stage} must be in 0..{count - 1}, got {index}")
    return index


def validate_combo(stage: str, index: int, combo: dict[str, Any]) -> dict[str, Any]:
    stage = validate_stage(stage)
    index = validate_index(stage, index)
    if not isinstance(combo, dict):
        raise TypeError("combo must be a dictionary")
    missing = sorted(COMBO_FIELDS - set(combo))
    extra = sorted(set(combo) - COMBO_FIELDS)
    if missing:
        raise ValueError(f"combo field {missing[0]} is missing")
    if extra:
        raise ValueError(f"combo field {extra[0]} is unexpected")
    expected = make_combos(stage)[index]
    for field in sorted(COMBO_FIELDS):
        if combo[field] != expected[field] or type(combo[field]) is not type(expected[field]):
            raise ValueError(f"protected combo field {field} mismatch for stage {stage} index {index}")
    return combo

