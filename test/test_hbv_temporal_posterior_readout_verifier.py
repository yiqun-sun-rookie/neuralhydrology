"""Independent recomputation tests for temporal-posterior evidence."""

from __future__ import annotations

import hashlib
import importlib
import inspect
import json
from pathlib import Path

import numpy as np
import pytest


VERIFIER_MODULE = (
    "hbv_multilead_joint_uncertainty.scripts."
    "verify_g3_temporal_posterior_readout"
)
METHODS = (
    "temporal_posterior",
    "full_posterior",
    "none_posterior",
)


def _paired(new, baseline, bootstrap, fraction):
    difference = new - baseline
    block_mean = np.mean(difference, axis=1)
    samples = np.mean(block_mean[bootstrap], axis=1)
    baseline_mse = np.mean(baseline, axis=(0, 1))
    return {
        "squared_error_difference": difference,
        "block_mean": block_mean,
        "mean": np.mean(block_mean, axis=0),
        "ci_low": np.percentile(samples, 2.5, axis=0),
        "ci_high": np.percentile(samples, 97.5, axis=0),
        "baseline_mse": baseline_mse,
        "meaningful_improvement_boundary": (
            baseline_mse * ((1.0 - fraction) ** 2 - 1.0)
        ),
        "meaningful_harm_boundary": (
            baseline_mse * ((1.0 + fraction) ** 2 - 1.0)
        ),
    }


def _write_package(directory: Path) -> Path:
    directory.mkdir()
    block_count, truth_count, lead_count, candidate_count = 4, 3, 3, 3
    config = {
        "matched_block_generation": {
            "count": block_count,
            "block_id_prefix": "test_block_",
            "forcing_seed_start": 10,
            "process_noise_seed_start": 20,
            "observation_noise_seed_start": 30,
        },
        "lead_days": [1, 3, 7],
        "temporal_readout": {
            "window_days": 30,
            "one_day_rule": "final_posterior_weighted",
            "three_and_seven_day_rule": (
                "highest_arithmetic_mean_posterior"
            ),
        },
        "bootstrap": {
            "unit": "matched_block",
            "replicates": 50,
            "seed": 40,
            "shared_resample_indices_across_leads": True,
        },
        "retention_thresholds": {
            "minimum_meaningful_rmse_fraction": 0.01,
            "minimum_temporal_selection_accuracy": 0.95,
        },
    }
    (directory / "config_snapshot.json").write_text(
        json.dumps(config, indent=2, sort_keys=True),
        encoding="utf-8",
    )

    history = np.broadcast_to(
        np.asarray([0.1, 0.2, 0.7]),
        (block_count, truth_count, 30, candidate_count),
    ).copy()
    history[..., -1, :] = np.asarray([0.8, 0.15, 0.05])
    final = history[..., -1, :]
    temporal_mean = np.mean(history, axis=2)
    selected = np.argmax(temporal_mean, axis=-1)
    candidates = np.empty(
        (block_count, truth_count, lead_count, candidate_count)
    )
    base = np.arange(block_count * truth_count).reshape(
        block_count,
        truth_count,
        1,
        1,
    )
    candidates[...] = (
        base
        + np.asarray([1.0, 2.0, 3.0]).reshape(1, 1, lead_count, 1)
        + np.asarray([0.0, 0.4, 0.8]).reshape(
            1,
            1,
            1,
            candidate_count,
        )
    )
    weights = np.zeros_like(candidates)
    weights[..., 0, :] = final
    weights[..., 1:, 2] = 1.0
    temporal = np.sum(weights * candidates, axis=-1)
    full = np.einsum("btc,btlc->btl", final, candidates)
    truth = candidates[..., 2] - 0.2
    none = full + np.asarray([0.2, 0.4, 0.8])
    forecasts = {
        "temporal_posterior": temporal,
        "full_posterior": full,
        "none_posterior": none,
    }
    squared = {
        method: np.square(value - truth)
        for method, value in forecasts.items()
    }
    generator = np.random.default_rng(config["bootstrap"]["seed"])
    bootstrap = generator.integers(
        0,
        block_count,
        size=(config["bootstrap"]["replicates"], block_count),
        endpoint=False,
    )
    arrays = {
        "block_ids": np.asarray(
            [f"test_block_{index + 1:03d}" for index in range(block_count)]
        ),
        "forcing_seeds": np.arange(10, 10 + block_count),
        "process_noise_seeds": np.arange(20, 20 + block_count),
        "observation_noise_seeds": np.arange(30, 30 + block_count),
        "lead_days": np.asarray([1, 3, 7]),
        "truth_forecasts": truth,
        "full_candidate_forecasts": candidates,
        "full_probability_history": history,
        "full_final_probabilities": final,
        "full_posterior_forecasts": full,
        "none_posterior_forecasts": none,
        "temporal_posterior_forecasts": temporal,
        "temporal_weights": weights,
        "temporal_mean_probabilities": temporal_mean,
        "selected_candidate_indices": selected,
        "true_candidate_indices": np.full_like(selected, 2),
        "bootstrap_indices": bootstrap,
        "one_day_maximum_absolute_difference": np.asarray(0.0),
    }
    for method in METHODS:
        arrays[f"squared_error_{method}"] = squared[method]
        arrays[f"rmse_{method}"] = np.sqrt(
            np.mean(squared[method], axis=(0, 1))
        )
    for baseline in ("full_posterior", "none_posterior"):
        name = f"temporal_minus_{baseline}"
        entry = _paired(
            squared["temporal_posterior"],
            squared[baseline],
            bootstrap,
            0.01,
        )
        for field, value in entry.items():
            arrays[f"{name}_{field}"] = value
    np.savez_compressed(directory / "evidence.npz", **arrays)
    checksums = {
        path.name: hashlib.sha256(path.read_bytes()).hexdigest()
        for path in directory.iterdir()
        if path.is_file()
    }
    (directory / "checksums.json").write_text(
        json.dumps(checksums, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    return directory


def _rewrite_evidence(directory: Path, mutation) -> None:
    path = directory / "evidence.npz"
    with np.load(path, allow_pickle=False) as archive:
        arrays = {name: archive[name].copy() for name in archive.files}
    mutation(arrays)
    np.savez_compressed(path, **arrays)
    checksums_path = directory / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    checksums["evidence.npz"] = hashlib.sha256(path.read_bytes()).hexdigest()
    checksums_path.write_text(
        json.dumps(checksums, indent=2, sort_keys=True),
        encoding="utf-8",
    )


def test_independent_verifier_recomputes_self_contained_package(tmp_path):
    verifier = importlib.import_module(VERIFIER_MODULE)
    directory = _write_package(tmp_path / "package")

    result = verifier.verify(directory)

    assert result["passed"] is True
    assert result["selection_accuracy"] == 1.0
    assert set(result["rmse"]) == set(METHODS)
    assert set(result["retention_gates"]) == {
        "one_day_exact",
        "selection_accuracy",
        "three_day_no_material_harm_vs_full",
        "seven_day_material_improvement_vs_full",
        "three_day_no_material_harm_vs_none",
        "seven_day_material_improvement_vs_none",
        "retain",
    }


def test_verifier_is_independent_of_project_readout_and_summary(tmp_path):
    verifier = importlib.import_module(VERIFIER_MODULE)
    source = inspect.getsource(verifier)

    assert "temporal_posterior_readout import" not in source
    assert "summarize_temporal_posterior_readout" not in source
    assert "summary.json" not in source


@pytest.mark.parametrize(
    ("mutation", "match"),
    [
        (
            lambda arrays: arrays["selected_candidate_indices"].__setitem__(
                (0, 0),
                0,
            ),
            "selected_candidate_indices",
        ),
        (
            lambda arrays: arrays["bootstrap_indices"].fill(0),
            "bootstrap_indices",
        ),
        (
            lambda arrays: arrays[
                "temporal_minus_full_posterior_ci_high"
            ].__setitem__(
                1,
                arrays[
                    "temporal_minus_full_posterior_ci_high"
                ][1]
                + 1.0,
            ),
            "ci_high",
        ),
    ],
)
def test_verifier_rejects_semantic_tampering_with_updated_checksum(
    tmp_path,
    mutation,
    match,
):
    verifier = importlib.import_module(VERIFIER_MODULE)
    directory = _write_package(tmp_path / "package")
    _rewrite_evidence(directory, mutation)

    with pytest.raises(ValueError, match=match):
        verifier.verify(directory)


def test_verifier_rejects_unregistered_file(tmp_path):
    verifier = importlib.import_module(VERIFIER_MODULE)
    directory = _write_package(tmp_path / "package")
    (directory / "extra.txt").write_text("tamper", encoding="utf-8")

    with pytest.raises(ValueError, match="checksum"):
        verifier.verify(directory)
