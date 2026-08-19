"""Run and audit one isolated Student-t model-evidence comparison.

This diagnostic is intentionally locked to CAMELS basin 07184000 and design
seed 0.  It reuses one frozen version-03B task as the common forcing, truth,
observation, candidate, and initial-moment source.  Both comparison arms run
online from day zero with the same Student-t evidence scorer.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

from camels_switch_confirmation.g2_switch_confirmation import (
    _atomic_save_npz,
    _build_bank,
    _evaluate_events,
)
from camels_switch_confirmation.register_parameter_path_design90 import (
    collection_fingerprint,
)
from hbv_joint_uncertainty.imm import (
    _logsumexp,
    _normalize_path_weights,
    normalize_log_weights_with_logs,
    student_t_log_model_evidence,
    student_t_model_evidence_scorer,
    update_model_probabilities_with_logs,
)
from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds


BASIN_ID = "07184000"
SEED = 0
DEGREES_OF_FREEDOM = 1.0
EXPECTED_FROZEN_FINGERPRINT = (
    "57d8fef9037c29d0a68f915d5337f3be7bfab2224ebada575be6161e070126e6"
)
EVIDENCE_SCALE_SEMANTICS = (
    "gaussian_filter_innovation_covariance_used_as_student_t_scale_matrix"
)
ARM_MODES = {
    "C": "full",
    "P": "pairwise_path_postcollapse",
}
COMMON_SOURCE_FIELDS = (
    "truth_q",
    "observations",
    "basin_id",
    "seed",
    "switch_days",
    "rotation",
    "stage_days",
    "true_candidate_indices",
    "truth_parfc",
    "candidate_parameter_names",
    "candidate_parameter_vectors",
    "observation_sigma",
    "rain",
    "pet",
    "temperature",
    "filter_process_variance_scale",
    "filter_process_covariance_structure",
    "filter_q_mode",
    "filter_q_state_multiplier",
    "filter_observation_variance_multiplier",
    "path_initial_probabilities",
    "path_initial_states",
    "path_initial_covariances",
)


def _sha256_file(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _write_json_new(path: str | Path, payload: dict) -> None:
    target = Path(path)
    with target.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


def _load_source(path: str | Path) -> dict[str, np.ndarray]:
    source_path = Path(path)
    with np.load(source_path, allow_pickle=False) as archive:
        missing = sorted(set(COMMON_SOURCE_FIELDS) - set(archive.files))
        if missing:
            raise ValueError(f"source task is missing fields: {missing}")
        source = {name: archive[name].copy() for name in COMMON_SOURCE_FIELDS}

    if str(source["basin_id"].item()) != BASIN_ID:
        raise ValueError(f"diagnostic is locked to basin {BASIN_ID}")
    if int(source["seed"].item()) != SEED:
        raise ValueError(f"diagnostic is locked to seed {SEED}")
    n_days = len(source["observations"])
    if n_days != 1260:
        raise ValueError(f"expected 1260 days, observed {n_days}")
    if source["candidate_parameter_vectors"].shape != (3, 13):
        raise ValueError("expected exactly three 13-parameter candidates")
    if source["path_initial_states"].shape != (3, 15):
        raise ValueError("expected three 15-state initial means")
    if source["path_initial_covariances"].shape != (3, 15, 15):
        raise ValueError("expected three 15-state initial covariances")
    for name in ("observations", "rain", "pet", "temperature"):
        if not np.all(np.isfinite(source[name])):
            raise ValueError(f"source field contains non-finite values: {name}")
    return source


def _members_and_initial_hydrology(source: dict[str, np.ndarray]):
    names = [str(value) for value in source["candidate_parameter_names"]]
    members = [
        {name: float(value) for name, value in zip(names, row)}
        for row in source["candidate_parameter_vectors"]
    ]
    initial_hydrology = source["path_initial_states"][0, :5].copy()
    return members, initial_hydrology


def _build_estimator(source: dict[str, np.ndarray], interaction_mode: str):
    members, initial_hydrology = _members_and_initial_hydrology(source)
    scorer = student_t_model_evidence_scorer(DEGREES_OF_FREEDOM)
    estimator, transitions = _build_bank(
        members,
        initial_hydrology,
        float(source["observation_sigma"].item()),
        resolve_hbv_bounds("v5"),
        q_scale=float(source["filter_process_variance_scale"].item()),
        q_structure=str(source["filter_process_covariance_structure"].item()),
        q_mode=str(source["filter_q_mode"].item()),
        q_state_multiplier=float(source["filter_q_state_multiplier"].item()),
        filter_r_multiplier=float(
            source["filter_observation_variance_multiplier"].item()
        ),
        interaction_mode=interaction_mode,
        parameter_state_mapping="conservative_parfc",
        model_evidence_scorer=scorer,
    )
    observed_states = np.asarray([item.state for item in estimator.filters])
    observed_covariances = np.asarray(
        [item.covariance for item in estimator.filters]
    )
    if not np.array_equal(observed_states, source["path_initial_states"]):
        raise ValueError("rebuilt initial states do not bitwise match the frozen task")
    if not np.array_equal(
        observed_covariances,
        source["path_initial_covariances"],
    ):
        raise ValueError(
            "rebuilt initial covariances do not bitwise match the frozen task"
        )
    if not np.array_equal(
        estimator.probabilities,
        source["path_initial_probabilities"],
    ):
        raise ValueError(
            "rebuilt initial probabilities do not bitwise match the frozen task"
        )
    return estimator, transitions


def _common_output_arrays(source: dict[str, np.ndarray], arm_id: str) -> dict:
    arrays = {name: value.copy() for name, value in source.items()}
    arrays.update(
        {
            "arm_id": np.array(arm_id),
            "state_interaction_mode": np.array(ARM_MODES[arm_id]),
            "parameter_state_mapping": np.array("conservative_parfc"),
            "model_evidence_distribution": np.array("student_t"),
            "model_evidence_degrees_of_freedom": np.array(
                DEGREES_OF_FREEDOM,
                dtype=np.float64,
            ),
            "model_evidence_scale_semantics": np.array(
                EVIDENCE_SCALE_SEMANTICS
            ),
            "filter_state_update_distribution": np.array("gaussian"),
        }
    )
    return arrays


def _run_arm(source: dict[str, np.ndarray], arm_id: str) -> dict[str, np.ndarray]:
    interaction_mode = ARM_MODES[arm_id]
    estimator, transitions = _build_estimator(source, interaction_mode)
    n_days = len(source["observations"])
    n_candidates = len(estimator.filters)
    n_state = estimator.filters[0].n_state
    probabilities = np.empty((n_days, n_candidates), dtype=np.float64)
    log_probabilities = np.empty_like(probabilities)
    combined_states = np.empty((n_days, n_state), dtype=np.float64)
    combined_covariances = np.empty((n_days, n_state, n_state), dtype=np.float64)
    arrays = _common_output_arrays(source, arm_id)

    if arm_id == "C":
        prior_probabilities = np.empty_like(probabilities)
        model_log_evidences = np.empty_like(probabilities)
        gaussian_log_likelihoods = np.empty_like(probabilities)
        innovations = np.empty((n_days, n_candidates, 1), dtype=np.float64)
        scales = np.empty((n_days, n_candidates, 1, 1), dtype=np.float64)
        candidate_states = np.empty(
            (n_days, n_candidates, n_state),
            dtype=np.float64,
        )
        candidate_covariances = np.empty(
            (n_days, n_candidates, n_state, n_state),
            dtype=np.float64,
        )
    else:
        shape = (n_days, n_candidates, n_candidates)
        branch_prior_log_probabilities = np.empty(shape, dtype=np.float64)
        branch_posterior_log_probabilities = np.empty(shape, dtype=np.float64)
        branch_posterior_probabilities = np.empty(shape, dtype=np.float64)
        model_log_evidences = np.full(shape, -np.inf, dtype=np.float64)
        gaussian_log_likelihoods = np.full(shape, np.nan, dtype=np.float64)
        innovations = np.full(shape + (1,), np.nan, dtype=np.float64)
        scales = np.full(shape + (1, 1), np.nan, dtype=np.float64)
        branch_active_mask = np.zeros(shape, dtype=bool)
        destination_states = np.empty(
            (n_days, n_candidates, n_state),
            dtype=np.float64,
        )
        destination_covariances = np.empty(
            (n_days, n_candidates, n_state, n_state),
            dtype=np.float64,
        )

    for day in range(n_days):
        for transition in transitions:
            transition.set_forcing(
                source["rain"][day],
                source["pet"][day],
                source["temperature"][day],
            )
        result = estimator.step(np.array([source["observations"][day]]))
        probabilities[day] = result.posterior_probabilities
        log_probabilities[day] = result.posterior_log_probabilities
        combined_states[day] = result.combined_state
        combined_covariances[day] = result.combined_covariance

        if arm_id == "C":
            prior_probabilities[day] = result.prior_probabilities
            model_log_evidences[day] = result.candidate_log_evidences
            for candidate, candidate_result in enumerate(result.candidate_results):
                gaussian_log_likelihoods[day, candidate] = (
                    candidate_result.log_likelihood
                )
                innovations[day, candidate] = candidate_result.innovation
                scales[day, candidate] = candidate_result.innovation_covariance
                candidate_states[day, candidate] = candidate_result.posterior_state
                candidate_covariances[day, candidate] = (
                    candidate_result.posterior_covariance
                )
        else:
            branch_prior_log_probabilities[day] = (
                result.branch_prior_log_probabilities
            )
            branch_posterior_log_probabilities[day] = (
                result.branch_posterior_log_probabilities
            )
            branch_posterior_probabilities[day] = (
                result.branch_posterior_probabilities
            )
            model_log_evidences[day] = result.branch_log_evidences
            branch_active_mask[day] = result.branch_active_mask
            destination_states[day] = result.destination_states
            destination_covariances[day] = result.destination_covariances
            for source_index in range(n_candidates):
                for destination_index in range(n_candidates):
                    branch = result.branch_results[source_index][destination_index]
                    if branch is None:
                        continue
                    gaussian_log_likelihoods[
                        day,
                        source_index,
                        destination_index,
                    ] = branch.log_likelihood
                    innovations[day, source_index, destination_index] = (
                        branch.innovation
                    )
                    scales[day, source_index, destination_index] = (
                        branch.innovation_covariance
                    )

    arrays.update(
        {
            "probabilities": probabilities,
            "log_probabilities": log_probabilities,
            "combined_states": combined_states,
            "combined_covariances": combined_covariances,
        }
    )
    if arm_id == "C":
        arrays.update(
            {
                "candidate_prior_probabilities": prior_probabilities,
                "candidate_model_log_evidences": model_log_evidences,
                "candidate_gaussian_log_likelihoods": gaussian_log_likelihoods,
                "candidate_innovations": innovations,
                "candidate_model_evidence_scale_matrices": scales,
                "candidate_posterior_states": candidate_states,
                "candidate_posterior_covariances": candidate_covariances,
            }
        )
    else:
        arrays.update(
            {
                "branch_prior_log_probabilities": (
                    branch_prior_log_probabilities
                ),
                "branch_posterior_log_probabilities": (
                    branch_posterior_log_probabilities
                ),
                "branch_posterior_probabilities": (
                    branch_posterior_probabilities
                ),
                "branch_model_log_evidences": model_log_evidences,
                "branch_gaussian_log_likelihoods": gaussian_log_likelihoods,
                "branch_innovations": innovations,
                "branch_model_evidence_scale_matrices": scales,
                "branch_active_mask": branch_active_mask,
                "destination_states": destination_states,
                "destination_covariances": destination_covariances,
            }
        )
    return arrays


def _longest_run(mask) -> int:
    longest = current = 0
    for value in np.asarray(mask, dtype=bool):
        current = current + 1 if value else 0
        longest = max(longest, current)
    return int(longest)


def _metrics_for_slice(arrays: dict[str, np.ndarray], start: int, end: int) -> dict:
    probabilities = arrays["probabilities"][start:end]
    log_probabilities = arrays["log_probabilities"][start:end]
    true_indices = arrays["true_candidate_indices"][start:end]
    row = np.arange(end - start)
    true_probabilities = probabilities[row, true_indices]
    true_log_probabilities = log_probabilities[row, true_indices]
    truth = np.eye(probabilities.shape[1], dtype=np.float64)[true_indices]
    return {
        "start_day": int(start),
        "end_day_inclusive": int(end - 1),
        "days": int(end - start),
        "mean_true_probability": float(np.mean(true_probabilities)),
        "median_true_probability": float(np.median(true_probabilities)),
        "final_true_probability": float(true_probabilities[-1]),
        "multiclass_brier_score": float(
            np.mean(np.sum((probabilities - truth) ** 2, axis=1))
        ),
        "mean_true_negative_log_probability": float(
            np.mean(-true_log_probabilities)
        ),
        "zero_true_probability_days": int(np.sum(true_probabilities == 0.0)),
        "true_probability_below_0_01_days": int(
            np.sum(true_probabilities < 0.01)
        ),
        "true_probability_above_0_5_days": int(
            np.sum(true_probabilities > 0.5)
        ),
        "longest_above_0_5_run_days": _longest_run(
            true_probabilities > 0.5
        ),
        "longest_below_0_01_run_days": _longest_run(
            true_probabilities < 0.01
        ),
    }


def _summary_for_arm(arrays: dict[str, np.ndarray]) -> dict:
    switch_pairs = list(
        zip(
            arrays["switch_days"].tolist(),
            arrays["rotation"][1:].tolist(),
        )
    )
    events = _evaluate_events(arrays["probabilities"], switch_pairs)
    normalized_events = [
        {
            "switch_day": int(event["switch_day"]),
            "new_member": int(event["new_member"]),
            "passed": bool(event["passed"]),
            "response_start_days": (
                None
                if event["response_start"] is None
                else int(event["response_start"])
            ),
        }
        for event in events
    ]
    return {
        "events_passed": int(sum(event["passed"] for event in normalized_events)),
        "events_total": len(normalized_events),
        "events": normalized_events,
        "full_period": _metrics_for_slice(arrays, 0, len(arrays["probabilities"])),
        "days_540_719": _metrics_for_slice(arrays, 540, 720),
        "days_720_899": _metrics_for_slice(arrays, 720, 900),
        "days_540_899": _metrics_for_slice(arrays, 540, 900),
        "day_719_true_probability": float(
            arrays["probabilities"][719, arrays["true_candidate_indices"][719]]
        ),
        "day_720_true_probability": float(
            arrays["probabilities"][720, arrays["true_candidate_indices"][720]]
        ),
    }


def _source_hashes(repo_root: Path, source_task: Path) -> dict:
    paths = {
        "source_task": source_task,
        "imm": repo_root / "src/hbv_joint_uncertainty/imm.py",
        "g2_switch_confirmation": (
            repo_root / "src/camels_switch_confirmation/g2_switch_confirmation.py"
        ),
        "runner": Path(__file__),
        "sigma_filter": repo_root / "src/hbv_joint_uncertainty/sigma_filter.py",
        "hbv_state_mapping": (
            repo_root / "src/hbv_joint_uncertainty/hbv_state_mapping.py"
        ),
    }
    return {
        name: {"path": str(path.resolve()), "sha256": _sha256_file(path)}
        for name, path in paths.items()
    }


def run_diagnostic(source_task: Path, frozen_root: Path, output_root: Path) -> dict:
    source_task = source_task.resolve()
    frozen_root = frozen_root.resolve()
    output_root = output_root.resolve()
    if output_root.exists():
        raise FileExistsError(f"output root already exists: {output_root}")
    if output_root == frozen_root or frozen_root in output_root.parents:
        raise ValueError("output root must be outside the frozen result root")
    if frozen_root not in source_task.parents:
        raise ValueError("source task must be inside the declared frozen result root")
    fingerprint_before = collection_fingerprint(frozen_root)
    if (
        fingerprint_before["sha256_of_newline_joined_sorted_entries"]
        != EXPECTED_FROZEN_FINGERPRINT
    ):
        raise ValueError("frozen result fingerprint does not match the registered value")
    source = _load_source(source_task)
    repo_root = Path(__file__).resolve().parents[2]
    git_head = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    contract = {
        "experiment_id": "CAMELS_PARFC_MODEL_EVIDENCE_FAIR_07184000_S0_01",
        "status": "isolated_single_task_diagnostic_not_formal_version03b_evidence",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "basin_id": BASIN_ID,
        "seed": SEED,
        "task_count": 2,
        "arms": ARM_MODES,
        "model_evidence": {
            "distribution": "student_t",
            "degrees_of_freedom": DEGREES_OF_FREEDOM,
            "scale_semantics": EVIDENCE_SCALE_SEMANTICS,
            "variance_matching_claimed": False,
            "filter_state_update_distribution": "gaussian",
        },
        "source_frozen_root": str(frozen_root),
        "source_frozen_fingerprint_before": fingerprint_before,
        "implementation": _source_hashes(repo_root, source_task),
        "git_head": git_head,
        "runtime": {
            "python": sys.version,
            "executable": sys.executable,
            "platform": platform.platform(),
            "numpy": np.__version__,
        },
        "claim_boundary": {
            "parameter_candidate_identification": "single_task_mechanism_diagnostic_only",
            "noise_candidate_identification": "not_tested",
            "complete_state_accuracy": "not_tested",
            "forecast_value": "not_tested",
            "real_observation_assimilation_value": "not_tested",
        },
    }
    output_root.mkdir(parents=True, exist_ok=False)
    _write_json_new(output_root / "run_contract.json", contract)

    summaries = {}
    for arm_id in ("C", "P"):
        arrays = _run_arm(source, arm_id)
        arm_directory = output_root / "arms" / arm_id
        arm_directory.mkdir(parents=True, exist_ok=False)
        arm_path = arm_directory / f"{BASIN_ID}_s{SEED}.npz"
        _atomic_save_npz(arm_path, **arrays)
        summaries[arm_id] = _summary_for_arm(arrays)

    fingerprint_after = collection_fingerprint(frozen_root)
    if fingerprint_after != fingerprint_before:
        raise RuntimeError("frozen result collection changed during the diagnostic")
    summary = {
        "experiment_id": contract["experiment_id"],
        "arms": summaries,
        "frozen_result_fingerprint_unchanged": True,
    }
    _write_json_new(output_root / "summary.json", summary)
    return summary


def _load_arm(path: Path) -> dict[str, np.ndarray]:
    with np.load(path, allow_pickle=False) as archive:
        return {name: archive[name].copy() for name in archive.files}


def _assert_array_equal(observed, expected, message: str) -> None:
    if not np.array_equal(observed, expected):
        maximum = float(np.nanmax(np.abs(observed - expected)))
        raise AssertionError(f"{message}; maximum absolute difference={maximum}")


def _verify_common_source(
    source: dict[str, np.ndarray],
    arm: dict[str, np.ndarray],
) -> None:
    for name in COMMON_SOURCE_FIELDS:
        _assert_array_equal(arm[name], source[name], f"source mismatch: {name}")
    if str(arm["model_evidence_distribution"].item()) != "student_t":
        raise AssertionError("unexpected model evidence distribution")
    if float(arm["model_evidence_degrees_of_freedom"].item()) != 1.0:
        raise AssertionError("unexpected Student-t degrees of freedom")
    if str(arm["model_evidence_scale_semantics"].item()) != EVIDENCE_SCALE_SEMANTICS:
        raise AssertionError("unexpected Student-t scale semantics")


def _verify_full_arm(arm: dict[str, np.ndarray]) -> None:
    n_days, n_candidates = arm["probabilities"].shape
    for day in range(n_days):
        recomputed_evidence = np.array(
            [
                student_t_log_model_evidence(
                    arm["candidate_innovations"][day, candidate],
                    arm["candidate_model_evidence_scale_matrices"][day, candidate],
                    DEGREES_OF_FREEDOM,
                )
                for candidate in range(n_candidates)
            ]
        )
        _assert_array_equal(
            recomputed_evidence,
            arm["candidate_model_log_evidences"][day],
            f"complete-interaction evidence mismatch on day {day}",
        )
        expected_probabilities, expected_logs = (
            update_model_probabilities_with_logs(
                arm["candidate_prior_probabilities"][day],
                recomputed_evidence,
            )
        )
        _assert_array_equal(
            expected_probabilities,
            arm["probabilities"][day],
            f"complete-interaction probabilities mismatch on day {day}",
        )
        _assert_array_equal(
            expected_logs,
            arm["log_probabilities"][day],
            f"complete-interaction log probabilities mismatch on day {day}",
        )


def _verify_path_arm(arm: dict[str, np.ndarray]) -> None:
    n_days, n_candidates = arm["probabilities"].shape
    for day in range(n_days):
        active = arm["branch_active_mask"][day]
        recomputed_evidence = np.full((n_candidates, n_candidates), -np.inf)
        for source in range(n_candidates):
            for destination in range(n_candidates):
                if not active[source, destination]:
                    continue
                recomputed_evidence[source, destination] = (
                    student_t_log_model_evidence(
                        arm["branch_innovations"][day, source, destination],
                        arm["branch_model_evidence_scale_matrices"][day, source, destination],
                        DEGREES_OF_FREEDOM,
                    )
                )
        _assert_array_equal(
            recomputed_evidence,
            arm["branch_model_log_evidences"][day],
            f"nine-path evidence mismatch on day {day}",
        )
        branch_probabilities, branch_logs = normalize_log_weights_with_logs(
            (
                arm["branch_prior_log_probabilities"][day]
                + recomputed_evidence
            ).reshape(-1)
        )
        branch_probabilities = branch_probabilities.reshape(
            n_candidates,
            n_candidates,
        )
        branch_logs = branch_logs.reshape(n_candidates, n_candidates)
        _assert_array_equal(
            branch_probabilities,
            arm["branch_posterior_probabilities"][day],
            f"nine-path branch probabilities mismatch on day {day}",
        )
        _assert_array_equal(
            branch_logs,
            arm["branch_posterior_log_probabilities"][day],
            f"nine-path branch log probabilities mismatch on day {day}",
        )
        raw_destination = np.array(
            [
                math.fsum(
                    float(value)
                    for value in branch_probabilities[:, destination]
                )
                for destination in range(n_candidates)
            ]
        )
        expected_probabilities = _normalize_path_weights(raw_destination)
        destination_logs = np.array(
            [
                _logsumexp(branch_logs[:, destination])
                for destination in range(n_candidates)
            ]
        )
        _, expected_logs = normalize_log_weights_with_logs(destination_logs)
        _assert_array_equal(
            expected_probabilities,
            arm["probabilities"][day],
            f"nine-path probabilities mismatch on day {day}",
        )
        _assert_array_equal(
            expected_logs,
            arm["log_probabilities"][day],
            f"nine-path log probabilities mismatch on day {day}",
        )


def verify_diagnostic(source_task: Path, frozen_root: Path, output_root: Path) -> dict:
    source = _load_source(source_task)
    with (output_root / "run_contract.json").open(encoding="utf-8") as handle:
        contract = json.load(handle)
    with (output_root / "summary.json").open(encoding="utf-8") as handle:
        recorded_summary = json.load(handle)
    arms = {
        arm_id: _load_arm(
            output_root / "arms" / arm_id / f"{BASIN_ID}_s{SEED}.npz"
        )
        for arm_id in ("C", "P")
    }
    for arm in arms.values():
        _verify_common_source(source, arm)
    _verify_full_arm(arms["C"])
    _verify_path_arm(arms["P"])
    recomputed_summary = {
        arm_id: _summary_for_arm(arrays)
        for arm_id, arrays in arms.items()
    }
    if recomputed_summary != recorded_summary["arms"]:
        raise AssertionError("summary does not match independently reloaded outputs")
    frozen_fingerprint = collection_fingerprint(frozen_root)
    if (
        frozen_fingerprint["sha256_of_newline_joined_sorted_entries"]
        != EXPECTED_FROZEN_FINGERPRINT
    ):
        raise AssertionError("frozen result fingerprint changed")
    result_files = sorted(
        path for path in output_root.rglob("*") if path.is_file()
    )
    verification = {
        "experiment_id": contract["experiment_id"],
        "status": "PASS",
        "probabilities_reconstructed_from_saved_online_evidence": True,
        "student_t_evidence_recomputed_from_saved_innovations_and_scales": True,
        "common_inputs_bitwise_equal_between_arms_and_source": True,
        "summary_recomputed_after_reload": True,
        "frozen_result_fingerprint": frozen_fingerprint,
        "result_files": [
            {
                "path": path.relative_to(output_root).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": _sha256_file(path),
            }
            for path in result_files
        ],
    }
    _write_json_new(output_root / "verification.json", verification)
    return verification


def _parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("run", "verify"))
    parser.add_argument("--source-task", type=Path, required=True)
    parser.add_argument("--frozen-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    if args.mode == "run":
        payload = run_diagnostic(
            args.source_task,
            args.frozen_root,
            args.output_root,
        )
    else:
        payload = verify_diagnostic(
            args.source_task,
            args.frozen_root,
            args.output_root,
        )
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
