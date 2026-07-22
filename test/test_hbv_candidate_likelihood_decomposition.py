import sys
from pathlib import Path

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.candidate_likelihood_decomposition import (  # noqa: E402
    analyze_evidence_arrays,
    attribute_stage,
    consistency_call,
    decompose_daily_log_likelihoods,
    score_component_margins,
)


GATES = {
    "daily_component_identity_maximum_absolute_error": 1e-12,
    "stage_cumulative_identity_maximum_absolute_error": 1e-11,
    "final_margin_decomposition_maximum_absolute_error": 1e-11,
}


def _synthetic_evidence(rng_seed=20260721):
    rng = np.random.default_rng(rng_seed)
    blocks, truths, days, candidates = 2, 2, 9, 3
    stage_starts = np.array([0, 3, 6], dtype=np.int64)
    stage_ends = np.array([3, 6, 9], dtype=np.int64)
    adaptation = np.int64(1)
    innovations = rng.normal(size=(blocks, truths, days, candidates))
    variances = rng.uniform(0.5, 2.0, size=(blocks, truths, days, candidates))
    daily = -0.5 * (np.log(2.0 * np.pi * variances) + np.square(innovations) / variances)
    truth_indices = rng.integers(0, candidates, size=(truths, days)).astype(np.int64)
    windows = [
        daily[..., int(start) + int(adaptation) : int(end), :]
        for start, end in zip(stage_starts, stage_ends)
    ]
    scored = np.stack(windows, axis=-3)
    cumulative = np.cumsum(scored, axis=-2)
    stage_truth = np.stack(
        [truth_indices[:, int(start) + int(adaptation)] for start in stage_starts],
        axis=1,
    )
    expanded_truth = np.broadcast_to(
        stage_truth[None, :, :, None], cumulative.shape[:-1]
    )
    true_cumulative = np.take_along_axis(
        cumulative, expanded_truth[..., None], axis=-1
    )[..., 0]
    wrong_mask = np.arange(candidates) != expanded_truth[..., None]
    best_wrong = np.max(np.where(wrong_mask, cumulative, -np.inf), axis=-1)
    margins = true_cumulative - best_wrong
    return {
        "candidate_innovations": innovations,
        "candidate_innovation_variances": variances,
        "candidate_daily_log_likelihoods": daily,
        "cumulative_log_likelihoods": cumulative,
        "true_candidate_cumulative_margins": margins,
        "truth_candidate_indices": truth_indices,
        "stage_start_days": stage_starts,
        "stage_end_days": stage_ends,
        "adaptation_days": adaptation,
    }


def test_analyze_evidence_arrays_passes_on_consistent_synthetic_evidence():
    evidence = _synthetic_evidence()
    analysis = analyze_evidence_arrays(evidence, GATES)
    integrity = analysis["integrity"]
    assert integrity["integrity_passed"] is True
    assert (
        integrity["daily_component_identity_maximum_absolute_error"]
        <= GATES["daily_component_identity_maximum_absolute_error"]
    )
    assert (
        integrity["stage_cumulative_identity_maximum_absolute_error"]
        <= GATES["stage_cumulative_identity_maximum_absolute_error"]
    )
    assert (
        integrity["final_margin_decomposition_maximum_absolute_error"]
        <= GATES["final_margin_decomposition_maximum_absolute_error"]
    )
    scores = analysis["scores"]
    np.testing.assert_allclose(
        scores.final_delta_total,
        evidence["true_candidate_cumulative_margins"][..., -1],
        rtol=0.0,
        atol=1e-12,
    )
    np.testing.assert_allclose(
        scores.final_delta_variance + scores.final_delta_innovation,
        scores.final_delta_total,
        rtol=0.0,
        atol=1e-12,
    )
    np.testing.assert_array_equal(
        analysis["stage_truth_candidate_indices"],
        np.stack(
            [
                evidence["truth_candidate_indices"][:, int(start) + 1]
                for start in evidence["stage_start_days"]
            ],
            axis=1,
        ),
    )


def test_markdown_table_renders_header_and_all_cells():
    import pandas as pd

    from hbv_multilead_joint_uncertainty.scripts.run_candidate_likelihood_decomposition import (
        _markdown_table,
    )

    frame = pd.DataFrame({"name": ["x", "y"], "value": [1, 2], "ratio": [0.25, -1.5]})
    text = _markdown_table(frame)
    lines = text.splitlines()
    assert lines[0] == "| name | value | ratio |"
    assert lines[1] == "| --- | --- | --- |"
    assert "| x | 1 | 0.25 |" in lines
    assert "| y | 2 | -1.5 |" in lines


def test_analyze_evidence_arrays_fails_when_daily_likelihood_corrupted():
    evidence = _synthetic_evidence()
    corrupted = dict(evidence)
    corrupted["candidate_daily_log_likelihoods"] = (
        evidence["candidate_daily_log_likelihoods"].copy()
    )
    corrupted["candidate_daily_log_likelihoods"][0, 0, 0, 0] += 1e-6
    analysis = analyze_evidence_arrays(corrupted, GATES)
    assert analysis["integrity"]["integrity_passed"] is False
    assert (
        analysis["integrity"]["daily_component_identity_maximum_absolute_error"]
        > GATES["daily_component_identity_maximum_absolute_error"]
    )


def test_decomposition_components_sum_to_gaussian_log_likelihood():
    innovations = np.array([[0.5, -1.0], [2.0, 0.0]])
    variances = np.array([[0.25, 1.0], [4.0, 0.5]])
    components = decompose_daily_log_likelihoods(innovations, variances)
    expected_variance_penalty = -0.5 * np.log(2.0 * np.pi * variances)
    expected_innovation_penalty = -0.5 * np.square(innovations) / variances
    np.testing.assert_allclose(
        components.variance_penalty, expected_variance_penalty, rtol=0.0, atol=0.0
    )
    np.testing.assert_allclose(
        components.innovation_penalty, expected_innovation_penalty, rtol=0.0, atol=0.0
    )
    expected_total = -0.5 * (
        np.log(2.0 * np.pi * variances) + np.square(innovations) / variances
    )
    np.testing.assert_allclose(
        components.variance_penalty + components.innovation_penalty,
        expected_total,
        rtol=0.0,
        atol=1e-15,
    )


@pytest.mark.parametrize(
    "innovations, variances",
    [
        (np.array([1.0]), np.array([0.0])),
        (np.array([1.0]), np.array([-0.5])),
        (np.array([np.nan]), np.array([1.0])),
        (np.array([1.0]), np.array([np.inf])),
        (np.array([1.0, 2.0]), np.array([1.0])),
    ],
)
def test_decomposition_rejects_invalid_inputs(innovations, variances):
    with pytest.raises(ValueError):
        decompose_daily_log_likelihoods(innovations, variances)


def test_component_margins_match_hand_computed_example():
    variance_penalty = np.array(
        [[[[[-1.0, -0.5, -2.0], [-1.0, -0.4, -0.3]]]]]
    )
    innovation_penalty = np.array(
        [[[[[-0.2, -1.0, -0.1], [-0.3, -0.2, -1.0]]]]]
    )
    truth = np.array([[0]], dtype=np.int64)
    scores = score_component_margins(variance_penalty, innovation_penalty, truth)
    np.testing.assert_allclose(
        scores.cumulative_variance_penalty[0, 0, 0, -1], [-2.0, -0.9, -2.3]
    )
    np.testing.assert_allclose(
        scores.cumulative_innovation_penalty[0, 0, 0, -1], [-0.5, -1.2, -1.1]
    )
    np.testing.assert_allclose(
        scores.cumulative_total[0, 0, 0, -1], [-2.5, -2.1, -3.4]
    )
    assert scores.best_wrong_candidate_indices[0, 0, 0] == 1
    assert scores.best_wrong_tie_counts[0, 0, 0] == 0
    np.testing.assert_allclose(scores.final_delta_variance[0, 0, 0], -1.1)
    np.testing.assert_allclose(scores.final_delta_innovation[0, 0, 0], 0.7)
    np.testing.assert_allclose(scores.final_delta_total[0, 0, 0], -0.4)
    np.testing.assert_allclose(
        scores.final_delta_variance + scores.final_delta_innovation,
        scores.final_delta_total,
        rtol=0.0,
        atol=1e-15,
    )
    assert scores.daily_best_wrong_candidate_indices[0, 0, 0, 0] == 1
    np.testing.assert_allclose(scores.daily_delta_total[0, 0, 0, 0], 0.3)
    np.testing.assert_allclose(scores.daily_delta_variance[0, 0, 0, 0], -0.5)
    np.testing.assert_allclose(scores.daily_delta_innovation[0, 0, 0, 0], 0.8)


def test_component_margins_break_final_ties_toward_lowest_wrong_index():
    variance_penalty = np.array(
        [[[[[-1.0, -1.0, -2.0], [-1.0, -1.0, -1.0]]]]]
    )
    innovation_penalty = np.array(
        [[[[[-1.0, -1.0, 0.0], [-1.0, -1.0, -1.0]]]]]
    )
    truth = np.array([[0]], dtype=np.int64)
    scores = score_component_margins(variance_penalty, innovation_penalty, truth)
    np.testing.assert_allclose(
        scores.cumulative_total[0, 0, 0, -1], [-4.0, -4.0, -4.0]
    )
    assert scores.best_wrong_candidate_indices[0, 0, 0] == 1
    assert scores.best_wrong_tie_counts[0, 0, 0] == 1


def test_component_margins_reject_inconsistent_shapes():
    variance_penalty = np.zeros((1, 1, 1, 2, 3))
    innovation_penalty = np.zeros((1, 1, 1, 2, 2))
    truth = np.array([[0]], dtype=np.int64)
    with pytest.raises(ValueError):
        score_component_margins(variance_penalty, innovation_penalty, truth)
    with pytest.raises(ValueError):
        score_component_margins(
            np.zeros((1, 1, 1, 2, 3)),
            np.zeros((1, 1, 1, 2, 3)),
            np.array([[3]], dtype=np.int64),
        )


def test_attribution_labels_follow_frozen_rules():
    no_advantage = attribute_stage(
        delta_variance=np.array([0.2, 0.3, -0.1]),
        delta_innovation=np.array([0.1, 0.0, 0.05]),
    )
    assert no_advantage["label"] == "no_median_advantage"

    variance_dominant = attribute_stage(
        delta_variance=np.array([-1.0, -0.8, -1.2]),
        delta_innovation=np.array([0.1, 0.2, 0.3]),
    )
    assert variance_dominant["label"] == "variance_penalty_dominant"

    innovation_dominant = attribute_stage(
        delta_variance=np.array([0.1, 0.2, 0.3]),
        delta_innovation=np.array([-1.0, -0.8, -1.2]),
    )
    assert innovation_dominant["label"] == "innovation_penalty_dominant"

    both_negative = attribute_stage(
        delta_variance=np.array([-1.0, -0.9, -1.1]),
        delta_innovation=np.array([-0.1, -0.2, -0.3]),
    )
    assert both_negative["label"] == "variance_penalty_dominant_both_negative"
    assert both_negative["median_delta_total"] < 0.0

    equal_negative = attribute_stage(
        delta_variance=np.array([-0.5, -0.5, -0.5]),
        delta_innovation=np.array([-0.5, -0.5, -0.5]),
    )
    assert equal_negative["label"] == "both_negative_equal"


def test_attribution_flags_median_decomposition_inconsistency():
    delta_variance = np.array([0.0, 0.1, -5.0])
    delta_innovation = np.array([0.0, -5.0, 0.1])
    result = attribute_stage(delta_variance, delta_innovation)
    assert result["median_delta_total"] < 0.0
    assert result["median_delta_variance"] >= 0.0
    assert result["median_delta_innovation"] >= 0.0
    assert result["label"] == "median_decomposition_inconsistent"


def test_attribution_reports_means_fractions_and_robustness():
    result = attribute_stage(
        delta_variance=np.array([-1.0, -0.8, -1.2, -0.6]),
        delta_innovation=np.array([0.1, 0.2, -0.1, 0.3]),
    )
    np.testing.assert_allclose(result["mean_delta_variance"], -0.9)
    np.testing.assert_allclose(result["mean_delta_innovation"], 0.125)
    np.testing.assert_allclose(result["fraction_delta_variance_negative"], 1.0)
    np.testing.assert_allclose(result["fraction_delta_innovation_negative"], 0.25)
    assert result["label"] == "variance_penalty_dominant"
    assert result["mean_label"] == "variance_penalty_dominant"
    assert result["robust"] is True


def test_consistency_call_requires_matching_nonempty_families():
    matched = consistency_call(
        "variance_penalty_dominant", "variance_penalty_dominant_both_negative"
    )
    assert matched["consistent"] is True
    assert matched["conclusion"] == "variance"

    crossed = consistency_call(
        "variance_penalty_dominant", "innovation_penalty_dominant"
    )
    assert crossed["consistent"] is False
    assert crossed["conclusion"] == "目前无法确定主要来源"

    missing = consistency_call("no_median_advantage", "variance_penalty_dominant")
    assert missing["consistent"] is False
    assert missing["conclusion"] == "目前无法确定主要来源"
