"""Independent verifier tests for forecast readout evidence."""

from __future__ import annotations

import hashlib
import importlib
import json
import sys
from pathlib import Path

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))
VERIFIER_MODULE = (
    "hbv_multilead_joint_uncertainty.scripts."
    "verify_g3_daily_rolling_forecast_readout_development"
)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_checksum_verifier_detects_tampering_and_ignores_its_own_report(
    tmp_path,
):
    verifier = importlib.import_module(VERIFIER_MODULE)
    artifact = tmp_path / "evidence.npz"
    artifact.write_bytes(b"sealed")
    (tmp_path / "checksums.json").write_text(
        json.dumps({"evidence.npz": _sha256(artifact)}),
        encoding="utf-8",
    )
    (tmp_path / "independent_verification.json").write_text(
        "{}", encoding="utf-8"
    )

    assert verifier.verify_checksums(tmp_path)["passed"] is True

    artifact.write_bytes(b"tampered")
    with pytest.raises(ValueError, match="checksum mismatch"):
        verifier.verify_checksums(tmp_path)


def _posterior_snapshot():
    states = np.asarray(
        [
            [
                [
                    [[1.0, 2.0], [3.0, 4.0], [5.0, 8.0]],
                    [[2.0, 3.0], [4.0, 6.0], [9.0, 10.0]],
                ]
            ]
        ],
        dtype=np.float64,
    )
    covariances = np.broadcast_to(
        np.asarray([np.eye(2), 2.0 * np.eye(2), 3.0 * np.eye(2)]),
        (*states.shape[:-2], 3, 2, 2),
    ).copy()
    probabilities = np.asarray(
        [[[[0.2, 0.7, 0.1], [0.5, 0.25, 0.25]]]],
        dtype=np.float64,
    )
    mean = np.einsum("...i,...ij->...j", probabilities, states)
    within = np.einsum(
        "...i,...ijk->...jk", probabilities, covariances
    )
    deviations = states - mean[..., None, :]
    between = np.einsum(
        "...i,...ij,...ik->...jk",
        probabilities,
        deviations,
        deviations,
    )
    uniform_weights = np.full(3, 1.0 / 3.0)
    uniform_mean = np.einsum("i,...ij->...j", uniform_weights, states)
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
    parameter_matrix = np.asarray(
        [[1.0, 2.0], [4.0, 8.0], [10.0, 20.0]]
    )
    maximum = np.argmax(probabilities, axis=-1)
    maximum_parameters = np.take(
        parameter_matrix,
        maximum,
        axis=0,
    )
    return {
        "origin_candidate_states": states,
        "origin_candidate_covariances": covariances,
        "origin_probabilities": probabilities,
        "posterior_mean_states": mean,
        "posterior_within_covariances": within,
        "posterior_between_covariances": between,
        "posterior_complete_covariances": within + between,
        "uniform_mean_states": uniform_mean,
        "uniform_within_covariances": uniform_within,
        "uniform_between_covariances": uniform_between,
        "uniform_complete_covariances": (
            uniform_within + uniform_between
        ),
        "candidate_parameter_matrix": parameter_matrix,
        "posterior_weighted_parameter_vectors": np.einsum(
            "...i,ij->...j", probabilities, parameter_matrix
        ),
        "uniform_parameter_vectors": np.broadcast_to(
            np.mean(parameter_matrix, axis=0),
            (*probabilities.shape[:-1], 2),
        ).copy(),
        "maximum_posterior_indices": maximum,
        "maximum_parameter_vectors": maximum_parameters,
    }


def test_snapshot_verifier_recomputes_state_covariance_and_parameter_moments():
    verifier = importlib.import_module(VERIFIER_MODULE)
    evidence = _posterior_snapshot()

    result = verifier.verify_posterior_snapshot_arrays(
        evidence,
        tolerance=1e-12,
    )

    assert result["passed"] is True
    assert result["maximum_absolute_difference"] == pytest.approx(0.0)


def test_snapshot_verifier_detects_tampered_combined_state():
    verifier = importlib.import_module(VERIFIER_MODULE)
    evidence = _posterior_snapshot()
    evidence["posterior_mean_states"] = evidence[
        "posterior_mean_states"
    ].copy()
    evidence["posterior_mean_states"][0, 0, 0, 0] += 0.1

    with pytest.raises(ValueError, match="posterior mean state"):
        verifier.verify_posterior_snapshot_arrays(
            evidence,
            tolerance=1e-12,
        )


def _algebraic_forecasts():
    candidate = np.arange(
        2 * 1 * 3 * 2 * 3, dtype=np.float64
    ).reshape(2, 1, 3, 2, 3)
    probabilities = np.asarray(
        [
            [[[0.2, 0.7, 0.1], [0.2, 0.7, 0.1], [0.2, 0.7, 0.1]]],
            [[[0.6, 0.2, 0.2], [0.6, 0.2, 0.2], [0.6, 0.2, 0.2]]],
        ]
    )
    current = np.sum(candidate * probabilities[..., None, :], axis=-1)
    maximum_indices = np.argmax(probabilities, axis=-1)
    maximum = np.empty(current.shape)
    for block, truth, origin in np.ndindex(current.shape[:3]):
        maximum[block, truth, origin] = candidate[
            block,
            truth,
            origin,
            :,
            maximum_indices[block, truth, origin],
        ]
    return {
        "current_candidate_forecasts": candidate,
        "origin_probabilities": probabilities,
        "maximum_posterior_indices": maximum_indices,
        "forecast__current_multiple_states": current,
        "forecast__maximum_posterior_candidate": maximum,
    }


def test_algebraic_forecast_verifier_detects_combination_and_selection():
    verifier = importlib.import_module(VERIFIER_MODULE)
    evidence = _algebraic_forecasts()

    result = verifier.verify_algebraic_forecasts(
        evidence, tolerance=1e-12
    )

    assert result["passed"] is True


def test_algebraic_forecast_verifier_detects_tampered_selection():
    verifier = importlib.import_module(VERIFIER_MODULE)
    evidence = _algebraic_forecasts()
    evidence["maximum_posterior_indices"] = evidence[
        "maximum_posterior_indices"
    ].copy()
    evidence["maximum_posterior_indices"][0, 0, 0] = 0

    with pytest.raises(ValueError, match="maximum posterior"):
        verifier.verify_algebraic_forecasts(
            evidence, tolerance=1e-12
        )
