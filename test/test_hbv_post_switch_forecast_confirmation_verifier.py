"""Independent verifier tests for post-switch forecast evidence."""

from __future__ import annotations

import importlib
import json

import numpy as np

from hbv_multilead_joint_uncertainty.post_switch_forecast_confirmation import (
    summarize_post_switch_forecasts,
)


VERIFIER_MODULE = (
    "hbv_multilead_joint_uncertainty.scripts."
    "verify_g3_post_switch_forecast_confirmation"
)
RUNNER_MODULE = (
    "hbv_multilead_joint_uncertainty.scripts."
    "run_g3_post_switch_forecast_confirmation"
)


def _package(tmp_path):
    truth = np.zeros((4, 2, 14, 3), dtype=np.float64)
    full = np.broadcast_to([2.0, 4.0, 8.0], truth.shape).copy()
    none = np.broadcast_to([2.2, 4.5, 9.0], truth.shape).copy()
    uniform = np.broadcast_to([2.5, 5.0, 10.0], truth.shape).copy()
    forecasts = {
        "full": full,
        "none": none,
        "uniform_independent": uniform,
    }
    statistics = summarize_post_switch_forecasts(
        forecasts,
        truth,
        (1, 3, 7),
        100,
        1234,
        0.01,
    )
    runner = importlib.import_module(RUNNER_MODULE)
    summary = {
        "result": runner._result_summary(statistics),
        "retention_decision": "retain",
        "integrity_status": "passed",
    }
    second = (2.4 * uniform - none) / 1.4
    first = 3.0 * uniform - 2.0 * second
    candidates = np.stack([first, second, second], axis=-1)
    all_candidates = np.concatenate(
        [candidates, candidates[:, :, :1]],
        axis=2,
    )
    probabilities = np.broadcast_to(
        np.asarray([0.8, 0.1, 0.1]),
        all_candidates.shape,
    ).copy()
    all_none = np.sum(probabilities * all_candidates, axis=-1)
    all_full = np.concatenate([full, full[:, :, :1]], axis=2)
    scoring_mask = np.asarray([True] * 14 + [False])
    evidence = {
        "lead_days": np.asarray([1, 3, 7]),
        "origin_indices": np.asarray(
            [*range(180, 187), *range(360, 367), 539]
        ),
        "target_indices": np.asarray(
            [*range(180, 187), *range(360, 367), 539]
        )[:, None]
        + np.asarray([1, 3, 7])[None, :],
        "scoring_origin_mask": scoring_mask,
        "truth_forecasts": truth,
        "full_forecasts": full,
        "none_forecasts": none,
        "uniform_independent_forecasts": uniform,
        "full_all_origin_forecasts": all_full,
        "none_all_origin_forecasts": all_none,
        "full_candidate_forecasts": np.repeat(
            all_full[..., None], 3, axis=-1
        ),
        "none_candidate_forecasts": all_candidates,
        "full_probabilities": probabilities,
        "none_probabilities": probabilities,
        "bootstrap_indices": statistics["bootstrap_indices"],
    }
    for method in ("full", "none", "uniform_independent"):
        evidence[f"squared_error_{method}"] = statistics["squared_errors"][
            method
        ]
        evidence[f"rmse_{method}"] = statistics["rmse"][method]
        evidence[f"per_origin_rmse_{method}"] = statistics[
            "per_origin_rmse"
        ][method]
    for comparison, entry in statistics["paired"].items():
        for field in (
            "squared_error_difference",
            "block_mean",
            "mean",
            "ci_low",
            "ci_high",
            "baseline_mse",
            "meaningful_improvement_boundary",
        ):
            evidence[f"{comparison}_{field}"] = entry[field]
    path = tmp_path / "evidence.npz"
    np.savez_compressed(path, **evidence)
    config = {
        "lead_days": [1, 3, 7],
        "bootstrap": {"replicates": 100, "seed": 1234},
        "retention_thresholds": {
            "minimum_meaningful_rmse_fraction": 0.01
        },
    }
    cross_checks = {"passed": True}
    return path, config, summary, cross_checks


def test_independent_verifier_recomputes_every_statistic(tmp_path):
    verifier = importlib.import_module(VERIFIER_MODULE)
    path, config, summary, cross_checks = _package(tmp_path)

    with np.load(path, allow_pickle=False) as evidence:
        report = verifier._verify_arrays(
            evidence,
            config,
            summary,
            cross_checks,
        )

    assert report["passed"] is True
    assert report["maximum_absolute_error"] <= 1e-12
    assert report["retention_decision_matches"] is True
    assert report["checked_numeric_field_count"] > 20


def test_independent_verifier_detects_tampered_rmse(tmp_path):
    verifier = importlib.import_module(VERIFIER_MODULE)
    path, config, summary, cross_checks = _package(tmp_path)
    with np.load(path, allow_pickle=False) as original:
        arrays = {name: original[name] for name in original.files}
    arrays["rmse_full"] = arrays["rmse_full"].copy()
    arrays["rmse_full"][0] += 0.1
    tampered = tmp_path / "tampered.npz"
    np.savez_compressed(tampered, **arrays)

    with np.load(tampered, allow_pickle=False) as evidence:
        report = verifier._verify_arrays(
            evidence,
            config,
            summary,
            cross_checks,
        )

    assert report["passed"] is False
    assert report["maximum_absolute_error"] >= 0.1 - 1e-12
