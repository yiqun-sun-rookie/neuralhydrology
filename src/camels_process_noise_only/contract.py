"""Frozen pure-data contract for the CAMELS-US process-noise-only design."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

import numpy as np
import pandas as pd


APPROVED_SIGMAS = np.array([0.01, 0.02, 0.04], dtype=np.float64)
APPROVED_ROTATION = np.array([1, 0, 2, 1, 2, 0, 1], dtype=np.int64)
APPROVED_STAGE_DAYS = 365
APPROVED_DESIGN_SEEDS = [0, 1]
N_CANDIDATES = 3
APPROVED_CONFIGURATION_REVISION = "01a_machine_precision_domain_tolerance"
APPROVED_DOMAIN_TOLERANCE_MULTIPLIER = 32.0


@dataclass(frozen=True)
class DomainProjectionCheck:
    """Numerical comparison between one raw state and its physical projection."""

    maximum_absolute_difference: float
    maximum_tolerance_ratio: float
    nonzero_difference_count: int
    violating_component_count: int
    violated: bool


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def validate_design_config(config: Mapping) -> None:
    """Reject any drift from the user-approved exploratory design contract."""
    _require(
        config.get("experiment_id") == "CAMELS_PROCESS_NOISE_ONLY_01",
        "experiment_id must be CAMELS_PROCESS_NOISE_ONLY_01",
    )
    _require(
        config.get("configuration_status")
        == "registered_exploratory_design_not_validation_frozen",
        "configuration status must remain exploratory and not validation frozen",
    )
    _require(
        config.get("configuration_revision") == APPROVED_CONFIGURATION_REVISION,
        "configuration revision must be the registered 01A domain-tolerance revision",
    )
    _require(
        config.get("supersedes_failed_config_sha256")
        == "5e26f85f64c95cea864194430bb223affbebfb187d491edb2908479a31d68af7",
        "configuration must preserve the failed predecessor SHA-256",
    )
    truth = config.get("truth", {})
    sigmas = np.asarray(truth.get("candidate_lognormal_sigmas", []), dtype=float)
    _require(
        sigmas.shape == APPROVED_SIGMAS.shape
        and np.array_equal(sigmas, APPROVED_SIGMAS),
        "candidate lognormal sigmas must be exactly [0.01, 0.02, 0.04]",
    )
    rotation = np.asarray(truth.get("rotation", []), dtype=np.int64)
    _require(
        rotation.shape == APPROVED_ROTATION.shape
        and np.array_equal(rotation, APPROVED_ROTATION),
        "truth rotation must be exactly [1, 0, 2, 1, 2, 0, 1]",
    )
    stage_days = truth.get("stage_days")
    _require(stage_days == APPROVED_STAGE_DAYS, "stage_days must be 365")
    _require(
        truth.get("window_days") == APPROVED_STAGE_DAYS * len(APPROVED_ROTATION),
        "window_days must equal seven 365-day stages",
    )
    _require(truth.get("noise_state_index") == 4, "noise_state_index must be 4")
    domain = truth.get("domain_check", {})
    expected_domain = {
        "method": "componentwise_projector_difference",
        "float_type": "float64",
        "tolerance_multiplier": APPROVED_DOMAIN_TOLERANCE_MULTIPLIER,
        "scale": "max(1, abs(raw_i), abs(projected_i))",
        "violation_rule": (
            "abs(projected_i-raw_i) > "
            "tolerance_multiplier*eps64*scale_i"
        ),
        "record_nonzero_differences": True,
        "replace_truth_state_with_projection": False,
    }
    for key, value in expected_domain.items():
        _require(domain.get(key) == value, f"truth domain check {key} changed")

    seeds = config.get("seeds", {})
    _require(
        seeds.get("design") == APPROVED_DESIGN_SEEDS,
        "design seeds must be exactly [0, 1]",
    )
    _require(
        seeds.get("reserved_validation_not_authorized") == [2, 3],
        "validation seeds 2 and 3 must remain reserved and unauthorized",
    )
    _require(seeds.get("entropy") == 20260809, "seed entropy must be 20260809")

    filter_config = config.get("filter", {})
    _require(
        filter_config.get("interaction_mode") == "full",
        "filter interaction must be full",
    )
    _require(filter_config.get("candidate_count") == 3, "candidate_count must be 3")
    _require(filter_config.get("state_dimension") == 15, "state_dimension must be 15")
    diagonal = float(filter_config.get("transition_diagonal", np.nan))
    off_diagonal = float(filter_config.get("transition_off_diagonal", np.nan))
    _require(
        np.isclose(diagonal, 364.0 / 365.0, rtol=0.0, atol=1e-16),
        "transition diagonal must be 364/365",
    )
    _require(
        np.isclose(off_diagonal, 1.0 / 730.0, rtol=0.0, atol=1e-18),
        "transition off diagonal must be 1/730",
    )
    _require(
        np.isclose(diagonal + 2.0 * off_diagonal, 1.0, rtol=0.0, atol=1e-15),
        "transition probabilities must sum to one",
    )

    event = config.get("event_rule", {})
    expected_event = {
        "adaptation_days": 90,
        "scoring_day_start_one_based": 91,
        "scoring_day_end_one_based": 180,
        "scoring_days": 90,
        "minimum_mean_true_probability": 0.5,
        "minimum_mean_margin": 0.1,
        "minimum_true_daily_argmax_days": 60,
    }
    for key, value in expected_event.items():
        _require(event.get(key) == value, f"event rule {key} must be {value}")

    metrics = config.get("probability_metrics", {})
    _require(
        metrics.get("stable_day_start_one_based") == 181
        and metrics.get("stable_day_end_one_based") == 365,
        "stable probability window must be days 181 through 365",
    )
    _require(
        metrics.get("maximum_mean_multiclass_brier") == 0.6,
        "maximum mean multiclass Brier score must be 0.6",
    )
    _require(
        metrics.get("maximum_classwise_expected_calibration_error") == 0.1,
        "maximum classwise expected calibration error must be 0.1",
    )

    selection = config.get("design_selection", {})
    _require(selection.get("basin_count") == 90, "design basin count must be 90")
    _require(
        selection.get("basins_per_tertile") == 30,
        "design selection must contain 30 basins per tertile",
    )
    _require(
        selection.get("source_rows_per_tertile") == 177,
        "each source tertile must contain 177 basins",
    )
    integrity = config.get("integrity", {})
    for key in (
        "require_zero_truth_domain_violations",
        "require_zero_truth_state_replacements",
        "require_recorded_raw_projection_differences",
    ):
        _require(integrity.get(key) is True, f"integrity contract {key} must be true")


def evaluate_domain_projection(
    raw_state,
    projected_state,
    tolerance_multiplier: float,
) -> DomainProjectionCheck:
    """Apply the registered componentwise float64 physical-domain check."""
    raw = np.asarray(raw_state, dtype=np.float64)
    projected = np.asarray(projected_state, dtype=np.float64)
    if raw.shape != projected.shape or raw.size == 0:
        raise ValueError("raw and projected states must have the same nonempty shape")
    if not np.all(np.isfinite(raw)) or not np.all(np.isfinite(projected)):
        raise ValueError("raw and projected states must be finite")
    multiplier = float(tolerance_multiplier)
    if not np.isfinite(multiplier) or multiplier <= 0.0:
        raise ValueError("domain tolerance multiplier must be finite and positive")
    difference = np.abs(projected - raw)
    scale = np.maximum.reduce(
        (np.ones_like(raw), np.abs(raw), np.abs(projected))
    )
    tolerance = multiplier * np.finfo(np.float64).eps * scale
    ratios = difference / tolerance
    violating = difference > tolerance
    return DomainProjectionCheck(
        maximum_absolute_difference=float(np.max(difference)),
        maximum_tolerance_ratio=float(np.max(ratios)),
        nonzero_difference_count=int(np.count_nonzero(difference)),
        violating_component_count=int(np.count_nonzero(violating)),
        violated=bool(np.any(violating)),
    )


def load_design_config(path: str | Path) -> dict:
    """Load a JSON design config and enforce every frozen invariant."""
    with Path(path).open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    validate_design_config(config)
    return config


def lognormal_variance(lower_groundwater_state: float, sigma: float) -> float:
    """Return the exact conditional variance of the mean-preserving multiplier."""
    state = float(lower_groundwater_state)
    noise_sigma = float(sigma)
    if not np.isfinite(state) or state < 0.0:
        raise ValueError("lower-groundwater state must be finite and nonnegative")
    if not np.isfinite(noise_sigma) or noise_sigma <= 0.0:
        raise ValueError("lognormal sigma must be finite and positive")
    return float(state**2 * np.expm1(noise_sigma**2))


def truth_candidate_indices(config: Mapping) -> np.ndarray:
    """Return the exact daily true noise-candidate index."""
    validate_design_config(config)
    stage_days = int(config["truth"]["stage_days"])
    rotation = np.asarray(config["truth"]["rotation"], dtype=np.int64)
    return np.repeat(rotation, stage_days)


def switch_days_and_directions(config: Mapping) -> list[tuple[int, int, int]]:
    """Return zero-based switch day, old index, and new index."""
    validate_design_config(config)
    stage_days = int(config["truth"]["stage_days"])
    rotation = [int(value) for value in config["truth"]["rotation"]]
    return [
        (stage_position * stage_days, rotation[stage_position - 1], rotation[stage_position])
        for stage_position in range(1, len(rotation))
    ]


def _validated_probabilities(probabilities, minimum_days: int) -> np.ndarray:
    values = np.asarray(probabilities, dtype=np.float64)
    if values.ndim != 2 or values.shape[1] != N_CANDIDATES:
        raise ValueError("probabilities must have shape (days, 3)")
    if len(values) < minimum_days:
        raise ValueError(f"probabilities must contain at least {minimum_days} days")
    if not np.all(np.isfinite(values)) or np.any(values < 0.0):
        raise ValueError("probabilities must be finite and nonnegative")
    if not np.allclose(values.sum(axis=1), 1.0, rtol=0.0, atol=1e-12):
        raise ValueError("daily probabilities must sum to one within 1e-12")
    return values


def evaluate_event(probabilities, true_index: int, config: Mapping) -> dict:
    """Evaluate one 365-day post-switch stage with the fixed 90-day rule."""
    validate_design_config(config)
    values = _validated_probabilities(
        probabilities, int(config["event_rule"]["scoring_day_end_one_based"])
    )
    true_candidate = int(true_index)
    if true_candidate < 0 or true_candidate >= N_CANDIDATES:
        raise ValueError("true_index must be 0, 1, or 2")
    start = int(config["event_rule"]["scoring_day_start_one_based"]) - 1
    end = int(config["event_rule"]["scoring_day_end_one_based"])
    segment = values[start:end]
    mean_probabilities = segment.mean(axis=0)
    mean_true = float(mean_probabilities[true_candidate])
    runner_up = float(np.max(np.delete(mean_probabilities, true_candidate)))
    margin = mean_true - runner_up
    other_daily = np.max(np.delete(segment, true_candidate, axis=1), axis=1)
    true_argmax_days = int(np.sum(segment[:, true_candidate] > other_daily))
    event_config = config["event_rule"]
    passed = bool(
        mean_true >= float(event_config["minimum_mean_true_probability"])
        and margin >= float(event_config["minimum_mean_margin"])
        and true_argmax_days
        >= int(event_config["minimum_true_daily_argmax_days"])
    )
    return {
        "passed": passed,
        "mean_true_probability": mean_true,
        "mean_runner_up_probability": runner_up,
        "mean_margin": float(margin),
        "true_daily_argmax_days": true_argmax_days,
    }


def _stable_indices(config: Mapping) -> np.ndarray:
    stage_days = int(config["truth"]["stage_days"])
    start = int(config["probability_metrics"]["stable_day_start_one_based"]) - 1
    end = int(config["probability_metrics"]["stable_day_end_one_based"])
    indices = []
    for stage_position in range(1, len(config["truth"]["rotation"])):
        offset = stage_position * stage_days
        indices.extend(range(offset + start, offset + end))
    return np.asarray(indices, dtype=np.int64)


def _classwise_expected_calibration_error(
    probabilities: np.ndarray,
    truth: np.ndarray,
    bin_edges: np.ndarray,
) -> float:
    total_count = len(truth)
    errors = []
    for candidate in range(N_CANDIDATES):
        candidate_probabilities = probabilities[:, candidate]
        outcomes = (truth == candidate).astype(np.float64)
        bins = np.digitize(candidate_probabilities, bin_edges[1:-1], right=False)
        error = 0.0
        for bin_index in range(len(bin_edges) - 1):
            mask = bins == bin_index
            count = int(mask.sum())
            if count == 0:
                continue
            error += count / total_count * abs(
                float(candidate_probabilities[mask].mean())
                - float(outcomes[mask].mean())
            )
        errors.append(error)
    return float(np.mean(errors))


def score_probabilities(
    probabilities,
    log_probabilities,
    truth_indices,
    config: Mapping,
) -> dict:
    """Score the six registered stable post-switch periods."""
    validate_design_config(config)
    expected_days = int(config["truth"]["window_days"])
    ordinary = _validated_probabilities(probabilities, expected_days)
    if len(ordinary) != expected_days:
        raise ValueError(f"probabilities must contain exactly {expected_days} days")
    logs = np.asarray(log_probabilities, dtype=np.float64)
    if logs.shape != ordinary.shape or not np.all(np.isfinite(logs)):
        raise ValueError("log_probabilities must be finite and match probabilities")
    truth = np.asarray(truth_indices)
    if truth.shape != (expected_days,) or not np.issubdtype(truth.dtype, np.integer):
        raise ValueError("truth_indices must be one integer per day")
    if np.any(truth < 0) or np.any(truth >= N_CANDIDATES):
        raise ValueError("truth_indices contain an invalid candidate")

    indices = _stable_indices(config)
    scored_probabilities = ordinary[indices]
    scored_logs = logs[indices]
    scored_truth = truth[indices].astype(np.int64, copy=False)
    one_hot = np.eye(N_CANDIDATES, dtype=np.float64)[scored_truth]
    brier = float(np.mean(np.sum((scored_probabilities - one_hot) ** 2, axis=1)))
    true_logs = scored_logs[np.arange(len(indices)), scored_truth]
    negative_log_probability = float(np.mean(-true_logs))
    bin_edges = np.asarray(
        config["probability_metrics"]["calibration_bin_edges"], dtype=np.float64
    )
    calibration = _classwise_expected_calibration_error(
        scored_probabilities, scored_truth, bin_edges
    )
    return {
        "n_days": int(len(indices)),
        "multiclass_brier": brier,
        "true_negative_log_probability": negative_log_probability,
        "classwise_expected_calibration_error": calibration,
    }


def select_design_basins(
    parameter_table: pd.DataFrame,
    g1_table: pd.DataFrame,
    config: Mapping,
) -> pd.DataFrame:
    """Select 30 deterministic equally spaced basins from each proxy tertile."""
    validate_design_config(config)
    parameter_columns = {"basin_id", "p_parPERC", "p_parK2"}
    g1_columns = {"basin_id", "sigma_obs"}
    if not parameter_columns.issubset(parameter_table.columns):
        raise ValueError("parameter table is missing required process-noise proxy fields")
    if not g1_columns.issubset(g1_table.columns):
        raise ValueError("G1 table is missing basin_id or sigma_obs")
    parameters = parameter_table[list(parameter_columns)].copy()
    observations = g1_table[list(g1_columns)].copy()
    parameters["basin_id"] = parameters["basin_id"].astype(str).str.zfill(8)
    observations["basin_id"] = observations["basin_id"].astype(str).str.zfill(8)
    merged = parameters.merge(
        observations,
        on="basin_id",
        how="inner",
        validate="one_to_one",
    )
    if len(merged) != 531:
        raise ValueError("design selection requires exactly 531 matched basins")
    numeric = merged[["p_parPERC", "p_parK2", "sigma_obs"]].to_numpy(
        dtype=np.float64
    )
    if not np.all(np.isfinite(numeric)):
        raise ValueError("design proxy inputs must be finite")
    if np.any(merged["p_parK2"].to_numpy(dtype=float) <= 0.0):
        raise ValueError("parK2 must be positive")
    if np.any(merged["sigma_obs"].to_numpy(dtype=float) <= 0.0):
        raise ValueError("sigma_obs must be positive")
    lower_scale = np.maximum(
        merged["p_parPERC"].to_numpy(dtype=float)
        / merged["p_parK2"].to_numpy(dtype=float),
        1.0,
    )
    proxy = (
        merged["p_parK2"].to_numpy(dtype=float)
        * lower_scale
        * np.sqrt(np.expm1(0.02**2))
        / merged["sigma_obs"].to_numpy(dtype=float)
    )
    merged["process_noise_observation_proxy"] = proxy
    ordered = merged.sort_values(
        ["process_noise_observation_proxy", "basin_id"], kind="mergesort"
    ).reset_index(drop=True)
    ordered["source_global_rank"] = np.arange(len(ordered), dtype=np.int64)
    positions = np.rint(np.linspace(0, 176, 30)).astype(np.int64)
    selected_frames = []
    for tertile in range(3):
        start = tertile * 177
        block = ordered.iloc[start : start + 177].reset_index(drop=True)
        chosen = block.iloc[positions].copy()
        chosen["proxy_tertile"] = tertile + 1
        chosen["within_tertile_position"] = positions
        selected_frames.append(chosen)
    selected = pd.concat(selected_frames, ignore_index=True)
    columns = [
        "basin_id",
        "proxy_tertile",
        "within_tertile_position",
        "source_global_rank",
        "process_noise_observation_proxy",
        "p_parPERC",
        "p_parK2",
        "sigma_obs",
    ]
    return selected[columns]
