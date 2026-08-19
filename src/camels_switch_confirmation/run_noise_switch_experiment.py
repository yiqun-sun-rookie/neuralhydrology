"""NOISE-X1: noise-switch identification experiment proper (switch + null control).

Preregistration: docs/plans/2026-08-19-noise-switch-experiment-prereg-v01.md
(frozen before any run; hash recorded there and in the run summary).

Three 15-state unscented filters share ONE calibrated parameter set and differ
ONLY in their assumed SLZ process-noise multiplier m in {1.0, 0.1, 10.0} --
the candidate hypothesis IS the noise level.  Truth rotates the injected noise
level through 7 stages of 180 days (all six directed switches); a null-control
scenario keeps the truth at m=1 for the whole window so that any sustained
detection of a wrong candidate is a false alarm attributable to the storage
random-walk confound diagnosed in NOISE-W1..W3 (open-loop only, hence this
closed-loop control).

The frozen filter stack (imm.py / sigma_filter.py / preflight.py) and the g2
machinery are imported, never modified.

Usage:
    python -X utf8 -m camels_switch_confirmation.run_noise_switch_experiment --run --workers 10
    python -X utf8 -m camels_switch_confirmation.run_noise_switch_experiment --summarize
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

for _variable in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS",
                  "NUMEXPR_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_variable, "1")

import numpy as np
import pandas as pd

_SRC = Path(__file__).resolve().parents[1]
if str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))

from camels_switch_confirmation.g1_precheck import (  # noqa: E402
    PARAM_KEYS,
    STATE_NAMES,
    WINDOW_START,
    _window_end,
)
from camels_switch_confirmation.g2_switch_confirmation import (  # noqa: E402
    CONSECUTIVE_DAYS,
    INITIAL_COVARIANCE_FRACTION,
    LAG_CAP,
    MARGIN_INCLUSIVE,
    N_HYDRO,
    N_STATE,
    PROB_THRESHOLD_EXCLUSIVE,
    TRANSITION_DIAGONAL,
    RisingRoutedObservation,
    _atomic_save_npz,
    build_state_dependent_lower_groundwater_covariance,
    rising_routed_discharge,
)
from camels_switch_confirmation.noise_switch_precheck import (  # noqa: E402
    NOISE_CANDIDATES,
    OUTPUT_ROOT as PRECHECK_ROOT,
    ROTATION,
    SEED_ENTROPY,
    STAGE_DAYS,
    WINDOW_DAYS,
    injection_sigma,
)
from camels_switch_confirmation.run_online_noise_pilot import (  # noqa: E402
    PARAMETER_TABLE,
    RESULTS,
)

PREREGISTRATION = ("docs/plans/2026-08-19-noise-switch-experiment-prereg-v01.md")
PREREGISTRATION_SHA256 = (
    "7ba7e3d0590b188dbdb9b0a844da63a90a3b27064bd4e59f7b8efc78889cb928")
OUTPUT_ROOT = RESULTS / "noise_switch_experiment_01_20260819_local"
ADMISSION_CSV = PRECHECK_ROOT / "admission.csv"
G1_CSV = RESULTS / "g1_precheck_v01" / "g1_precheck.csv"
DATA_ROOT = "data/camels_us"
BOUNDS_PRESET = "v5"

NULL_ROTATION = (0,) * len(ROTATION)
SCENARIOS = {"switch": ROTATION, "null": NULL_ROTATION}
ARM_MODES = {"C": "full", "P": "pairwise_path_postcollapse"}
SEEDS = (0, 1)
TRUE_NULL_INDEX = 0                     # null truth stays on candidate 0 (m=1)
TRUTH_STREAM_TAG = 10                   # distinct from precheck (E, basin, cell)
OBS_STREAM_TAG = 11
PRIMARY_WINDOW_DAYS = 90
SECONDARY_WINDOW_DAYS = 30
WORKERS = 10


def switch_events_from_rotation(rotation, stage_days=STAGE_DAYS,
                                n_days=WINDOW_DAYS):
    """(day, from_index, to_index) for every stage boundary that switches."""
    events = []
    for position in range(1, len(rotation)):
        day = position * stage_days
        if day >= n_days:
            break
        if rotation[position] != rotation[position - 1]:
            events.append((day, rotation[position - 1], rotation[position]))
    return events


def generate_truth(rotation, params, rain, pet, temp, init_hydro, rng, bounds,
                   stage_days=STAGE_DAYS):
    """Stepwise 15-state truth with stagewise SLZ noise level; one normal/day."""
    from hbv_joint_uncertainty.hbv_adapter import advance_state
    state = np.zeros(N_STATE, dtype=np.float64)
    state[:N_HYDRO] = init_hydro
    n_days = min(len(rain), len(rotation) * stage_days)
    truth_q = np.zeros(n_days, dtype=np.float64)
    truth_index = np.zeros(n_days, dtype=np.int64)
    clips = 0
    day = 0
    for stage_index in rotation:
        sigma = injection_sigma(NOISE_CANDIDATES[stage_index])
        for _ in range(stage_days):
            if day >= n_days:
                break
            truth_index[day] = stage_index
            state = advance_state(state, rain[day], pet[day], temp[day], params,
                                  bounds=bounds)
            noisy = state[4] * np.exp(rng.normal(-0.5 * sigma ** 2, sigma))
            if not np.isfinite(noisy) or noisy < 0.0:
                clips += 1
                noisy = max(noisy, 0.0) if np.isfinite(noisy) else 0.0
            state[4] = noisy
            truth_q[day] = rising_routed_discharge(state, params["lag_time"])
            day += 1
    return truth_q, truth_index, clips


def _sustained_rule(probabilities, candidate, start):
    """id23-verbatim 5-day rule for one candidate starting at one day."""
    segment = probabilities[start:start + CONSECUTIVE_DAYS]
    if segment.shape[0] < CONSECUTIVE_DAYS:
        return False
    winning = segment[:, candidate]
    rivals = np.delete(segment, candidate, axis=1).max(axis=1)
    return bool(np.all(winning > PROB_THRESHOLD_EXCLUSIVE)
                and np.all(winning - rivals >= MARGIN_INCLUSIVE))


def evaluate_switch_events(probabilities, events, window_days):
    """Per switch: pass iff a sustained run starts within the window."""
    outcomes = []
    n_days = probabilities.shape[0]
    for switch_day, from_index, to_index in events:
        window_end = min(switch_day + window_days, n_days)
        passed, start = False, None
        for candidate_start in range(switch_day,
                                     window_end - CONSECUTIVE_DAYS + 1):
            if _sustained_rule(probabilities, to_index, candidate_start):
                passed, start = True, candidate_start - switch_day
                break
        outcomes.append({
            "switch_day": switch_day, "from_index": from_index,
            "to_index": to_index, "passed": passed, "response_start": start,
            "type": (f"m{NOISE_CANDIDATES[from_index]:g}"
                     f"_to_m{NOISE_CANDIDATES[to_index]:g}"),
        })
    return outcomes


def count_false_alarms(probabilities, true_index=TRUE_NULL_INDEX):
    """Merged count of sustained wrong-candidate runs over the whole window."""
    n_days = probabilities.shape[0]
    alarms = 0
    for candidate in range(probabilities.shape[1]):
        if candidate == true_index:
            continue
        previous = False
        for start in range(0, n_days - CONSECUTIVE_DAYS + 1):
            current = _sustained_rule(probabilities, candidate, start)
            if current and not previous:
                alarms += 1
            previous = current
    return alarms


def build_noise_bank(params, init_hydro, sigma_obs, bounds, interaction_mode):
    """Three identical-parameter filters differing only in Q multiplier."""
    from hbv_joint_uncertainty.imm import (
        InteractingMultipleModel,
        PairwisePathMultipleModel,
    )
    from hbv_joint_uncertainty.preflight import (
        ForcingTransition, build_transition_matrix, project_hbv_state)
    from hbv_joint_uncertainty.sigma_filter import ModifiedUnscentedFilter

    shared_state0 = np.zeros(N_STATE, dtype=np.float64)
    shared_state0[:N_HYDRO] = init_hydro
    state0 = project_hbv_state(shared_state0, params)
    state_scales = np.maximum(np.abs(state0), 1.0)
    p0 = np.diag((INITIAL_COVARIANCE_FRACTION * state_scales) ** 2)
    common_r = np.array([[sigma_obs ** 2]], dtype=np.float64)

    def state_projector(values):
        return project_hbv_state(values, params)

    filters, transitions = [], []
    for multiplier in NOISE_CANDIDATES:
        transition = ForcingTransition(params, parameter_bounds=bounds,
                                       state_projector=state_projector)
        filters.append(ModifiedUnscentedFilter(
            state=state0.copy(), covariance=p0.copy(),
            transition=transition,
            observation=RisingRoutedObservation(params),
            process_covariance=build_state_dependent_lower_groundwater_covariance(
                max(float(state0[4]), 0.0), multiplier),
            observation_covariance=common_r.copy(),
            state_projector=state_projector,
            alpha=0.6874, beta=2.0, kappa=-2.0,
        ))
        transitions.append(transition)

    transition_matrix = build_transition_matrix(len(NOISE_CANDIDATES),
                                                TRANSITION_DIAGONAL)
    initial_probabilities = np.full(len(NOISE_CANDIDATES),
                                    1.0 / len(NOISE_CANDIDATES))
    if interaction_mode == "pairwise_path_postcollapse":
        def identity_moment_transform(source, destination, mean, covariance):
            # identical parameters: every candidate shares one state space, so
            # the source->destination remap is the identity (fresh copies)
            del source, destination
            return np.array(mean, dtype=np.float64), np.array(
                covariance, dtype=np.float64)

        estimator = PairwisePathMultipleModel(
            filters=filters,
            transition_matrix=transition_matrix,
            initial_probabilities=initial_probabilities,
            pairwise_moment_transform=identity_moment_transform,
            model_evidence_scorer=None,
        )
        estimator.recursive_probability_representation = "ordinary_float"
    else:
        estimator = InteractingMultipleModel(
            filters=filters,
            transition_matrix=transition_matrix,
            initial_probabilities=initial_probabilities,
            parameter_groups=list(range(len(NOISE_CANDIDATES))),
            pairwise_moment_transform=None,
            model_evidence_scorer=None,
        )
    estimator.interaction_mode = interaction_mode
    return estimator, transitions


def assign_candidate_process_covariances(estimator, slz_predicted):
    """Each candidate gets its OWN Q -- the hypothesis under test."""
    level = max(float(slz_predicted), 0.0)
    for candidate, multiplier in zip(estimator.filters, NOISE_CANDIDATES):
        candidate.process_covariance = (
            build_state_dependent_lower_groundwater_covariance(level, multiplier))


def _run_task(args_tuple):
    (basin_id, seed, arm, scenario, output_root, window_days) = args_tuple
    import sys as _sys
    if str(_SRC) not in _sys.path:
        _sys.path.insert(0, str(_SRC))
    from hydroagent.data_loading import load_camels_basin
    from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds

    started = time.time()
    task_id = f"{basin_id}_s{seed}_{arm}_{scenario}"
    target = (Path(output_root) / "arms" / arm / scenario / "probs"
              / f"{basin_id}_s{seed}.npz")
    if target.exists():
        return {"task_id": task_id, "run_status": "skipped_existing",
                "error_message": "", "_elapsed_s": 0.0}
    try:
        rotation = SCENARIOS[scenario]
        table = pd.read_csv(PARAMETER_TABLE, dtype={"basin_id": str})
        table["basin_id"] = table["basin_id"].str.zfill(8)
        row = table[table["basin_id"] == basin_id].iloc[0]
        params = {key: float(row[f"p_{key}"]) for key in PARAM_KEYS}
        lag_capped = params["lag_time"] > LAG_CAP
        params["lag_time"] = min(params["lag_time"], LAG_CAP)
        init_hydro = np.array([float(row[f"state_{name}"])
                               for name in STATE_NAMES])

        g1 = pd.read_csv(G1_CSV, dtype={"basin_id": str})
        g1["basin_id"] = g1["basin_id"].str.zfill(8)
        sigma_obs = float(g1.set_index("basin_id").loc[basin_id, "sigma_obs"])

        bounds = resolve_hbv_bounds(BOUNDS_PRESET)
        forcing, _obs, _area = load_camels_basin(
            basin_id, data_root=DATA_ROOT, start_date=WINDOW_START,
            end_date=_window_end(), forcing="maurer", pet_method="oudin",
            keep_obs_nan_days=True)
        rain = forcing["prcp"].values.astype(np.float64)[:window_days]
        pet_column = "ep" if "ep" in forcing.columns else "pet"
        pet = forcing[pet_column].values.astype(np.float64)[:window_days]
        temp = (forcing["tmean"].values.astype(np.float64)
                if "tmean" in forcing.columns
                else np.zeros_like(rain))[:window_days]

        truth_rng = np.random.default_rng(np.random.SeedSequence(
            (SEED_ENTROPY, int(basin_id), int(seed), TRUTH_STREAM_TAG)))
        obs_rng = np.random.default_rng(np.random.SeedSequence(
            (SEED_ENTROPY, int(basin_id), int(seed), OBS_STREAM_TAG)))

        truth_q, truth_index, clips = generate_truth(
            rotation, params, rain, pet, temp, init_hydro, truth_rng, bounds)
        n_days = len(truth_q)
        observations = truth_q + obs_rng.normal(0.0, sigma_obs, size=n_days)

        estimator, transitions = build_noise_bank(
            params, init_hydro, sigma_obs, bounds, ARM_MODES[arm])
        probabilities = np.zeros((n_days, len(NOISE_CANDIDATES)),
                                 dtype=np.float64)
        log_probabilities = np.zeros_like(probabilities)
        process_variances = np.zeros((n_days, len(NOISE_CANDIDATES)),
                                     dtype=np.float64)
        for day in range(n_days):
            for transition in transitions:
                transition.set_forcing(rain[day], pet[day], temp[day])
            predicted_reference = transitions[0](estimator.state.copy())
            assign_candidate_process_covariances(estimator,
                                                 predicted_reference[4])
            for index in range(len(NOISE_CANDIDATES)):
                process_variances[day, index] = (
                    estimator.filters[index].process_covariance[4, 4])
            result = estimator.step(np.array([observations[day]]))
            probabilities[day] = result.posterior_probabilities
            log_probabilities[day] = result.posterior_log_probabilities

        events = switch_events_from_rotation(rotation, n_days=n_days)
        _atomic_save_npz(
            target,
            probabilities=probabilities,
            log_probabilities=log_probabilities,
            truth_q=truth_q,
            observations=observations,
            truth_candidate_indices=truth_index,
            rotation=np.asarray(rotation, dtype=np.int64),
            stage_days=np.array(STAGE_DAYS, dtype=np.int64),
            switch_days=np.array([d for d, _, _ in events], dtype=np.int64),
            noise_candidates=np.asarray(NOISE_CANDIDATES, dtype=np.float64),
            filter_process_lower_groundwater_variances=process_variances,
            observation_sigma=np.array(sigma_obs, dtype=np.float64),
            truth_clip_count=np.array(clips, dtype=np.int64),
            basin_id=np.array(str(basin_id)),
            seed=np.array(int(seed), dtype=np.int64),
            arm_id=np.array(str(arm)),
            scenario=np.array(str(scenario)),
            state_interaction_mode=np.array(ARM_MODES[arm]),
            lag_capped=np.array(bool(lag_capped)),
            preregistration_sha256=np.array(PREREGISTRATION_SHA256),
        )
        return {"task_id": task_id, "run_status": "success",
                "error_message": "", "truth_clip_count": int(clips),
                "lag_capped": bool(lag_capped),
                "_elapsed_s": round(time.time() - started, 2)}
    except Exception as exception:  # noqa: BLE001 - recorded, never fatal
        return {"task_id": task_id, "run_status": "failed",
                "error_message": f"{type(exception).__name__}: {exception}",
                "_elapsed_s": round(time.time() - started, 2)}


def _admitted_basins():
    admitted = pd.read_csv(ADMISSION_CSV, dtype={"basin_id": str})
    admitted["basin_id"] = admitted["basin_id"].str.zfill(8)
    return admitted[admitted["admitted"]]["basin_id"].tolist()


def run_all(arguments) -> None:
    basins = [b.zfill(8) for b in (arguments.basins or _admitted_basins())]
    output_root = Path(arguments.output_root)
    if (arguments.window_days != WINDOW_DAYS
            and output_root == OUTPUT_ROOT):
        raise ValueError("shortened windows must write to a non-default root")
    tasks = [(basin, seed, arm, scenario, str(output_root),
              arguments.window_days)
             for basin in basins for seed in arguments.seeds
             for arm in arguments.arms for scenario in arguments.scenarios]
    print(f"[noise-switch] tasks={len(tasks)} basins={len(basins)} "
          f"seeds={arguments.seeds} arms={arguments.arms} "
          f"scenarios={arguments.scenarios} window={arguments.window_days}d")
    for arm in arguments.arms:
        for scenario in arguments.scenarios:
            (output_root / "arms" / arm / scenario / "probs").mkdir(
                parents=True, exist_ok=True)
    if arguments.workers > 1 and len(tasks) > 1:
        with ProcessPoolExecutor(max_workers=arguments.workers) as pool:
            records = list(pool.map(_run_task, tasks, chunksize=1))
    else:
        records = [_run_task(task) for task in tasks]
    (output_root / "verification").mkdir(parents=True, exist_ok=True)
    failures = [r for r in records if r["run_status"] == "failed"]
    with open(output_root / "verification" / "run_failures.json", "w",
              encoding="utf-8") as handle:
        json.dump(failures, handle, indent=2, ensure_ascii=False)
    done = sum(r["run_status"] == "success" for r in records)
    skipped = sum(r["run_status"] == "skipped_existing" for r in records)
    print(f"[noise-switch] success={done} skipped={skipped} "
          f"failed={len(failures)}")


def summarize(arguments) -> None:
    output_root = Path(arguments.output_root)
    rows = []
    for arm in arguments.arms:
        for scenario in arguments.scenarios:
            directory = output_root / "arms" / arm / scenario / "probs"
            for path in sorted(directory.glob("*.npz")):
                with np.load(path, allow_pickle=False) as archive:
                    probabilities = archive["probabilities"]
                    truth_index = archive["truth_candidate_indices"]
                    rotation = tuple(int(x) for x in archive["rotation"])
                    clips = int(archive["truth_clip_count"])
                    basin = str(archive["basin_id"])
                    seed = int(archive["seed"])
                n_days = probabilities.shape[0]
                true_p = probabilities[np.arange(n_days), truth_index]
                record = {
                    "basin_id": basin, "seed": seed, "arm": arm,
                    "scenario": scenario, "n_days": n_days,
                    "truth_clip_count": clips,
                    "zero_true_probability_days": int((true_p == 0.0).sum()),
                    "mean_true_probability": float(true_p.mean()),
                    "argmax_wrong_fraction": float(
                        (probabilities.argmax(axis=1) != truth_index).mean()),
                }
                if scenario == "switch":
                    events = switch_events_from_rotation(rotation,
                                                         n_days=n_days)
                    for window, label in ((PRIMARY_WINDOW_DAYS, "90"),
                                          (SECONDARY_WINDOW_DAYS, "30")):
                        outcomes = evaluate_switch_events(
                            probabilities, events, window)
                        record[f"events_passed_w{label}"] = sum(
                            o["passed"] for o in outcomes)
                        record["events_total"] = len(outcomes)
                        for outcome in outcomes:
                            record[f"{outcome['type']}_w{label}_pass"] = bool(
                                outcome["passed"])
                            record[f"{outcome['type']}_w{label}_start"] = (
                                outcome["response_start"]
                                if outcome["response_start"] is not None
                                else -1)
                else:
                    record["false_alarms"] = count_false_alarms(probabilities)
                rows.append(record)
    frame = pd.DataFrame(rows)
    (output_root / "verification").mkdir(parents=True, exist_ok=True)
    frame.to_csv(output_root / "verification" / "task_metrics.csv",
                 index=False)

    events = switch_events_from_rotation(ROTATION)
    type_labels = [f"m{NOISE_CANDIDATES[f]:g}_to_m{NOISE_CANDIDATES[t]:g}"
                   for _, f, t in events]
    summary = {
        "preregistration": PREREGISTRATION,
        "preregistration_sha256": PREREGISTRATION_SHA256,
        "primary_window_days": PRIMARY_WINDOW_DAYS,
        "secondary_window_days": SECONDARY_WINDOW_DAYS,
        "arms": {},
    }
    for arm in arguments.arms:
        switch_frame = frame[(frame["arm"] == arm)
                             & (frame["scenario"] == "switch")]
        null_frame = frame[(frame["arm"] == arm)
                           & (frame["scenario"] == "null")]
        arm_summary = {
            "switch_tasks": int(len(switch_frame)),
            "null_tasks": int(len(null_frame)),
            "per_type_pass_rate_w90": {},
            "per_type_pass_rate_w30": {},
        }
        for label in type_labels:
            for window in ("90", "30"):
                column = f"{label}_w{window}_pass"
                if column in switch_frame:
                    arm_summary[f"per_type_pass_rate_w{window}"][label] = (
                        float(switch_frame[column].mean()))
        if len(null_frame):
            with_alarm = (null_frame["false_alarms"] > 0)
            arm_summary["null_false_alarm_task_fraction"] = float(
                with_alarm.mean())
            arm_summary["null_false_alarm_total"] = int(
                null_frame["false_alarms"].sum())
            arm_summary["null_argmax_wrong_fraction_median"] = float(
                null_frame["argmax_wrong_fraction"].median())
            fraction = arm_summary["null_false_alarm_task_fraction"]
            if fraction >= 0.5:
                verdict = "confound_confirmed_design_void"
            elif fraction <= 0.1:
                verdict = "confound_negligible"
            else:
                verdict = "partial_confound_conditional_gate"
            arm_summary["null_verdict"] = verdict
        rates = arm_summary["per_type_pass_rate_w90"]
        if len(rates) == len(type_labels) and len(null_frame):
            fraction = arm_summary["null_false_alarm_task_fraction"]
            if arm_summary["null_verdict"] == "confound_confirmed_design_void":
                claim = "void"
            elif arm_summary["null_verdict"] == "confound_negligible":
                claim = ("pass" if all(r >= 0.5 for r in rates.values())
                         else "per_type_only")
            else:
                claim = ("pass_conditional"
                         if all(r >= 0.5 and (r - fraction) >= 0.3
                                for r in rates.values())
                         else "per_type_only")
            arm_summary["claim_gate_w90"] = claim
        summary["arms"][arm] = arm_summary
    with open(output_root / "verification" / "summary.json", "w",
              encoding="utf-8") as handle:
        json.dump(summary, handle, indent=2, ensure_ascii=False)
    print(json.dumps(summary, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--summarize", action="store_true")
    parser.add_argument("--basins", nargs="*", default=None)
    parser.add_argument("--seeds", nargs="*", type=int, default=list(SEEDS))
    parser.add_argument("--arms", nargs="*", default=list(ARM_MODES))
    parser.add_argument("--scenarios", nargs="*", default=list(SCENARIOS))
    parser.add_argument("--workers", type=int, default=WORKERS)
    parser.add_argument("--window-days", type=int, default=WINDOW_DAYS)
    parser.add_argument("--output-root", default=str(OUTPUT_ROOT))
    arguments = parser.parse_args()
    if arguments.run:
        run_all(arguments)
    if arguments.summarize:
        summarize(arguments)
    if not arguments.run and not arguments.summarize:
        parser.error("pass --run and/or --summarize")


if __name__ == "__main__":
    main()
