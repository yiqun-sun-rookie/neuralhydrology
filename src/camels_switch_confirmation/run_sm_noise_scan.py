"""Single-basin scan: soil-moisture process noise added to the 03C filter.

Diagnostic sweep motivated by the completed stubborn-basin diagnosis: every
remaining 03C catastrophic task shows positive soil-moisture (SM) corruption
with collapsed variance under the zero-SM-process-noise channel.  Each scan
variant adds one SM process-variance term on top of the registered 03C
state-proportional SLZ covariance; everything else is unchanged.  Tasks are
the eight afflicted arm-specific cases plus two healthy controls.
"""

from __future__ import annotations

import json
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np

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

ROOT_03C = Path(
    r"G:\wt\camels-rising\results\23_camels_switch_confirmation"
    r"\camels_parfc_transition_path_03c_design90_propq_s01_20260814_local"
)
OUTPUT_ROOT = Path(
    r"G:\wt\camels-rising\results\23_camels_switch_confirmation"
    r"\camels_parfc_sm_noise_scan_02_rain_20260814_local"
)
PARAMETER_TABLE = Path(
    r"G:\wt\camels-rising\results\10_global_conceptual_model_benchmark"
    r"\camels_us_531_repro_v01\summary\hbv_lite_cma_rising_local_full.csv"
)
TASKS = (
    ("03049800", 1, "P", "afflicted"),
    ("02430085", 1, "P", "afflicted"),
    ("02221525", 1, "P", "afflicted"),
    ("02193340", 1, "P", "afflicted"),
    ("07145700", 0, "P", "afflicted"),
    ("07145700", 1, "P", "afflicted"),
    ("02096846", 0, "C", "afflicted"),
    ("02096846", 1, "C", "afflicted"),
    ("07184000", 0, "P", "control"),
    ("07184000", 1, "P", "control"),
)
VARIANTS = {
    "sm_rain_0p05": ("rain", 0.05),
    "sm_rain_0p1": ("rain", 0.1),
    "sm_rain_0p2": ("rain", 0.2),
    "sm_rain_0p4": ("rain", 0.4),
}
ARM_MODES = {"C": "full", "P": "pairwise_path_postcollapse"}
SEVERE_NLL = 100.0


def _run_task(args):
    basin, seed, arm, role, variant = args
    kind, value = VARIANTS[variant]
    with np.load(
        ROOT_03C / "arms" / arm / "probs" / f"{basin}_s{seed}.npz",
        allow_pickle=False,
    ) as archive:
        names = [str(x) for x in archive["candidate_parameter_names"]]
        members = [
            {n: float(v) for n, v in zip(names, row)}
            for row in archive["candidate_parameter_vectors"]
        ]
        rain = archive["rain"].copy()
        pet = archive["pet"].copy()
        temp = archive["temperature"].copy()
        obs = archive["observations"].copy()
        tci = archive["true_candidate_indices"].astype(int).copy()
        base_p = archive["probabilities"].copy()
        base_lp = archive["log_probabilities"].copy()
        switch_days = archive["switch_days"].astype(int).copy()
        rotation = archive["rotation"].astype(int).copy()
        sigma = float(archive["observation_sigma"].item())
    import pandas as pd

    params = pd.read_csv(PARAMETER_TABLE, dtype={"basin_id": str})
    params["basin_id"] = params["basin_id"].str.zfill(8)
    row = params[params["basin_id"] == basin].iloc[0]
    initial = np.array(
        [float(row[f"state_{s}"]) for s in ("SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ")]
    )
    estimator, transitions = _build_bank(
        members,
        initial,
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
        if kind == "fixed":
            common_q[2, 2] = value
        elif kind == "proportional":
            common_q[2, 2] = (value * max(float(reference[2]), 0.0)) ** 2
        elif kind == "rain":
            common_q[2, 2] = (value * max(float(rain[day]), 0.0)) ** 2
        else:
            raise ValueError(f"unknown SM noise kind: {kind}")
        assign_common_process_covariance(estimator, common_q)
        result = estimator.step(np.array([obs[day]]))
        probabilities[day] = result.posterior_probabilities
        log_probabilities[day] = result.posterior_log_probabilities

    def metrics(p, lp):
        row_index = np.arange(n_days)
        true_p = p[row_index, tci]
        true_nll = -lp[row_index, tci]
        onehot = np.eye(3)[tci]
        pairs = list(zip(switch_days.tolist(), rotation[1:].tolist()))
        return {
            "zero_days": int(np.sum(true_p == 0.0)),
            "severe_days": int(np.sum(true_nll > SEVERE_NLL)),
            "nll": float(np.mean(true_nll)),
            "brier": float(np.mean(np.sum((p - onehot) ** 2, axis=1))),
            "events_w30": int(
                sum(e["passed"] for e in _evaluate_events_window(p, pairs, 30))
            ),
            "events_w90": int(
                sum(e["passed"] for e in _evaluate_events_window(p, pairs, 90))
            ),
        }

    record = {
        "basin_id": basin,
        "seed": seed,
        "arm": arm,
        "role": role,
        "variant": variant,
        "new": metrics(probabilities, log_probabilities),
        "baseline_03c": metrics(base_p, base_lp),
    }
    task_dir = OUTPUT_ROOT / variant
    task_dir.mkdir(parents=True, exist_ok=True)
    _atomic_save_npz(
        task_dir / f"{basin}_s{seed}_{arm}.npz",
        probabilities=probabilities,
        log_probabilities=log_probabilities,
        true_candidate_indices=tci,
        basin_id=np.array(basin),
        seed=np.array(seed, dtype=np.int64),
        arm_id=np.array(arm),
        variant=np.array(variant),
        sm_noise_kind=np.array(kind),
        sm_noise_value=np.array(value, dtype=np.float64),
    )
    return record


def main() -> None:
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=False)
    work = [
        (basin, seed, arm, role, variant)
        for variant in VARIANTS
        for basin, seed, arm, role in TASKS
    ]
    with ProcessPoolExecutor(max_workers=10) as pool:
        records = list(pool.map(_run_task, work))
    with (OUTPUT_ROOT / "scan_summary.json").open("x", encoding="utf-8") as handle:
        json.dump(records, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(json.dumps(records, ensure_ascii=False))


if __name__ == "__main__":
    main()
