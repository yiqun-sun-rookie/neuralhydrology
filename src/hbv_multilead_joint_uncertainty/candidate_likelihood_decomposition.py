"""Read-only decomposition of frozen candidate Gaussian observation log likelihoods."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


_ATTRIBUTION_FAMILIES = {
    "variance_penalty_dominant": "variance",
    "variance_penalty_dominant_both_negative": "variance",
    "innovation_penalty_dominant": "innovation",
    "innovation_penalty_dominant_both_negative": "innovation",
}


@dataclass(frozen=True)
class DailyLogLikelihoodComponents:
    """Elementwise Gaussian log-likelihood split into its two penalty terms."""

    variance_penalty: np.ndarray
    innovation_penalty: np.ndarray


@dataclass(frozen=True)
class ComponentMarginScores:
    """Stage-cumulative components and true-vs-best-wrong margin decomposition."""

    cumulative_variance_penalty: np.ndarray
    cumulative_innovation_penalty: np.ndarray
    cumulative_total: np.ndarray
    best_wrong_candidate_indices: np.ndarray
    best_wrong_tie_counts: np.ndarray
    final_delta_variance: np.ndarray
    final_delta_innovation: np.ndarray
    final_delta_total: np.ndarray
    daily_best_wrong_candidate_indices: np.ndarray
    daily_delta_variance: np.ndarray
    daily_delta_innovation: np.ndarray
    daily_delta_total: np.ndarray


def decompose_daily_log_likelihoods(
    innovations, innovation_variances
) -> DailyLogLikelihoodComponents:
    """Split -0.5*(log(2*pi*S) + nu^2/S) into its variance and innovation terms."""

    innovation_values = np.asarray(innovations, dtype=np.float64)
    variance_values = np.asarray(innovation_variances, dtype=np.float64)
    if innovation_values.shape != variance_values.shape:
        raise ValueError("innovations and innovation_variances must share one shape")
    if not np.all(np.isfinite(innovation_values)) or not np.all(
        np.isfinite(variance_values)
    ):
        raise ValueError("innovations and innovation_variances must be finite")
    if not np.all(variance_values > 0.0):
        raise ValueError("innovation_variances must be strictly positive")
    return DailyLogLikelihoodComponents(
        variance_penalty=-0.5 * np.log(2.0 * np.pi * variance_values),
        innovation_penalty=-0.5 * np.square(innovation_values) / variance_values,
    )


def _take_candidate(values: np.ndarray, indices: np.ndarray) -> np.ndarray:
    return np.take_along_axis(values, indices[..., None], axis=-1)[..., 0]


def score_component_margins(
    variance_penalty, innovation_penalty, truth_candidate_indices
) -> ComponentMarginScores:
    """Accumulate components per stage and decompose true-vs-best-wrong margins.

    The comparator on every day is the wrong candidate with the maximum TOTAL
    cumulative log likelihood on that day; final-day quantities therefore use the
    same best wrong candidate as the frozen day-10 margin. Ties take the lowest
    candidate index and are counted separately.
    """

    variance_values = np.asarray(variance_penalty, dtype=np.float64)
    innovation_values = np.asarray(innovation_penalty, dtype=np.float64)
    truth = np.asarray(truth_candidate_indices, dtype=np.int64)
    if variance_values.ndim != 5 or variance_values.shape != innovation_values.shape:
        raise ValueError(
            "component arrays must share shape (blocks, truths, stages, days, candidates)"
        )
    if not np.all(np.isfinite(variance_values)) or not np.all(
        np.isfinite(innovation_values)
    ):
        raise ValueError("component arrays must be finite")
    blocks, truths, stages, days, candidates = variance_values.shape
    if blocks == 0 or truths == 0 or stages == 0 or days == 0:
        raise ValueError("component array dimensions must be nonempty")
    if candidates < 2:
        raise ValueError("component arrays must contain competing candidates")
    if truth.shape != (truths, stages) or np.any(truth < 0) or np.any(
        truth >= candidates
    ):
        raise ValueError(
            "truth_candidate_indices must have one valid candidate per truth and stage"
        )

    cumulative_variance = np.cumsum(variance_values, axis=-2)
    cumulative_innovation = np.cumsum(innovation_values, axis=-2)
    cumulative_total = cumulative_variance + cumulative_innovation

    expanded_truth = np.broadcast_to(
        truth[None, :, :, None], (blocks, truths, stages, days)
    )
    candidate_indices = np.arange(candidates, dtype=np.int64)
    wrong_mask = candidate_indices != expanded_truth[..., None]
    masked_total = np.where(wrong_mask, cumulative_total, -np.inf)
    daily_best_wrong = np.argmax(masked_total, axis=-1).astype(np.int64)
    daily_max_wrong_total = np.max(masked_total, axis=-1)

    daily_delta_variance = _take_candidate(
        cumulative_variance, expanded_truth
    ) - _take_candidate(cumulative_variance, daily_best_wrong)
    daily_delta_innovation = _take_candidate(
        cumulative_innovation, expanded_truth
    ) - _take_candidate(cumulative_innovation, daily_best_wrong)
    daily_delta_total = (
        _take_candidate(cumulative_total, expanded_truth) - daily_max_wrong_total
    )

    final_tie_counts = (
        np.sum(
            masked_total[..., -1, :] == daily_max_wrong_total[..., -1, None],
            axis=-1,
        ).astype(np.int64)
        - 1
    )
    return ComponentMarginScores(
        cumulative_variance_penalty=cumulative_variance,
        cumulative_innovation_penalty=cumulative_innovation,
        cumulative_total=cumulative_total,
        best_wrong_candidate_indices=daily_best_wrong[..., -1],
        best_wrong_tie_counts=final_tie_counts,
        final_delta_variance=daily_delta_variance[..., -1],
        final_delta_innovation=daily_delta_innovation[..., -1],
        final_delta_total=daily_delta_total[..., -1],
        daily_best_wrong_candidate_indices=daily_best_wrong,
        daily_delta_variance=daily_delta_variance,
        daily_delta_innovation=daily_delta_innovation,
        daily_delta_total=daily_delta_total,
    )


def analyze_evidence_arrays(evidence, gates) -> dict:
    """Decompose one frozen run's arrays and gate them against the saved evidence.

    ``evidence`` must expose the frozen keys ``candidate_innovations``,
    ``candidate_innovation_variances``, ``candidate_daily_log_likelihoods``,
    ``cumulative_log_likelihoods``, ``true_candidate_cumulative_margins``,
    ``truth_candidate_indices``, ``stage_start_days``, ``stage_end_days`` and
    ``adaptation_days``. All inputs are read only; nothing is recomputed from
    the filters themselves.
    """

    innovations = np.asarray(evidence["candidate_innovations"], dtype=np.float64)
    variances = np.asarray(
        evidence["candidate_innovation_variances"], dtype=np.float64
    )
    frozen_daily = np.asarray(
        evidence["candidate_daily_log_likelihoods"], dtype=np.float64
    )
    frozen_cumulative = np.asarray(
        evidence["cumulative_log_likelihoods"], dtype=np.float64
    )
    frozen_margins = np.asarray(
        evidence["true_candidate_cumulative_margins"], dtype=np.float64
    )
    truth_indices = np.asarray(evidence["truth_candidate_indices"], dtype=np.int64)
    stage_starts = np.asarray(evidence["stage_start_days"], dtype=np.int64)
    stage_ends = np.asarray(evidence["stage_end_days"], dtype=np.int64)
    adaptation = int(np.asarray(evidence["adaptation_days"]))
    if innovations.ndim != 4 or innovations.shape != variances.shape:
        raise ValueError(
            "daily arrays must share shape (blocks, truths, days, candidates)"
        )
    if frozen_daily.shape != innovations.shape:
        raise ValueError("frozen daily log likelihoods must match the daily arrays")
    if stage_starts.shape != stage_ends.shape or stage_starts.ndim != 1:
        raise ValueError("stage day boundaries must be matching vectors")

    components = decompose_daily_log_likelihoods(innovations, variances)
    daily_identity_error = float(
        np.max(
            np.abs(
                components.variance_penalty
                + components.innovation_penalty
                - frozen_daily
            ),
            initial=0.0,
        )
    )

    def _windows(daily_values: np.ndarray) -> np.ndarray:
        stacked = [
            daily_values[..., int(start) + adaptation : int(end), :]
            for start, end in zip(stage_starts, stage_ends)
        ]
        lengths = {window.shape[-2] for window in stacked}
        if len(lengths) != 1:
            raise ValueError("all stages must leave the same number of scoring days")
        return np.stack(stacked, axis=-3)

    scored_variance = _windows(components.variance_penalty)
    scored_innovation = _windows(components.innovation_penalty)
    stage_truth = np.stack(
        [truth_indices[:, int(start) + adaptation] for start in stage_starts],
        axis=1,
    )
    scores = score_component_margins(scored_variance, scored_innovation, stage_truth)
    cumulative_identity_error = float(
        np.max(np.abs(scores.cumulative_total - frozen_cumulative), initial=0.0)
    )
    margin_error = float(
        np.max(
            np.abs(scores.final_delta_total - frozen_margins[..., -1]), initial=0.0
        )
    )
    integrity_passed = bool(
        daily_identity_error
        <= float(gates["daily_component_identity_maximum_absolute_error"])
        and cumulative_identity_error
        <= float(gates["stage_cumulative_identity_maximum_absolute_error"])
        and margin_error
        <= float(gates["final_margin_decomposition_maximum_absolute_error"])
        and np.all(np.isfinite(scores.cumulative_total))
    )
    return {
        "components": components,
        "scored_variance_penalty": scored_variance,
        "scored_innovation_penalty": scored_innovation,
        "stage_truth_candidate_indices": stage_truth,
        "scores": scores,
        "integrity": {
            "daily_component_identity_maximum_absolute_error": daily_identity_error,
            "stage_cumulative_identity_maximum_absolute_error": (
                cumulative_identity_error
            ),
            "final_margin_decomposition_maximum_absolute_error": margin_error,
            "integrity_passed": integrity_passed,
        },
    }


def _attribution_label(
    delta_variance_statistic: float,
    delta_innovation_statistic: float,
    delta_total_statistic: float,
) -> str:
    if delta_total_statistic >= 0.0:
        return "no_median_advantage"
    variance_negative = delta_variance_statistic < 0.0
    innovation_negative = delta_innovation_statistic < 0.0
    if variance_negative and not innovation_negative:
        return "variance_penalty_dominant"
    if innovation_negative and not variance_negative:
        return "innovation_penalty_dominant"
    if variance_negative and innovation_negative:
        if abs(delta_variance_statistic) > abs(delta_innovation_statistic):
            return "variance_penalty_dominant_both_negative"
        if abs(delta_innovation_statistic) > abs(delta_variance_statistic):
            return "innovation_penalty_dominant_both_negative"
        return "both_negative_equal"
    return "median_decomposition_inconsistent"


def attribute_stage(delta_variance, delta_innovation) -> dict:
    """Apply the frozen median-first attribution rules to one stage's trials."""

    variance_deltas = np.asarray(delta_variance, dtype=np.float64)
    innovation_deltas = np.asarray(delta_innovation, dtype=np.float64)
    if (
        variance_deltas.ndim != 1
        or variance_deltas.shape != innovation_deltas.shape
        or variance_deltas.size == 0
    ):
        raise ValueError("delta arrays must be one nonempty vector each")
    if not np.all(np.isfinite(variance_deltas)) or not np.all(
        np.isfinite(innovation_deltas)
    ):
        raise ValueError("delta arrays must be finite")
    total_deltas = variance_deltas + innovation_deltas
    median_variance = float(np.median(variance_deltas))
    median_innovation = float(np.median(innovation_deltas))
    median_total = float(np.median(total_deltas))
    mean_variance = float(np.mean(variance_deltas))
    mean_innovation = float(np.mean(innovation_deltas))
    mean_total = float(np.mean(total_deltas))
    label = _attribution_label(median_variance, median_innovation, median_total)
    mean_label = _attribution_label(mean_variance, mean_innovation, mean_total)
    family = _ATTRIBUTION_FAMILIES.get(label)
    mean_family = _ATTRIBUTION_FAMILIES.get(mean_label)
    robust = None if family is None else bool(mean_family == family)
    return {
        "trial_count": int(variance_deltas.size),
        "median_delta_variance": median_variance,
        "median_delta_innovation": median_innovation,
        "median_delta_total": median_total,
        "mean_delta_variance": mean_variance,
        "mean_delta_innovation": mean_innovation,
        "mean_delta_total": mean_total,
        "fraction_delta_variance_negative": float(np.mean(variance_deltas < 0.0)),
        "fraction_delta_innovation_negative": float(np.mean(innovation_deltas < 0.0)),
        "label": label,
        "mean_label": mean_label,
        "robust": robust,
    }


def consistency_call(development_label, confirmation_label) -> dict:
    """Frozen development-vs-confirmation direction rule for one scenario stage."""

    development_family = _ATTRIBUTION_FAMILIES.get(str(development_label))
    confirmation_family = _ATTRIBUTION_FAMILIES.get(str(confirmation_label))
    consistent = development_family is not None and (
        development_family == confirmation_family
    )
    return {
        "development_family": development_family,
        "confirmation_family": confirmation_family,
        "consistent": bool(consistent),
        "conclusion": development_family if consistent else "目前无法确定主要来源",
    }
