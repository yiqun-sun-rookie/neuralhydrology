"""G1 precheck: bank construction + feasibility + identifiability prediction (prereg v01).

Per basin (all 531, no NSE filter — decision A):
  1. Build the 3-member parFC bank from the rising-kernel calibration table.
  2. sigma_obs = max(0.10 * median(real obs discharge in window), 0.02) mm/d.
  3. Discharge footprint D for each of the 3 candidate pairs: deterministic
     simulations from the stored calibration-final state over the FIRST 180
     days of the window, D = mean |dQ|; r = D / sigma_obs; r_min = min over
     pairs (the hardest pair governs identifiability).
  4. T_lik = ln(19) / (r_min^2 / 2)  (Gaussian equal-variance approximation).
  5. Prediction label (draft thresholds, frozen later): identifiable iff
     r_min >= 2.0 and T_lik <= 30.
  6. Truth feasibility: 7 stages x 180 d, rotation 1-2-3-1-3-2-1 (all 6
     directed switches once), states inherited across boundaries, daily
     MULTIPLICATIVE lognormal process noise on SLZ only
     (SLZ *= exp(N(-sigma^2/2, sigma)), sigma = 0.02), 2 preregistered noise
     realizations. Zero clipping holds by construction; the gate degenerates
     to finite-state + min-SLZ bookkeeping (G1 amendment from the additive
     draft, which clipped on the first smoke basins).

No filter runs in G1. Usage:
    python -X utf8 -m src.camels_switch_confirmation.g1_precheck --workers 6
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

# ---- preregistered constants (draft values; frozen at freeze step) ----
WINDOW_START = "1989-10-01"
STAGE_DAYS = 180
ROTATION = (0, 1, 2, 0, 2, 1, 0)          # 7 stages -> all 6 directed switches
WINDOW_DAYS = STAGE_DAYS * len(ROTATION)   # 1260
LAG_KERNEL = "rising"
BOUNDS_PRESET = "v5"
SIGMA_OBS_FRACTION = 0.10
SIGMA_OBS_FLOOR = 0.02
SLZ_LOGNORMAL_SIGMA = 0.02   # multiplicative: SLZ *= exp(N(-s^2/2, s)), mean-preserving,
                             # strictly positive -> zero clipping BY CONSTRUCTION.
                             # (G1 amendment: the v01 additive-Gaussian draft produced
                             # clipping on the very first smoke basins; recorded in prereg.)
N_SEEDS = 2
SEED_ENTROPY = 20260807                    # preregistered
R_MIN_THRESHOLD = 2.0
T_LIK_MAX_DAYS = 30.0
FOOTPRINT_DAYS = 180

STATE_NAMES = ("SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ")
PARAM_KEYS = ("parTT", "parCFMAX", "parCFR", "parCWH", "parFC", "parBETA",
              "parLP", "parK0", "parK1", "parUZL", "parPERC", "parK2",
              "lag_time")

RISING_TABLE = ("results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01"
                "/summary/hbv_lite_cma_rising_local_full.csv")
OUT_DIR = "results/23_camels_switch_confirmation/g1_precheck_v01"


def _window_end() -> str:
    return (pd.Timestamp(WINDOW_START)
            + pd.Timedelta(days=WINDOW_DAYS - 1)).strftime("%Y-%m-%d")


def _run_one(args_tuple):
    (basin_id, data_root, row) = args_tuple
    import sys as _sys
    if str(_REPO_ROOT / "src") not in _sys.path:
        _sys.path.insert(0, str(_REPO_ROOT / "src"))
    from hydroagent.data_loading import load_camels_basin
    from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds, simulate_hbv_lite
    from camels_switch_confirmation.bank import build_bank

    t0 = time.time()
    try:
        params = {k: float(row[f"p_{k}"]) for k in PARAM_KEYS}
        init_state = {s: float(row[f"state_{s}"]) for s in STATE_NAMES}

        members, clipped = build_bank(params, resolve_hbv_bounds(BOUNDS_PRESET)["parFC"])

        forcing, obs, _ = load_camels_basin(
            basin_id, data_root=data_root,
            start_date=WINDOW_START, end_date=_window_end(),
            forcing="maurer", pet_method="oudin", keep_obs_nan_days=True,
        )
        rain = forcing["prcp"].values.astype(np.float64)
        pet_col = "ep" if "ep" in forcing.columns else "pet"
        pet = forcing[pet_col].values.astype(np.float64)
        temp = (forcing["tmean"].values.astype(np.float64)
                if "tmean" in forcing.columns else np.zeros_like(rain))
        n_days = len(rain)

        obs_arr = obs.values.astype(np.float64)
        finite = obs_arr[np.isfinite(obs_arr)]
        obs_median = float(np.median(finite)) if len(finite) else float("nan")
        sigma_obs = max(SIGMA_OBS_FRACTION * obs_median, SIGMA_OBS_FLOOR) \
            if np.isfinite(obs_median) else SIGMA_OBS_FLOOR

        # -- footprints: deterministic sims from the SAME stored init state --
        fp_days = min(FOOTPRINT_DAYS, n_days)
        sims = []
        for m in members:
            q, _ = simulate_hbv_lite(rain[:fp_days], pet[:fp_days], temp[:fp_days],
                                     m, initial_state=init_state, lag_kernel=LAG_KERNEL)
            sims.append(q)
        d12 = float(np.mean(np.abs(sims[0] - sims[1])))
        d23 = float(np.mean(np.abs(sims[1] - sims[2])))
        d13 = float(np.mean(np.abs(sims[0] - sims[2])))
        r_pairs = [d / sigma_obs for d in (d12, d23, d13)]
        r_min = float(min(r_pairs))
        t_lik = float(np.log(19.0) / (r_min ** 2 / 2.0)) if r_min > 0 else float("inf")
        predicted = bool(r_min >= R_MIN_THRESHOLD and t_lik <= T_LIK_MAX_DAYS)

        # -- truth feasibility: stagewise noisy generation, SLZ-only noise --
        slz_sigma = SLZ_LOGNORMAL_SIGMA
        clip_counts, min_slz = [], []
        for k in range(N_SEEDS):
            rng = np.random.default_rng(
                np.random.SeedSequence((SEED_ENTROPY, int(basin_id), k)))
            state = dict(init_state)
            clips = 0
            lo_slz = state["SLZ"]
            day = 0
            for stage_idx in ROTATION:
                m = members[stage_idx]
                for _ in range(STAGE_DAYS):
                    if day >= n_days:
                        break
                    _, state = simulate_hbv_lite(
                        rain[day:day + 1], pet[day:day + 1], temp[day:day + 1],
                        m, initial_state=state, lag_kernel=LAG_KERNEL)
                    noisy = state["SLZ"] * np.exp(
                        rng.normal(-0.5 * slz_sigma ** 2, slz_sigma))
                    if not np.isfinite(noisy) or noisy < 0.0:
                        clips += 1
                        noisy = max(noisy, 0.0) if np.isfinite(noisy) else 0.0
                    state["SLZ"] = noisy
                    lo_slz = min(lo_slz, noisy)
                    day += 1
            clip_counts.append(clips)
            min_slz.append(lo_slz)

        return {
            "basin_id": basin_id, "run_status": "success", "error_message": "",
            "nse_calibration_table": float(row["nse"]),
            "fc_member1": members[0]["parFC"], "fc_member2": members[1]["parFC"],
            "fc_member3": members[2]["parFC"],
            "fc_clipped_any": bool(any(clipped)),
            "sigma_obs": sigma_obs, "obs_median": obs_median,
            "footprint_12": d12, "footprint_23": d23, "footprint_13": d13,
            "r_12": r_pairs[0], "r_23": r_pairs[1], "r_13": r_pairs[2],
            "r_min": r_min, "t_lik_days": t_lik,
            "predicted_identifiable": predicted,
            "slz_sigma": slz_sigma,
            "clip_count_seed0": clip_counts[0], "clip_count_seed1": clip_counts[1],
            "min_slz_seed0": min_slz[0], "min_slz_seed1": min_slz[1],
            "feasible_zero_clipping": bool(sum(clip_counts) == 0),
            "n_forcing_days": n_days,
            "_elapsed_s": round(time.time() - t0, 2),
        }
    except Exception as exc:  # noqa: BLE001
        return {"basin_id": basin_id, "run_status": "failed",
                "error_message": str(exc),
                "_elapsed_s": round(time.time() - t0, 2)}


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--data-root", default="data/camels_us")
    p.add_argument("--workers", type=int, default=6)
    p.add_argument("--limit", type=int, default=None)
    args = p.parse_args(argv)

    table = pd.read_csv(_REPO_ROOT / RISING_TABLE, dtype={"basin_id": str})
    table["basin_id"] = table["basin_id"].str.zfill(8)
    rows = table.to_dict("records")
    if args.limit:
        rows = rows[: args.limit]

    out_dir = _REPO_ROOT / OUT_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"[{time.strftime('%H:%M:%S')}] G1 precheck: {len(rows)} basins, "
          f"window {WINDOW_START} +{WINDOW_DAYS}d, kernel={LAG_KERNEL}")
    work = [(r["basin_id"], args.data_root, r) for r in rows]
    results = []
    t_start = time.time()
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(_run_one, w): w[0] for w in work}
        for i, fut in enumerate(as_completed(futures), start=1):
            try:
                res = fut.result()
            except Exception as exc:  # noqa: BLE001
                res = {"basin_id": futures[fut], "run_status": "failed",
                       "error_message": f"worker exception: {exc}"}
            results.append(res)
            if i % 50 == 0 or i == len(work):
                print(f"[{time.strftime('%H:%M:%S')}] {i}/{len(work)} "
                      f"wall={(time.time() - t_start) / 60:.1f}min", flush=True)

    df = pd.DataFrame(results).sort_values("basin_id").reset_index(drop=True)
    csv_path = out_dir / "g1_precheck.csv"
    df.to_csv(csv_path, index=False)

    ok = df[df["run_status"] == "success"]
    meta = {
        "prereg": "docs/plans/2026-08-07-camels-large-sample-parameter-switch-"
                  "confirmation-prereg-v01.md",
        "table": RISING_TABLE, "lag_kernel": LAG_KERNEL,
        "window_start": WINDOW_START, "stage_days": STAGE_DAYS,
        "rotation": list(ROTATION), "window_days": WINDOW_DAYS,
        "sigma_obs_fraction": SIGMA_OBS_FRACTION, "sigma_obs_floor": SIGMA_OBS_FLOOR,
        "slz_lognormal_sigma": SLZ_LOGNORMAL_SIGMA,
        "n_seeds": N_SEEDS, "seed_entropy": SEED_ENTROPY,
        "r_min_threshold_draft": R_MIN_THRESHOLD, "t_lik_max_days_draft": T_LIK_MAX_DAYS,
        "footprint_days": FOOTPRINT_DAYS,
        "n_basins": len(df), "n_success": int(len(ok)),
        "n_failed": int((df["run_status"] == "failed").sum()),
        "wall_clock_s": round(time.time() - t_start, 1),
    }
    if len(ok):
        meta.update({
            "n_predicted_identifiable": int(ok["predicted_identifiable"].sum()),
            "n_feasible_zero_clipping": int(ok["feasible_zero_clipping"].sum()),
            "n_fc_clipped_any": int(ok["fc_clipped_any"].sum()),
            "r_min_median": float(ok["r_min"].median()),
            "r_min_p05": float(ok["r_min"].quantile(0.05)),
            "r_min_p95": float(ok["r_min"].quantile(0.95)),
            "total_clip_events": int(ok["clip_count_seed0"].sum()
                                     + ok["clip_count_seed1"].sum()),
        })
    (out_dir / "g1_precheck.metadata.json").write_text(
        json.dumps(meta, indent=2), encoding="utf-8")

    print(json.dumps({k: meta[k] for k in meta
                      if k.startswith(("n_", "r_min", "total"))}, indent=2))
    print(f"CSV: {csv_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
