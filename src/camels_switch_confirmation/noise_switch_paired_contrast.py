"""NOISE-X2 analysis: paired switch-vs-null contrast on the noise-level posterior.

Preregistration: docs/plans/2026-08-19-noise-switch-confirmation-prereg-v02.md
(frozen before seeds 2/3 were run; hash below and in the summary).

The discovery run (NOISE-X1, seeds 0/1) showed that the inherited binary event
rule false-fires in the null control while the posterior LEVEL separates the
truth levels almost perfectly.  This module implements the confirmation
criterion registered in v02: for each task, the mean posterior of a candidate
during the stages where that level is the truth, MINUS the mean posterior of
the same candidate on the SAME calendar days in the null control (where the
truth is always m=1).  Same days => same forcing, same observation noise
realisation, same season; the difference isolates the truth level.

Read-only over existing npz artifacts; runs no filter.

Usage:
    python -X utf8 -m camels_switch_confirmation.noise_switch_paired_contrast \
        --root results/23_camels_switch_confirmation/noise_switch_confirmation_02_20260819_local
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

from camels_switch_confirmation.noise_switch_precheck import (
    NOISE_CANDIDATES,
    ROTATION,
    STAGE_DAYS,
)
from camels_switch_confirmation.run_noise_switch_experiment import (
    ARM_MODES,
    OUTPUT_ROOT as DISCOVERY_ROOT,
)

PREREGISTRATION = "docs/plans/2026-08-19-noise-switch-confirmation-prereg-v02.md"
PREREGISTRATION_SHA256 = (
    "fdb5ceb3b16d93d463e3457dabc3e6b989c3f48a3fbd3e6a0631e9679f61c5ee")

# registered thresholds -- frozen before seeds 2/3 were run
MEDIAN_UPLIFT_MIN = 0.10
POSITIVE_FRACTION_MIN = 0.90
PLACEBO_ABS_MEDIAN_MAX = 0.05
AUC_REFERENCE = 0.90
TESTED_LEVELS = (1, 2)          # candidate indices judged: low (m=0.1), high (m=10)
PLACEBO_LEVEL = 0               # middle: truth identical in both scenarios


def stage_days_for(candidate_index, rotation=ROTATION, stage_days=STAGE_DAYS):
    """Calendar days on which `candidate_index` is the truth in the switch run."""
    blocks = [np.arange(position * stage_days, (position + 1) * stage_days)
              for position, index in enumerate(rotation)
              if index == candidate_index]
    if not blocks:
        raise ValueError(f"candidate {candidate_index} never active in rotation")
    return np.concatenate(blocks)


def paired_uplift(switch_probabilities, null_probabilities, candidate_index):
    """Mean posterior on the candidate's own stages, minus the null on same days."""
    days = stage_days_for(candidate_index)
    n_days = min(switch_probabilities.shape[0], null_probabilities.shape[0])
    days = days[days < n_days]
    switch_mean = float(switch_probabilities[days, candidate_index].mean())
    null_mean = float(null_probabilities[days, candidate_index].mean())
    return switch_mean - null_mean, switch_mean, null_mean


def rank_auc(positive_values, negative_values):
    """P(positive > negative) with ties at half weight; 1.0 = perfect separation."""
    positive = np.asarray(positive_values, dtype=np.float64)[:, None]
    negative = np.asarray(negative_values, dtype=np.float64)[None, :]
    greater = float((positive > negative).mean())
    equal = float((positive == negative).mean())
    return greater + 0.5 * equal


def _load(path):
    with np.load(path, allow_pickle=False) as archive:
        return archive["probabilities"]


def collect(root, arms):
    """One row per (basin, seed, arm) holding every registered per-task quantity."""
    rows = []
    root = Path(root)
    for arm in arms:
        switch_dir = root / "arms" / arm / "switch" / "probs"
        null_dir = root / "arms" / arm / "null" / "probs"
        for switch_path in sorted(switch_dir.glob("*.npz")):
            null_path = null_dir / switch_path.name
            if not null_path.exists():
                raise FileNotFoundError(f"missing null counterpart: {null_path}")
            switch_probabilities = _load(switch_path)
            null_probabilities = _load(null_path)
            basin, seed_tag = switch_path.stem.split("_s")
            row = {"basin_id": basin, "seed": int(seed_tag), "arm": arm}
            for candidate in range(len(NOISE_CANDIDATES)):
                uplift, switch_mean, null_mean = paired_uplift(
                    switch_probabilities, null_probabilities, candidate)
                tag = f"m{NOISE_CANDIDATES[candidate]:g}"
                row[f"uplift_{tag}"] = uplift
                row[f"switch_mean_{tag}"] = switch_mean
                row[f"null_mean_{tag}"] = null_mean
            truth = np.repeat(np.asarray(ROTATION), STAGE_DAYS)[
                :switch_probabilities.shape[0]]
            row["switch_argmax_accuracy"] = float(
                (switch_probabilities.argmax(axis=1) == truth).mean())
            row["null_argmax_accuracy"] = float(
                (null_probabilities.argmax(axis=1) == PLACEBO_LEVEL).mean())
            rows.append(row)
    return pd.DataFrame(rows)


def judge(frame, arms):
    """Apply the registered gates verbatim; no discretion, no post-hoc tuning."""
    verdicts = {}
    for arm in arms:
        subset = frame[frame["arm"] == arm]
        arm_result = {"tasks": int(len(subset)), "levels": {}}
        placebo_tag = f"m{NOISE_CANDIDATES[PLACEBO_LEVEL]:g}"
        placebo_median = float(subset[f"uplift_{placebo_tag}"].median())
        arm_result["placebo_median_uplift"] = placebo_median
        arm_result["placebo_gate_passed"] = bool(
            abs(placebo_median) <= PLACEBO_ABS_MEDIAN_MAX)
        for candidate in TESTED_LEVELS:
            tag = f"m{NOISE_CANDIDATES[candidate]:g}"
            uplift = subset[f"uplift_{tag}"]
            median_uplift = float(uplift.median())
            positive_fraction = float((uplift > 0).mean())
            auc = rank_auc(subset[f"switch_mean_{tag}"],
                           subset[f"null_mean_{tag}"])
            passed = bool(median_uplift > MEDIAN_UPLIFT_MIN
                          and positive_fraction >= POSITIVE_FRACTION_MIN)
            arm_result["levels"][tag] = {
                "median_uplift": median_uplift,
                "uplift_p10": float(uplift.quantile(0.1)),
                "uplift_p90": float(uplift.quantile(0.9)),
                "positive_fraction": positive_fraction,
                "switch_mean_median": float(subset[f"switch_mean_{tag}"].median()),
                "null_mean_median": float(subset[f"null_mean_{tag}"].median()),
                "auc_switch_vs_null": auc,
                "auc_reference_met": bool(auc >= AUC_REFERENCE),
                "gate_passed": passed,
            }
        arm_result["switch_argmax_accuracy_median"] = float(
            subset["switch_argmax_accuracy"].median())
        arm_result["null_argmax_accuracy_median"] = float(
            subset["null_argmax_accuracy"].median())
        if not arm_result["placebo_gate_passed"]:
            arm_result["verdict"] = "void_placebo_gate_violated"
        elif all(level["gate_passed"] for level in arm_result["levels"].values()):
            arm_result["verdict"] = "identification_confirmed"
        else:
            arm_result["verdict"] = "not_confirmed"
        verdicts[arm] = arm_result
    return verdicts


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=str(DISCOVERY_ROOT))
    parser.add_argument("--arms", nargs="*", default=list(ARM_MODES))
    parser.add_argument("--label", default="confirmation")
    arguments = parser.parse_args()

    frame = collect(arguments.root, arguments.arms)
    verdicts = judge(frame, arguments.arms)
    output = Path(arguments.root) / "verification"
    output.mkdir(parents=True, exist_ok=True)
    frame.to_csv(output / "paired_contrast_tasks.csv", index=False)
    summary = {
        "preregistration": PREREGISTRATION,
        "preregistration_sha256": PREREGISTRATION_SHA256,
        "label": arguments.label,
        "seeds": sorted(int(s) for s in frame["seed"].unique()),
        "thresholds": {
            "median_uplift_min": MEDIAN_UPLIFT_MIN,
            "positive_fraction_min": POSITIVE_FRACTION_MIN,
            "placebo_abs_median_max": PLACEBO_ABS_MEDIAN_MAX,
            "auc_reference": AUC_REFERENCE,
        },
        "arms": verdicts,
    }
    with open(output / "paired_contrast_summary.json", "w",
              encoding="utf-8") as handle:
        json.dump(summary, handle, indent=2, ensure_ascii=False)
    print(json.dumps(summary, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
