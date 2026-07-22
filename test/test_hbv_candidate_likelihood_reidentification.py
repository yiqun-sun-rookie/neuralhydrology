import sys
from pathlib import Path

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.candidate_likelihood_reidentification import (  # noqa: E402
    agreement_call,
    analyze_reidentification_evidence,
    classify_reidentification,
    dominant_failure_label,
    recompute_first_days,
    summarize_categories,
)


GATES = {
    "recomputed_first_day_mismatches": 0,
    "recomputed_first_stable_day_mismatches": 0,
    "stable_category_vs_frozen_flag_mismatches": 0,
    "partition_violations": 0,
}


def test_recompute_first_days_matches_hand_computed_trajectories():
    ranks = np.array(
        [[[
            [2, 1, 2, 1, 1],
            [2, 2, 2, 2, 2],
            [1, 1, 1, 1, 1],
        ]]],
        dtype=np.int64,
    )
    first, first_stable = recompute_first_days(ranks)
    np.testing.assert_array_equal(first[0, 0], [2, -1, 1])
    np.testing.assert_array_equal(first_stable[0, 0], [4, -1, 1])


def test_recompute_first_days_rejects_invalid_ranks():
    with pytest.raises(ValueError):
        recompute_first_days(np.array([[[[0, 1]]]], dtype=np.int64))
    with pytest.raises(ValueError):
        recompute_first_days(np.array([[1, 2]], dtype=np.int64))


def test_classification_covers_all_four_categories():
    first = np.array([[[3, 2, -1, 1]]], dtype=np.int64)
    first_stable = np.array([[[3, -1, -1, 7]]], dtype=np.int64)
    categories = classify_reidentification(first, first_stable, 6)
    assert categories[0, 0, 0] == "stable"
    assert categories[0, 0, 1] == "first_then_lost"
    assert categories[0, 0, 2] == "never_first"
    assert categories[0, 0, 3] == "stable_too_late"


def test_classification_rejects_inconsistent_inputs():
    with pytest.raises(ValueError):
        classify_reidentification(
            np.array([[[1]]], dtype=np.int64),
            np.array([[[1, 2]]], dtype=np.int64),
            6,
        )
    with pytest.raises(ValueError):
        classify_reidentification(
            np.array([[[-1]]], dtype=np.int64),
            np.array([[[4]]], dtype=np.int64),
            6,
        )


def test_dominant_failure_label_follows_frozen_rules():
    assert (
        dominant_failure_label(
            {"never_first": 5, "first_then_lost": 2, "stable_too_late": 1}
        )
        == "never_first"
    )
    assert (
        dominant_failure_label(
            {"never_first": 3, "first_then_lost": 3, "stable_too_late": 1}
        )
        == "tie:first_then_lost+never_first"
    )
    assert (
        dominant_failure_label(
            {"never_first": 0, "first_then_lost": 0, "stable_too_late": 0}
        )
        == "no_failures"
    )


def test_agreement_call_requires_identical_labels():
    same = agreement_call("never_first", "never_first")
    assert same["consistent"] is True
    assert same["conclusion"] == "never_first"
    crossed = agreement_call("never_first", "first_then_lost")
    assert crossed["consistent"] is False
    assert crossed["conclusion"] == "目前无法确定主导失败模式"


def test_summarize_categories_reports_counts_fractions_and_medians():
    categories = np.array(
        ["stable", "stable", "never_first", "first_then_lost"], dtype="<U16"
    )
    first = np.array([2, 1, -1, 4], dtype=np.int64)
    first_stable = np.array([3, 1, -1, -1], dtype=np.int64)
    summary = summarize_categories(categories, first, first_stable)
    assert summary["trial_count"] == 4
    assert summary["count_stable"] == 2
    assert summary["count_never_first"] == 1
    assert summary["count_first_then_lost"] == 1
    assert summary["count_stable_too_late"] == 0
    np.testing.assert_allclose(summary["fraction_stable"], 0.5)
    np.testing.assert_allclose(summary["median_first_day_among_ever_first"], 2.0)
    np.testing.assert_allclose(summary["median_first_stable_day_among_stable"], 2.0)
    assert summary["dominant_failure_label"] == "tie:first_then_lost+never_first"


def _synthetic_evidence():
    ranks = np.array(
        [
            [
                [
                    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
                    [3, 2, 1, 2, 3, 3, 3, 3, 3, 3],
                    [2, 2, 2, 2, 2, 2, 1, 1, 1, 1],
                ],
                [
                    [2, 1, 1, 1, 1, 1, 1, 1, 1, 1],
                    [3, 3, 3, 3, 3, 3, 3, 3, 3, 3],
                    [2, 1, 1, 2, 1, 1, 1, 1, 1, 1],
                ],
            ]
        ],
        dtype=np.int64,
    )
    first, first_stable = recompute_first_days(ranks)
    stable = (first_stable >= 1) & (first_stable <= 6)
    return {
        "true_candidate_cumulative_ranks": ranks,
        "first_cumulative_rank_one_day": first,
        "first_stable_cumulative_rank_one_day": first_stable,
        "stable_cumulative_identifiable": stable,
        "block_ids": np.array(["block_a"]),
    }


def test_analyze_evidence_passes_and_classifies_synthetic_trajectories():
    evidence = _synthetic_evidence()
    analysis = analyze_reidentification_evidence(evidence, GATES, 6)
    assert analysis["integrity"]["integrity_passed"] is True
    categories = analysis["categories"]
    assert categories[0, 0, 0] == "stable"
    assert categories[0, 0, 1] == "first_then_lost"
    assert categories[0, 0, 2] == "stable_too_late"
    assert categories[0, 1, 0] == "stable"
    assert categories[0, 1, 1] == "never_first"
    assert categories[0, 1, 2] == "stable"
    daily = analysis["daily_rank_one_fraction"]
    np.testing.assert_allclose(daily[0, :], [0.5, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
    np.testing.assert_allclose(daily[1, 0], 0.0)


def test_analyze_evidence_fails_when_frozen_first_day_corrupted():
    evidence = _synthetic_evidence()
    corrupted = dict(evidence)
    corrupted["first_cumulative_rank_one_day"] = (
        evidence["first_cumulative_rank_one_day"].copy()
    )
    corrupted["first_cumulative_rank_one_day"][0, 0, 0] = 5
    analysis = analyze_reidentification_evidence(corrupted, GATES, 6)
    assert analysis["integrity"]["integrity_passed"] is False
    assert analysis["integrity"]["recomputed_first_day_mismatches"] > 0


def test_analyze_evidence_fails_when_stable_flag_disagrees():
    evidence = _synthetic_evidence()
    corrupted = dict(evidence)
    corrupted["stable_cumulative_identifiable"] = (
        evidence["stable_cumulative_identifiable"].copy()
    )
    corrupted["stable_cumulative_identifiable"][0, 1, 1] = True
    analysis = analyze_reidentification_evidence(corrupted, GATES, 6)
    assert analysis["integrity"]["integrity_passed"] is False
    assert analysis["integrity"]["stable_category_vs_frozen_flag_mismatches"] > 0
