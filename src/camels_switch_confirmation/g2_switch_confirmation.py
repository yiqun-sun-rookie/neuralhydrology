"""G2: large-sample parameter-switch confirmation run (frozen config g2_frozen_v01).

Per (basin, seed): generate the 15-state synthetic truth with the frozen
rotation and SLZ lognormal noise, synthesize observations, run the 3-member
rising-kernel IMM bank, evaluate the 6 directed switch events against the
id23-verbatim rule, and write per-event verdicts. The main process joins the
outcomes with the frozen G1 prediction labels into the transfer confusion
matrix.

Usage:
    python -X utf8 -m src.camels_switch_confirmation.g2_switch_confirmation --workers 6
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

for _v in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS",
           "NUMEXPR_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_v, "1")

import numpy as np
import pandas as pd

_HERE = Path(__file__).resolve()
_REPO_ROOT = _HERE.parents[2]
if str(_REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT / "src"))
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from camels_switch_confirmation.g1_precheck import (  # noqa: E402
    LAG_KERNEL, N_SEEDS, PARAM_KEYS, ROTATION, RISING_TABLE, SEED_ENTROPY,
    STAGE_DAYS, STATE_NAMES, WINDOW_DAYS, WINDOW_START, _window_end,
)

# ---- frozen G2 constants (configs/g2_frozen_v01.json is authoritative) ----
FROZEN_CONFIG = "src/camels_switch_confirmation/configs/g2_frozen_v01.json"
G1_CSV = "results/23_camels_switch_confirmation/g1_precheck_v01/g1_precheck.csv"
OUT_DIR = "results/23_camels_switch_confirmation/g2_switch_confirmation_v01"
BOUNDS_PRESET = "v5"
LAG_CAP = 10.0
SLZ_LOGNORMAL_SIGMA = 0.02
PROCESS_VARIANCE_SCALE = 1e-4
TRANSITION_DIAGONAL = 0.98
INITIAL_COVARIANCE_FRACTION = 0.001
RESPONSE_WINDOW_DAYS = 30
CONSECUTIVE_DAYS = 5
PROB_THRESHOLD_EXCLUSIVE = 0.5
MARGIN_INCLUSIVE = 0.1
N_HYDRO = 5
N_STATE = 15


def rising_routed_discharge(state: np.ndarray, lag_time: float) -> float:
    """Rising-half routed discharge: largest weight on the OLDEST raw runoff."""
    n_lag = int(np.ceil(min(float(lag_time), LAG_CAP)))
    n_lag = max(n_lag, 1)
    weights = np.arange(1, n_lag + 1, dtype=np.float64)
    weights /= weights.sum()
    routing = np.asarray(state, dtype=np.float64)[N_HYDRO:N_HYDRO + n_lag]
    return float(weights @ routing)


class RisingRoutedObservation:
    """Candidate-specific rising-half routed discharge observation."""

    def __init__(self, parameters):
        self.parameters = dict(parameters)

    def __call__(self, state: np.ndarray) -> np.ndarray:
        from hbv_joint_uncertainty.preflight import project_hbv_state
        physical = project_hbv_state(state, self.parameters)
        return np.array(
            [rising_routed_discharge(physical, self.parameters["lag_time"])],
            dtype=np.float64)


def _generate_truth(members, rain, pet, temp, init_hydro, rng, bounds):
    """15-state stepwise truth: rotation, SLZ lognormal noise, rising routing.

    Returns (truth_q, switch_days, clip_count). One rng normal per day.
    """
    from hbv_joint_uncertainty.hbv_adapter import advance_state
    state = np.zeros(N_STATE, dtype=np.float64)
    state[:N_HYDRO] = init_hydro
    n_days = min(len(rain), WINDOW_DAYS)
    truth_q = np.zeros(n_days, dtype=np.float64)
    switch_days = []
    clips = 0
    day = 0
    for stage_pos, member_idx in enumerate(ROTATION):
        params = members[member_idx]
        if stage_pos > 0 and day < n_days:
            switch_days.append((day, member_idx))
        for _ in range(STAGE_DAYS):
            if day >= n_days:
                break
            state = advance_state(state, rain[day], pet[day], temp[day], params,
                                  bounds=bounds)
            noisy = state[4] * np.exp(
                rng.normal(-0.5 * SLZ_LOGNORMAL_SIGMA ** 2, SLZ_LOGNORMAL_SIGMA))
            if not np.isfinite(noisy) or noisy < 0.0:
                clips += 1
                noisy = max(noisy, 0.0) if np.isfinite(noisy) else 0.0
            state[4] = noisy
            truth_q[day] = rising_routed_discharge(state, params["lag_time"])
            day += 1
    return truth_q, switch_days, clips


def _build_bank(members, init_hydro, sigma_obs, bounds, q_scale=PROCESS_VARIANCE_SCALE):
    from hbv_joint_uncertainty.imm import InteractingMultipleModel
    from hbv_joint_uncertainty.preflight import (
        ForcingTransition, build_process_covariance, build_transition_matrix,
        project_hbv_state)
    from hbv_joint_uncertainty.sigma_filter import ModifiedUnscentedFilter

    # First-contact amendment (2026-08-07, recorded in prereg): ONE common
    # process covariance built from the CENTER member (theta*), so the three
    # candidates differ only in their dynamics hypothesis (parFC), never in
    # assumed noise. Member-specific Q (the id23 construction) injects a
    # systematic likelihood bias toward the smallest-FC member: its tighter Q
    # gives a sharper innovation variance and a persistently higher likelihood
    # regardless of which member generated the truth (diagnosed on basin
    # 01022500 stage 0: wrong member wins 110-128/180 days under both matched
    # and id23 observation noise).
    common_q = build_process_covariance(members[0], q_scale)
    filters, transitions = [], []
    for params in members:
        state0 = np.zeros(N_STATE, dtype=np.float64)
        state0[:N_HYDRO] = init_hydro
        state0 = project_hbv_state(state0, params)
        state_scales = np.maximum(np.abs(state0), 1.0)
        p0 = np.diag((INITIAL_COVARIANCE_FRACTION * state_scales) ** 2)
        transition = ForcingTransition(params, parameter_bounds=bounds)
        filters.append(ModifiedUnscentedFilter(
            state=state0, covariance=p0,
            transition=transition,
            observation=RisingRoutedObservation(params),
            process_covariance=common_q,
            observation_covariance=np.array([[sigma_obs ** 2]]),
            state_projector=lambda values, p=params: __import__(
                "hbv_joint_uncertainty.preflight", fromlist=["project_hbv_state"]
            ).project_hbv_state(values, p),
            alpha=0.6874, beta=2.0, kappa=-2.0,
        ))
        transitions.append(transition)
    estimator = InteractingMultipleModel(
        filters=filters,
        transition_matrix=build_transition_matrix(len(members), TRANSITION_DIAGONAL),
        initial_probabilities=np.full(len(members), 1.0 / len(members)),
        parameter_groups=list(range(len(members))),
    )
    return estimator, transitions


def _evaluate_events(probs, switch_days):
    """id23-verbatim rule per switch: within 30 d, a 5-day run with new-true
    posterior > 0.5 (strict) and margin >= 0.1, run entirely inside window."""
    events = []
    n_days = probs.shape[0]
    for switch_day, new_idx in switch_days:
        window_end = min(switch_day + RESPONSE_WINDOW_DAYS, n_days)
        passed, start = False, None
        latest_start = window_end - CONSECUTIVE_DAYS
        for t0 in range(switch_day, latest_start + 1):
            seg = probs[t0:t0 + CONSECUTIVE_DAYS]
            new_p = seg[:, new_idx]
            others = np.delete(seg, new_idx, axis=1).max(axis=1)
            if np.all(new_p > PROB_THRESHOLD_EXCLUSIVE) and \
               np.all(new_p - others >= MARGIN_INCLUSIVE):
                passed, start = True, t0 - switch_day
                break
        events.append({"switch_day": switch_day, "new_member": new_idx,
                       "passed": passed, "response_start": start})
    return events


def _run_one(args_tuple):
    (basin_id, seed_k, data_root, row, q_scale, out_tag) = args_tuple
    import sys as _sys
    if str(_REPO_ROOT / "src") not in _sys.path:
        _sys.path.insert(0, str(_REPO_ROOT / "src"))
    from hydroagent.data_loading import load_camels_basin
    from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds
    from camels_switch_confirmation.bank import build_bank as build_members

    t0 = time.time()
    try:
        params = {k: float(row[f"p_{k}"]) for k in PARAM_KEYS}
        lag_capped = params["lag_time"] > LAG_CAP
        params["lag_time"] = min(params["lag_time"], LAG_CAP)
        init_hydro = np.array([float(row[f"state_{s}"]) for s in STATE_NAMES])
        sigma_obs = float(row["sigma_obs"])

        v_bounds = resolve_hbv_bounds(BOUNDS_PRESET)
        members, _ = build_members(params, v_bounds["parFC"])

        forcing, _, _ = load_camels_basin(
            basin_id, data_root=data_root,
            start_date=WINDOW_START, end_date=_window_end(),
            forcing="maurer", pet_method="oudin", keep_obs_nan_days=True)
        rain = forcing["prcp"].values.astype(np.float64)
        pet_col = "ep" if "ep" in forcing.columns else "pet"
        pet = forcing[pet_col].values.astype(np.float64)
        temp = (forcing["tmean"].values.astype(np.float64)
                if "tmean" in forcing.columns else np.zeros_like(rain))

        truth_rng = np.random.default_rng(
            np.random.SeedSequence((SEED_ENTROPY, int(basin_id), seed_k)))
        obs_rng = np.random.default_rng(
            np.random.SeedSequence((SEED_ENTROPY, int(basin_id), seed_k, 1)))

        truth_q, switch_days, clips = _generate_truth(
            members, rain, pet, temp, init_hydro, truth_rng, v_bounds)
        n_days = len(truth_q)
        observations = truth_q + obs_rng.normal(0.0, sigma_obs, size=n_days)

        estimator, transitions = _build_bank(members, init_hydro, sigma_obs, v_bounds,
                                             q_scale=q_scale)
        probs = np.zeros((n_days, len(members)), dtype=np.float64)
        for day in range(n_days):
            for tr in transitions:
                tr.set_forcing(rain[day], pet[day], temp[day])
            result = estimator.step(np.array([observations[day]]))
            probs[day] = result.posterior_probabilities

        events = _evaluate_events(probs, switch_days)
        out_dir = _REPO_ROOT / (OUT_DIR + (f"_{out_tag}" if out_tag else "")) / "probs"
        out_dir.mkdir(parents=True, exist_ok=True)
        np.savez_compressed(out_dir / f"{basin_id}_s{seed_k}.npz",
                            probabilities=probs, truth_q=truth_q,
                            switch_days=np.array([d for d, _ in switch_days]))

        rec = {"basin_id": basin_id, "seed": seed_k, "run_status": "success",
               "error_message": "", "lag_capped": bool(lag_capped),
               "truth_clip_count": clips,
               "n_events": len(events),
               "n_events_passed": sum(e["passed"] for e in events),
               "_elapsed_s": round(time.time() - t0, 2)}
        for i, e in enumerate(events):
            rec[f"event{i}_pass"] = bool(e["passed"])
            rec[f"event{i}_start"] = (e["response_start"]
                                      if e["response_start"] is not None else -1)
            rec[f"event{i}_new_member"] = e["new_member"]
            sd = e["switch_day"]
            rec[f"event{i}_window_rain_mm"] = float(
                np.sum(rain[sd:sd + RESPONSE_WINDOW_DAYS]))
        return rec
    except Exception as exc:  # noqa: BLE001
        return {"basin_id": basin_id, "seed": seed_k, "run_status": "failed",
                "error_message": str(exc),
                "_elapsed_s": round(time.time() - t0, 2)}


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--data-root", default="data/camels_us")
    p.add_argument("--workers", type=int, default=6)
    p.add_argument("--limit", type=int, default=None,
                   help="limit number of BASINS (each still runs both seeds)")
    p.add_argument("--q-scale", type=float, default=PROCESS_VARIANCE_SCALE,
                   help="filter process-noise variance scale (EXPLORATORY sweeps only; "
                        "the frozen value is 1e-4)")
    p.add_argument("--out-tag", default="",
                   help="suffix for the output dir, e.g. q1e5 (exploratory sweeps)")
    args = p.parse_args(argv)

    table = pd.read_csv(_REPO_ROOT / RISING_TABLE, dtype={"basin_id": str})
    table["basin_id"] = table["basin_id"].str.zfill(8)
    rows = table.to_dict("records")
    if args.limit:
        rows = rows[: args.limit]

    g1 = pd.read_csv(_REPO_ROOT / G1_CSV, dtype={"basin_id": str})
    g1["basin_id"] = g1["basin_id"].str.zfill(8)
    g1_map = g1.set_index("basin_id")[["sigma_obs", "predicted_identifiable"]]

    out_dir = _REPO_ROOT / (OUT_DIR + (f"_{args.out_tag}" if args.out_tag else ""))
    out_dir.mkdir(parents=True, exist_ok=True)

    work = []
    for r in rows:
        sigma = g1_map.loc[r["basin_id"], "sigma_obs"]
        r = dict(r)
        r["sigma_obs"] = float(sigma)
        for k in range(N_SEEDS):
            work.append((r["basin_id"], k, args.data_root, r, args.q_scale, args.out_tag))

    print(f"[{time.strftime('%H:%M:%S')}] G2 run: {len(rows)} basins x "
          f"{N_SEEDS} seeds = {len(work)} tasks")
    results = []
    t_start = time.time()
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(_run_one, w): (w[0], w[1]) for w in work}
        for i, fut in enumerate(as_completed(futures), start=1):
            try:
                res = fut.result()
            except Exception as exc:  # noqa: BLE001
                bid, sk = futures[fut]
                res = {"basin_id": bid, "seed": sk, "run_status": "failed",
                       "error_message": f"worker exception: {exc}"}
            results.append(res)
            if i % 50 == 0 or i == len(work):
                el = (time.time() - t_start) / 60
                eta = el / i * (len(work) - i)
                print(f"[{time.strftime('%H:%M:%S')}] {i}/{len(work)} "
                      f"wall={el:.1f}min ETA={eta:.0f}min", flush=True)

    df = pd.DataFrame(results).sort_values(["basin_id", "seed"]).reset_index(drop=True)
    df.to_csv(out_dir / "g2_events.csv", index=False)

    # ---- basin verdicts + transfer confusion matrix ----
    ok = df[df["run_status"] == "success"]
    verdicts = []
    for bid, grp in ok.groupby("basin_id"):
        total = int(grp["n_events"].sum())
        passed = int(grp["n_events_passed"].sum())
        verdict = ("pass" if (total == 12 and passed == 12)
                   else "partial" if passed >= 8 else "fail")
        verdicts.append({"basin_id": bid, "events_total": total,
                         "events_passed": passed, "verdict": verdict})
    vdf = pd.DataFrame(verdicts).merge(
        g1[["basin_id", "predicted_identifiable", "r_min", "nse_calibration_table"]],
        on="basin_id")
    vdf.to_csv(out_dir / "g2_basin_verdicts.csv", index=False)

    summary = {"config": FROZEN_CONFIG, "q_scale": args.q_scale,
               "out_tag": args.out_tag, "n_tasks": len(work),
               "n_success": int(len(ok)),
               "n_failed": int((df["run_status"] == "failed").sum()),
               "wall_clock_min": round((time.time() - t_start) / 60, 1)}
    if len(vdf):
        pred = vdf[vdf["predicted_identifiable"]]
        unpred = vdf[~vdf["predicted_identifiable"]]
        pass_rate_pred = float((pred["verdict"] == "pass").mean()) if len(pred) else float("nan")
        pass_rate_unpred = float((unpred["verdict"] == "pass").mean()) if len(unpred) else float("nan")
        # one-sided two-proportion z-test
        z = p_val = float("nan")
        if len(pred) and len(unpred):
            x1, n1 = (pred["verdict"] == "pass").sum(), len(pred)
            x2, n2 = (unpred["verdict"] == "pass").sum(), len(unpred)
            pool_p = (x1 + x2) / (n1 + n2)
            se = np.sqrt(pool_p * (1 - pool_p) * (1 / n1 + 1 / n2))
            if se > 0:
                from math import erf, sqrt
                z = float((x1 / n1 - x2 / n2) / se)
                p_val = float(0.5 * (1 - erf(z / sqrt(2))))
        summary.update({
            "n_basins": len(vdf),
            "confusion": {
                "predicted_identifiable": {
                    "n": int(len(pred)),
                    "pass": int((pred["verdict"] == "pass").sum()),
                    "partial": int((pred["verdict"] == "partial").sum()),
                    "fail": int((pred["verdict"] == "fail").sum())},
                "predicted_fail": {
                    "n": int(len(unpred)),
                    "pass": int((unpred["verdict"] == "pass").sum()),
                    "partial": int((unpred["verdict"] == "partial").sum()),
                    "fail": int((unpred["verdict"] == "fail").sum())}},
            "pass_rate_predicted": pass_rate_pred,
            "pass_rate_unpredicted": pass_rate_unpred,
            "transfer_gate_rate_ok": bool(pass_rate_pred >= 0.80) if np.isfinite(pass_rate_pred) else None,
            "z": z, "p_one_sided": p_val,
            "transfer_gate_significant": bool(p_val < 0.05) if np.isfinite(p_val) else None,
        })
    (out_dir / "g2_summary.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
