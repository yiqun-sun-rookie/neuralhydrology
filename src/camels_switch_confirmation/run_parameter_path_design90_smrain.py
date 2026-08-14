"""03D Design90: rain-proportional soil-moisture process noise at scale.

Single-factor change against 03C: the filter process covariance gains
``Q[SM,SM] = (0.2 * daily_rain)**2`` on top of the registered
state-proportional SLZ term.  All inputs (forcing, observations, candidates,
observation sigma) are read directly from the frozen 03C task files, so the
task identity is inherited bit-for-bit.  The module runs all 360 tasks and
then recomputes the dual-window scientific summary from its own saved
outputs, paired against the frozen 03C task metrics.  Preregistration:
docs/plans/2026-08-14-camels-parfc-transition-path-03d-design90-smrain-prereg-v01.md
"""

from __future__ import annotations

import json
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
import pandas as pd

_SRC = Path(__file__).resolve().parents[1]
if str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))

from camels_switch_confirmation.g2_switch_confirmation import (  # noqa: E402
    _atomic_save_npz,
    _build_bank,
    assign_common_process_covariance,
    build_state_dependent_lower_groundwater_covariance,
)
from camels_switch_confirmation.summarize_parameter_path_design90_propq import (  # noqa: E402
    _evaluate_events_window,
)
from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds  # noqa: E402

EXPERIMENT_ID = "CAMELS_PARFC_TRANSITION_PATH_03D_DESIGN90_SMRAIN"
SM_RAIN_COEFFICIENT = 0.2
Q_MODE_LABEL = "slz_state_proportional_plus_sm_rain_0p2"
ROOT_03C = Path(
    r"G:\wt\camels-rising\results\23_camels_switch_confirmation"
    r"\camels_parfc_transition_path_03c_design90_propq_s01_20260814_local"
)
OUTPUT_ROOT = Path(
    r"G:\wt\camels-rising\results\23_camels_switch_confirmation"
    r"\camels_parfc_transition_path_03d_design90_smrain_s01_20260814_local"
)
PARAMETER_TABLE = Path(
    r"G:\wt\camels-rising\results\10_global_conceptual_model_benchmark"
    r"\camels_us_531_repro_v01\summary\hbv_lite_cma_rising_local_full.csv"
)
ARM_MODES = {"C": "full", "P": "pairwise_path_postcollapse"}
WINDOWS = (30, 90)
SEVERE_NLL = 100.0


def _initial_hydrology(basin: str) -> np.ndarray:
    params = pd.read_csv(PARAMETER_TABLE, dtype={"basin_id": str})
    params["basin_id"] = params["basin_id"].str.zfill(8)
    row = params[params["basin_id"] == basin].iloc[0]
    return np.array(
        [float(row[f"state_{s}"]) for s in ("SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ")]
    )


def _run_task(args):
    basin, seed, arm = args
    source = ROOT_03C / "arms" / arm / "probs" / f"{basin}_s{seed}.npz"
    with np.load(source, allow_pickle=False) as archive:
        names = [str(x) for x in archive["candidate_parameter_names"]]
        members = [
            {n: float(v) for n, v in zip(names, row)}
            for row in archive["candidate_parameter_vectors"]
        ]
        rain = archive["rain"].copy()
        pet = archive["pet"].copy()
        temp = archive["temperature"].copy()
        obs = archive["observations"].copy()
        tci = archive["true_candidate_indices"].astype(np.int64).copy()
        truth_parfc = archive["truth_parfc"].copy()
        switch_days = archive["switch_days"].astype(np.int64).copy()
        rotation = archive["rotation"].astype(np.int64).copy()
        sigma = float(archive["observation_sigma"].item())
    estimator, transitions = _build_bank(
        members,
        _initial_hydrology(basin),
        sigma,
        resolve_hbv_bounds("v5"),
        q_scale=np.nan,
        q_structure="lower_groundwater_state_only",
        q_mode="lower_groundwater_state_proportional",
        q_state_multiplier=1.0,
        filter_r_multiplier=1.0,
        interaction_mode=ARM_MODES[arm],
        parameter_state_mapping="conservative_parfc",
    )
    n_days = len(obs)
    probabilities = np.empty((n_days, 3))
    log_probabilities = np.empty((n_days, 3))
    for day in range(n_days):
        for transition in transitions:
            transition.set_forcing(rain[day], pet[day], temp[day])
        reference = transitions[0](estimator.state.copy())
        common_q = build_state_dependent_lower_groundwater_covariance(
            reference[4], 1.0
        )
        common_q[2, 2] = (SM_RAIN_COEFFICIENT * max(float(rain[day]), 0.0)) ** 2
        assign_common_process_covariance(estimator, common_q)
        result = estimator.step(np.array([obs[day]]))
        probabilities[day] = result.posterior_probabilities
        log_probabilities[day] = result.posterior_log_probabilities
    out_dir = OUTPUT_ROOT / "arms" / arm / "probs"
    _atomic_save_npz(
        out_dir / f"{basin}_s{seed}.npz",
        probabilities=probabilities,
        log_probabilities=log_probabilities,
        true_candidate_indices=tci,
        truth_parfc=truth_parfc,
        switch_days=switch_days,
        rotation=rotation,
        basin_id=np.array(basin),
        seed=np.array(seed, dtype=np.int64),
        arm_id=np.array(arm),
        filter_q_mode=np.array(Q_MODE_LABEL),
        sm_rain_coefficient=np.array(SM_RAIN_COEFFICIENT, dtype=np.float64),
        source_03c_task=np.array(str(source)),
    )
    return {"basin_id": basin, "seed": seed, "arm_id": arm, "status": "success"}


def _task_metrics(npz_path: Path) -> dict:
    with np.load(npz_path, allow_pickle=False) as archive:
        probs = archive["probabilities"].copy()
        log_probs = archive["log_probabilities"].copy()
        tci = archive["true_candidate_indices"].astype(int).copy()
        truth_parfc = archive["truth_parfc"].copy()
        switch_days = archive["switch_days"].astype(int).copy()
        rotation = archive["rotation"].astype(int).copy()
        basin = str(archive["basin_id"].item())
        seed = int(archive["seed"].item())
        arm = str(archive["arm_id"].item())
        if str(archive["filter_q_mode"].item()) != Q_MODE_LABEL:
            raise ValueError(f"{npz_path} was not produced by the 03D filter")
    row = np.arange(len(probs))
    true_p = probs[row, tci]
    true_nll = -log_probs[row, tci]
    onehot = np.eye(3)[tci]
    record = {
        "basin_id": basin,
        "seed": seed,
        "arm_id": arm,
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


def _aggregate(frame: pd.DataFrame) -> dict:
    result = {
        "tasks": int(len(frame)),
        "zero_true_probability_days": int(frame["zero_true_probability_days"].sum()),
        "severe_negative_log_probability_days": int(
            frame["severe_negative_log_probability_days"].sum()
        ),
        "true_probability_below_0_01_days": int(
            frame["true_probability_below_0_01_days"].sum()
        ),
        "mean_true_negative_log_probability": float(
            frame["mean_true_negative_log_probability"].mean()
        ),
        "median_task_nll": float(
            frame["mean_true_negative_log_probability"].median()
        ),
        "multiclass_brier": float(frame["multiclass_brier"].mean()),
    }
    for window in WINDOWS:
        by_type = {}
        for index in range(6):
            switch_day = int(frame[f"event{index}_switch_day"].iloc[0])
            direction = str(frame[f"event{index}_direction"].iloc[0])
            passed = int(frame[f"event{index}_w{window}_pass"].sum())
            by_type[f"switch_day_{switch_day}"] = {
                "direction": direction,
                "passed": passed,
                "total": int(len(frame)),
                "pass_rate": passed / len(frame),
            }
        result[f"window_{window}d"] = {
            "events_passed": int(frame[f"events_passed_w{window}"].sum()),
            "events_total": int(len(frame)) * 6,
            "per_type_min_pass_rate": min(
                value["pass_rate"] for value in by_type.values()
            ),
            "increase_pass_rate": sum(
                v["passed"] for v in by_type.values() if v["direction"] == "increase"
            ) / (3 * len(frame)),
            "decrease_pass_rate": sum(
                v["passed"] for v in by_type.values() if v["direction"] == "decrease"
            ) / (3 * len(frame)),
            "by_transition": by_type,
        }
    return result


def _paired_against_03c(frame: pd.DataFrame) -> dict:
    baseline = pd.read_csv(
        ROOT_03C / "verification" / "task_metrics.csv", dtype={"basin_id": str}
    )
    merged = frame.merge(
        baseline,
        on=("basin_id", "seed", "arm_id"),
        suffixes=("_new", "_old"),
        validate="one_to_one",
    )
    if len(merged) != len(frame):
        raise ValueError("03D tasks do not pair one-to-one with 03C task metrics")
    counts = {}
    for name, higher_is_better in (
        ("events_passed_w30", True),
        ("events_passed_w90", True),
        ("multiclass_brier", False),
        ("mean_true_negative_log_probability", False),
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
    counts["severe_days_total_old"] = int(
        merged["severe_negative_log_probability_days_old"].sum()
    )
    counts["severe_days_total_new"] = int(
        merged["severe_negative_log_probability_days_new"].sum()
    )
    return counts


def main() -> None:
    baseline_metrics = pd.read_csv(
        ROOT_03C / "verification" / "task_metrics.csv", dtype={"basin_id": str}
    )
    tasks = sorted(
        {
            (str(row.basin_id), int(row.seed))
            for row in baseline_metrics.itertuples(index=False)
        }
    )
    if len(tasks) != 180:
        raise ValueError("expected 180 basin-seed identities from 03C")
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=False)
    for arm in ("C", "P"):
        (OUTPUT_ROOT / "arms" / arm / "probs").mkdir(parents=True, exist_ok=False)
    work = [(basin, seed, arm) for arm in ("C", "P") for basin, seed in tasks]
    with ProcessPoolExecutor(max_workers=10) as pool:
        records = list(pool.map(_run_task, work))
    failures = [r for r in records if r["status"] != "success"]
    if failures:
        raise RuntimeError(f"03D task failures: {failures}")

    metric_rows = []
    for arm in ("C", "P"):
        for npz_path in sorted((OUTPUT_ROOT / "arms" / arm / "probs").glob("*.npz")):
            metric_rows.append(_task_metrics(npz_path))
    frame = pd.DataFrame(metric_rows)
    if len(frame) != 360:
        raise ValueError("03D outputs must cover exactly 360 tasks")
    verification = OUTPUT_ROOT / "verification"
    verification.mkdir(exist_ok=False)
    frame.to_csv(verification / "task_metrics.csv", index=False)
    summary = {
        "experiment_id": EXPERIMENT_ID,
        "sm_rain_coefficient": SM_RAIN_COEFFICIENT,
        "q_mode": Q_MODE_LABEL,
        "task_count": 360,
        "preregistration": (
            "docs/plans/2026-08-14-camels-parfc-transition-path-"
            "03d-design90-smrain-prereg-v01.md"
        ),
        "arm_summary": {
            arm: _aggregate(frame[frame["arm_id"] == arm].reset_index(drop=True))
            for arm in ("C", "P")
        },
        "paired_against_03c": {
            arm: _paired_against_03c(frame[frame["arm_id"] == arm])
            for arm in ("C", "P")
        },
        "claim_boundary": {
            "parameter_candidate_identification": "exploratory_design90_only",
            "variant_selected_on_scan_containing_all_afflicted_tasks": True,
            "noise_candidate_identification": "not_tested",
            "complete_state_accuracy": "not_tested",
            "forecast_value": "not_tested",
            "real_observation_assimilation_value": "not_tested",
        },
    }
    with (verification / "verification_summary.json").open(
        "x", encoding="utf-8"
    ) as handle:
        json.dump(summary, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(json.dumps(summary["arm_summary"], ensure_ascii=False)[:2000])


if __name__ == "__main__":
    main()
