"""Stage-1 online noise estimation pilot (preregistered).

Preregistration: docs/plans/2026-08-17-online-noise-pilot-stage1-prereg-v01.md
Charter: docs/plans/2026-08-17-online-noise-estimation-charter-v01.md

Arms (both strictly causal, fully deterministic):
  A1     adaptive covariance matching of the two noise scalars (m, c) in the loop;
  A2     15-cell fixed-scalar grid; Bayesian model averaging over per-day marginal
         log-likelihoods with cumulative (A2cum) and discounted (A2f99) weighting.
Gate G1: the oracle grid cell (m=1, c=0.2) must reproduce the frozen 03D task
outputs bit-for-bit before any arm result is interpreted.

Subcommands: g1 | grid | a1 | summarize
"""

from __future__ import annotations

import argparse
import json
import math
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

EXPERIMENT_ID = "CAMELS_ONLINE_NOISE_PILOT_01"
PREREGISTRATION = "docs/plans/2026-08-17-online-noise-pilot-stage1-prereg-v01.md"
RESULTS = Path(r"G:\wt\camels-rising\results\23_camels_switch_confirmation")
ROOT_03C = RESULTS / "camels_parfc_transition_path_03c_design90_propq_s01_20260814_local"
ROOT_03D = RESULTS / "camels_parfc_transition_path_03d_design90_smrain_s01_20260814_local"
ROOT_03B = RESULTS / "camels_parfc_transition_path_03b_design90_s01_20260811_local"
OUTPUT_ROOT = RESULTS / "online_noise_pilot_01_20260817_local"
PARAMETER_TABLE = Path(
    r"G:\wt\camels-rising\results\10_global_conceptual_model_benchmark"
    r"\camels_us_531_repro_v01\summary\hbv_lite_cma_rising_local_full.csv"
)
ARM_MODES = {"C": "full", "P": "pairwise_path_postcollapse"}
BASINS = ("03049800", "02193340", "07145700", "07184000")
SEEDS = (0, 1)
CONTROL_BASIN = "07184000"

GRID_M = (0.1, 0.3, 1.0, 3.0, 10.0)
GRID_C = (0.0, 0.2, 0.4)
ORACLE_CELL = (1.0, 0.2)
A1_INIT_M = 0.03
A1_INIT_C = 0.02
A1_LAMBDA = 0.98
A1_GAMMA = 0.1
A1_STEP_CLIP = (0.8, 1.25)
A1_M_BOUNDS = (1e-3, 100.0)
A1_C_BOUNDS = (1e-3, 2.0)
Z2_WINSOR = 100.0
RAIN_THRESHOLD = 0.1
BMA_FORGET = 0.99
WINDOWS = (30, 90)
SEVERE_NLL = 100.0
WORKERS = 10
G2_NLL_TOLERANCE = 0.05
RANK_TIE = 0.02


def grid_cells():
    return [(m, c) for m in GRID_M for c in GRID_C]


def cell_tag(m: float, c: float) -> str:
    return f"m{m:g}_c{c:g}"


def pilot_tasks():
    return [
        (basin, seed, arm)
        for arm in ("C", "P")
        for basin in BASINS
        for seed in SEEDS
    ]


def _logsumexp_1d(values: np.ndarray) -> float:
    array = np.asarray(values, dtype=np.float64).ravel()
    finite = array[np.isfinite(array)]
    if len(finite) == 0:
        return float("-inf")
    peak = float(finite.max())
    return peak + math.log(float(np.exp(finite - peak).sum()))


def bma_log_weights(loglik: np.ndarray, forget: float | None = None) -> np.ndarray:
    """Per-day causal log weights (n_configs, n_days) from per-day log-likelihoods."""
    loglik = np.asarray(loglik, dtype=np.float64)
    if forget is None:
        score = np.cumsum(loglik, axis=1)
    else:
        score = np.empty_like(loglik)
        running = np.zeros(loglik.shape[0])
        for day in range(loglik.shape[1]):
            running = forget * running + loglik[:, day]
            score[:, day] = running
    norm = score.max(axis=0, keepdims=True)
    log_norm = norm + np.log(np.exp(score - norm).sum(axis=0, keepdims=True))
    return score - log_norm


def combine_log_posteriors(log_weights: np.ndarray, log_posts: np.ndarray) -> np.ndarray:
    """Mix per-config log posteriors (G,T,K) with per-day log weights (G,T)."""
    stacked = log_posts + log_weights[:, :, None]
    peak = stacked.max(axis=0)
    safe_peak = np.where(np.isfinite(peak), peak, 0.0)
    mixed = safe_peak + np.log(np.exp(stacked - safe_peak[None]).sum(axis=0))
    return np.where(np.isfinite(peak), mixed, float("-inf"))


def a1_update(m, c, ewma_dry, ewma_rain, z2, is_rain):
    """One preregistered covariance-matching update; returns the next-day scalars."""
    if z2 is None or not math.isfinite(z2):
        return m, c, ewma_dry, ewma_rain
    z2 = min(float(z2), Z2_WINSOR)
    if is_rain:
        ewma_rain = A1_LAMBDA * ewma_rain + (1.0 - A1_LAMBDA) * z2
        step = min(max(ewma_rain**A1_GAMMA, A1_STEP_CLIP[0]), A1_STEP_CLIP[1])
        c = min(max(c * step, A1_C_BOUNDS[0]), A1_C_BOUNDS[1])
    else:
        ewma_dry = A1_LAMBDA * ewma_dry + (1.0 - A1_LAMBDA) * z2
        step = min(max(ewma_dry**A1_GAMMA, A1_STEP_CLIP[0]), A1_STEP_CLIP[1])
        m = min(max(m * step, A1_M_BOUNDS[0]), A1_M_BOUNDS[1])
    return m, c, ewma_dry, ewma_rain


def _initial_hydrology(basin: str) -> np.ndarray:
    params = pd.read_csv(PARAMETER_TABLE, dtype={"basin_id": str})
    params["basin_id"] = params["basin_id"].str.zfill(8)
    row = params[params["basin_id"] == basin].iloc[0]
    return np.array(
        [float(row[f"state_{s}"]) for s in ("SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ")]
    )


def _load_task(basin: str, seed: int, arm: str) -> dict:
    source = ROOT_03C / "arms" / arm / "probs" / f"{basin}_s{seed}.npz"
    with np.load(source, allow_pickle=False) as archive:
        names = [str(x) for x in archive["candidate_parameter_names"]]
        task = {
            "members": [
                {n: float(v) for n, v in zip(names, row)}
                for row in archive["candidate_parameter_vectors"]
            ],
            "rain": archive["rain"].copy(),
            "pet": archive["pet"].copy(),
            "temp": archive["temperature"].copy(),
            "obs": archive["observations"].copy(),
            "tci": archive["true_candidate_indices"].astype(np.int64).copy(),
            "truth_parfc": archive["truth_parfc"].copy(),
            "switch_days": archive["switch_days"].astype(np.int64).copy(),
            "rotation": archive["rotation"].astype(np.int64).copy(),
            "sigma": float(archive["observation_sigma"].item()),
            "source": str(source),
        }
    return task


def _make_estimator(task: dict, basin: str, arm: str):
    return _build_bank(
        task["members"],
        _initial_hydrology(basin),
        task["sigma"],
        resolve_hbv_bounds("v5"),
        q_scale=np.nan,
        q_structure="lower_groundwater_state_only",
        q_mode="lower_groundwater_state_proportional",
        q_state_multiplier=1.0,
        filter_r_multiplier=1.0,
        interaction_mode=ARM_MODES[arm],
        parameter_state_mapping="conservative_parfc",
    )


def _common_q(estimator, transitions, rain_today: float, m: float, c: float) -> None:
    reference = transitions[0](estimator.state.copy())
    common_q = build_state_dependent_lower_groundwater_covariance(reference[4], m)
    common_q[2, 2] = (c * max(float(rain_today), 0.0)) ** 2
    assign_common_process_covariance(estimator, common_q)


def _marginal_log_likelihood(result, arm: str) -> float:
    if arm == "C":
        with np.errstate(divide="ignore"):
            prior_log = np.log(np.asarray(result.prior_probabilities, dtype=np.float64))
        return _logsumexp_1d(prior_log + np.asarray(result.candidate_log_evidences))
    mask = np.asarray(result.branch_active_mask, dtype=bool)
    values = (
        np.asarray(result.branch_prior_log_probabilities, dtype=np.float64)
        + np.asarray(result.branch_log_evidences, dtype=np.float64)
    )[mask]
    return _logsumexp_1d(values)


def _combined_z2(result, arm: str):
    pairs = []
    if arm == "C":
        for weight, filt in zip(result.prior_probabilities, result.candidate_results):
            if filt is not None and weight > 0.0:
                pairs.append((float(weight), filt))
    else:
        mask = np.asarray(result.branch_active_mask, dtype=bool)
        logw = np.asarray(result.branch_prior_log_probabilities, dtype=np.float64)
        for s in range(mask.shape[0]):
            for d in range(mask.shape[1]):
                if mask[s, d] and result.branch_results[s][d] is not None:
                    pairs.append((math.exp(logw[s, d]), result.branch_results[s][d]))
    z2 = 0.0
    total = 0.0
    for weight, filt in pairs:
        nu = float(np.ravel(filt.innovation)[0])
        s_var = float(np.ravel(filt.innovation_covariance)[0])
        if s_var > 0.0 and math.isfinite(nu):
            z2 += weight * (nu * nu) / s_var
            total += weight
    if total <= 0.0:
        return None
    return min(z2 / total, Z2_WINSOR)


def _run_fixed(args):
    basin, seed, arm, m, c = args
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
    out_dir = OUTPUT_ROOT / "grid" / arm / cell_tag(m, c) / "probs"
    out_dir.mkdir(parents=True, exist_ok=True)
    _atomic_save_npz(
        out_dir / f"{basin}_s{seed}.npz",
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
    return {"basin_id": basin, "seed": seed, "arm_id": arm, "cell": cell_tag(m, c),
            "status": "success"}


def _run_a1(args):
    basin, seed, arm = args
    task = _load_task(basin, seed, arm)
    estimator, transitions = _make_estimator(task, basin, arm)
    n_days = len(task["obs"])
    probabilities = np.empty((n_days, 3))
    log_probabilities = np.empty((n_days, 3))
    m_traj = np.empty(n_days)
    c_traj = np.empty(n_days)
    z2_traj = np.full(n_days, np.nan)
    m, c = A1_INIT_M, A1_INIT_C
    ewma_dry = 1.0
    ewma_rain = 1.0
    for day in range(n_days):
        for transition in transitions:
            transition.set_forcing(task["rain"][day], task["pet"][day], task["temp"][day])
        m_traj[day] = m
        c_traj[day] = c
        _common_q(estimator, transitions, task["rain"][day], m, c)
        result = estimator.step(np.array([task["obs"][day]]))
        probabilities[day] = result.posterior_probabilities
        log_probabilities[day] = result.posterior_log_probabilities
        z2 = _combined_z2(result, arm)
        if z2 is not None:
            z2_traj[day] = z2
        is_rain = float(task["rain"][day]) >= RAIN_THRESHOLD
        m, c, ewma_dry, ewma_rain = a1_update(m, c, ewma_dry, ewma_rain, z2, is_rain)
    out_dir = OUTPUT_ROOT / "a1" / arm / "probs"
    out_dir.mkdir(parents=True, exist_ok=True)
    _atomic_save_npz(
        out_dir / f"{basin}_s{seed}.npz",
        probabilities=probabilities,
        log_probabilities=log_probabilities,
        m_trajectory=m_traj,
        c_trajectory=c_traj,
        z2_trajectory=z2_traj,
        true_candidate_indices=task["tci"],
        truth_parfc=task["truth_parfc"],
        switch_days=task["switch_days"],
        rotation=task["rotation"],
        basin_id=np.array(basin),
        seed=np.array(seed, dtype=np.int64),
        arm_id=np.array(arm),
        source_03c_task=np.array(task["source"]),
    )
    return {"basin_id": basin, "seed": seed, "arm_id": arm, "status": "success"}


def _pool_run(function, work):
    with ProcessPoolExecutor(max_workers=WORKERS) as pool:
        records = list(pool.map(function, work))
    failures = [r for r in records if r["status"] != "success"]
    if failures:
        raise RuntimeError(f"pilot task failures: {failures}")
    return records


def run_g1() -> None:
    m, c = ORACLE_CELL
    _pool_run(_run_fixed, [(b, s, a, m, c) for b, s, a in pilot_tasks()])
    report = {"experiment_id": EXPERIMENT_ID, "gate": "G1", "cell": cell_tag(m, c),
              "tasks": [], "passed": True}
    for basin, seed, arm in pilot_tasks():
        ours = OUTPUT_ROOT / "grid" / arm / cell_tag(m, c) / "probs" / f"{basin}_s{seed}.npz"
        ref = ROOT_03D / "arms" / arm / "probs" / f"{basin}_s{seed}.npz"
        with np.load(ours, allow_pickle=False) as new, np.load(ref, allow_pickle=False) as old:
            probs_equal = bool(np.array_equal(new["probabilities"], old["probabilities"]))
            logs_equal = bool(
                np.array_equal(new["log_probabilities"], old["log_probabilities"])
            )
            max_abs = float(np.max(np.abs(new["probabilities"] - old["probabilities"])))
        entry = {"basin_id": basin, "seed": seed, "arm_id": arm,
                 "probabilities_bit_equal": probs_equal,
                 "log_probabilities_bit_equal": logs_equal,
                 "max_abs_probability_diff": max_abs}
        report["tasks"].append(entry)
        if not (probs_equal and logs_equal):
            report["passed"] = False
    verification = OUTPUT_ROOT / "verification"
    verification.mkdir(parents=True, exist_ok=True)
    with (verification / "g1_report.json").open("w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(json.dumps({"g1_passed": report["passed"]}))
    if not report["passed"]:
        raise SystemExit(1)


def run_grid() -> None:
    g1_report = json.loads(
        (OUTPUT_ROOT / "verification" / "g1_report.json").read_text(encoding="utf-8")
    )
    if not g1_report["passed"]:
        raise SystemExit("G1 gate failed; the grid must not run")
    work = [
        (basin, seed, arm, m, c)
        for (m, c) in grid_cells()
        if (m, c) != ORACLE_CELL
        for basin, seed, arm in pilot_tasks()
    ]
    _pool_run(_run_fixed, work)
    print(json.dumps({"grid_runs": len(work)}))


def run_a1_arm() -> None:
    g1_report = json.loads(
        (OUTPUT_ROOT / "verification" / "g1_report.json").read_text(encoding="utf-8")
    )
    if not g1_report["passed"]:
        raise SystemExit("G1 gate failed; A1 must not run")
    _pool_run(_run_a1, pilot_tasks())
    print(json.dumps({"a1_runs": len(pilot_tasks())}))


def _metrics_from(probs, log_probs, tci, truth_parfc, switch_days, rotation) -> dict:
    row = np.arange(len(probs))
    true_p = probs[row, tci]
    true_nll = -log_probs[row, tci]
    onehot = np.eye(3)[tci]
    record = {
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
    return record


def _scalar_diagnostics(m_traj, c_traj, switch_days) -> dict:
    tail = slice(int(0.7 * len(m_traj)), None)
    diag = {
        "m_tail_median": float(np.median(m_traj[tail])),
        "c_tail_median": float(np.median(c_traj[tail])),
        "m_final": float(m_traj[-1]),
        "c_final": float(c_traj[-1]),
    }
    jumps = 0
    for switch_day in switch_days.tolist():
        lo = max(1, switch_day - 15)
        hi = min(len(m_traj), switch_day + 15)
        for traj in (m_traj, c_traj):
            ratio = np.abs(np.log(traj[lo:hi] / np.maximum(traj[lo - 1:hi - 1], 1e-300)))
            if len(ratio) and float(ratio.max()) > math.log(2.0):
                jumps += 1
                break
    diag["switch_windows_with_scalar_jump_gt2x"] = jumps
    return diag


def summarize() -> None:
    cells = grid_cells()
    m_values = np.array([m for m, _ in cells])
    c_values = np.array([c for _, c in cells])
    anchors = {}
    for label, root in (("03B", ROOT_03B), ("03D", ROOT_03D)):
        frame = pd.read_csv(root / "verification" / "task_metrics.csv",
                            dtype={"basin_id": str})
        anchors[label] = frame
    rows = []
    diagnostics = {}
    for basin, seed, arm in pilot_tasks():
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
                    meta = {k: archive[k].copy() for k in (
                        "true_candidate_indices", "truth_parfc", "switch_days",
                        "rotation")}
        loglik = np.asarray(loglik)
        logp = np.asarray(logp)
        tci = meta["true_candidate_indices"].astype(int)
        for arm_name, forget in (("A2cum", None), ("A2f99", BMA_FORGET)):
            log_w = bma_log_weights(loglik, forget)
            combined_logp = combine_log_posteriors(log_w, logp)
            combined = np.exp(combined_logp)
            combined = combined / np.maximum(combined.sum(axis=1, keepdims=True), 1e-300)
            record = {"basin_id": basin, "seed": seed, "arm_id": arm,
                      "estimator": arm_name}
            record.update(_metrics_from(combined, combined_logp, tci,
                                        meta["truth_parfc"], meta["switch_days"],
                                        meta["rotation"]))
            weights = np.exp(log_w)
            m_traj = (weights * m_values[:, None]).sum(axis=0)
            c_traj = (weights * c_values[:, None]).sum(axis=0)
            diagnostics[f"{arm_name}/{arm}/{basin}_s{seed}"] = _scalar_diagnostics(
                m_traj, np.maximum(c_traj, 1e-6), meta["switch_days"])
            rows.append(record)
        a1_path = OUTPUT_ROOT / "a1" / arm / "probs" / f"{basin}_s{seed}.npz"
        with np.load(a1_path, allow_pickle=False) as archive:
            record = {"basin_id": basin, "seed": seed, "arm_id": arm,
                      "estimator": "A1"}
            record.update(_metrics_from(
                archive["probabilities"], archive["log_probabilities"],
                archive["true_candidate_indices"].astype(int),
                archive["truth_parfc"], archive["switch_days"].astype(np.int64),
                archive["rotation"].astype(np.int64)))
            diagnostics[f"A1/{arm}/{basin}_s{seed}"] = _scalar_diagnostics(
                archive["m_trajectory"], archive["c_trajectory"],
                archive["switch_days"].astype(np.int64))
            rows.append(record)
    frame = pd.DataFrame(rows)
    verification = OUTPUT_ROOT / "verification"
    frame.to_csv(verification / "task_metrics.csv", index=False)

    def anchor_value(label, basin, seed, arm, column):
        table = anchors[label]
        match = table[(table["basin_id"] == basin) & (table["seed"] == seed)
                      & (table["arm_id"] == arm)]
        if len(match) != 1:
            raise ValueError(f"{label} anchor missing for {basin}_s{seed}/{arm}")
        return float(match.iloc[0][column])

    summary = {"experiment_id": EXPERIMENT_ID, "preregistration": PREREGISTRATION,
               "estimators": {}}
    for arm_name in ("A1", "A2cum", "A2f99"):
        sub = frame[frame["estimator"] == arm_name]
        deltas, worse_than_03b, control_fail = [], 0, []
        for record in sub.itertuples(index=False):
            nll_03d = anchor_value("03D", record.basin_id, record.seed,
                                   record.arm_id, "mean_true_negative_log_probability")
            nll_03b = anchor_value("03B", record.basin_id, record.seed,
                                   record.arm_id, "mean_true_negative_log_probability")
            zero_03d = anchor_value("03D", record.basin_id, record.seed,
                                    record.arm_id, "zero_true_probability_days")
            deltas.append(record.mean_true_negative_log_probability - nll_03d)
            if record.mean_true_negative_log_probability > nll_03b:
                worse_than_03b += 1
            if record.basin_id == CONTROL_BASIN:
                ok = (record.mean_true_negative_log_probability
                      <= nll_03d + G2_NLL_TOLERANCE
                      and record.zero_true_probability_days <= zero_03d)
                control_fail.append(not ok)
        summary["estimators"][arm_name] = {
            "mean_nll_delta_vs_03d": float(np.mean(deltas)),
            "median_nll_delta_vs_03d": float(np.median(deltas)),
            "tasks_worse_than_03b": worse_than_03b,
            "survival_pass": worse_than_03b < 8,
            "g2_control_pass": not any(control_fail),
            "zero_days_total": int(sub["zero_true_probability_days"].sum()),
            "severe_days_total": int(
                sub["severe_negative_log_probability_days"].sum()),
            "events_w90_total": int(sub["events_passed_w90"].sum()),
            "events_w30_total": int(sub["events_passed_w30"].sum()),
        }
    survivors = {
        k: v for k, v in summary["estimators"].items()
        if v["survival_pass"] and v["g2_control_pass"]
    }
    summary["ranking_gates"] = (
        "eligibility = survival gate AND G2 control no-harm gate, per prereg section 3; "
        "an earlier summarize omitted G2 from eligibility (disclosed and corrected "
        "2026-08-17, no filter runs changed)"
    )
    if survivors:
        ranked = sorted(survivors.items(), key=lambda kv: kv[1]["mean_nll_delta_vs_03d"])
        best_name, best = ranked[0]
        simplicity = {"A1": 0, "A2cum": 1, "A2f99": 2}
        ties = [name for name, value in ranked
                if value["mean_nll_delta_vs_03d"] - best["mean_nll_delta_vs_03d"]
                < RANK_TIE]
        winner = sorted(ties, key=lambda name: simplicity[name])[0]
        summary["ranking"] = {"winner": winner, "order": [name for name, _ in ranked],
                              "tie_set": ties}
    else:
        summary["ranking"] = {"winner": None, "note": "all arms eliminated"}
    summary["scalar_diagnostics"] = diagnostics
    summary["claim_boundary"] = {
        "purpose": "estimator_selection_only",
        "afflicted_tasks_participated_in_03d_selection": True,
        "real_observation_applicability": "not_tested",
    }
    with (verification / "pilot_summary.json").open("w", encoding="utf-8") as handle:
        json.dump(summary, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    compact = {name: {k: v for k, v in value.items() if k != "by_task"}
               for name, value in summary["estimators"].items()}
    print(json.dumps({"ranking": summary["ranking"], "estimators": compact},
                     ensure_ascii=False))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("g1", "grid", "a1", "summarize"))
    args = parser.parse_args()
    if args.command == "g1":
        run_g1()
    elif args.command == "grid":
        run_grid()
    elif args.command == "a1":
        run_a1_arm()
    else:
        summarize()


if __name__ == "__main__":
    main()
