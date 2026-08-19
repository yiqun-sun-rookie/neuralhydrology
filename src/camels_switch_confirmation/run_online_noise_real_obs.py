"""Stage-3: A2f99 online noise estimation on REAL CAMELS observations (preregistered).

Preregistration: docs/plans/2026-08-18-online-noise-stage3-camels-real-observation-prereg-v01.md

The single changed variable versus stage 2 is the observation source: real
gauged discharge replaces synthetic truth-plus-noise.  Everything else is
inherited bit-for-bit: candidate bank (parFC x1/x0.5/x2), maurer+Oudin forcing
over the frozen 1260-day window, sigma_obs from the frozen G1 precheck, filter
construction, arms C/P, and the frozen A2f99 estimator (15-cell grid,
lambda=0.99, uniform prior).

There is NO truth on real data, so no truth-derived field may appear in any
output (enforced by _load_cell_npz), and no identification-correctness claim
is evaluated.  The claims are carried by R1 (robust operation), R2 (one-step
forecast skill vs the degenerate control), R3 (consistency, descriptive only).

Control arm (CTRL, amendment 01b): a true SINGLE-member bank holding only the
center candidate.  The original triplet control (three identical copies) was
retired after its "posterior stays uniform" identity was proven false: the
interact-mix dot product sums in a different order for the third destination
(1 ulp), and 1260 days of thresholded dynamics amplified that to O(1) posterior
collapse in 46/52 basins.  With one member the mixing step has a single addend
(bitwise exact), the posterior is structurally identical to 1, and the mixture
forecast IS the single calibrated model's filter forecast -- which is what the
preregistration declared the control should measure.

Subcommands: precheck | run | summarize.  ``run`` skips already-saved outputs.
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

from camels_switch_confirmation.bank import build_bank  # noqa: E402
from camels_switch_confirmation.g1_precheck import (  # noqa: E402
    LAG_KERNEL,
    PARAM_KEYS,
    STATE_NAMES,
    WINDOW_START,
    _window_end,
)
from camels_switch_confirmation.g2_switch_confirmation import (  # noqa: E402
    _atomic_save_npz,
)
from camels_switch_confirmation.run_online_noise_pilot import (  # noqa: E402
    BMA_FORGET,
    PARAMETER_TABLE,
    RESULTS,
    ROOT_03C,
    _common_q,
    _make_estimator,
    _marginal_log_likelihood,
    bma_log_weights,
    cell_tag,
    combine_log_posteriors,
    grid_cells,
)

EXPERIMENT_ID = "CAMELS_ONLINE_NOISE_REAL_OBS_STAGE3_01"
PREREGISTRATION = (
    "docs/plans/2026-08-18-online-noise-stage3-camels-real-observation-prereg-v01.md"
)
OUTPUT_ROOT = RESULTS / "online_noise_real_obs_stage3_01_20260818_local"
G1_CSV = RESULTS / "g1_precheck_v01" / "g1_precheck.csv"
PILOT_BASINS = frozenset({"03049800", "02193340", "07145700", "07184000"})
ARMS = ("C", "P", "CTRL")
MAIN_ARMS = ("C", "P")
ADMISSION_NSE_MIN = 0.3
LOCKIN_PROB = 0.999
LOCKIN_RELEASE = 0.99
LOCKIN_DAYS = 300
BOUNDARY_M = 10.0
BOUNDARY_C = 0.4
BOUNDARY_WEIGHT_MAX = 0.5
R1_PASS_FRACTION = 0.8
STRATA_EDGES = (1.0, 2.0, 3.0)
PERMUTATION_SEED = 20260818  # numerical method for the sign-flip p only, disclosed
PERMUTATIONS = 20000
TRUTH_KEYS = frozenset(
    {"true_candidate_indices", "truth_parfc", "switch_days", "rotation",
     "source_03c_task"}
)
WORKERS = 10


# --------------------------------------------------------------------------
# shared loading helpers (no filter involved)
# --------------------------------------------------------------------------

def design90_basins() -> list:
    frame = pd.read_csv(
        ROOT_03C / "verification" / "task_metrics.csv", dtype={"basin_id": str}
    )
    basins = sorted(set(frame["basin_id"]))
    if len(basins) != 90:
        raise ValueError("expected 90 design basins from 03C task metrics")
    return basins


def _calibration_row(basin: str) -> pd.Series:
    table = pd.read_csv(PARAMETER_TABLE, dtype={"basin_id": str})
    table["basin_id"] = table["basin_id"].str.zfill(8)
    match = table[table["basin_id"] == basin]
    if len(match) != 1:
        raise ValueError(f"expected one calibration row for basin {basin}")
    return match.iloc[0]


def _g1_frame() -> pd.DataFrame:
    frame = pd.read_csv(G1_CSV, dtype={"basin_id": str})
    frame["basin_id"] = frame["basin_id"].str.zfill(8)
    return frame.set_index("basin_id")


def _load_real_forcing_and_obs(basin: str):
    from hydroagent.data_loading import load_camels_basin

    forcing, obs, _ = load_camels_basin(
        basin,
        data_root="data/camels_us",
        start_date=WINDOW_START,
        end_date=_window_end(),
        forcing="maurer",
        pet_method="oudin",
        keep_obs_nan_days=True,
    )
    rain = forcing["prcp"].values.astype(np.float64)
    pet_col = "ep" if "ep" in forcing.columns else "pet"
    pet = forcing[pet_col].values.astype(np.float64)
    temp = (
        forcing["tmean"].values.astype(np.float64)
        if "tmean" in forcing.columns
        else np.zeros_like(rain)
    )
    observations = np.asarray(obs, dtype=np.float64)
    if len(rain) != 1260 or len(observations) != 1260:
        raise ValueError(f"basin {basin}: expected 1260 forcing/obs days")
    if not np.all(np.isfinite(observations)):
        raise ValueError(f"basin {basin}: real observations contain non-finite days")
    return rain, pet, temp, observations


CTRL_POSTERIOR_TOLERANCE = 1e-12  # structural identity, near-zero tolerance (01b)


def control_members(members: list) -> list:
    """Control bank (amendment 01b): exactly one member, the center candidate.

    A single member makes the interact-mixing step a one-addend product
    (bitwise exact) and the posterior structurally equal to 1 -- the triplet
    variant was retired because destination-dependent summation order (1 ulp)
    was chaos-amplified into posterior collapse.
    """
    return [dict(members[0])]


def assert_ctrl_posterior_exact(probabilities: np.ndarray) -> float:
    """Hard integrity gate: single-member posterior must equal one."""
    array = np.asarray(probabilities, dtype=np.float64)
    if array.ndim != 2 or array.shape[1] != 1:
        raise ValueError(
            f"control posterior must have shape (days, 1), got {array.shape}"
        )
    deviation = float(np.max(np.abs(array - 1.0)))
    if deviation > CTRL_POSTERIOR_TOLERANCE:
        raise ValueError(
            "control posterior deviates from the single-member identity: "
            f"max |p-1| = {deviation:.3e} > {CTRL_POSTERIOR_TOLERANCE:.0e}"
        )
    return deviation


def _load_real_task(basin: str, arm: str) -> dict:
    from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds

    row = _calibration_row(basin)
    params = {k: float(row[f"p_{k}"]) for k in PARAM_KEYS}
    members, _ = build_bank(params, resolve_hbv_bounds("v5")["parFC"])
    if arm == "CTRL":
        members = control_members(members)
    rain, pet, temp, observations = _load_real_forcing_and_obs(basin)
    sigma = float(_g1_frame().loc[basin, "sigma_obs"])
    return {
        "members": members,
        "rain": rain,
        "pet": pet,
        "temp": temp,
        "obs": observations,
        "sigma": sigma,
        "source": f"real_obs:{basin}:{WINDOW_START}:{_window_end()}",
    }


# --------------------------------------------------------------------------
# precheck (deterministic simulations only, frozen admission rule)
# --------------------------------------------------------------------------

def _precheck_one(basin: str) -> dict:
    from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds, simulate_hbv_lite

    row = _calibration_row(basin)
    params = {k: float(row[f"p_{k}"]) for k in PARAM_KEYS}
    init_state = {s: float(row[f"state_{s}"]) for s in STATE_NAMES}
    members, _ = build_bank(params, resolve_hbv_bounds("v5")["parFC"])
    rain, pet, temp, observations = _load_real_forcing_and_obs(basin)
    g1 = _g1_frame().loc[basin]
    sigma = float(g1["sigma_obs"])
    record = {
        "basin_id": basin,
        "sigma_obs": sigma,
        "r_min": float(g1["r_min"]),
        "predicted_identifiable": bool(g1["predicted_identifiable"]),
        "fc_clipped_any": bool(g1["fc_clipped_any"]),
        "obs_median": float(np.median(observations)),
    }
    denominator = float(np.sum((observations - observations.mean()) ** 2))
    maes = []
    nses = []
    for index, member in enumerate(members, start=1):
        simulated, _ = simulate_hbv_lite(
            rain, pet, temp, member, initial_state=init_state,
            lag_kernel=LAG_KERNEL,
        )
        simulated = np.asarray(simulated, dtype=np.float64)
        member_nse = 1.0 - float(np.sum((simulated - observations) ** 2)) / denominator
        member_mae = float(np.mean(np.abs(simulated - observations)))
        record[f"nse_m{index}"] = member_nse
        record[f"mae_m{index}"] = member_mae
        nses.append(member_nse)
        maes.append(member_mae)
    record["mae_center_over_sigma"] = maes[0] / sigma
    record["misfit_to_footprint"] = (
        (maes[0] / sigma) / record["r_min"] if record["r_min"] > 0 else np.inf
    )
    record["argbest_offline"] = int(np.argmax(nses)) + 1
    return record


def admission_mask(frame: pd.DataFrame) -> pd.Series:
    """Frozen admission rule: identifiable AND center-NSE floor AND not clipped."""
    return (
        frame["predicted_identifiable"].astype(bool)
        & (frame["nse_m1"] >= ADMISSION_NSE_MIN)
        & ~frame["fc_clipped_any"].astype(bool)
    )


def stratum_label(ratio: float) -> str:
    if ratio < STRATA_EDGES[0]:
        return "lt1"
    if ratio < STRATA_EDGES[1]:
        return "1to2"
    if ratio < STRATA_EDGES[2]:
        return "2to3"
    return "ge3"


def precheck() -> None:
    records = [_precheck_one(basin) for basin in design90_basins()]
    frame = pd.DataFrame(records)
    frame["admitted"] = admission_mask(frame)
    frame["stratum"] = frame["misfit_to_footprint"].map(stratum_label)
    out_dir = OUTPUT_ROOT / "precheck"
    out_dir.mkdir(parents=True, exist_ok=True)
    frame.to_csv(out_dir / "stage3_realdata_precheck.csv", index=False)
    frame[frame["admitted"]].to_csv(out_dir / "admission.csv", index=False)
    print(f"precheck: {len(frame)} basins, admitted {int(frame['admitted'].sum())}")


def admitted_frame() -> pd.DataFrame:
    path = OUTPUT_ROOT / "precheck" / "admission.csv"
    if not path.exists():
        raise FileNotFoundError("run the precheck subcommand first")
    return pd.read_csv(path, dtype={"basin_id": str})


# --------------------------------------------------------------------------
# filter runs
# --------------------------------------------------------------------------

def _make_real_estimator(task: dict, basin: str, arm: str):
    """C/P inherit the stage-1 construction; CTRL is full interaction."""
    effective = "C" if arm == "CTRL" else arm
    return _make_estimator(task, basin, effective)


def _run_cell(args):
    """One cell run; numerical crashes are recorded, not raised (amendment 01a)."""
    basin, arm, m, c = args
    try:
        return _run_cell_inner(basin, arm, m, c)
    except Exception as exc:  # noqa: BLE001 - amendment 01a rule 2
        return {"basin_id": basin, "arm_id": arm, "cell": cell_tag(m, c),
                "status": "failed", "skipped": False,
                "error": f"{type(exc).__name__}: {exc}"}


def _run_cell_inner(basin, arm, m, c):
    out_dir = OUTPUT_ROOT / "grid" / arm / cell_tag(m, c) / "probs"
    out_path = out_dir / f"{basin}.npz"
    if out_path.exists():
        return {"basin_id": basin, "arm_id": arm, "cell": cell_tag(m, c),
                "status": "success", "skipped": True}
    task = _load_real_task(basin, arm)
    estimator, transitions = _make_real_estimator(task, basin, arm)
    n_days = len(task["obs"])
    n_members = len(task["members"])  # 3 main arms, 1 control (amendment 01b)
    probabilities = np.empty((n_days, n_members))
    log_probabilities = np.empty((n_days, n_members))
    marginal = np.empty(n_days)
    forecast = np.empty(n_days)
    for day in range(n_days):
        for transition in transitions:
            transition.set_forcing(task["rain"][day], task["pet"][day], task["temp"][day])
        _common_q(estimator, transitions, task["rain"][day], m, c)
        result = estimator.step(np.array([task["obs"][day]]))
        probabilities[day] = result.posterior_probabilities
        log_probabilities[day] = result.posterior_log_probabilities
        marginal[day] = _marginal_log_likelihood(
            result, "C" if arm == "CTRL" else arm
        )
        forecast[day] = float(np.ravel(result.combined_prior_observation)[0])
    out_dir.mkdir(parents=True, exist_ok=True)
    _atomic_save_npz(
        out_path,
        probabilities=probabilities,
        log_probabilities=log_probabilities,
        marginal_log_likelihood=marginal,
        one_step_forecast=forecast,
        observations=task["obs"],
        basin_id=np.array(basin),
        arm_id=np.array(arm),
        grid_m=np.array(m, dtype=np.float64),
        grid_c=np.array(c, dtype=np.float64),
        window_start=np.array(WINDOW_START),
        source=np.array(task["source"]),
    )
    return {"basin_id": basin, "arm_id": arm, "cell": cell_tag(m, c),
            "status": "success", "skipped": False}


def run() -> None:
    basins = sorted(admitted_frame()["basin_id"])
    work = [
        (basin, arm, m, c)
        for (m, c) in grid_cells()
        for arm in ARMS
        for basin in basins
    ]
    with ProcessPoolExecutor(max_workers=WORKERS) as pool:
        records = list(pool.map(_run_cell, work, chunksize=4))
    failures = [r for r in records if r["status"] != "success"]
    out_dir = OUTPUT_ROOT / "verification"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "run_failures.json").write_text(
        json.dumps(failures, indent=1), encoding="utf-8"
    )
    print(f"run: {len(records)} cells, failures {len(failures)}")
    for failure in failures:
        print(f"  FAILED {failure['basin_id']} {failure['arm_id']} "
              f"{failure['cell']}: {failure['error']}")


# --------------------------------------------------------------------------
# summarize (R1 / R2 / R3, no truth anywhere)
# --------------------------------------------------------------------------

def _load_cell_npz(path: Path) -> dict:
    """Load one cell output; refuse any truth-derived field (stage-3 contract)."""
    with np.load(path, allow_pickle=False) as archive:
        present = TRUTH_KEYS & set(archive.files)
        if present:
            raise ValueError(
                f"truth-derived fields {sorted(present)} are forbidden in "
                f"stage-3 outputs: {path}"
            )
        return {name: archive[name].copy() for name in archive.files}


def forecast_log_weights(loglik: np.ndarray, forget) -> np.ndarray:
    """Causal one-step-ahead weights: day t uses evidence through day t-1 only."""
    posterior = bma_log_weights(loglik, forget)
    shifted = np.empty_like(posterior)
    shifted[:, 0] = -np.log(loglik.shape[0])
    shifted[:, 1:] = posterior[:, :-1]
    return shifted


def mixture_forecast(loglik: np.ndarray, forecasts: np.ndarray,
                     forget) -> np.ndarray:
    weights = np.exp(forecast_log_weights(loglik, forget))
    return np.sum(weights * forecasts, axis=0)


def nse(simulated: np.ndarray, observed: np.ndarray) -> float:
    observed = np.asarray(observed, dtype=np.float64)
    simulated = np.asarray(simulated, dtype=np.float64)
    return 1.0 - float(np.sum((simulated - observed) ** 2)) / float(
        np.sum((observed - observed.mean()) ** 2)
    )


def kge(simulated: np.ndarray, observed: np.ndarray) -> float:
    observed = np.asarray(observed, dtype=np.float64)
    simulated = np.asarray(simulated, dtype=np.float64)
    correlation = float(np.corrcoef(simulated, observed)[0, 1])
    alpha = float(simulated.std() / observed.std())
    beta = float(simulated.mean() / observed.mean())
    return 1.0 - float(
        np.sqrt((correlation - 1.0) ** 2 + (alpha - 1.0) ** 2 + (beta - 1.0) ** 2)
    )


def detect_lockin(probabilities: np.ndarray) -> bool:
    """Irreversible lock: >=LOCKIN_DAYS at >=LOCKIN_PROB then never below release.

    Because the lock run itself is above the release level, the whole locked
    stretch must live inside the terminal suffix where the series stays at or
    above LOCKIN_RELEASE; within that suffix we look for any LOCKIN_DAYS run
    at or above LOCKIN_PROB.
    """
    n_days = probabilities.shape[0]
    for candidate in range(probabilities.shape[1]):
        series = probabilities[:, candidate]
        above_release = series >= LOCKIN_RELEASE
        suffix_start = n_days
        for day in range(n_days - 1, -1, -1):
            if above_release[day]:
                suffix_start = day
            else:
                break
        if suffix_start > n_days - LOCKIN_DAYS:
            continue
        run = 0
        for value in series[suffix_start:]:
            run = run + 1 if value >= LOCKIN_PROB else 0
            if run >= LOCKIN_DAYS:
                return True
    return False


def boundary_cell_indices(cells: list) -> list:
    return [
        index for index, (m, c) in enumerate(cells)
        if m == BOUNDARY_M or c == BOUNDARY_C
    ]


def _sign_flip_p(differences: np.ndarray) -> float:
    """Deterministic-seed sign-flip permutation p for the mean paired difference."""
    rng = np.random.default_rng(PERMUTATION_SEED)
    observed = abs(float(differences.mean()))
    signs = rng.choice((-1.0, 1.0), size=(PERMUTATIONS, len(differences)))
    permuted = np.abs((signs * differences[None, :]).mean(axis=1))
    return float((np.sum(permuted >= observed - 1e-15) + 1) / (PERMUTATIONS + 1))


def _paired_block(diffs: pd.Series) -> dict:
    from scipy.stats import wilcoxon

    values = diffs.to_numpy(dtype=np.float64)
    values = values[np.isfinite(values)]  # crashed arms drop out of pairing (01a)
    if len(values) == 0:
        return {"n": 0, "improved": 0, "worse": 0, "median_diff": float("nan"),
                "mean_diff": float("nan"), "wilcoxon_p": float("nan"),
                "sign_flip_permutation_p": float("nan")}
    nonzero = values[values != 0.0]
    if len(nonzero) >= 5:
        wilcoxon_p = float(wilcoxon(nonzero).pvalue)
    else:
        wilcoxon_p = float("nan")
    return {
        "n": int(len(values)),
        "improved": int(np.sum(values > 0)),
        "worse": int(np.sum(values < 0)),
        "median_diff": float(np.median(values)),
        "mean_diff": float(values.mean()),
        "wilcoxon_p": wilcoxon_p,
        "sign_flip_permutation_p": _sign_flip_p(values),
    }


def _r2_verdict(block: dict) -> bool:
    return bool(
        block["median_diff"] > 0
        and block["wilcoxon_p"] < 0.05
        and block["sign_flip_permutation_p"] < 0.05
    )


def summarize() -> None:
    admitted = admitted_frame().set_index("basin_id")
    basins = sorted(admitted.index)
    cells = grid_cells()
    boundary = boundary_cell_indices(cells)
    rows = []
    for basin in basins:
        observations = None
        per_arm = {}
        for arm in ARMS:
            loglik, forecasts, log_posts = [], [], []
            complete = True
            ctrl_deviation = 0.0
            for (m, c) in cells:
                cell_path = (OUTPUT_ROOT / "grid" / arm / cell_tag(m, c)
                             / "probs" / f"{basin}.npz")
                if not cell_path.exists():
                    complete = False  # crashed cell (amendment 01a rule 3)
                    break
                data = _load_cell_npz(cell_path)
                if arm == "CTRL":  # structural identity gate (amendment 01b)
                    ctrl_deviation = max(
                        ctrl_deviation,
                        assert_ctrl_posterior_exact(data["probabilities"]),
                    )
                loglik.append(data["marginal_log_likelihood"])
                forecasts.append(data["one_step_forecast"])
                log_posts.append(data["log_probabilities"])
                observations = data["observations"]
            if not complete:
                per_arm[arm] = None
                continue
            loglik = np.asarray(loglik)
            forecasts = np.asarray(forecasts)
            log_posts = np.asarray(log_posts)
            log_weights = bma_log_weights(loglik, BMA_FORGET)
            mixed_log_posterior = combine_log_posteriors(log_weights, log_posts)
            with np.errstate(over="ignore"):
                mixed_posterior = np.exp(mixed_log_posterior)
            mixed_posterior /= mixed_posterior.sum(axis=1, keepdims=True)
            forecast = mixture_forecast(loglik, forecasts, BMA_FORGET)
            weights_mean = np.exp(log_weights).mean(axis=1)
            entropy = -np.sum(
                np.where(mixed_posterior > 0,
                         mixed_posterior * np.log(mixed_posterior), 0.0),
                axis=1,
            )
            mode = np.argmax(mixed_posterior, axis=1)
            flips = int(np.sum(mode[1:] != mode[:-1]))
            run_lengths = np.diff(
                np.concatenate(([0], np.flatnonzero(mode[1:] != mode[:-1]) + 1,
                                [len(mode)]))
            )
            per_arm[arm] = {
                "finite": bool(
                    np.all(np.isfinite(loglik)) and np.all(np.isfinite(forecast))
                    and np.all(np.isfinite(mixed_posterior))
                ),
                "lockin": detect_lockin(mixed_posterior),
                "boundary_weight": float(weights_mean[boundary].sum()),
                "nse": nse(forecast, observations),
                "kge": kge(forecast, observations),
                "mean_weighted_loglik": float(
                    (np.exp(log_weights) * loglik).sum(axis=0).mean()
                ),
                "entropy_median": float(np.median(entropy)),
                "mode_flips": flips,
                "longest_stable_days": int(run_lengths.max()),
                "timeavg_mode": int(np.argmax(mixed_posterior.mean(axis=0))) + 1,
                "ctrl_max_posterior_dev": (
                    ctrl_deviation if arm == "CTRL" else float("nan")
                ),
            }
        meta = admitted.loc[basin]
        ctrl = per_arm["CTRL"]
        for arm in ARMS:
            block = per_arm[arm]
            crashed = block is None
            nan = float("nan")
            pairable = (not crashed) and (ctrl is not None)
            rows.append({
                "basin_id": basin,
                "arm_id": arm,
                "pilot_basin": basin in PILOT_BASINS,
                "stratum": meta["stratum"],
                "misfit_to_footprint": float(meta["misfit_to_footprint"]),
                "argbest_offline": int(meta["argbest_offline"]),
                "crashed": crashed,
                "r1_finite": False if crashed else block["finite"],
                "r1_no_lockin": True if crashed else not block["lockin"],
                "r1_boundary_weight": nan if crashed else block["boundary_weight"],
                "r1_boundary_ok": (
                    True if crashed
                    else block["boundary_weight"] < BOUNDARY_WEIGHT_MAX
                ),
                "forecast_nse": nan if crashed else block["nse"],
                "forecast_kge": nan if crashed else block["kge"],
                "forecast_nse_ctrl": nan if ctrl is None else ctrl["nse"],
                "forecast_kge_ctrl": nan if ctrl is None else ctrl["kge"],
                "nse_diff_vs_ctrl": (
                    block["nse"] - ctrl["nse"] if pairable else nan
                ),
                "kge_diff_vs_ctrl": (
                    block["kge"] - ctrl["kge"] if pairable else nan
                ),
                "mean_weighted_loglik": nan if crashed else block["mean_weighted_loglik"],
                "entropy_median": nan if crashed else block["entropy_median"],
                "mode_flips": -1 if crashed else block["mode_flips"],
                "longest_stable_days": -1 if crashed else block["longest_stable_days"],
                "timeavg_mode": 0 if crashed else block["timeavg_mode"],
                "ctrl_max_posterior_dev": nan if crashed else block["ctrl_max_posterior_dev"],
            })
    metrics = pd.DataFrame(rows)
    out_dir = OUTPUT_ROOT / "verification"
    out_dir.mkdir(parents=True, exist_ok=True)
    metrics.to_csv(out_dir / "task_metrics.csv", index=False)

    summary = {
        "experiment_id": EXPERIMENT_ID,
        "preregistration": PREREGISTRATION,
        "n_admitted": len(basins),
        "claim_boundary": {
            "identification_correctness": "not_claimable_no_truth",
            "synthetic_s1_s2_transfer": "not_claimable",
            "claims": ["R1 robust operation", "R2 forecast skill vs control",
                       "R3 consistency (descriptive)"],
            "permutation_seed_note": (
                "sign-flip permutation uses fixed seed "
                f"{PERMUTATION_SEED}; numerical method only, no data randomness"
            ),
        },
        "gates": {},
        "R2": {},
        "R3": {},
        "control": {},
    }
    crashed_rows = metrics[metrics["crashed"]]
    summary["crashes"] = {
        "n_crashed_basin_arms": int(len(crashed_rows)),
        "list": crashed_rows[["basin_id", "arm_id"]].to_dict(orient="records"),
        "handling": "amendment 01a: crash = R1 numerical collapse, drops from R2 pairing",
    }
    for arm in MAIN_ARMS:
        arm_rows = metrics[metrics["arm_id"] == arm]
        r1_pass = (
            arm_rows["r1_finite"] & arm_rows["r1_no_lockin"]
            & arm_rows["r1_boundary_ok"]
        )
        saturated = arm_rows["r1_boundary_weight"] >= BOUNDARY_WEIGHT_MAX
        summary["gates"][arm] = {
            "n_crashed": int(arm_rows["crashed"].sum()),
            "r1_pass_fraction": float(r1_pass.mean()),
            "r1_passed": bool(r1_pass.mean() >= R1_PASS_FRACTION),
            "r1_finite_fraction": float(arm_rows["r1_finite"].mean()),
            "r1_no_lockin_fraction": float(arm_rows["r1_no_lockin"].mean()),
            "r1_boundary_ok_fraction": float(arm_rows["r1_boundary_ok"].mean()),
            "grid_saturation_majority": bool(saturated.mean() > 0.5),
        }
        r2_arm = {}
        for scope_name, scope_rows in (
            ("all", arm_rows),
            ("no_pilot", arm_rows[~arm_rows["pilot_basin"]]),
        ):
            for metric in ("nse", "kge"):
                block = _paired_block(scope_rows[f"{metric}_diff_vs_ctrl"])
                block["verdict"] = _r2_verdict(block)
                r2_arm[f"{scope_name}_{metric}"] = block
            r2_arm[f"{scope_name}_by_stratum"] = {
                stratum: _paired_block(group["nse_diff_vs_ctrl"])
                for stratum, group in scope_rows.groupby("stratum")
            }
        summary["R2"][arm] = r2_arm
        valid_rows = arm_rows[~arm_rows["crashed"]]
        confusion = pd.crosstab(
            valid_rows["timeavg_mode"], valid_rows["argbest_offline"]
        )
        summary["R3"][arm] = {
            "n_valid": int(len(valid_rows)),
            "mode_flips_median": float(valid_rows["mode_flips"].median()),
            "longest_stable_days_median": float(
                valid_rows["longest_stable_days"].median()
            ),
            "entropy_median_of_medians": float(
                valid_rows["entropy_median"].median()
            ),
            "timeavg_mode_vs_offline_best_agreement": float(
                (valid_rows["timeavg_mode"] == valid_rows["argbest_offline"]).mean()
            ),
            "confusion_timeavg_mode_rows_offline_cols": {
                str(row): {str(col): int(confusion.loc[row, col])
                           for col in confusion.columns}
                for row in confusion.index
            },
        }
    ctrl_rows = metrics[metrics["arm_id"] == "CTRL"]
    summary["control"] = {
        "design": "single-member center-candidate filter (amendment 01b)",
        "max_posterior_deviation_from_one": float(
            ctrl_rows["ctrl_max_posterior_dev"].max()
        ),
        "forecast_nse_median": float(ctrl_rows["forecast_nse"].median()),
        "forecast_kge_median": float(ctrl_rows["forecast_kge"].median()),
    }
    strata_records = metrics.groupby(["arm_id", "stratum"]).agg(
        n=("basin_id", "count"),
        nse_diff_median=("nse_diff_vs_ctrl", "median"),
        kge_diff_median=("kge_diff_vs_ctrl", "median"),
        forecast_nse_median=("forecast_nse", "median"),
    ).reset_index()
    (out_dir / "strata.json").write_text(
        json.dumps(strata_records.to_dict(orient="records"), indent=1),
        encoding="utf-8",
    )
    (out_dir / "verification_summary.json").write_text(
        json.dumps(summary, indent=1), encoding="utf-8"
    )
    print(json.dumps(summary["gates"], indent=1))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("precheck", "run", "summarize"))
    arguments = parser.parse_args()
    if arguments.command == "precheck":
        precheck()
    elif arguments.command == "run":
        run()
    else:
        summarize()


if __name__ == "__main__":
    main()
