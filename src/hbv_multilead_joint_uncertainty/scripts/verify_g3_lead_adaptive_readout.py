"""Independently recompute the lead-adaptive confirmation from raw evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


_METHODS = (
    "lead_adaptive",
    "full_posterior",
    "none_posterior",
    "uniform",
    "oracle",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _verify_checksums(directory: Path) -> None:
    manifest_path = directory / "checksums.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    actual = {
        path.relative_to(directory).as_posix(): _sha256(path)
        for path in sorted(directory.rglob("*"))
        if path.is_file() and path.name != "checksums.json"
    }
    if manifest != actual:
        raise ValueError("checksum manifest does not exactly match package files")


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
    if not np.allclose(
        np.asarray(actual),
        np.asarray(expected),
        rtol=0.0,
        atol=atol,
        equal_nan=False,
    ):
        maximum = float(
            np.max(np.abs(np.asarray(actual) - np.asarray(expected)))
        )
        raise ValueError(
            f"{name} recomputation mismatch; maximum absolute error={maximum}"
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
        "meaningful_improvement_boundary": baseline_mse
        * ((1.0 - fraction) ** 2 - 1.0),
        "meaningful_harm_boundary": baseline_mse
        * ((1.0 + fraction) ** 2 - 1.0),
    }


def verify(output_directory: Path) -> dict:
    """Verify one complete package without calling project summarizers."""

    directory = output_directory.resolve()
    if not directory.is_dir():
        raise FileNotFoundError(f"formal output directory is missing: {directory}")
    _verify_checksums(directory)
    config = json.loads(
        (directory / "config_snapshot.json").read_text(encoding="utf-8")
    )
    with np.load(directory / "evidence.npz", allow_pickle=False) as archive:
        evidence = {name: archive[name].copy() for name in archive.files}

    leads = np.asarray(evidence["lead_days"], dtype=np.int64)
    _assert_exact("configured lead days", leads, config["lead_days"])
    probabilities = np.asarray(
        evidence["full_final_probabilities"],
        dtype=np.float64,
    )
    candidates = np.asarray(
        evidence["full_candidate_forecasts"],
        dtype=np.float64,
    )
    truth = np.asarray(evidence["truth_forecasts"], dtype=np.float64)
    if candidates.shape[:3] != truth.shape:
        raise ValueError("candidate forecast dimensions do not match truth")
    if probabilities.shape != (
        truth.shape[0],
        truth.shape[1],
        candidates.shape[-1],
    ):
        raise ValueError("final probability dimensions do not match candidates")
    if not all(
        np.all(np.isfinite(value))
        for value in (probabilities, candidates, truth)
    ):
        raise ValueError("formal numeric evidence must be finite")
    if np.any(probabilities < 0.0) or not np.allclose(
        np.sum(probabilities, axis=-1),
        1.0,
        rtol=0.0,
        atol=1e-12,
    ):
        raise ValueError("formal final probabilities are invalid")

    selected = np.argmax(probabilities, axis=-1)
    _assert_exact(
        "selected_candidate_indices",
        selected,
        evidence["selected_candidate_indices"],
    )
    rule_by_lead = {
        int(lead): str(rule)
        for lead, rule in config["readout_rule_by_lead"].items()
    }
    weights = np.empty_like(candidates)
    candidate_count = candidates.shape[-1]
    for lead_index, lead in enumerate(leads):
        rule = rule_by_lead[int(lead)]
        if rule == "uniform":
            weights[..., lead_index, :] = 1.0 / candidate_count
        elif rule == "highest_posterior":
            weights[..., lead_index, :] = 0.0
            for block, truth_index in np.ndindex(selected.shape):
                weights[
                    block,
                    truth_index,
                    lead_index,
                    selected[block, truth_index],
                ] = 1.0
        else:
            raise ValueError(f"unsupported configured rule: {rule!r}")
    _assert_close(
        "lead_adaptive_weights",
        weights,
        evidence["lead_adaptive_weights"],
        atol=0.0,
    )
    lead_adaptive = np.sum(weights * candidates, axis=-1)
    _assert_close(
        "lead_adaptive_forecasts",
        lead_adaptive,
        evidence["lead_adaptive_forecasts"],
        atol=1e-12,
    )
    full_posterior = np.einsum(
        "btc,btlc->btl",
        probabilities,
        candidates,
    )
    _assert_close(
        "full_posterior_forecasts",
        full_posterior,
        evidence["full_posterior_forecasts"],
        atol=1e-12,
    )
    uniform = np.mean(candidates, axis=-1)
    _assert_close(
        "uniform_forecasts",
        uniform,
        evidence["uniform_forecasts"],
        atol=1e-12,
    )
    forecasts = {
        "lead_adaptive": lead_adaptive,
        "full_posterior": full_posterior,
        "none_posterior": np.asarray(
            evidence["none_posterior_forecasts"],
            dtype=np.float64,
        ),
        "uniform": uniform,
        "oracle": np.asarray(evidence["oracle_forecasts"], dtype=np.float64),
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
            atol=1e-12,
        )
        rmse[method] = np.sqrt(np.mean(squared, axis=(0, 1)))
        _assert_close(
            f"rmse_{method}",
            rmse[method],
            evidence[f"rmse_{method}"],
            atol=1e-12,
        )

    bootstrap_indices = np.asarray(
        evidence["bootstrap_indices"],
        dtype=np.int64,
    )
    expected_bootstrap_shape = (
        int(config["bootstrap"]["replicates"]),
        truth.shape[0],
    )
    if bootstrap_indices.shape != expected_bootstrap_shape:
        raise ValueError("bootstrap index dimensions do not match config")
    if np.any(bootstrap_indices < 0) or np.any(
        bootstrap_indices >= truth.shape[0]
    ):
        raise ValueError("bootstrap indices are out of range")
    fraction = float(
        config["retention_thresholds"][
            "minimum_meaningful_rmse_fraction"
        ]
    )
    paired = {}
    for baseline in ("none_posterior", "full_posterior"):
        name = f"lead_adaptive_minus_{baseline}"
        entry = _paired_statistics(
            squared_errors["lead_adaptive"],
            squared_errors[baseline],
            bootstrap_indices,
            fraction,
        )
        paired[name] = entry
        for field, computed in entry.items():
            label = (
                f"{name} interval {field}"
                if field in {"ci_low", "ci_high"}
                else f"{name} {field}"
            )
            _assert_close(
                label,
                computed,
                evidence[f"{name}_{field}"],
                atol=1e-12,
            )

    multiday_mask = np.isin(leads, config["retention_thresholds"]["multiday_leads"])
    _assert_exact(
        "multiday lead mask",
        multiday_mask,
        evidence["multiday_lead_mask"],
    )
    none_mse = np.mean(squared_errors["none_posterior"], axis=(0, 1))
    normalized_multiday = (
        squared_errors["lead_adaptive"][..., multiday_mask]
        - squared_errors["none_posterior"][..., multiday_mask]
    ) / none_mse[multiday_mask]
    _assert_close(
        "multiday normalized squared-error difference",
        normalized_multiday,
        evidence["multiday_normalized_squared_error_difference"],
        atol=1e-12,
    )
    composite_block_mean = np.mean(normalized_multiday, axis=(1, 2))
    _assert_close(
        "multiday composite block mean",
        composite_block_mean,
        evidence["multiday_composite_block_mean"],
        atol=1e-12,
    )
    composite_bootstrap = np.mean(
        composite_block_mean[bootstrap_indices],
        axis=1,
    )
    composite = {
        "mean": float(np.mean(composite_block_mean)),
        "ci_low": float(np.percentile(composite_bootstrap, 2.5)),
        "ci_high": float(np.percentile(composite_bootstrap, 97.5)),
    }

    true_indices = np.asarray(
        evidence["true_candidate_indices"],
        dtype=np.int64,
    )
    selection_accuracy = float(np.mean(selected == true_indices))
    none = paired["lead_adaptive_minus_none_posterior"]
    full = paired["lead_adaptive_minus_full_posterior"]
    none_improves = (
        none["ci_high"] < none["meaningful_improvement_boundary"]
    )
    none_no_harm = none["ci_high"] <= none["meaningful_harm_boundary"]
    full_improves = (
        full["ci_high"] < full["meaningful_improvement_boundary"]
    )
    full_no_harm = full["ci_high"] <= full["meaningful_harm_boundary"]
    gates = {
        "none_at_least_one_material_improvement": bool(
            np.any(none_improves)
        ),
        "none_all_leads_no_material_harm": bool(np.all(none_no_harm)),
        "multiday_composite_improves": bool(composite["ci_high"] < 0.0),
        "highest_posterior_selection_accuracy": bool(
            selection_accuracy
            >= float(
                config["retention_thresholds"][
                    "minimum_highest_posterior_selection_accuracy"
                ]
            )
        ),
        "full_at_least_one_material_improvement": bool(
            np.any(full_improves)
        ),
        "full_all_leads_no_material_harm": bool(np.all(full_no_harm)),
    }
    gates["retain"] = bool(all(gates.values()))
    return {
        "passed": True,
        "retention_decision": "retain" if gates["retain"] else "reject",
        "rmse": {
            method: [float(value) for value in rmse[method]]
            for method in _METHODS
        },
        "selection_accuracy": selection_accuracy,
        "multiday_normalized_mse_composite": composite,
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
