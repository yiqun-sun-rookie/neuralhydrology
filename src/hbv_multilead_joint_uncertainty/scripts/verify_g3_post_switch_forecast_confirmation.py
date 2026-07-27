"""Independently verify the post-switch forecast confirmation evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


_METHODS = ("full", "none", "uniform_independent")
_COMPARISONS = {
    "full_minus_none": "none",
    "full_minus_uniform_independent": "uniform_independent",
}
_ATOL = 1e-12


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _maximum_error(left, right) -> float:
    left_values = np.asarray(left)
    right_values = np.asarray(right)
    if left_values.shape != right_values.shape:
        return float("inf")
    if left_values.dtype.kind in "bUSO" or right_values.dtype.kind in "bUSO":
        return 0.0 if np.array_equal(left_values, right_values) else float("inf")
    return float(
        np.max(
            np.abs(
                left_values.astype(np.float64)
                - right_values.astype(np.float64)
            ),
            initial=0.0,
        )
    )


def _require(archive: np.lib.npyio.NpzFile, name: str) -> np.ndarray:
    if name not in archive.files:
        raise ValueError(f"evidence is missing array {name}")
    return np.asarray(archive[name])


def _verify_arrays(
    evidence: np.lib.npyio.NpzFile,
    config: dict,
    summary: dict,
    cross_checks: dict,
) -> dict:
    """Recompute all numerical claims without production summary code."""

    leads = _require(evidence, "lead_days")
    if not np.array_equal(leads, np.asarray([1, 3, 7])):
        raise ValueError("lead-day evidence does not equal 1, 3, and 7")
    truth = _require(evidence, "truth_forecasts").astype(np.float64)
    if truth.ndim != 4 or truth.shape[-1] != 3:
        raise ValueError("truth evidence shape is invalid")
    scoring_mask = _require(evidence, "scoring_origin_mask").astype(bool)
    origins = _require(evidence, "origin_indices")
    targets = _require(evidence, "target_indices")
    if (
        scoring_mask.shape != origins.shape
        or targets.shape != (len(origins), 3)
        or not np.array_equal(targets, origins[:, None] + leads[None, :])
        or int(np.sum(scoring_mask)) != truth.shape[2]
    ):
        raise ValueError("origin, target, or scoring-mask evidence is invalid")

    stored_forecasts = {
        "full": _require(evidence, "full_forecasts").astype(np.float64),
        "none": _require(evidence, "none_forecasts").astype(np.float64),
        "uniform_independent": _require(
            evidence, "uniform_independent_forecasts"
        ).astype(np.float64),
    }
    full_all = _require(
        evidence, "full_all_origin_forecasts"
    ).astype(np.float64)
    none_all = _require(
        evidence, "none_all_origin_forecasts"
    ).astype(np.float64)
    full_candidates = _require(
        evidence, "full_candidate_forecasts"
    ).astype(np.float64)
    none_candidates = _require(
        evidence, "none_candidate_forecasts"
    ).astype(np.float64)
    full_probabilities = _require(
        evidence, "full_probabilities"
    ).astype(np.float64)
    none_probabilities = _require(
        evidence, "none_probabilities"
    ).astype(np.float64)
    if (
        full_all.shape != none_all.shape
        or full_candidates.shape != none_candidates.shape
        or full_probabilities.shape != full_candidates.shape
        or none_probabilities.shape != none_candidates.shape
        or full_all.shape != full_candidates.shape[:-1]
        or full_all.shape[2] != len(origins)
        or stored_forecasts["full"].shape != truth.shape
        or any(values.shape != truth.shape for values in stored_forecasts.values())
    ):
        raise ValueError("forecast evidence shapes are inconsistent")
    if not all(
        np.all(np.isfinite(values))
        for values in (
            truth,
            full_all,
            none_all,
            full_candidates,
            none_candidates,
            full_probabilities,
            none_probabilities,
            *stored_forecasts.values(),
        )
    ):
        raise ValueError("forecast evidence must be finite")

    recomputed_forecasts = {
        "full": full_all[:, :, scoring_mask],
        "none": none_all[:, :, scoring_mask],
        "uniform_independent": np.mean(
            none_candidates[:, :, scoring_mask],
            axis=-1,
        ),
    }
    numeric_errors: dict[str, float] = {}
    for method in _METHODS:
        numeric_errors[f"forecast_{method}"] = _maximum_error(
            stored_forecasts[method],
            recomputed_forecasts[method],
        )
    numeric_errors["full_combination"] = _maximum_error(
        full_all,
        np.sum(full_probabilities * full_candidates, axis=-1),
    )
    numeric_errors["none_combination"] = _maximum_error(
        none_all,
        np.sum(none_probabilities * none_candidates, axis=-1),
    )
    numeric_errors["full_probability_sum"] = _maximum_error(
        np.sum(full_probabilities, axis=-1),
        np.ones(full_probabilities.shape[:-1]),
    )
    numeric_errors["none_probability_sum"] = _maximum_error(
        np.sum(none_probabilities, axis=-1),
        np.ones(none_probabilities.shape[:-1]),
    )
    numeric_errors["full_probability_freezing"] = _maximum_error(
        full_probabilities,
        np.broadcast_to(
            full_probabilities[..., :1, :],
            full_probabilities.shape,
        ),
    )
    numeric_errors["none_probability_freezing"] = _maximum_error(
        none_probabilities,
        np.broadcast_to(
            none_probabilities[..., :1, :],
            none_probabilities.shape,
        ),
    )

    squared_errors = {
        method: np.square(values - truth)
        for method, values in recomputed_forecasts.items()
    }
    rmse = {
        method: np.sqrt(np.mean(values, axis=(0, 1, 2)))
        for method, values in squared_errors.items()
    }
    per_origin_rmse = {
        method: np.sqrt(np.mean(values, axis=(0, 1)))
        for method, values in squared_errors.items()
    }
    for method in _METHODS:
        numeric_errors[f"squared_error_{method}"] = _maximum_error(
            _require(evidence, f"squared_error_{method}"),
            squared_errors[method],
        )
        numeric_errors[f"rmse_{method}"] = _maximum_error(
            _require(evidence, f"rmse_{method}"),
            rmse[method],
        )
        numeric_errors[f"per_origin_rmse_{method}"] = _maximum_error(
            _require(evidence, f"per_origin_rmse_{method}"),
            per_origin_rmse[method],
        )

    replicates = int(config["bootstrap"]["replicates"])
    seed = int(config["bootstrap"]["seed"])
    generator = np.random.default_rng(seed)
    bootstrap_indices = generator.integers(
        0,
        truth.shape[0],
        size=(replicates, truth.shape[0]),
        endpoint=False,
    )
    numeric_errors["bootstrap_indices"] = _maximum_error(
        _require(evidence, "bootstrap_indices"),
        bootstrap_indices,
    )
    fraction = float(
        config["retention_thresholds"][
            "minimum_meaningful_rmse_fraction"
        ]
    )
    multiplier = (1.0 - fraction) ** 2 - 1.0
    paired: dict[str, dict[str, np.ndarray]] = {}
    for comparison, baseline in _COMPARISONS.items():
        difference = squared_errors["full"] - squared_errors[baseline]
        block_mean = np.mean(difference, axis=(1, 2))
        bootstrap_means = np.mean(
            block_mean[bootstrap_indices],
            axis=1,
        )
        entry = {
            "squared_error_difference": difference,
            "block_mean": block_mean,
            "mean": np.mean(block_mean, axis=0),
            "ci_low": np.percentile(bootstrap_means, 2.5, axis=0),
            "ci_high": np.percentile(bootstrap_means, 97.5, axis=0),
            "baseline_mse": np.mean(
                squared_errors[baseline],
                axis=(0, 1, 2),
            ),
        }
        entry["meaningful_improvement_boundary"] = (
            entry["baseline_mse"] * multiplier
        )
        entry["materially_improves"] = (
            entry["ci_high"]
            < entry["meaningful_improvement_boundary"]
        )
        paired[comparison] = entry
        for field in (
            "squared_error_difference",
            "block_mean",
            "mean",
            "ci_low",
            "ci_high",
            "baseline_mse",
            "meaningful_improvement_boundary",
        ):
            numeric_errors[f"{comparison}_{field}"] = _maximum_error(
                _require(evidence, f"{comparison}_{field}"),
                entry[field],
            )

    gates = {
        "full_materially_improves_none_all_leads": bool(
            np.all(paired["full_minus_none"]["materially_improves"])
        ),
        "full_materially_improves_uniform_independent_all_leads": bool(
            np.all(
                paired["full_minus_uniform_independent"][
                    "materially_improves"
                ]
            )
        ),
    }
    gates["retain"] = bool(all(gates.values()))

    summary_result = summary.get("result", {})
    summary_errors: dict[str, float] = {}
    for method in _METHODS:
        summary_errors[f"summary_rmse_{method}"] = _maximum_error(
            summary_result.get("rmse", {}).get(method, []),
            rmse[method],
        )
        summary_errors[f"summary_per_origin_rmse_{method}"] = _maximum_error(
            summary_result.get("per_origin_rmse", {}).get(method, []),
            per_origin_rmse[method],
        )
    for comparison, entry in paired.items():
        stored = summary_result.get("paired", {}).get(comparison, {})
        for field in (
            "mean",
            "ci_low",
            "ci_high",
            "baseline_mse",
            "meaningful_improvement_boundary",
            "materially_improves",
        ):
            summary_errors[f"summary_{comparison}_{field}"] = _maximum_error(
                stored.get(field, []),
                entry[field],
            )
    stored_gates = summary_result.get("retention_gates", {})
    gate_match = stored_gates == gates
    decision = "retain" if gates["retain"] else "reject"
    decision_match = summary.get("retention_decision") == decision
    integrity_match = (
        summary.get("integrity_status") == "passed"
        and cross_checks.get("passed") is True
    )
    maximum_error = max(
        [*numeric_errors.values(), *summary_errors.values()],
        default=0.0,
    )
    passed = bool(
        np.isfinite(maximum_error)
        and maximum_error <= _ATOL
        and gate_match
        and decision_match
        and integrity_match
    )
    return {
        "passed": passed,
        "maximum_absolute_error": float(maximum_error),
        "checked_numeric_field_count": (
            len(numeric_errors) + len(summary_errors)
        ),
        "numeric_errors": numeric_errors,
        "summary_errors": summary_errors,
        "retention_gates_match": gate_match,
        "retention_decision_matches": decision_match,
        "integrity_status_matches": integrity_match,
        "recomputed_retention_gates": gates,
        "recomputed_retention_decision": decision,
    }


def _verify_package_checksums(directory: Path) -> dict:
    checksum_path = directory / "checksums.json"
    checksums = json.loads(checksum_path.read_text(encoding="utf-8"))
    files = {
        path.relative_to(directory).as_posix()
        for path in directory.rglob("*")
        if path.is_file() and path.name != "checksums.json"
    }
    names_match = set(checksums) == files
    mismatches = [
        relative
        for relative, expected in checksums.items()
        if not (directory / relative).is_file()
        or _sha256(directory / relative) != expected
    ]
    return {
        "passed": bool(names_match and not mismatches),
        "file_set_matches": names_match,
        "mismatches": sorted(mismatches),
        "checked_file_count": len(checksums),
    }


def verify(results_dir: Path, output_dir: Path) -> dict:
    results = results_dir.resolve()
    output = output_dir.resolve()
    incomplete = output.with_name(output.name + ".incomplete")
    if output.exists() or incomplete.exists():
        raise FileExistsError("refusing to overwrite verification evidence")
    if not results.is_dir():
        raise FileNotFoundError("formal results directory is missing")
    package = _verify_package_checksums(results)
    config = json.loads(
        (results / "config_snapshot.json").read_text(encoding="utf-8")
    )
    summary = json.loads(
        (results / "summary.json").read_text(encoding="utf-8")
    )
    cross_checks = json.loads(
        (results / "cross_checks.json").read_text(encoding="utf-8")
    )
    with np.load(results / "evidence.npz", allow_pickle=False) as evidence:
        arrays = _verify_arrays(evidence, config, summary, cross_checks)
    report = {
        "passed": bool(package["passed"] and arrays["passed"]),
        "formal_results_directory": str(results),
        "formal_results_sha256": _sha256(results / "evidence.npz"),
        "package_checksums": package,
        "array_recomputation": arrays,
    }
    incomplete.mkdir(parents=True, exist_ok=False)
    (incomplete / "verification.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    checksums = {
        "verification.json": _sha256(incomplete / "verification.json")
    }
    (incomplete / "checksums.json").write_text(
        json.dumps(checksums, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    incomplete.replace(output)
    if not report["passed"]:
        raise RuntimeError("independent verification failed")
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    arguments = parser.parse_args()
    report = verify(arguments.results_dir, arguments.output_dir)
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
