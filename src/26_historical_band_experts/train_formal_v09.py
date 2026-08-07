"""Formal version-09 main-training primitives.

Stage S1 of `docs/plans/2026-08-07-id26-v09-main-training-implementation.md`: the frozen
24-run order and the dropout RNG streams. The single-run trainer itself lands in S2.

The run order is frozen twice on purpose -- here as data, and in
``stage_authorization_v09.MAIN_ALLOWED_RUNS`` as code. `validate_run_order_v09` refuses to
accept one without the other, so an edit to either side fails before any training starts.
"""
from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path

import torch

from models_formal_v09 import VARIANTS_FORMAL_V09, _EXPECTED_TRAINABLE_COUNTS

_SCHEMA = "historical_multiscale_formal_v09_run_order_v1"
_SCOPE = "FORMAL-MAIN-24"
_EXPECTED_RUNS = 24
_RUNS_PER_FAMILY = 8
_RUNS_PER_SEED = 3
# The strict-nesting stage already burned this stream in (train_strict_formal_v09 line 163).
# The main runs must use the identical formula or the two stages diverge silently.
_DROPOUT_MULTIPLIER = 1_000_003
_DROPOUT_OFFSET = 900_001


@dataclass(frozen=True)
class FormalRunSpecV09:
    """One of the 24 frozen main-training runs."""

    position: int
    seed: int
    family: str
    run_id: str
    variant: str
    trainable_parameters: int
    results_root: str


def _require_mapping(value, label: str) -> Mapping:
    if not isinstance(value, Mapping):
        raise ValueError(f"run order {label} must be an object")
    return value


def _validate_families_v09(order: Mapping) -> dict[str, dict]:
    families = _require_mapping(order.get("families"), "families")
    if len(families) != 3:
        raise ValueError("run order must register exactly three model families")
    resolved: dict[str, dict] = {}
    roots: set[str] = set()
    for name, entry in families.items():
        entry = _require_mapping(entry, f"family {name}")
        variant = entry.get("variant")
        if variant not in VARIANTS_FORMAL_V09:
            raise ValueError(f"run order family {name} names an unregistered variant")
        expected = _EXPECTED_TRAINABLE_COUNTS[variant]
        if entry.get("trainable_parameters") != expected:
            raise ValueError(
                f"run order family {name} trainable parameter count disagrees with the model registry")
        root = entry.get("results_root")
        if not isinstance(root, str) or not root:
            raise ValueError(f"run order family {name} results root is invalid")
        if root in roots:
            raise ValueError("run order families must not share a results root")
        roots.add(root)
        resolved[name] = {
            "variant": variant,
            "trainable_parameters": expected,
            "results_root": root,
        }
    return resolved


def validate_run_order_v09(order: Mapping) -> tuple[FormalRunSpecV09, ...]:
    """Accept only the exact frozen 24-run order; never mutate the input."""
    order = _require_mapping(order, "document")
    if order.get("schema") != _SCHEMA:
        raise ValueError("run order schema drift")
    if order.get("scope") != _SCOPE:
        raise ValueError("run order scope drift")

    families = _validate_families_v09(order)

    seeds = order.get("seeds")
    if not isinstance(seeds, Sequence) or isinstance(seeds, (str, bytes)):
        raise ValueError("run order seed list is invalid")
    seeds = tuple(seeds)
    if len(seeds) != 8 or len(set(seeds)) != 8 or any(not isinstance(s, int) for s in seeds):
        raise ValueError("run order must register exactly eight unique integer seeds")

    runs = order.get("runs")
    if not isinstance(runs, Sequence) or isinstance(runs, (str, bytes)):
        raise ValueError("run order runs must be a list")
    if len(runs) != _EXPECTED_RUNS:
        raise ValueError(f"run order must contain exactly {_EXPECTED_RUNS} runs")

    specs: list[FormalRunSpecV09] = []
    seen_ids: set[str] = set()
    for index, entry in enumerate(runs, start=1):
        entry = _require_mapping(entry, f"run {index}")
        if entry.get("position") != index:
            raise ValueError(f"run order position drift at slot {index}")
        seed = entry.get("seed")
        if seed not in seeds:
            raise ValueError(f"run order seed at position {index} is not in the frozen seed list")
        family = entry.get("family")
        if family not in families:
            raise ValueError(f"run order family at position {index} is not registered")
        run_id = entry.get("run_id")
        expected_id = f"{family}-S{seed}"
        if run_id != expected_id:
            raise ValueError(f"run order run identifier at position {index} disagrees with its family and seed")
        if run_id in seen_ids:
            raise ValueError(f"run order run identifier {run_id} is duplicated")
        seen_ids.add(run_id)
        specs.append(
            FormalRunSpecV09(
                position=index,
                seed=int(seed),
                family=family,
                run_id=run_id,
                variant=families[family]["variant"],
                trainable_parameters=families[family]["trainable_parameters"],
                results_root=families[family]["results_root"],
            ))

    family_counts: dict[str, int] = {}
    seed_counts: dict[int, int] = {}
    for spec in specs:
        family_counts[spec.family] = family_counts.get(spec.family, 0) + 1
        seed_counts[spec.seed] = seed_counts.get(spec.seed, 0) + 1
    if any(count != _RUNS_PER_FAMILY for count in family_counts.values()) or len(family_counts) != 3:
        raise ValueError(f"each model family must appear exactly {_RUNS_PER_FAMILY} times")
    if any(count != _RUNS_PER_SEED for count in seed_counts.values()) or len(seed_counts) != 8:
        raise ValueError(f"each seed must appear exactly {_RUNS_PER_SEED} times")

    _assert_matches_authorization_v09(specs)
    return tuple(specs)


def _assert_matches_authorization_v09(specs: Sequence[FormalRunSpecV09]) -> None:
    """Cross-check the data copy of the order against the code copy."""
    from stage_authorization_v09 import MAIN_ALLOWED_RUNS

    if tuple(spec.run_id for spec in specs) != tuple(MAIN_ALLOWED_RUNS):
        raise ValueError("run order disagrees with the authorized run identifiers")


def load_run_order_v09(path: str | Path) -> tuple[FormalRunSpecV09, ...]:
    """Load and validate the frozen order from disk."""
    path = Path(os.path.abspath(path))
    return validate_run_order_v09(json.loads(path.read_text(encoding="utf-8")))


def dropout_seed_v09(seed: int) -> int:
    """Derive the dropout stream seed; identical for all three families of one seed."""
    seed = int(seed)
    if seed <= 0:
        raise ValueError("training seed must be a positive integer")
    return seed * _DROPOUT_MULTIPLIER + _DROPOUT_OFFSET


def _state_sha256(state: torch.Tensor) -> str:
    return hashlib.sha256(state.cpu().numpy().tobytes()).hexdigest()


def reset_training_dropout_rng_v09(seed: int) -> dict:
    """Reset the CPU and every CUDA dropout stream, then report their state hashes.

    Called after the model and optimizer are constructed so that model initialisation never
    consumes the dropout stream; the three families of one seed then enter their first batch
    with byte-identical RNG state.
    """
    dropout_seed = dropout_seed_v09(seed)
    torch.manual_seed(dropout_seed)
    cuda_hash = None
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(dropout_seed)
        states = torch.cuda.get_rng_state_all()
        cuda_hash = hashlib.sha256(b"".join(s.cpu().numpy().tobytes() for s in states)).hexdigest()
    return {
        "dropout_seed": dropout_seed,
        "cpu_state_sha256": _state_sha256(torch.get_rng_state()),
        "cuda_state_sha256": cuda_hash,
    }
