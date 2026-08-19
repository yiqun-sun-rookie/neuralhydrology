"""Stage-2: A2f99 online noise estimation on the design-90 set (preregistered).

Preregistration: docs/plans/2026-08-17-online-noise-a2f99-design90-stage2-prereg-v01.md

The estimator is frozen as selected by the stage-1 pilot: the 15-cell noise
grid (m x c) with per-day marginal log-likelihoods combined by discounted
Bayesian model averaging (lambda=0.99).  A2cum (undiscounted) is computed as a
descriptive reference only.  Inputs inherit the frozen 03C task files
bit-for-bit; 03D is the known-sigma oracle anchor for pairing.

Subcommands: run | summarize.  ``run`` skips already-saved outputs, so it is
restartable after interruption.
"""

from __future__ import annotations

import argparse
import json
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
import pandas as pd

_SRC = Path(__file__).resolve().parents[1]
if str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))

from camels_switch_confirmation.g2_switch_confirmation import _atomic_save_npz  # noqa: E402
from camels_switch_confirmation.run_online_noise_pilot import (  # noqa: E402
    BMA_FORGET,
    RESULTS,
    ROOT_03C,
    ROOT_03D,
    SEVERE_NLL,
    WINDOWS,
    _common_q,
    _load_task,
    _make_estimator,
    _marginal_log_likelihood,
    bma_log_weights,
    cell_tag,
    combine_log_posteriors,
    grid_cells,
)
from camels_switch_confirmation.run_parameter_path_design90_smrain import (  # noqa: E402
    _aggregate,
)
from camels_switch_confirmation.summarize_parameter_path_design90_propq import (  # noqa: E402
    _evaluate_events_window,
)

EXPERIMENT_ID = "CAMELS_ONLINE_NOISE_A2F99_DESIGN90_01"
PREREGISTRATION = (
    "docs/plans/2026-08-17-online-noise-a2f99-design90-stage2-prereg-v01.md"
)
OUTPUT_ROOT = RESULTS / "online_noise_a2f99_design90_01_20260817_local"
PILOT_BASINS = frozenset({"03049800", "02193340", "07145700", "07184000"})
ESTIMATORS = (("A2f99", BMA_FORGET), ("A2cum", None))
PRIMARY_ESTIMATOR = "A2f99"
S1_MEDIAN_TOLERANCE = 0.05
WORKERS = 10


def design90_identities():
    frame = pd.read_csv(
        ROOT_03C / "verification" / "task_metrics.csv", dtype={"basin_id": str}
    )
    identities = sorted(
        {(str(row.basin_id), int(row.seed)) for row in frame.itertuples(index=False)}
    )
    if len(identities) != 180:
        raise ValueError("expected 180 basin-seed identities from 03C")
    return identities


def design90_tasks():
    return [
        (basin, seed, arm)
        for arm in ("C", "P")
        for basin, seed in design90_identities()
    ]


def generalization_mask(frame: pd.DataFrame) -> pd.Series:
    return ~frame["basin_id"].isin(PILOT_BASINS)


def _run_cell(args):
    basin, seed, arm, m, c = args
    out_dir = OUTPUT_ROOT / "grid" / arm / cell_tag(m, c) / "probs"
    out_path = out_dir / f"{basin}_s{seed}.npz"
    if out_path.exists():
        return {"basin_id": basin, "seed": seed, "arm_id": arm,
                "cell": cell_tag(m, c), "status": "success", "skipped": True}
    task = _load_task(basin, seed, arm)
    estimator, transitions = _make_estimator(task, basin, arm)
    n_days = len(task["obs"])
    probabilities = np.empty((n_days, 3))
    log_probabilities = np.empty((n_days, 3))
    marginal = np.empty(n_days)
    for day in range(n_days):
        for transition in transitions:
            transition.set_forcing(task["rain"][day], task["pet"][day], task["temp"][day])
        _common_q(estimator, transitions, task["rain"][day], m, c)
        result = estimator.step(np.array([task["obs"][day]]))
        probabilities[day] = result.posterior_probabilities
        log_probabilities[day] = result.posterior_log_probabilities
        marginal[day] = _marginal_log_likelihood(result, arm)
    out_dir.mkdir(parents=True, exist_ok=True)
    _atomic_save_npz(
        out_path,
        probabilities=probabilities,
        log_probabilities=log_probabilities,
        marginal_log_likelihood=marginal,
        true_candidate_indices=task["tci"],
        truth_parfc=task["truth_parfc"],
        switch_days=task["switch_days"],
        rotation=task["rotation"],
        basin_id=np.array(basin),
        seed=np.array(seed, dtype=np.int64),
        arm_id=np.array(arm),
        grid_m=np.array(m, dtype=np.float64),
        grid_c=np.array(c, dtype=np.float64),
        source_03c_task=np.array(task["source"]),
    )
    return {"basin_id": basin, "seed": seed, "arm_id": arm,
            "cell": cell_tag(m, c), "status": "success", "skipped": False}


def run() -> None:
    work = [
        (basin, seed, arm, m, c)
        for (m, c) in grid_cells()
        for basin, seed, arm in design90_tasks()
    ]
    with ProcessPoolExecutor(max_workers=WORKERS) as pool:
        records = list(pool.map(_run_cell, work, chunksize=8))
    failures = [r for r in records if r["status"] != "success"]
    if failures:
        raise RuntimeError(f"stage-2 task failures: {failures}")
    skipped = sum(1 for r in records if r.get("skipped"))
    print(json.dumps({"total": len(records), "computed": len(records) - skipped,
                      "skipped": skipped}))


def _task_row(probs, log_probs, tci, truth_parfc, switch_days, rotation,
              basin, seed, arm, estimator) -> dict:
    row_index = np.arange(len(probs))
    true_p = probs[row_index, tci]
    true_nll = -log_probs[row_index, tci]
    onehot = np.eye(3)[tci]
    record = {
        "basin_id": basin,
        "seed": seed,
        "arm_id": arm,
        "estimator": estimator,
        "zero_true_probability_days": int(np.sum(true_p == 0.0)),
        "severe_negative_log_probability_days": int(np.sum(true_nll > SEVERE_NLL)),
        "true_probability_below_0_01_days": int(np.sum(true_p < 0.01)),
        "mean_true_negative_log_probability": float(np.mean(true_nll)),
        "multiclass_brier": float(np.mean(np.sum((probs - onehot) ** 2, axis=1))),
    }
    pairs = list(zip(switch_days.tolist(), rotation[1:].tolist()))
    for window in WINDOWS:
        events = _evaluate_events_window(probs, pairs, window)
        record[f"events_passed_w{window}"] = int(sum(e["passed"] for e in events))
        for index, event in enumerate(events):
            switch_day = event["switch_day"]
            direction = (
                "increase"
                if float(truth_parfc[switch_day]) > float(truth_parfc[switch_day - 1])
                else "decrease"
            )
            record[f"event{index}_w{window}_pass"] = bool(event["passed"])
            if window == WINDOWS[0]:
                record[f"event{index}_switch_day"] = int(switch_day)
                record[f"event{index}_direction"] = direction
    return record


def _paired_counts(sub: pd.DataFrame, anchor: pd.DataFrame) -> dict:
    merged = sub.merge(
        anchor,
        on=("basin_id", "seed", "arm_id"),
        suffixes=("_new", "_old"),
        validate="one_to_one",
    )
    if len(merged) != len(sub):
        raise ValueError("stage-2 tasks do not pair one-to-one with 03D metrics")
    counts = {}
    for name, higher_is_better in (
        ("events_passed_w30", True),
        ("events_passed_w90", True),
        ("multiclass_brier", False),
        ("mean_true_negative_log_probability", False),
        ("zero_true_probability_days", False),
    ):
        new = merged[f"{name}_new"]
        old = merged[f"{name}_old"]
        counts[name] = {
            "improved": int(((new > old) == higher_is_better)[new != old].sum()),
            "equal": int((new == old).sum()),
            "worse": int(((new < old) == higher_is_better)[new != old].sum()),
        }
    counts["zero_days_total_old"] = int(merged["zero_true_probability_days_old"].sum())
    counts["zero_days_total_new"] = int(merged["zero_true_probability_days_new"].sum())
    counts["mean_nll_old"] = float(
        merged["mean_true_negative_log_probability_old"].mean())
    counts["mean_nll_new"] = float(
        merged["mean_true_negative_log_probability_new"].mean())
    counts["median_nll_old"] = float(
        merged["mean_true_negative_log_probability_old"].median())
    counts["median_nll_new"] = float(
        merged["mean_true_negative_log_probability_new"].median())
    return counts


def summarize() -> None:
    cells = grid_cells()
    rows = []
    for basin, seed, arm in design90_tasks():
        loglik = []
        logp = []
        meta = None
        for m, c in cells:
            path = (OUTPUT_ROOT / "grid" / arm / cell_tag(m, c) / "probs"
                    / f"{basin}_s{seed}.npz")
            with np.load(path, allow_pickle=False) as archive:
                loglik.append(archive["marginal_log_likelihood"].copy())
                logp.append(archive["log_probabilities"].copy())
                if meta is None:
                    meta = {key: archive[key].copy() for key in (
                        "true_candidate_indices", "truth_parfc", "switch_days",
                        "rotation")}
        loglik = np.asarray(loglik)
        logp = np.asarray(logp)
        tci = meta["true_candidate_indices"].astype(int)
        for estimator, forget in ESTIMATORS:
            log_w = bma_log_weights(loglik, forget)
            combined_logp = combine_log_posteriors(log_w, logp)
            combined = np.exp(combined_logp)
            combined = combined / np.maximum(combined.sum(axis=1, keepdims=True), 1e-300)
            rows.append(_task_row(
                combined, combined_logp, tci, meta["truth_parfc"],
                meta["switch_days"].astype(np.int64),
                meta["rotation"].astype(np.int64),
                basin, seed, arm, estimator))
    frame = pd.DataFrame(rows)
    if len(frame) != 360 * len(ESTIMATORS):
        raise ValueError("stage-2 summary must cover 360 tasks per estimator")
    verification = OUTPUT_ROOT / "verification"
    verification.mkdir(parents=True, exist_ok=True)
    frame.to_csv(verification / "task_metrics.csv", index=False)

    anchor = pd.read_csv(
        ROOT_03D / "verification" / "task_metrics.csv", dtype={"basin_id": str}
    )
    summary = {
        "experiment_id": EXPERIMENT_ID,
        "preregistration": PREREGISTRATION,
        "estimator_definition": {
            "grid_m": sorted({m for m, _ in cells}),
            "grid_c": sorted({c for _, c in cells}),
            "cells": [cell_tag(m, c) for m, c in cells],
            "forget": BMA_FORGET,
        },
        "blocks": {},
    }
    for estimator, _ in ESTIMATORS:
        for arm in ("C", "P"):
            base = frame[(frame["estimator"] == estimator)
                         & (frame["arm_id"] == arm)].reset_index(drop=True)
            anchor_arm = anchor[anchor["arm_id"] == arm].reset_index(drop=True)
            for subset_name in ("all", "generalization"):
                sub = base if subset_name == "all" else base[
                    generalization_mask(base)].reset_index(drop=True)
                anchor_sub = anchor_arm if subset_name == "all" else anchor_arm[
                    generalization_mask(anchor_arm)].reset_index(drop=True)
                block = {
                    "aggregate": _aggregate(sub),
                    "paired_vs_03d": _paired_counts(sub, anchor_sub),
                }
                key = f"{estimator}/{arm}/{subset_name}"
                if estimator == PRIMARY_ESTIMATOR and subset_name == "generalization":
                    aggregate = block["aggregate"]
                    paired = block["paired_vs_03d"]
                    s1 = {
                        "w90_all_types_ge_0_5":
                            aggregate["window_90d"]["per_type_min_pass_rate"] >= 0.5,
                        "median_nll_within_tolerance":
                            paired["median_nll_new"]
                            <= paired["median_nll_old"] + S1_MEDIAN_TOLERANCE,
                        "zero_days_not_increased":
                            paired["zero_days_total_new"]
                            <= paired["zero_days_total_old"],
                    }
                    s1["passed"] = all(s1.values())
                    nll_pair = paired["mean_true_negative_log_probability"]
                    s2 = {
                        "paired_nll_improved_gt_worse":
                            nll_pair["improved"] > nll_pair["worse"],
                        "mean_nll_below_oracle":
                            paired["mean_nll_new"] < paired["mean_nll_old"],
                    }
                    s2["passed"] = s1["passed"] and all(s2.values())
                    block["gates"] = {"S1": s1, "S2": s2}
                summary["blocks"][key] = block
    summary["claim_boundary"] = {
        "estimator_frozen_from_pilot": True,
        "claims_carried_by": "A2f99 generalization subset only",
        "noise_structure_known_synthetic_only": True,
        "real_observation_applicability": "not_tested",
        "forecast_value": "not_tested",
        "complete_state_accuracy": "not_tested",
        "noise_candidate_identification": "not_tested",
    }
    with (verification / "verification_summary.json").open(
        "w", encoding="utf-8"
    ) as handle:
        json.dump(summary, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    headline = {
        key: {
            "gates": value.get("gates"),
            "zero_days_new": value["paired_vs_03d"]["zero_days_total_new"],
            "zero_days_old": value["paired_vs_03d"]["zero_days_total_old"],
            "median_nll_new": value["paired_vs_03d"]["median_nll_new"],
            "median_nll_old": value["paired_vs_03d"]["median_nll_old"],
            "w90_min_rate": value["aggregate"]["window_90d"]["per_type_min_pass_rate"],
        }
        for key, value in summary["blocks"].items()
        if key.startswith(PRIMARY_ESTIMATOR)
    }
    print(json.dumps(headline, ensure_ascii=False))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("run", "summarize"))
    args = parser.parse_args()
    if args.command == "run":
        run()
    else:
        summarize()


if __name__ == "__main__":
    main()
