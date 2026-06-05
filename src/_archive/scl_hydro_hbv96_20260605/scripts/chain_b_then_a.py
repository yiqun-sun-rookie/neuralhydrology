"""Chain runner: Step B (debug humid basin 11481200) → Step A (full 531).

Step B: Extended-config single-basin calibration on basin 11481200.
        n_epochs=300, n_restarts=5, lr=0.02, n_substep=2.
        ~100 min in foreground (1 process, 1 thread).
        Used to verify whether the sanity-3 humid underperformance
        (NSE_eval=0.26) was an Adam convergence issue (improvable
        with more iterations) vs structural.

Step A: If step-B eval NSE exceeds B_PASS_THRESHOLD, automatically
        launch the 531-basin repro_v01 runner with the configured
        budget (default 6 workers, BelowNormal priority on Windows).

Resource posture (per user request 2026-05-28):
    - Step B: 1 process, 1 thread (~3% CPU).
    - Step A: 6 workers × 1 thread each = 6 of 32 logical cores
              (≈ 19% CPU footprint); 26 threads free for foreground work.

Usage::

    python -X utf8 -m src.scl_hydro.scripts.chain_b_then_a
"""
from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

# Force single-threaded numerics inside *this* process for step B.
for _var in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS",
             "NUMEXPR_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_var, "1")

_HERE = Path(__file__).resolve()
_REPO_ROOT = _HERE.parents[3]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

import numpy as np  # noqa: E402
import torch        # noqa: E402

torch.set_num_threads(1)

from src.hydroagent.data_loading import load_camels_basin           # noqa: E402
from src.scl_hydro.hbv96_p1_calibrate import (                       # noqa: E402
    calibrate_hbv96_p1,
    simulate_hbv96_p1,
)


# ---- Step B config (single-basin Adam convergence test) ----
B_BASIN = "11481200"   # humid basin where sanity 3 stalled at 0.26
B_CAL_START, B_CAL_END = "1999-10-01", "2008-09-30"
B_EVAL_START, B_EVAL_END = "1989-10-01", "1999-09-30"
B_FORCING = "maurer"
B_N_EPOCHS = 300
B_N_RESTARTS = 5
B_LR = 0.02
B_N_SUBSTEP = 2

# ---- Pass / fail threshold for step B → step A gating ----
# Sanity 3 produced NSE_eval=0.264 on this basin with 120 epoch × 3 restart.
# 0.40 is a modest improvement target — if 300×5 cannot reach 0.40 the
# problem is likely structural, not convergence, and we should not waste
# 60+ hours on a full 531 run that won't help humid basins.
B_PASS_THRESHOLD = 0.40

# ---- Step A config (will be passed as CLI flags to the 531 runner) ----
A_WORKERS = 6
A_EPOCHS = 200
A_RESTARTS = 3
A_LR = 0.02
A_N_SUBSTEP = 2


def _nse(obs: np.ndarray, sim: np.ndarray) -> float:
    mask = np.isfinite(obs) & np.isfinite(sim)
    if mask.sum() < 10:
        return float("nan")
    o = obs[mask]
    s = sim[mask]
    denom = ((o - o.mean()) ** 2).sum()
    if denom < 1e-12:
        return float("nan")
    return float(1.0 - ((o - s) ** 2).sum() / denom)


def step_b() -> tuple[float, float, float]:
    """Run extended-config calibration on B_BASIN. Returns (nse_cal, nse_eval, elapsed_s)."""
    t0 = time.time()

    fc_cal, oc_cal, _ = load_camels_basin(
        B_BASIN, start_date=B_CAL_START, end_date=B_CAL_END, forcing=B_FORCING,
    )
    rain_c = fc_cal["prcp"].values.astype(np.float64)
    pet_c  = fc_cal["ep"].values.astype(np.float64)
    temp_c = fc_cal["tmean"].values.astype(np.float64)
    obs_c  = oc_cal.values.astype(np.float64)

    print(f"[step B] basin={B_BASIN}  config: epochs={B_N_EPOCHS}, restarts={B_N_RESTARTS}, "
          f"lr={B_LR}, n_substep={B_N_SUBSTEP}", flush=True)
    print(f"[step B] cal data: T={len(rain_c)} days, "
          f"rain_mean={rain_c.mean():.2f}, pet_mean={pet_c.mean():.2f}, "
          f"obs_mean={obs_c.mean():.2f}", flush=True)

    result = calibrate_hbv96_p1(
        rain_c, pet_c, temp_c, obs_c,
        n_epochs=B_N_EPOCHS, lr=B_LR, n_restarts=B_N_RESTARTS, n_substep=B_N_SUBSTEP,
    )
    nse_cal = float(result["nse"])
    elapsed_cal = time.time() - t0
    print(f"[step B] calibration done in {elapsed_cal:.0f}s: NSE_cal={nse_cal:+.3f}", flush=True)
    print(f"[step B] params={result['optimized_params']}", flush=True)

    # Evaluation
    fc_e, oc_e, _ = load_camels_basin(
        B_BASIN, start_date=B_EVAL_START, end_date=B_EVAL_END, forcing=B_FORCING,
    )
    rain_e = fc_e["prcp"].values.astype(np.float64)
    pet_e  = fc_e["ep"].values.astype(np.float64)
    temp_e = fc_e["tmean"].values.astype(np.float64)
    obs_e  = oc_e.values.astype(np.float64)

    q_eval, _ = simulate_hbv96_p1(
        rain_e, pet_e, temp_e,
        result["optimized_params"],
        state_init=result["final_state"],
        n_substep=B_N_SUBSTEP,
    )
    warmup = 365
    nse_eval = _nse(obs_e[warmup:], q_eval[warmup:])
    elapsed_total = time.time() - t0
    print(f"[step B] eval NSE = {nse_eval:+.3f}  (vs sanity-3 baseline 0.264; "
          f"vs XAJ-PDD broken-PET baseline 0.757)", flush=True)
    print(f"[step B] total elapsed = {elapsed_total:.0f}s "
          f"({elapsed_total/60:.1f} min)", flush=True)
    return nse_cal, nse_eval, elapsed_total


def step_a() -> int:
    """Launch the 531-basin runner as a subprocess with BelowNormal priority on Windows."""
    print("[step A] launching 531-basin runner...", flush=True)
    print(f"[step A] config: workers={A_WORKERS}, epochs={A_EPOCHS}, "
          f"restarts={A_RESTARTS}, lr={A_LR}, n_substep={A_N_SUBSTEP}", flush=True)

    cmd = [
        sys.executable, "-X", "utf8",
        "-m", "src.scl_hydro.scripts.run_hbv96_p1_repro_v01",
        "--workers", str(A_WORKERS),
        "--epochs", str(A_EPOCHS),
        "--restarts", str(A_RESTARTS),
        "--lr", str(A_LR),
        "--n-substep", str(A_N_SUBSTEP),
    ]

    # Inherit env (already has OMP/MKL=1 from this script's top-level setdefault).
    env = os.environ.copy()
    creationflags = 0
    if sys.platform == "win32":
        # BELOW_NORMAL_PRIORITY_CLASS = 0x00004000
        creationflags = 0x00004000

    print(f"[step A] cmd = {' '.join(cmd)}", flush=True)
    # Execute in foreground of THIS process — i.e. inherit our stdout —
    # so the launching task's output file captures the full A log.
    rc = subprocess.call(cmd, env=env, creationflags=creationflags)
    print(f"[step A] subprocess exited with rc={rc}", flush=True)
    return rc


def main() -> int:
    print(f"[chain] starting B → A chain at {time.strftime('%Y-%m-%d %H:%M:%S')}", flush=True)
    print(f"[chain] working dir = {os.getcwd()}", flush=True)

    nse_cal, nse_eval, elapsed = step_b()

    print()
    print(f"[chain] step B summary: NSE_cal={nse_cal:+.3f}, NSE_eval={nse_eval:+.3f}, "
          f"{elapsed/60:.1f} min", flush=True)

    if not np.isfinite(nse_eval) or nse_eval < B_PASS_THRESHOLD:
        print(f"[chain] step B FAILED gate (NSE_eval {nse_eval:.3f} < threshold {B_PASS_THRESHOLD})",
              flush=True)
        print("[chain] aborting — step A not launched.", flush=True)
        print("[chain] decide next: try more epochs/restarts, change lr schedule, or "
              "investigate structural issue on humid basins.", flush=True)
        return 2

    print(f"[chain] step B PASSED gate (NSE_eval {nse_eval:.3f} ≥ {B_PASS_THRESHOLD})", flush=True)
    print("[chain] launching step A (full 531-basin run)...", flush=True)
    print()

    return step_a()


if __name__ == "__main__":
    raise SystemExit(main())
