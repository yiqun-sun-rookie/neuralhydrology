"""Independently verify the daily rolling development evidence package."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Mapping

import numpy as np


_METHODS = ("full", "none", "uniform_independent")
_STRATA = (
    ("days_000_006", 0, 6),
    ("days_007_029", 7, 29),
    ("days_030_089", 30, 89),
    ("days_090_179", 90, 179),
)
_ATOL = 1e-12


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_checksums(result_dir: Path) -> dict[str, object]:
    """Verify every artifact listed in checksums.json."""

    root = Path(result_dir).resolve()
    checksum_path = root / "checksums.json"
    expected = json.loads(checksum_path.read_text(encoding="utf-8"))
    if not isinstance(expected, dict) or not expected:
        raise ValueError("checksum manifest must be a nonempty object")
    actual = {}
    for relative, expected_digest in expected.items():
        path = root / relative
        if not path.is_file():
            raise ValueError(f"checksum artifact is missing: {relative}")
        actual[relative] = _sha256(path)
        if actual[relative] != expected_digest:
            raise ValueError(f"checksum mismatch: {relative}")
    unlisted = {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file() and path.name != "checksums.json"
    } - set(expected)
    if unlisted:
        raise ValueError(f"checksum manifest omits artifacts: {sorted(unlisted)}")
    return {
        "passed": True,
        "verified_file_count": len(actual),
    }


def _require(
    evidence: Mapping[str, np.ndarray],
    name: str,
    shape: tuple[int, ...] | None = None,
) -> np.ndarray:
    if name not in evidence:
        raise ValueError(f"evidence is missing {name}")
    values = np.asarray(evidence[name])
    if shape is not None and values.shape != shape:
        raise ValueError(
            f"{name} has shape {values.shape}, expected {shape}"
        )
    return values


def _assert_equal(
    name: str,
    actual,
    expected,
) -> None:
    if not np.array_equal(np.asarray(actual), np.asarray(expected)):
        raise ValueError(f"{name} mismatch")


def _assert_close(
    name: str,
    actual,
    expected,
    differences: list[float],
) -> None:
    left = np.asarray(actual, dtype=np.float64)
    right = np.asarray(expected, dtype=np.float64)
    if left.shape != right.shape:
        raise ValueError(f"{name} shape mismatch")
    difference = float(
        np.max(np.abs(left - right), initial=0.0)
    )
    differences.append(difference)
    if not np.allclose(left, right, rtol=0.0, atol=_ATOL):
        raise ValueError(f"{name} mismatch; maximum difference {difference}")


def _independent_index():
    leads = np.arange(1, 8, dtype=np.int64)
    origins = np.arange(180, 540, dtype=np.int64)
    targets = origins[:, None] + leads[None, :]
    available = targets < 540
    origin_stage = np.searchsorted(
        np.asarray([180, 360]),
        origins,
        side="right",
    )
    target_stage = np.full(targets.shape, -1, dtype=np.int64)
    target_stage[available] = np.searchsorted(
        np.asarray([180, 360]),
        targets[available],
        side="right",
    )
    same = available & (target_stage == origin_stage[:, None])
    cross = available & (target_stage > origin_stage[:, None])
    unavailable = ~available
    offsets = origins - np.where(origin_stage == 1, 180, 360)
    return {
        "lead_days": leads,
        "origin_indices": origins,
        "target_indices": targets,
        "origin_stage_indices": origin_stage,
        "target_stage_indices": target_stage,
        "days_since_switch": offsets,
        "same_stage_mask": same,
        "cross_switch_mask": cross,
        "unavailable_mask": unavailable,
    }


def _masked_rmse(
    squared_error: np.ndarray,
    mask: np.ndarray,
) -> np.ndarray:
    result = np.empty(7, dtype=np.float64)
    for lead_index in range(7):
        selected = squared_error[
            :,
            :,
            mask[:, lead_index],
            lead_index,
        ]
        result[lead_index] = np.sqrt(np.mean(selected))
    return result


def _block_mse(
    squared_error: np.ndarray,
    mask: np.ndarray,
) -> np.ndarray:
    result = np.empty((squared_error.shape[0], 7), dtype=np.float64)
    for lead_index in range(7):
        selected = squared_error[
            :,
            :,
            mask[:, lead_index],
            lead_index,
        ]
        result[:, lead_index] = np.mean(selected, axis=(1, 2))
    return result


def _summary_array(summary: dict, *keys) -> np.ndarray:
    value = summary
    for key in keys:
        value = value[key]
    return np.asarray(value)


def verify_evidence(
    evidence: Mapping[str, np.ndarray],
    summary: dict,
    config: dict,
) -> dict[str, object]:
    """Recompute the development result without importing runner summaries."""

    if tuple(config.get("lead_days", ())) != tuple(range(1, 8)):
        raise ValueError("config lead days mismatch")
    if tuple(config.get("stage_lengths", ())) != (180, 180, 180):
        raise ValueError("config stage lengths mismatch")
    if tuple(config.get("switch_days", ())) != (180, 360):
        raise ValueError("config switch days mismatch")
    block_count = int(config["expected_block_count"])
    truth_count = int(config["expected_truth_count"])
    shape = (block_count, truth_count, 360, 7)
    candidate_shape = (*shape, 3)
    differences: list[float] = []

    expected_index = _independent_index()
    for name, expected in expected_index.items():
        _assert_equal(
            f"{name} mask or index",
            _require(evidence, name, expected.shape),
            expected,
        )
    same_mask = expected_index["same_stage_mask"]
    cross_mask = expected_index["cross_switch_mask"]
    _assert_equal(
        "same-stage sample count",
        np.sum(same_mask, axis=0),
        [358, 356, 354, 352, 350, 348, 346],
    )
    _assert_equal(
        "cross-switch sample count",
        np.sum(cross_mask, axis=0),
        np.arange(1, 8),
    )

    truth = _require(evidence, "truth_forecasts", shape).astype(
        np.float64
    )
    forecasts = {
        "full": _require(evidence, "full_forecasts", shape).astype(
            np.float64
        ),
        "none": _require(evidence, "none_forecasts", shape).astype(
            np.float64
        ),
        "uniform_independent": _require(
            evidence,
            "uniform_independent_forecasts",
            shape,
        ).astype(np.float64),
    }
    candidates = {
        "full": _require(
            evidence, "full_candidate_forecasts", candidate_shape
        ).astype(np.float64),
        "none": _require(
            evidence, "none_candidate_forecasts", candidate_shape
        ).astype(np.float64),
    }
    probabilities = {
        "full": _require(
            evidence, "full_probabilities", candidate_shape
        ).astype(np.float64),
        "none": _require(
            evidence, "none_probabilities", candidate_shape
        ).astype(np.float64),
    }
    if not all(
        np.all(np.isfinite(values))
        for values in (
            truth,
            *forecasts.values(),
            *candidates.values(),
            *probabilities.values(),
        )
    ):
        raise ValueError("forecast evidence contains non-finite values")
    for mode in ("full", "none"):
        _assert_close(
            f"{mode} forecast combination",
            forecasts[mode],
            np.sum(candidates[mode] * probabilities[mode], axis=-1),
            differences,
        )
        _assert_close(
            f"{mode} probability normalization",
            np.sum(probabilities[mode], axis=-1),
            np.ones(shape),
            differences,
        )
        _assert_close(
            f"{mode} fixed probability across leads",
            probabilities[mode],
            np.broadcast_to(
                probabilities[mode][..., :1, :],
                candidate_shape,
            ),
            differences,
        )
    _assert_close(
        "uniform independent forecast reconstruction",
        forecasts["uniform_independent"],
        np.mean(candidates["none"], axis=-1),
        differences,
    )

    squared_errors = {
        method: np.square(values - truth)
        for method, values in forecasts.items()
    }
    rmse = {
        method: _masked_rmse(values, same_mask)
        for method, values in squared_errors.items()
    }
    block_mse = {
        method: _block_mse(values, same_mask)
        for method, values in squared_errors.items()
    }
    for method in _METHODS:
        _assert_close(
            f"{method} squared error",
            _require(evidence, f"squared_error_{method}", shape),
            squared_errors[method],
            differences,
        )
        _assert_close(
            f"{method} block mean squared error",
            _require(
                evidence,
                f"block_mse_{method}",
                (block_count, 7),
            ),
            block_mse[method],
            differences,
        )
        _assert_close(
            f"{method} root mean square error",
            _require(evidence, f"rmse_{method}", (7,)),
            rmse[method],
            differences,
        )
        _assert_close(
            f"{method} summary root mean square error",
            _summary_array(summary, "result", "rmse", method),
            rmse[method],
            differences,
        )

    bootstrap = config["bootstrap"]
    generator = np.random.default_rng(int(bootstrap["seed"]))
    expected_bootstrap = generator.integers(
        0,
        block_count,
        size=(int(bootstrap["replicates"]), block_count),
        endpoint=False,
    )
    saved_bootstrap = _require(
        evidence,
        "bootstrap_indices",
        expected_bootstrap.shape,
    )
    _assert_equal(
        "bootstrap matched-block indices",
        saved_bootstrap,
        expected_bootstrap,
    )
    fraction = float(
        config["development_gates"][
            "minimum_full_stage_rmse_improvement_fraction"
        ]
    )
    comparisons = {
        "full_minus_none": "none",
        "full_minus_uniform_independent": "uniform_independent",
    }
    for comparison, control in comparisons.items():
        block_difference = block_mse["full"] - block_mse[control]
        bootstrap_means = np.mean(
            block_difference[expected_bootstrap],
            axis=1,
        )
        expected_fields = {
            "block_mean": block_difference,
            "mean": np.mean(block_difference, axis=0),
            "ci_low": np.percentile(bootstrap_means, 2.5, axis=0),
            "ci_high": np.percentile(bootstrap_means, 97.5, axis=0),
            "baseline_mse": np.mean(block_mse[control], axis=0),
        }
        expected_fields["meaningful_improvement_boundary"] = (
            expected_fields["baseline_mse"]
            * ((1.0 - fraction) ** 2 - 1.0)
        )
        expected_fields["materially_improves"] = (
            expected_fields["ci_high"]
            < expected_fields["meaningful_improvement_boundary"]
        )
        for field, expected in expected_fields.items():
            saved = _require(
                evidence,
                f"{comparison}_{field}",
                expected.shape,
            )
            if expected.dtype == bool:
                _assert_equal(
                    f"{comparison} {field}",
                    saved,
                    expected,
                )
            else:
                _assert_close(
                    f"{comparison} {field}",
                    saved,
                    expected,
                    differences,
                )
        summary_entry = summary["result"][
            "paired_descriptive_intervals"
        ][comparison]
        for field in (
            "mean",
            "ci_low",
            "ci_high",
            "baseline_mse",
            "meaningful_improvement_boundary",
        ):
            _assert_close(
                f"{comparison} summary {field}",
                summary_entry[field],
                expected_fields[field],
                differences,
            )
        _assert_equal(
            f"{comparison} summary materially improves",
            summary_entry["materially_improves"],
            expected_fields["materially_improves"],
        )

    offsets = expected_index["days_since_switch"]
    for stratum, minimum, maximum in _STRATA:
        mask = same_mask & (
            (offsets >= minimum) & (offsets <= maximum)
        )[:, None]
        _assert_equal(
            f"{stratum} sample count",
            _require(evidence, f"{stratum}_sample_count", (7,)),
            np.sum(mask, axis=0),
        )
        for method in _METHODS:
            expected = _masked_rmse(squared_errors[method], mask)
            _assert_close(
                f"{stratum} {method} root mean square error",
                _require(evidence, f"{stratum}_rmse_{method}", (7,)),
                expected,
                differences,
            )
            _assert_close(
                f"{stratum} {method} summary",
                summary["result"]["time_strata"][stratum]["rmse"][
                    method
                ],
                expected,
                differences,
            )

    for method in _METHODS:
        expected_cross = _masked_rmse(
            squared_errors[method],
            cross_mask,
        )
        _assert_close(
            f"{method} cross-switch root mean square error",
            _require(
                evidence, f"cross_switch_rmse_{method}", (7,)
            ),
            expected_cross,
            differences,
        )

    relative_none = rmse["full"] / rmse["none"] - 1.0
    relative_uniform = (
        rmse["full"] / rmse["uniform_independent"] - 1.0
    )
    passes_none = relative_none <= -fraction
    passes_uniform = relative_uniform <= -fraction
    advance = bool(
        np.all(passes_none)
        and np.all(passes_uniform)
        and summary.get("integrity_status") == "passed"
        and summary.get("protected_artifacts_unchanged") is True
    )
    gate = summary["result"]["development_gate"]
    _assert_equal(
        "development full-versus-none gate",
        gate["full_vs_none_passes"],
        passes_none,
    )
    _assert_equal(
        "development full-versus-uniform gate",
        gate["full_vs_uniform_independent_passes"],
        passes_uniform,
    )
    if bool(gate["advance_to_formal_confirmation"]) != advance:
        raise ValueError("development advance decision mismatch")
    return {
        "passed": True,
        "verified_numeric_field_count": len(differences),
        "maximum_absolute_difference": float(
            max(differences, default=0.0)
        ),
        "advance_to_formal_confirmation": advance,
    }


def verify_result_directory(result_dir: Path) -> dict[str, object]:
    root = Path(result_dir).resolve()
    checksum_report = verify_checksums(root)
    config = json.loads(
        (root / "config_snapshot.json").read_text(encoding="utf-8")
    )
    summary = json.loads(
        (root / "summary.json").read_text(encoding="utf-8")
    )
    with np.load(root / "evidence.npz", allow_pickle=False) as archive:
        evidence = {
            name: np.asarray(archive[name])
            for name in archive.files
        }
    evidence_report = verify_evidence(evidence, summary, config)
    return {
        "passed": True,
        "checksums": checksum_report,
        "evidence": evidence_report,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--result-dir", type=Path, required=True)
    arguments = parser.parse_args()
    result_dir = arguments.result_dir
    if not result_dir.is_absolute():
        result_dir = arguments.repo_root / result_dir
    report = verify_result_directory(result_dir)
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
