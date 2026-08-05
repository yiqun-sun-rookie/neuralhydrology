"""Tamper tests for the independent daily rolling development verifier."""

from __future__ import annotations

import copy
import hashlib
import importlib
import json

import numpy as np
import pytest

from hbv_multilead_joint_uncertainty.daily_rolling_forecast import (
    build_daily_rolling_index,
    summarize_daily_rolling_forecasts,
)


RUNNER_MODULE = (
    "hbv_multilead_joint_uncertainty.scripts."
    "run_g3_daily_rolling_forecast_development"
)
VERIFIER_MODULE = (
    "hbv_multilead_joint_uncertainty.scripts."
    "verify_g3_daily_rolling_forecast_development"
)


def _payload():
    runner = importlib.import_module(RUNNER_MODULE)
    index = build_daily_rolling_index()
    shape = (8, 3, 360, 7)
    truth = np.zeros(shape, dtype=np.float64)
    full = np.zeros(shape, dtype=np.float64)
    none = np.full(shape, 2.0, dtype=np.float64)
    full_candidates = np.zeros((*shape, 3), dtype=np.float64)
    none_candidates = np.broadcast_to(
        np.asarray([1.0, 2.0, 6.0]),
        (*shape, 3),
    ).copy()
    full_probabilities = np.broadcast_to(
        np.asarray([0.2, 0.3, 0.5]),
        (*shape, 3),
    ).copy()
    none_probabilities = np.broadcast_to(
        np.asarray([0.0, 1.0, 0.0]),
        (*shape, 3),
    ).copy()
    forecasts = {
        "full": full,
        "none": none,
        "uniform_independent": np.mean(
            none_candidates,
            axis=-1,
        ),
    }
    statistics = summarize_daily_rolling_forecasts(
        forecasts,
        truth,
        index,
        bootstrap_replicates=20000,
        bootstrap_seed=8820001,
        minimum_meaningful_rmse_fraction=0.01,
    )
    decision = runner._development_decision(
        statistics["rmse"],
        {
            "minimum_full_stage_rmse_improvement_fraction": 0.01,
            "require_all_seven_leads_against_both_controls": True,
        },
        integrity_passed=True,
    )
    payload = {
        "index": index,
        "statistics": statistics,
        "decision": decision,
        "truth_forecasts": truth,
        "forecasts": forecasts,
        "candidate_forecasts": {
            "full": full_candidates,
            "none": none_candidates,
        },
        "probabilities": {
            "full": full_probabilities,
            "none": none_probabilities,
        },
        "block_ids": np.asarray(
            [f"block_{index:02d}" for index in range(8)]
        ),
        "candidate_ids": np.asarray(["a", "b", "c"]),
    }
    evidence = runner._evidence_arrays(payload)
    summary = {
        "integrity_status": "passed",
        "protected_artifacts_unchanged": True,
        "result": runner._result_summary(payload),
    }
    config = {
        "lead_days": list(range(1, 8)),
        "stage_lengths": [180, 180, 180],
        "switch_days": [180, 360],
        "expected_block_count": 8,
        "expected_truth_count": 3,
        "bootstrap": {
            "unit": "matched_block",
            "replicates": 20000,
            "seed": 8820001,
            "shared_resample_indices_across_leads_and_comparisons": True,
        },
        "development_gates": {
            "minimum_full_stage_rmse_improvement_fraction": 0.01,
            "require_all_seven_leads_against_both_controls": True,
        },
    }
    return evidence, summary, config


def test_independent_verifier_accepts_consistent_arrays():
    verifier = importlib.import_module(VERIFIER_MODULE)
    evidence, summary, config = _payload()

    report = verifier.verify_evidence(evidence, summary, config)

    assert report["passed"] is True
    assert report["maximum_absolute_difference"] == pytest.approx(0.0)


@pytest.mark.parametrize(
    ("key", "mutate", "match"),
    [
        (
            "full_forecasts",
            lambda values: values.__setitem__((0, 0, 0, 0), 1.0),
            "forecast combination|squared error",
        ),
        (
            "same_stage_mask",
            lambda values: values.__setitem__((0, 0), False),
            "mask",
        ),
        (
            "block_mse_none",
            lambda values: values.__setitem__((0, 0), 999.0),
            "block",
        ),
    ],
)
def test_independent_verifier_rejects_tampering(key, mutate, match):
    verifier = importlib.import_module(VERIFIER_MODULE)
    evidence, summary, config = _payload()
    evidence = {
        name: np.array(values, copy=True)
        for name, values in evidence.items()
    }
    mutate(evidence[key])

    with pytest.raises(ValueError, match=match):
        verifier.verify_evidence(evidence, summary, config)


def test_checksum_verifier_rejects_tampering(tmp_path):
    verifier = importlib.import_module(VERIFIER_MODULE)
    result_dir = tmp_path / "result"
    result_dir.mkdir()
    artifact = result_dir / "artifact.txt"
    artifact.write_text("original", encoding="utf-8")
    checksums = {
        "artifact.txt": hashlib.sha256(artifact.read_bytes()).hexdigest()
    }
    (result_dir / "checksums.json").write_text(
        json.dumps(checksums),
        encoding="utf-8",
    )
    artifact.write_text("tampered", encoding="utf-8")

    with pytest.raises(ValueError, match="checksum"):
        verifier.verify_checksums(result_dir)
