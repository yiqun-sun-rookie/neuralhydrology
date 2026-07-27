"""Independently recompute temporal-posterior evidence from raw arrays."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


_METHODS = (
    "temporal_posterior",
    "full_posterior",
    "none_posterior",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _verify_checksums(directory: Path) -> None:
    manifest = json.loads(
        (directory / "checksums.json").read_text(encoding="utf-8")
    )
    actual = {
        path.relative_to(directory).as_posix(): _sha256(path)
        for path in sorted(directory.rglob("*"))
        if path.is_file() and path.name != "checksums.json"
    }
    if manifest != actual:
        raise ValueError(
            "checksum manifest does not exactly match package files"
        )


def _assert_exact(name: str, actual, expected) -> None:
    if not np.array_equal(np.asarray(actual), np.asarray(expected)):
        raise ValueError(f"{name} exact recomputation mismatch")


def _assert_close(
    name: str,
    actual,
    expected,
    *,
    atol: float = 1e-12,
) -> None:
    actual_array = np.asarray(actual)
    expected_array = np.asarray(expected)
    if not np.allclose(
        actual_array,
        expected_array,
        rtol=0.0,
        atol=atol,
        equal_nan=False,
    ):
        maximum = float(np.max(np.abs(actual_array - expected_array)))
        raise ValueError(
            f"{name} recomputation mismatch; "
            f"maximum absolute error={maximum}"
        )


def _paired_statistics(
    new_squared_error: np.ndarray,
    baseline_squared_error: np.ndarray,
    bootstrap_indices: np.ndarray,
    fraction: float,
) -> dict[str, np.ndarray]:
    difference = new_squared_error - baseline_squared_error
    block_mean = np.mean(difference, axis=1)
    bootstrap_mean = np.mean(block_mean[bootstrap_indices], axis=1)
    baseline_mse = np.mean(baseline_squared_error, axis=(0, 1))
    return {
        "squared_error_difference": difference,
        "block_mean": block_mean,
        "mean": np.mean(block_mean, axis=0),
        "ci_low": np.percentile(bootstrap_mean, 2.5, axis=0),
        "ci_high": np.percentile(bootstrap_mean, 97.5, axis=0),
        "baseline_mse": baseline_mse,
        "meaningful_improvement_boundary": (
            baseline_mse * ((1.0 - fraction) ** 2 - 1.0)
        ),
        "meaningful_harm_boundary": (
            baseline_mse * ((1.0 + fraction) ** 2 - 1.0)
        ),
    }


def _expected_block_contract(config: dict) -> dict[str, np.ndarray]:
    generation = config["matched_block_generation"]
    count = int(generation["count"])
    prefix = str(generation["block_id_prefix"])
    return {
        "block_ids": np.asarray(
            [f"{prefix}{offset + 1:03d}" for offset in range(count)]
        ),
        "forcing_seeds": np.arange(
            int(generation["forcing_seed_start"]),
            int(generation["forcing_seed_start"]) + count,
            dtype=np.int64,
        ),
        "process_noise_seeds": np.arange(
            int(generation["process_noise_seed_start"]),
            int(generation["process_noise_seed_start"]) + count,
            dtype=np.int64,
        ),
        "observation_noise_seeds": np.arange(
            int(generation["observation_noise_seed_start"]),
            int(generation["observation_noise_seed_start"]) + count,
            dtype=np.int64,
        ),
    }


def verify(output_directory: Path) -> dict:
    """Verify a complete package without importing project readout logic."""

    directory = output_directory.resolve()
    if not directory.is_dir():
        raise FileNotFoundError(
            f"formal output directory is missing: {directory}"
        )
    _verify_checksums(directory)
    config = json.loads(
        (directory / "config_snapshot.json").read_text(encoding="utf-8")
    )
    with np.load(directory / "evidence.npz", allow_pickle=False) as archive:
        evidence = {name: archive[name].copy() for name in archive.files}

    if config["temporal_readout"] != {
        "window_days": 30,
        "one_day_rule": "final_posterior_weighted",
        "three_and_seven_day_rule": (
            "highest_arithmetic_mean_posterior"
        ),
    }:
        raise ValueError("temporal readout config does not match the contract")
    leads = np.asarray(evidence["lead_days"], dtype=np.int64)
    _assert_exact("configured lead days", leads, config["lead_days"])
    _assert_exact("required lead days", leads, [1, 3, 7])
    for name, expected in _expected_block_contract(config).items():
        _assert_exact(name, evidence[name], expected)

    history = np.asarray(
        evidence["full_probability_history"],
        dtype=np.float64,
    )
    candidates = np.asarray(
        evidence["full_candidate_forecasts"],
        dtype=np.float64,
    )
    truth = np.asarray(evidence["truth_forecasts"], dtype=np.float64)
    if history.ndim != 4 or candidates.ndim != 4 or truth.ndim != 3:
        raise ValueError("formal evidence dimensions are invalid")
    if candidates.shape[:3] != truth.shape:
        raise ValueError("candidate forecast dimensions do not match truth")
    if history.shape[:2] != truth.shape[:2]:
        raise ValueError("probability history dimensions do not match truth")
    if history.shape[-1] != candidates.shape[-1]:
        raise ValueError("candidate dimensions do not match")
    window = int(config["temporal_readout"]["window_days"])
    if history.shape[2] < window:
        raise ValueError("probability history is shorter than the window")
    if not all(
        np.all(np.isfinite(value))
        for value in (history, candidates, truth)
    ):
        raise ValueError("formal numeric evidence must be finite")
    if np.any(history < 0.0) or not np.allclose(
        np.sum(history, axis=-1),
        1.0,
        rtol=0.0,
        atol=1e-12,
    ):
        raise ValueError("formal probability history is invalid")

    final_probabilities = history[..., -1, :]
    _assert_close(
        "full_final_probabilities",
        final_probabilities,
        evidence["full_final_probabilities"],
        atol=0.0,
    )
    normalized_history = history / np.sum(
        history,
        axis=-1,
        keepdims=True,
    )
    temporal_mean = np.mean(
        normalized_history[..., -window:, :],
        axis=2,
    )
    temporal_mean /= np.sum(temporal_mean, axis=-1, keepdims=True)
    _assert_close(
        "temporal_mean_probabilities",
        temporal_mean,
        evidence["temporal_mean_probabilities"],
    )
    selected = np.argmax(temporal_mean, axis=-1)
    _assert_exact(
        "selected_candidate_indices",
        selected,
        evidence["selected_candidate_indices"],
    )

    weights = np.zeros_like(candidates)
    weights[..., 0, :] = normalized_history[..., -1, :]
    for block, truth_index in np.ndindex(selected.shape):
        weights[block, truth_index, 1:, selected[block, truth_index]] = 1.0
    _assert_close(
        "temporal_weights",
        weights,
        evidence["temporal_weights"],
        atol=0.0,
    )
    temporal = np.sum(weights * candidates, axis=-1)
    full = np.einsum("btc,btlc->btl", final_probabilities, candidates)
    none = np.asarray(
        evidence["none_posterior_forecasts"],
        dtype=np.float64,
    )
    if none.shape != truth.shape or not np.all(np.isfinite(none)):
        raise ValueError("none-posterior forecasts are invalid")
    _assert_close(
        "temporal_posterior_forecasts",
        temporal,
        evidence["temporal_posterior_forecasts"],
    )
    _assert_close(
        "full_posterior_forecasts",
        full,
        evidence["full_posterior_forecasts"],
    )
    forecasts = {
        "temporal_posterior": temporal,
        "full_posterior": full,
        "none_posterior": none,
    }

    squared_errors = {}
    rmse = {}
    for method in _METHODS:
        squared = np.square(forecasts[method] - truth)
        squared_errors[method] = squared
        _assert_close(
            f"squared_error_{method}",
            squared,
            evidence[f"squared_error_{method}"],
        )
        rmse[method] = np.sqrt(np.mean(squared, axis=(0, 1)))
        _assert_close(
            f"rmse_{method}",
            rmse[method],
            evidence[f"rmse_{method}"],
        )

    bootstrap = config["bootstrap"]
    generator = np.random.default_rng(int(bootstrap["seed"]))
    bootstrap_indices = generator.integers(
        0,
        truth.shape[0],
        size=(int(bootstrap["replicates"]), truth.shape[0]),
        endpoint=False,
    )
    _assert_exact(
        "bootstrap_indices",
        bootstrap_indices,
        evidence["bootstrap_indices"],
    )
    fraction = float(
        config["retention_thresholds"][
            "minimum_meaningful_rmse_fraction"
        ]
    )
    paired = {}
    for baseline in ("full_posterior", "none_posterior"):
        name = f"temporal_minus_{baseline}"
        entry = _paired_statistics(
            squared_errors["temporal_posterior"],
            squared_errors[baseline],
            bootstrap_indices,
            fraction,
        )
        paired[name] = entry
        for field, value in entry.items():
            _assert_close(
                f"{name}_{field}",
                value,
                evidence[f"{name}_{field}"],
            )

    one_day_difference = float(
        np.max(np.abs(temporal[..., 0] - full[..., 0]), initial=0.0)
    )
    _assert_close(
        "one_day_maximum_absolute_difference",
        one_day_difference,
        evidence["one_day_maximum_absolute_difference"],
    )
    true_indices = np.asarray(
        evidence["true_candidate_indices"],
        dtype=np.int64,
    )
    if true_indices.shape != selected.shape:
        raise ValueError("true candidate index dimensions are invalid")
    if np.any(true_indices < 0) or np.any(
        true_indices >= candidates.shape[-1]
    ):
        raise ValueError("true candidate indices are out of range")
    selection_accuracy = float(np.mean(selected == true_indices))
    full_pair = paired["temporal_minus_full_posterior"]
    none_pair = paired["temporal_minus_none_posterior"]
    gates = {
        "one_day_exact": bool(one_day_difference <= 1e-12),
        "selection_accuracy": bool(
            selection_accuracy
            >= float(
                config["retention_thresholds"][
                    "minimum_temporal_selection_accuracy"
                ]
            )
        ),
        "three_day_no_material_harm_vs_full": bool(
            full_pair["ci_high"][1]
            < full_pair["meaningful_harm_boundary"][1]
        ),
        "seven_day_material_improvement_vs_full": bool(
            full_pair["ci_high"][2]
            < full_pair["meaningful_improvement_boundary"][2]
        ),
        "three_day_no_material_harm_vs_none": bool(
            none_pair["ci_high"][1]
            < none_pair["meaningful_harm_boundary"][1]
        ),
        "seven_day_material_improvement_vs_none": bool(
            none_pair["ci_high"][2]
            < none_pair["meaningful_improvement_boundary"][2]
        ),
    }
    gates["retain"] = bool(all(gates.values()))
    return {
        "passed": True,
        "retention_decision": (
            "retain" if gates["retain"] else "reject"
        ),
        "rmse": {
            method: [float(value) for value in rmse[method]]
            for method in _METHODS
        },
        "selection_accuracy": selection_accuracy,
        "paired": {
            name: {
                field: [
                    float(value) for value in np.asarray(entry[field])
                ]
                for field in (
                    "mean",
                    "ci_low",
                    "ci_high",
                    "meaningful_improvement_boundary",
                    "meaningful_harm_boundary",
                )
            }
            for name, entry in paired.items()
        },
        "retention_gates": gates,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    arguments = parser.parse_args()
    print(
        json.dumps(
            verify(arguments.output_dir),
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
