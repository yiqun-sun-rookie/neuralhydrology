"""Independently verify the daily rolling forecast readout comparison."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path
from typing import Mapping

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES  # noqa: E402
from hbv_multilead_joint_uncertainty.forecast import (  # noqa: E402
    forecast_from_posterior,
)
from hbv_multilead_joint_uncertainty.methods import (  # noqa: E402
    MethodCandidate,
    build_method_bank,
)
from hbv_multilead_joint_uncertainty.scripts.run_three_stage_switching_validation import (  # noqa: E402
    _protected_hashes,
)


_READOUT_METHODS = (
    "current_multiple_states",
    "posterior_unique_complete_covariance_weighted_parameters",
    "posterior_unique_within_covariance_weighted_parameters",
    "posterior_unique_complete_covariance_maximum_parameters",
    "maximum_posterior_candidate",
    "uniform_unique_complete_covariance_uniform_parameters",
)
_CONTROLS = (
    "no_state_interaction_multiple_states",
    "no_state_interaction_uniform_candidates",
)
_ALL_METHODS = _READOUT_METHODS + _CONTROLS
_UNIQUE_METHODS = (
    "posterior_unique_complete_covariance_weighted_parameters",
    "posterior_unique_within_covariance_weighted_parameters",
    "posterior_unique_complete_covariance_maximum_parameters",
    "uniform_unique_complete_covariance_uniform_parameters",
)
_TIME_STRATA = (
    ("days_000_006", 0, 6),
    ("days_007_029", 7, 29),
    ("days_030_089", 30, 89),
    ("days_090_179", 90, 179),
)
_SOURCE_FILES = (
    "src/hbv_multilead_joint_uncertainty/forecast_readout.py",
    (
        "src/hbv_multilead_joint_uncertainty/scripts/"
        "run_g3_daily_rolling_forecast_readout_development.py"
    ),
    (
        "src/hbv_multilead_joint_uncertainty/scripts/"
        "verify_g3_daily_rolling_forecast_readout_development.py"
    ),
    "src/hbv_multilead_joint_uncertainty/forecast.py",
    "src/hbv_multilead_joint_uncertainty/daily_rolling_forecast.py",
    "src/hbv_multilead_joint_uncertainty/methods.py",
    "src/hbv_joint_uncertainty/preflight.py",
    "src/hbv_joint_uncertainty/imm.py",
    "src/hbv_joint_uncertainty/sigma_filter.py",
    "test/test_hbv_forecast_readout.py",
    "test/test_hbv_daily_rolling_forecast_readout_runner.py",
    "test/test_hbv_daily_rolling_forecast_readout_verifier.py",
    (
        "src/hbv_multilead_joint_uncertainty/configs/"
        "g3_daily_rolling_forecast_readout_development_v01.json"
    ),
    "docs/plans/2026-07-28-id23-daily-rolling-forecast-readout-design.md",
)
_POSTHOC_REPORT = "independent_verification.json"


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_checksums(result_dir: Path) -> dict[str, object]:
    """Verify the original immutable manifest and ignore one post-hoc report."""

    root = Path(result_dir).resolve()
    expected = json.loads(
        (root / "checksums.json").read_text(encoding="utf-8")
    )
    if not isinstance(expected, dict) or not expected:
        raise ValueError("checksum manifest must be a nonempty object")
    for relative, expected_digest in expected.items():
        path = root / relative
        if not path.is_file():
            raise ValueError(f"checksum artifact is missing: {relative}")
        if _sha256(path) != expected_digest:
            raise ValueError(f"checksum mismatch: {relative}")
    unlisted = {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file()
        and path.name not in {"checksums.json", _POSTHOC_REPORT}
    } - set(expected)
    if unlisted:
        raise ValueError(
            f"checksum manifest omits artifacts: {sorted(unlisted)}"
        )
    return {
        "passed": True,
        "verified_file_count": len(expected),
    }


def _array(
    evidence: Mapping[str, np.ndarray],
    name: str,
) -> np.ndarray:
    if name not in evidence:
        raise ValueError(f"evidence is missing {name}")
    return np.asarray(evidence[name])


def _close(
    name: str,
    actual,
    expected,
    tolerance: float,
    differences: list[float],
) -> None:
    left = np.asarray(actual, dtype=np.float64)
    right = np.asarray(expected, dtype=np.float64)
    if left.shape != right.shape:
        raise ValueError(
            f"{name} shape mismatch: {left.shape} versus {right.shape}"
        )
    difference = float(
        np.max(np.abs(left - right), initial=0.0)
    )
    differences.append(difference)
    if not np.allclose(
        left,
        right,
        rtol=0.0,
        atol=float(tolerance),
    ):
        raise ValueError(
            f"{name} mismatch; maximum absolute difference {difference}"
        )


def _equal(name: str, actual, expected) -> None:
    if not np.array_equal(np.asarray(actual), np.asarray(expected)):
        raise ValueError(f"{name} mismatch")


def verify_posterior_snapshot_arrays(
    evidence: Mapping[str, np.ndarray],
    *,
    tolerance: float,
) -> dict[str, object]:
    """Recompute posterior state, covariance, parameter, and selection arrays."""

    states = _array(evidence, "origin_candidate_states").astype(
        np.float64
    )
    covariances = _array(
        evidence, "origin_candidate_covariances"
    ).astype(np.float64)
    probabilities = _array(evidence, "origin_probabilities").astype(
        np.float64
    )
    if states.ndim < 3:
        raise ValueError("candidate state snapshot rank is invalid")
    candidate_count = states.shape[-2]
    state_count = states.shape[-1]
    if covariances.shape != (*states.shape, state_count):
        raise ValueError("candidate covariance snapshot shape is invalid")
    if probabilities.shape != states.shape[:-1]:
        raise ValueError("posterior probability snapshot shape is invalid")
    if not all(
        np.all(np.isfinite(values))
        for values in (states, covariances, probabilities)
    ):
        raise ValueError("posterior snapshots contain nonfinite values")
    if np.any(probabilities < 0.0):
        raise ValueError("posterior probabilities are negative")
    differences: list[float] = []
    _close(
        "posterior probability normalization",
        np.sum(probabilities, axis=-1),
        np.ones(probabilities.shape[:-1]),
        tolerance,
        differences,
    )
    mean = np.einsum(
        "...i,...ij->...j",
        probabilities,
        states,
    )
    within = np.einsum(
        "...i,...ijk->...jk",
        probabilities,
        covariances,
    )
    deviations = states - mean[..., None, :]
    between = np.einsum(
        "...i,...ij,...ik->...jk",
        probabilities,
        deviations,
        deviations,
    )
    complete = within + between
    uniform_weights = np.full(
        candidate_count, 1.0 / candidate_count, dtype=np.float64
    )
    uniform_mean = np.einsum(
        "i,...ij->...j", uniform_weights, states
    )
    uniform_within = np.einsum(
        "i,...ijk->...jk", uniform_weights, covariances
    )
    uniform_deviations = states - uniform_mean[..., None, :]
    uniform_between = np.einsum(
        "i,...ij,...ik->...jk",
        uniform_weights,
        uniform_deviations,
        uniform_deviations,
    )
    uniform_complete = uniform_within + uniform_between
    for name, actual, expected in (
        ("posterior mean state", _array(evidence, "posterior_mean_states"), mean),
        (
            "posterior within covariance",
            _array(evidence, "posterior_within_covariances"),
            within,
        ),
        (
            "posterior between covariance",
            _array(evidence, "posterior_between_covariances"),
            between,
        ),
        (
            "posterior complete covariance",
            _array(evidence, "posterior_complete_covariances"),
            complete,
        ),
        (
            "uniform mean state",
            _array(evidence, "uniform_mean_states"),
            uniform_mean,
        ),
        (
            "uniform within covariance",
            _array(evidence, "uniform_within_covariances"),
            uniform_within,
        ),
        (
            "uniform between covariance",
            _array(evidence, "uniform_between_covariances"),
            uniform_between,
        ),
        (
            "uniform complete covariance",
            _array(evidence, "uniform_complete_covariances"),
            uniform_complete,
        ),
    ):
        _close(name, actual, expected, tolerance, differences)

    parameter_matrix = _array(
        evidence, "candidate_parameter_matrix"
    ).astype(np.float64)
    if (
        parameter_matrix.ndim != 2
        or parameter_matrix.shape[0] != candidate_count
        or not np.all(np.isfinite(parameter_matrix))
    ):
        raise ValueError("candidate parameter matrix shape is invalid")
    posterior_parameters = np.einsum(
        "...i,ij->...j", probabilities, parameter_matrix
    )
    uniform_parameters = np.broadcast_to(
        np.mean(parameter_matrix, axis=0),
        (*probabilities.shape[:-1], parameter_matrix.shape[1]),
    )
    maximum_indices = np.argmax(probabilities, axis=-1)
    maximum_parameters = parameter_matrix[maximum_indices]
    _close(
        "posterior weighted parameter vector",
        _array(evidence, "posterior_weighted_parameter_vectors"),
        posterior_parameters,
        tolerance,
        differences,
    )
    _close(
        "uniform parameter vector",
        _array(evidence, "uniform_parameter_vectors"),
        uniform_parameters,
        tolerance,
        differences,
    )
    _equal(
        "maximum posterior candidate index",
        _array(evidence, "maximum_posterior_indices"),
        maximum_indices,
    )
    _close(
        "maximum posterior parameter vector",
        _array(evidence, "maximum_parameter_vectors"),
        maximum_parameters,
        tolerance,
        differences,
    )
    return {
        "passed": True,
        "verified_numeric_field_count": len(differences),
        "maximum_absolute_difference": float(
            max(differences, default=0.0)
        ),
    }


def verify_algebraic_forecasts(
    evidence: Mapping[str, np.ndarray],
    *,
    tolerance: float,
) -> dict[str, object]:
    """Verify weighted discharge and maximum-candidate selection identities."""

    candidates = _array(
        evidence, "current_candidate_forecasts"
    ).astype(np.float64)
    probabilities = _array(
        evidence, "origin_probabilities"
    ).astype(np.float64)
    maximum_indices = _array(
        evidence, "maximum_posterior_indices"
    ).astype(np.int64)
    if candidates.ndim < 3:
        raise ValueError("candidate forecast rank is invalid")
    if probabilities.shape != candidates.shape[:-2] + (
        candidates.shape[-1],
    ):
        raise ValueError("candidate forecast probability shape is invalid")
    expected_indices = np.argmax(probabilities, axis=-1)
    _equal(
        "maximum posterior candidate index",
        maximum_indices,
        expected_indices,
    )
    differences: list[float] = []
    current = np.sum(
        candidates * probabilities[..., None, :],
        axis=-1,
    )
    _close(
        "current weighted forecast",
        _array(evidence, "forecast__current_multiple_states"),
        current,
        tolerance,
        differences,
    )
    selected_index = np.broadcast_to(
        maximum_indices[..., None, None],
        (*maximum_indices.shape, candidates.shape[-2], 1),
    )
    selected = np.take_along_axis(
        candidates, selected_index, axis=-1
    )[..., 0]
    _close(
        "maximum posterior candidate forecast",
        _array(evidence, "forecast__maximum_posterior_candidate"),
        selected,
        tolerance,
        differences,
    )
    return {
        "passed": True,
        "verified_numeric_field_count": len(differences),
        "maximum_absolute_difference": float(
            max(differences, default=0.0)
        ),
    }


def _independent_index() -> dict[str, np.ndarray]:
    leads = np.arange(1, 8, dtype=np.int64)
    origins = np.arange(180, 540, dtype=np.int64)
    targets = origins[:, None] + leads[None, :]
    available = targets < 540
    origin_stage = np.searchsorted(
        np.asarray([180, 360]), origins, side="right"
    )
    target_stage = np.full(targets.shape, -1, dtype=np.int64)
    target_stage[available] = np.searchsorted(
        np.asarray([180, 360]),
        targets[available],
        side="right",
    )
    same = available & (target_stage == origin_stage[:, None])
    cross = available & (target_stage > origin_stage[:, None])
    unavailable = ~available
    offsets = origins - np.where(origin_stage == 1, 180, 360)
    return {
        "lead_days": leads,
        "origin_indices": origins,
        "target_indices": targets,
        "origin_stage_indices": origin_stage,
        "target_stage_indices": target_stage,
        "days_since_switch": offsets,
        "same_stage_mask": same,
        "cross_switch_mask": cross,
        "unavailable_mask": unavailable,
    }


def _masked_rmse(
    squared_error: np.ndarray,
    mask: np.ndarray,
) -> np.ndarray:
    result = np.empty(squared_error.shape[-1], dtype=np.float64)
    for lead in range(squared_error.shape[-1]):
        result[lead] = np.sqrt(
            np.mean(squared_error[:, :, mask[:, lead], lead])
        )
    return result


def _block_mse(
    squared_error: np.ndarray,
    mask: np.ndarray,
) -> np.ndarray:
    result = np.empty(
        (squared_error.shape[0], squared_error.shape[-1]),
        dtype=np.float64,
    )
    for lead in range(squared_error.shape[-1]):
        result[:, lead] = np.mean(
            squared_error[:, :, mask[:, lead], lead],
            axis=(1, 2),
        )
    return result


def verify_statistics(
    evidence: Mapping[str, np.ndarray],
    summary: dict,
    config: dict,
    *,
    tolerance: float,
) -> dict[str, object]:
    """Recompute every saved metric, interval, stratum, and decision."""

    index = _independent_index()
    for name, expected in index.items():
        _equal(name, _array(evidence, name), expected)
    _equal(
        "same-stage sample count",
        np.sum(index["same_stage_mask"], axis=0),
        np.asarray([358, 356, 354, 352, 350, 348, 346]),
    )
    block_count = int(config["expected_block_count"])
    truth_count = int(config["expected_truth_count"])
    shape = (block_count, truth_count, 360, 7)
    truth = _array(evidence, "truth_forecasts").astype(np.float64)
    if truth.shape != shape or not np.all(np.isfinite(truth)):
        raise ValueError("truth forecast array is invalid")
    forecasts = {
        method: _array(evidence, f"forecast__{method}").astype(
            np.float64
        )
        for method in _ALL_METHODS
    }
    if any(
        values.shape != shape or not np.all(np.isfinite(values))
        for values in forecasts.values()
    ):
        raise ValueError("saved forecast arrays are invalid")
    squared = {
        method: np.square(values - truth)
        for method, values in forecasts.items()
    }
    rmse = {
        method: _masked_rmse(
            values, index["same_stage_mask"]
        )
        for method, values in squared.items()
    }
    block_mse = {
        method: _block_mse(
            values, index["same_stage_mask"]
        )
        for method, values in squared.items()
    }
    differences: list[float] = []
    for method in _ALL_METHODS:
        _close(
            f"{method} squared error",
            _array(evidence, f"squared_error__{method}"),
            squared[method],
            tolerance,
            differences,
        )
        _close(
            f"{method} block mean squared error",
            _array(evidence, f"block_mse__{method}"),
            block_mse[method],
            tolerance,
            differences,
        )
        _close(
            f"{method} root mean square error",
            _array(evidence, f"rmse__{method}"),
            rmse[method],
            tolerance,
            differences,
        )
        _close(
            f"{method} summary root mean square error",
            summary["result"]["rmse"][method],
            rmse[method],
            tolerance,
            differences,
        )

    bootstrap = _array(evidence, "bootstrap_indices").astype(np.int64)
    if bootstrap.shape != (
        int(config["bootstrap"]["replicates"]),
        block_count,
    ):
        raise ValueError("bootstrap index shape changed")
    if np.any(bootstrap < 0) or np.any(bootstrap >= block_count):
        raise ValueError("bootstrap index is out of range")
    fraction = float(
        config["decision_rules"][
            "minimum_meaningful_rmse_fraction"
        ]
    )
    baselines = (
        str(config["decision_rules"]["replacement_baseline"]),
        str(config["decision_rules"]["general_repair_baseline"]),
    )
    alternatives = tuple(
        method for method in _ALL_METHODS if method not in set(baselines)
    )
    expected_decisions = {}
    for method in alternatives:
        expected_decisions[method] = {}
        for baseline in baselines:
            comparison = f"minus_{baseline}"
            block_difference = block_mse[method] - block_mse[baseline]
            bootstrap_difference = np.mean(
                block_difference[bootstrap], axis=1
            )
            baseline_mse = np.mean(block_mse[baseline], axis=0)
            boundary = baseline_mse * (
                (1.0 - fraction) ** 2 - 1.0
            )
            relative = rmse[method] / rmse[baseline] - 1.0
            point = relative <= -fraction
            ci_low = np.percentile(
                bootstrap_difference, 2.5, axis=0
            )
            ci_high = np.percentile(
                bootstrap_difference, 97.5, axis=0
            )
            interval = ci_high < boundary
            fields = {
                "block_mean_mse_difference": block_difference,
                "mean_mse_difference": np.mean(
                    block_difference, axis=0
                ),
                "ci_low": ci_low,
                "ci_high": ci_high,
                "baseline_mse": baseline_mse,
                "meaningful_improvement_boundary": boundary,
                "relative_rmse_fraction": relative,
                "point_estimate_passes": point,
                "interval_passes": interval,
            }
            for field, expected in fields.items():
                saved = _array(
                    evidence,
                    f"comparison__{method}__{comparison}__{field}",
                )
                if np.asarray(expected).dtype == bool:
                    _equal(
                        f"{method} {comparison} {field}",
                        saved,
                        expected,
                    )
                else:
                    _close(
                        f"{method} {comparison} {field}",
                        saved,
                        expected,
                        tolerance,
                        differences,
                    )
            saved_summary = summary["result"]["comparisons"][method][
                comparison
            ]
            for field in (
                "mean_mse_difference",
                "ci_low",
                "ci_high",
                "baseline_mse",
                "meaningful_improvement_boundary",
                "relative_rmse_fraction",
            ):
                _close(
                    f"{method} {comparison} summary {field}",
                    saved_summary[field],
                    fields[field],
                    tolerance,
                    differences,
                )
            _equal(
                f"{method} {comparison} summary point gate",
                saved_summary["point_estimate_passes"],
                point,
            )
            _equal(
                f"{method} {comparison} summary interval gate",
                saved_summary["interval_passes"],
                interval,
            )
            all_pass = bool(np.all(point) and np.all(interval))
            if bool(saved_summary["all_leads_pass"]) != all_pass:
                raise ValueError(
                    f"{method} {comparison} all-lead decision mismatch"
                )
            expected_decisions[method][baseline] = all_pass
        saved_decision = summary["result"]["decisions"][method]
        if (
            bool(saved_decision["replace_current_multiple_states"])
            != expected_decisions[method][baselines[0]]
            or bool(saved_decision["repair_general_degradation"])
            != expected_decisions[method][baselines[1]]
        ):
            raise ValueError(f"{method} decision mismatch")

    offsets = index["days_since_switch"]
    for stratum, minimum, maximum in _TIME_STRATA:
        stratum_mask = index["same_stage_mask"] & (
            (offsets >= minimum) & (offsets <= maximum)
        )[:, None]
        _equal(
            f"{stratum} sample count",
            _array(
                evidence, f"stratum__{stratum}__sample_count"
            ),
            np.sum(stratum_mask, axis=0),
        )
        for method in _ALL_METHODS:
            expected = _masked_rmse(squared[method], stratum_mask)
            _close(
                f"{stratum} {method} root mean square error",
                _array(
                    evidence,
                    f"stratum__{stratum}__rmse__{method}",
                ),
                expected,
                tolerance,
                differences,
            )
            _close(
                f"{stratum} {method} summary",
                summary["result"]["time_strata"][stratum]["rmse"][
                    method
                ],
                expected,
                tolerance,
                differences,
            )
    return {
        "passed": True,
        "verified_numeric_field_count": len(differences),
        "maximum_absolute_difference": float(
            max(differences, default=0.0)
        ),
    }


def _single_candidate_forecast(
    parameters: np.ndarray,
    state: np.ndarray,
    covariance: np.ndarray,
    process_covariance: np.ndarray,
    process_scale: float,
    observation_standard_deviation: float,
    future_forcing: np.ndarray,
    lead_days: np.ndarray,
    identifier: str,
) -> tuple[np.ndarray, np.ndarray]:
    parameter_dict = {
        name: float(value)
        for name, value in zip(PARAMETER_NAMES, parameters)
    }
    candidate = MethodCandidate(
        candidate_id=identifier,
        parameter_id=identifier,
        process_id="process_2",
        process_scale=float(process_scale),
        parameters=parameter_dict,
        process_covariance=np.asarray(
            process_covariance, dtype=np.float64
        ).copy(),
    )
    bank = build_method_bank(
        (candidate,),
        {identifier: np.asarray(state, dtype=np.float64)},
        np.asarray(covariance, dtype=np.float64),
        float(observation_standard_deviation),
        factor_transition_stay_probability=1.0,
        interaction_mode="none",
    )
    projected = bank.estimator.filters[0].state.copy()
    forecast = forecast_from_posterior(
        bank,
        future_forcing,
        lead_days=lead_days,
        interaction_mode="none",
    )
    return forecast.combined_predictions, projected


def verify_forecast_reconstruction(
    evidence: Mapping[str, np.ndarray],
    *,
    tolerance: float,
    progress_callback=None,
) -> dict[str, object]:
    """Rebuild every candidate and unique-state forecast from origin snapshots."""

    states = _array(evidence, "origin_candidate_states").astype(
        np.float64
    )
    covariances = _array(
        evidence, "origin_candidate_covariances"
    ).astype(np.float64)
    candidate_parameters = _array(
        evidence, "candidate_parameter_matrix"
    ).astype(np.float64)
    future_forcing = _array(evidence, "future_forcing").astype(
        np.float64
    )
    lead_days = _array(evidence, "lead_days").astype(np.int64)
    process_covariance = _array(
        evidence, "selected_process_covariance"
    ).astype(np.float64)
    process_scale = float(
        _array(evidence, "selected_process_scale")
    )
    observation_standard_deviation = float(
        _array(evidence, "observation_standard_deviation")
    )
    saved_candidate_forecasts = _array(
        evidence, "current_candidate_forecasts"
    ).astype(np.float64)
    projected_states = _array(
        evidence, "unique_projected_states"
    ).astype(np.float64)
    unique_method_names = tuple(
        _array(evidence, "unique_method_names").astype(str)
    )
    if unique_method_names != _UNIQUE_METHODS:
        raise ValueError("unique method order changed")
    if states.shape[:3] != (8, 3, 360):
        raise ValueError("origin state snapshot shape changed")
    if future_forcing.shape != (8, 360, 7, 3):
        raise ValueError("future forcing shape changed")

    posterior_mean = _array(evidence, "posterior_mean_states")
    posterior_within = _array(
        evidence, "posterior_within_covariances"
    )
    posterior_complete = _array(
        evidence, "posterior_complete_covariances"
    )
    uniform_mean = _array(evidence, "uniform_mean_states")
    uniform_complete = _array(
        evidence, "uniform_complete_covariances"
    )
    posterior_parameters = _array(
        evidence, "posterior_weighted_parameter_vectors"
    )
    maximum_parameters = _array(
        evidence, "maximum_parameter_vectors"
    )
    uniform_parameters = _array(
        evidence, "uniform_parameter_vectors"
    )
    unique_contracts = {
        _UNIQUE_METHODS[0]: (
            posterior_mean,
            posterior_complete,
            posterior_parameters,
        ),
        _UNIQUE_METHODS[1]: (
            posterior_mean,
            posterior_within,
            posterior_parameters,
        ),
        _UNIQUE_METHODS[2]: (
            posterior_mean,
            posterior_complete,
            maximum_parameters,
        ),
        _UNIQUE_METHODS[3]: (
            uniform_mean,
            uniform_complete,
            uniform_parameters,
        ),
    }
    maximum_difference = 0.0
    field_count = 0
    started = time.monotonic()
    for block in range(8):
        for truth_case in range(3):
            for origin in range(360):
                forcing = future_forcing[block, origin]
                for candidate_index in range(3):
                    prediction, _ = _single_candidate_forecast(
                        candidate_parameters[candidate_index],
                        states[
                            block,
                            truth_case,
                            origin,
                            candidate_index,
                        ],
                        covariances[
                            block,
                            truth_case,
                            origin,
                            candidate_index,
                        ],
                        process_covariance,
                        process_scale,
                        observation_standard_deviation,
                        forcing,
                        lead_days,
                        (
                            f"verify_candidate_{candidate_index}_"
                            f"{block}_{truth_case}_{origin}"
                        ),
                    )
                    difference = float(
                        np.max(
                            np.abs(
                                prediction
                                - saved_candidate_forecasts[
                                    block,
                                    truth_case,
                                    origin,
                                    :,
                                    candidate_index,
                                ]
                            )
                        )
                    )
                    maximum_difference = max(
                        maximum_difference, difference
                    )
                    field_count += 1
                    if difference > tolerance:
                        raise ValueError(
                            "candidate forecast reconstruction mismatch; "
                            f"maximum difference {difference}"
                        )
                for method_index, method in enumerate(_UNIQUE_METHODS):
                    state_values, covariance_values, parameter_values = (
                        unique_contracts[method]
                    )
                    prediction, projected = _single_candidate_forecast(
                        parameter_values[block, truth_case, origin],
                        state_values[block, truth_case, origin],
                        covariance_values[block, truth_case, origin],
                        process_covariance,
                        process_scale,
                        observation_standard_deviation,
                        forcing,
                        lead_days,
                        (
                            f"verify_{method_index}_"
                            f"{block}_{truth_case}_{origin}"
                        ),
                    )
                    saved = _array(
                        evidence, f"forecast__{method}"
                    )[block, truth_case, origin]
                    forecast_difference = float(
                        np.max(np.abs(prediction - saved))
                    )
                    projection_difference = float(
                        np.max(
                            np.abs(
                                projected
                                - projected_states[
                                    block,
                                    truth_case,
                                    origin,
                                    method_index,
                                ]
                            )
                        )
                    )
                    difference = max(
                        forecast_difference, projection_difference
                    )
                    maximum_difference = max(
                        maximum_difference, difference
                    )
                    field_count += 2
                    if difference > tolerance:
                        raise ValueError(
                            f"{method} reconstruction mismatch; "
                            f"maximum difference {difference}"
                        )
        if progress_callback is not None:
            progress_callback(
                block + 1,
                8,
                time.monotonic() - started,
            )
    return {
        "passed": True,
        "verified_forecast_origin_count": 8 * 3 * 360,
        "verified_numeric_field_count": field_count,
        "maximum_absolute_difference": maximum_difference,
    }


def _verify_source_and_inputs(
    repo_root: Path,
    result_dir: Path,
    config: dict,
    summary: dict,
) -> dict[str, object]:
    source_snapshot = result_dir / "source_snapshot"
    differences = []
    for relative in _SOURCE_FILES:
        current = (repo_root / relative).resolve()
        saved = source_snapshot / current.name
        if not current.is_file() or not saved.is_file():
            raise ValueError(f"source snapshot is missing {relative}")
        current_hash = _sha256(current)
        saved_hash = _sha256(saved)
        if current_hash != saved_hash:
            raise ValueError(f"source snapshot mismatch: {relative}")
    input_keys = (
        ("sealed_ideal_input_evidence", "ideal_input_evidence_sha256"),
        (
            "sealed_daily_rolling_evidence",
            "daily_rolling_evidence_sha256",
        ),
        ("sealed_factorial_evidence", "factorial_evidence_sha256"),
    )
    for config_key, summary_key in input_keys:
        source = config[config_key]
        actual = _sha256((repo_root / source["path"]).resolve())
        if actual != source["sha256"] or summary[summary_key] != actual:
            raise ValueError(f"input source mismatch: {config_key}")
        differences.append(0.0)
    return {
        "passed": True,
        "verified_source_file_count": len(_SOURCE_FILES),
        "verified_input_file_count": len(input_keys),
        "maximum_absolute_difference": max(differences, default=0.0),
    }


def _verify_protected(
    repo_root: Path,
    result_dir: Path,
    config: dict,
    summary: dict,
) -> dict[str, object]:
    record = json.loads(
        (result_dir / "protected_artifact_integrity.json").read_text(
            encoding="utf-8"
        )
    )
    if (
        record.get("status") != "unchanged"
        or record.get("before") != record.get("after_evidence_writes")
        or summary.get("protected_artifacts_unchanged") is not True
    ):
        raise ValueError("protected artifact record reports a change")
    current = _protected_hashes(
        repo_root, config.get("protected_paths", ())
    )
    if current != record["after_evidence_writes"]:
        raise ValueError("protected artifacts changed after the run")
    return {
        "passed": True,
        "verified_protected_path_count": len(
            config.get("protected_paths", ())
        ),
    }


def verify_result_directory(
    repo_root: Path,
    result_dir: Path,
    *,
    progress_callback=None,
) -> dict[str, object]:
    root = Path(repo_root).resolve()
    result = Path(result_dir).resolve()
    checksum_report = verify_checksums(result)
    config = json.loads(
        (result / "config_snapshot.json").read_text(encoding="utf-8")
    )
    summary = json.loads(
        (result / "summary.json").read_text(encoding="utf-8")
    )
    cross_checks = json.loads(
        (result / "cross_checks.json").read_text(encoding="utf-8")
    )
    if (
        config.get("classification")
        != "development_mechanism_comparison"
        or tuple(config.get("readout_methods", ())) != _READOUT_METHODS
        or tuple(config.get("comparison_controls", ())) != _CONTROLS
        or tuple(config.get("lead_days", ())) != tuple(range(1, 8))
        or tuple(config.get("stage_lengths", ())) != (180, 180, 180)
        or tuple(config.get("switch_days", ())) != (180, 360)
        or config.get("expected_block_count") != 8
        or config.get("expected_truth_count") != 3
        or config.get("expected_candidate_count") != 3
        or config.get("expected_state_count") != 15
    ):
        raise ValueError("config snapshot does not match frozen design")
    if (
        summary.get("integrity_status") != "passed"
        or cross_checks.get("passed") is not True
    ):
        raise ValueError("runner integrity checks did not pass")
    expected_config_hash = hashlib.sha256(
        (result / "config_snapshot.json").read_bytes()
    ).hexdigest()
    if summary.get("config_sha256") != expected_config_hash:
        raise ValueError("config snapshot hash mismatch")
    with np.load(result / "evidence.npz", allow_pickle=False) as archive:
        evidence = {
            name: np.asarray(archive[name])
            for name in archive.files
        }
    tolerance = float(
        config["numerical_tolerances"]["verification"]
    )
    snapshot_report = verify_posterior_snapshot_arrays(
        evidence, tolerance=tolerance
    )
    algebraic_report = verify_algebraic_forecasts(
        evidence, tolerance=tolerance
    )
    reconstruction_report = verify_forecast_reconstruction(
        evidence,
        tolerance=tolerance,
        progress_callback=progress_callback,
    )
    statistics_report = verify_statistics(
        evidence,
        summary,
        config,
        tolerance=tolerance,
    )
    source_report = _verify_source_and_inputs(
        root, result, config, summary
    )
    protected_report = _verify_protected(
        root, result, config, summary
    )
    maximum_difference = max(
        report.get("maximum_absolute_difference", 0.0)
        for report in (
            snapshot_report,
            algebraic_report,
            reconstruction_report,
            statistics_report,
            source_report,
        )
    )
    return {
        "passed": True,
        "checksums": checksum_report,
        "posterior_snapshots": snapshot_report,
        "algebraic_forecasts": algebraic_report,
        "forecast_reconstruction": reconstruction_report,
        "statistics": statistics_report,
        "sources_and_inputs": source_report,
        "protected_artifacts": protected_report,
        "maximum_absolute_difference": float(maximum_difference),
    }


def _write_report(path: Path, report: dict) -> None:
    target = Path(path)
    temporary = target.with_name(f".{target.name}.{os.getpid()}.tmp")
    temporary.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, target)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--result-dir", type=Path, required=True)
    parser.add_argument("--write-report", action="store_true")
    arguments = parser.parse_args()
    result_dir = arguments.result_dir
    if not result_dir.is_absolute():
        result_dir = arguments.repo_root / result_dir

    def progress(completed, total, elapsed):
        print(
            json.dumps(
                {
                    "verified_blocks": completed,
                    "total_blocks": total,
                    "elapsed_seconds": round(float(elapsed), 1),
                }
            ),
            flush=True,
        )

    report = verify_result_directory(
        arguments.repo_root,
        result_dir,
        progress_callback=progress,
    )
    if arguments.write_report:
        _write_report(result_dir / _POSTHOC_REPORT, report)
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
