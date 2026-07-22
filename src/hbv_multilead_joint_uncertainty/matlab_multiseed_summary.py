"""Frozen summary rules for the multi-seed MATLAB rerun (matlab_multiseed_params_v01).

Implements the pre-frozen reduction of per-seed anchor metrics: numpy-linear
quantiles over non-censored values with censoring reported alongside, the
three-tier rng(1) position rule, the stable-top<=budget bridge fraction, and
divergent-seed flagging. Anchor extraction reuses the alignment round's
``_anchor_metrics`` implementation verbatim (design requirement).
"""

from __future__ import annotations

import numpy as np

from hbv_multilead_joint_uncertainty.scripts.run_walrus_imm_alignment import _anchor_metrics


def summarize_metric(values, reference) -> dict:
    """Quantile summary with censoring and the frozen rng(1) position rule."""
    observed = [float(value) for value in values if value is not None]
    n_censored = len(values) - len(observed)
    result = {
        "n_total": len(values),
        "n_observed": len(observed),
        "n_censored": n_censored,
        "censored_fraction": n_censored / len(values) if values else None,
        "min": None,
        "q25": None,
        "median": None,
        "q75": None,
        "max": None,
        "reference": reference,
        "reference_call": "无可比样本",
        "reference_quantile_note": None,
    }
    if not observed:
        return result
    array = np.asarray(observed, dtype=np.float64)
    result["min"] = float(array.min())
    result["q25"] = float(np.quantile(array, 0.25))
    result["median"] = float(np.quantile(array, 0.5))
    result["q75"] = float(np.quantile(array, 0.75))
    result["max"] = float(array.max())

    if reference is None:
        result["reference_call"] = "参考值缺失"
        return result
    reference = float(reference)
    if reference < result["min"] or reference > result["max"]:
        result["reference_call"] = "异常，单实现结论依赖种子"
    else:
        result["reference_call"] = "非异常"
        if reference < result["q25"] or reference > result["q75"]:
            quantile_position = float(np.mean(array <= reference))
            result["reference_quantile_note"] = (
                f"位于四分位距外，经验分位位置 {quantile_position:.2f}"
            )
    return result


def bridge_fraction(stable_top_cycles, budget: int) -> float:
    """Fraction of seeds whose stable-top cycle falls within the cycle budget.

    Censored seeds (None: never stably on top) count as not within budget.
    """
    if len(stable_top_cycles) == 0:
        raise ValueError("stable_top_cycles must be nonempty")
    within = sum(
        1 for value in stable_top_cycles if value is not None and value <= budget
    )
    return within / len(stable_top_cycles)


def seed_anchor_row(seed: int, imm_probs: np.ndarray, t1_2: int, t2_3: int) -> dict:
    """Six anchor values for one seed, or a divergent row when probs are non-finite."""
    probs = np.asarray(imm_probs, dtype=np.float64)
    row = {"seed": int(seed), "divergent": bool(not np.all(np.isfinite(probs)))}
    keys = (
        ("phase1", "true_filter_mean_prob"),
        ("phase1", "first_top_cycle"),
        ("phase1", "stable_top_cycle"),
        ("phase2", "true_filter_mean_prob"),
        ("phase2", "first_top_cycle"),
        ("phase2", "stable_top_cycle"),
    )
    if row["divergent"]:
        for phase, metric in keys:
            row[f"{phase}_{metric}"] = None
        return row
    anchors = _anchor_metrics(probs, {"t1_2": int(t1_2), "t2_3": int(t2_3)})
    for phase, metric in keys:
        row[f"{phase}_{metric}"] = anchors[phase][metric]
    return row
