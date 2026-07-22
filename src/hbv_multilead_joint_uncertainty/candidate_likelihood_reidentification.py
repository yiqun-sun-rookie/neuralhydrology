"""Read-only re-identification timing analysis of frozen candidate rank evidence."""

from __future__ import annotations

import numpy as np


FAILURE_CATEGORIES = ("never_first", "first_then_lost", "stable_too_late")
ALL_CATEGORIES = FAILURE_CATEGORIES + ("stable",)


def recompute_first_days(ranks) -> tuple[np.ndarray, np.ndarray]:
    """Recompute first rank-one day and first stable rank-one day from ranks.

    Mirrors the frozen scorer: days are one-based, -1 means never; the stable
    day is the first day from which the true candidate holds strict rank one
    through the final scoring day.
    """

    rank_values = np.asarray(ranks, dtype=np.int64)
    if rank_values.ndim != 4:
        raise ValueError("ranks must have shape (blocks, truths, stages, days)")
    if np.any(rank_values < 1):
        raise ValueError("ranks must be one-based positive integers")
    rank_one = rank_values == 1
    ever_first = np.any(rank_one, axis=-1)
    first_day = np.where(
        ever_first, np.argmax(rank_one, axis=-1) + 1, -1
    ).astype(np.int64)
    stable_from = np.flip(
        np.logical_and.accumulate(np.flip(rank_one, axis=-1), axis=-1), axis=-1
    )
    ever_stable = np.any(stable_from, axis=-1)
    first_stable_day = np.where(
        ever_stable, np.argmax(stable_from, axis=-1) + 1, -1
    ).astype(np.int64)
    return first_day, first_stable_day


def classify_reidentification(
    first_day, first_stable_day, latest_qualifying_day
) -> np.ndarray:
    """Assign each (block, truth, stage) cell to one frozen category."""

    first = np.asarray(first_day, dtype=np.int64)
    first_stable = np.asarray(first_stable_day, dtype=np.int64)
    latest = int(latest_qualifying_day)
    if first.shape != first_stable.shape:
        raise ValueError("first_day and first_stable_day must share one shape")
    if latest < 1:
        raise ValueError("latest_qualifying_day must be positive")
    if np.any((first == -1) & (first_stable != -1)):
        raise ValueError("a trial that never reaches rank one cannot hold rank one")
    categories = np.full(first.shape, "", dtype="<U16")
    categories[first == -1] = "never_first"
    categories[(first >= 1) & (first_stable == -1)] = "first_then_lost"
    categories[first_stable > latest] = "stable_too_late"
    categories[(first_stable >= 1) & (first_stable <= latest)] = "stable"
    if np.any(categories == ""):
        raise ValueError("category assignment must cover every trial stage")
    return categories


def dominant_failure_label(failure_counts) -> str:
    """Frozen rule: strict max failure category, alphabetical tie label, or none."""

    counts = {name: int(failure_counts[name]) for name in FAILURE_CATEGORIES}
    total = sum(counts.values())
    if total == 0:
        return "no_failures"
    maximum = max(counts.values())
    tied = sorted(name for name, value in counts.items() if value == maximum)
    if len(tied) == 1:
        return tied[0]
    return "tie:" + "+".join(tied)


def agreement_call(development_label, confirmation_label) -> dict:
    """Frozen development-vs-confirmation rule for the dominant failure mode."""

    consistent = str(development_label) == str(confirmation_label)
    return {
        "development_label": str(development_label),
        "confirmation_label": str(confirmation_label),
        "consistent": bool(consistent),
        "conclusion": (
            str(development_label) if consistent else "目前无法确定主导失败模式"
        ),
    }


def _optional_float(values: np.ndarray) -> float | None:
    return float(np.median(values)) if values.size else None


def summarize_categories(categories, first_day, first_stable_day) -> dict:
    """Counts, fractions and timing medians for one stage's flattened trials."""

    category_values = np.asarray(categories, dtype="<U16").ravel()
    first = np.asarray(first_day, dtype=np.int64).ravel()
    first_stable = np.asarray(first_stable_day, dtype=np.int64).ravel()
    if category_values.shape != first.shape or first.shape != first_stable.shape:
        raise ValueError("category and day arrays must share one flattened shape")
    if category_values.size == 0:
        raise ValueError("summaries need at least one trial")
    counts = {
        f"count_{name}": int(np.sum(category_values == name))
        for name in ALL_CATEGORIES
    }
    total = int(category_values.size)
    ever_first_days = first[first >= 1]
    stable_days = first_stable[
        (first_stable >= 1) & (category_values == "stable")
    ]
    quartiles = (
        np.percentile(ever_first_days, [25.0, 75.0]).tolist()
        if ever_first_days.size
        else [None, None]
    )
    return {
        "trial_count": total,
        **counts,
        **{
            f"fraction_{name}": counts[f"count_{name}"] / total
            for name in ALL_CATEGORIES
        },
        "ever_first_count": int(ever_first_days.size),
        "median_first_day_among_ever_first": _optional_float(ever_first_days),
        "first_day_quartile_25": quartiles[0],
        "first_day_quartile_75": quartiles[1],
        "median_first_stable_day_among_stable": _optional_float(stable_days),
        "dominant_failure_label": dominant_failure_label(
            {name: counts[f"count_{name}"] for name in FAILURE_CATEGORIES}
        ),
    }


def analyze_reidentification_evidence(evidence, gates, latest_qualifying_day) -> dict:
    """Recompute, gate against frozen arrays, and classify one run's evidence."""

    ranks = np.asarray(evidence["true_candidate_cumulative_ranks"], dtype=np.int64)
    frozen_first = np.asarray(
        evidence["first_cumulative_rank_one_day"], dtype=np.int64
    )
    frozen_first_stable = np.asarray(
        evidence["first_stable_cumulative_rank_one_day"], dtype=np.int64
    )
    frozen_stable = np.asarray(
        evidence["stable_cumulative_identifiable"], dtype=bool
    )
    first, first_stable = recompute_first_days(ranks)
    if (
        frozen_first.shape != first.shape
        or frozen_first_stable.shape != first.shape
        or frozen_stable.shape != first.shape
    ):
        raise ValueError("frozen day arrays must match the rank array shape")
    first_mismatches = int(np.sum(first != frozen_first))
    first_stable_mismatches = int(np.sum(first_stable != frozen_first_stable))
    categories = classify_reidentification(
        frozen_first, frozen_first_stable, latest_qualifying_day
    )
    stable_mismatches = int(np.sum((categories == "stable") != frozen_stable))
    membership = np.zeros(categories.shape, dtype=np.int64)
    for name in ALL_CATEGORIES:
        membership += (categories == name).astype(np.int64)
    partition_violations = int(np.sum(membership != 1))
    integrity = {
        "recomputed_first_day_mismatches": first_mismatches,
        "recomputed_first_stable_day_mismatches": first_stable_mismatches,
        "stable_category_vs_frozen_flag_mismatches": stable_mismatches,
        "partition_violations": partition_violations,
    }
    integrity["integrity_passed"] = bool(
        all(
            integrity[name] <= int(gates[name])
            for name in (
                "recomputed_first_day_mismatches",
                "recomputed_first_stable_day_mismatches",
                "stable_category_vs_frozen_flag_mismatches",
                "partition_violations",
            )
        )
    )
    rank_one = ranks == 1
    daily_fraction = np.mean(rank_one, axis=(0, 1))
    daily_median_rank = np.median(ranks, axis=(0, 1))
    return {
        "first_day": first,
        "first_stable_day": first_stable,
        "categories": categories,
        "daily_rank_one_fraction": daily_fraction,
        "daily_median_rank": daily_median_rank,
        "integrity": integrity,
    }
