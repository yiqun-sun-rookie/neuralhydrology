"""Frozen continuation gate for the fixed historical-band pilot."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path

import numpy as np
import pandas as pd

from metrics import per_basin_nse
from train import VARIANTS


SEEDS = (100, 200, 300)
MIN_MEDIAN_EFFECT = 0.01
MIN_WIN_FRACTION = 0.55
MAX_MEAN_EXPERT_WEIGHT = 0.95
BOOTSTRAP_SEED = 260726
BOOTSTRAP_RESAMPLES = 10_000
VALIDATION_START = pd.Timestamp("2006-10-01")
VALIDATION_END = pd.Timestamp("2008-09-30")
EXPECTED_VALIDATION_DATES = pd.date_range(VALIDATION_START, VALIDATION_END, freq="D")
EXPECTED_BASIN_COUNT = 60

def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _atomic_text(path: Path, text: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, path)


def _atomic_frame(path: Path, frame: pd.DataFrame) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    frame.to_csv(temporary, index=False)
    os.replace(temporary, path)


def paired_bootstrap_interval(
    values: np.ndarray,
    seed: int = BOOTSTRAP_SEED,
    n_resamples: int = BOOTSTRAP_RESAMPLES,
) -> tuple[float, float]:
    """Return a deterministic percentile interval for the paired median effect."""
    values = np.asarray(values, dtype=np.float64)
    values = values[np.isfinite(values)]
    if len(values) < 2:
        return float("nan"), float("nan")
    generator = np.random.default_rng(seed)
    sample_indices = generator.integers(0, len(values), size=(n_resamples, len(values)))
    medians = np.median(values[sample_indices], axis=1)
    return float(np.quantile(medians, 0.025)), float(np.quantile(medians, 0.975))


def evaluate_continuation(
    per_seed: pd.DataFrame,
    paired_per_basin: pd.DataFrame,
    mean_weights: dict[str, float],
) -> dict:
    """Apply the six preregistered criteria without runtime threshold overrides."""
    median_pass = per_seed["median_delta_expert_fusion"] >= MIN_MEDIAN_EFFECT
    win_pass = per_seed["win_fraction_expert_fusion"] >= MIN_WIN_FRACTION
    bootstrap_low, bootstrap_high = paired_bootstrap_interval(
        paired_per_basin["delta_expert_fusion_mean"].to_numpy(dtype=np.float64)
    )
    mainstream_median = float(
        np.nanmedian(paired_per_basin["delta_expert_mainstream_mean"].to_numpy(dtype=np.float64))
    )
    maximum_weight = float(max(mean_weights.values())) if mean_weights else float("nan")
    criteria = {
        "median_effect": bool(int(median_pass.sum()) >= 2),
        "basin_win_fraction": bool(int(win_pass.sum()) >= 2),
        "two_seed_joint_consistency": bool(int((median_pass & win_pass).sum()) >= 2),
        "bootstrap_lower_above_zero": bool(np.isfinite(bootstrap_low) and bootstrap_low > 0),
        "not_worse_than_mainstream": bool(np.isfinite(mainstream_median) and mainstream_median >= 0),
        "no_weight_collapse": bool(np.isfinite(maximum_weight) and maximum_weight <= MAX_MEAN_EXPERT_WEIGHT),
    }
    return {
        "verdict": "GO" if all(criteria.values()) else "NO_GO",
        "criteria": criteria,
        "bootstrap_95_interval": [bootstrap_low, bootstrap_high],
        "median_delta_expert_mainstream": mainstream_median,
        "mean_expert_weights": mean_weights,
        "maximum_mean_expert_weight": maximum_weight,
        "thresholds": {
            "minimum_median_effect": MIN_MEDIAN_EFFECT,
            "minimum_basin_win_fraction": MIN_WIN_FRACTION,
            "minimum_joint_passing_seeds": 2,
            "maximum_mean_expert_weight": MAX_MEAN_EXPERT_WEIGHT,
        },
    }


def _expected_runs() -> list[str]:
    return [f"{variant}_s{seed}" for variant in VARIANTS for seed in SEEDS]


def validate_prediction_frame(
    predictions: pd.DataFrame,
    expected_basins: tuple[str, ...] | None = None,
    expected_dates: pd.DatetimeIndex = EXPECTED_VALIDATION_DATES,
) -> pd.DataFrame:
    """Reject incomplete, duplicate, or non-finite daily prediction evidence."""
    required = {"basin", "date", "qobs", "qsim"}
    missing = required - set(predictions.columns)
    if missing:
        raise ValueError(f"prediction table is missing columns: {sorted(missing)}")
    frame = predictions.copy()
    frame["basin"] = frame["basin"].astype(str).str.zfill(8)
    frame["date"] = pd.to_datetime(frame["date"], errors="raise")
    if frame.duplicated(["basin", "date"]).any():
        raise ValueError("prediction table contains a duplicate basin-date key")
    values = frame[["qobs", "qsim"]].to_numpy(dtype=np.float64)
    if not np.isfinite(values).all():
        raise ValueError("prediction table contains non-finite observed or simulated discharge")

    actual_basins = tuple(sorted(frame["basin"].unique()))
    if expected_basins is None:
        if len(actual_basins) != EXPECTED_BASIN_COUNT:
            raise ValueError(
                f"prediction basin count must be {EXPECTED_BASIN_COUNT}, got {len(actual_basins)}"
            )
        basin_ids = actual_basins
    else:
        basin_ids = tuple(str(basin).zfill(8) for basin in expected_basins)
        if set(actual_basins) != set(basin_ids):
            raise ValueError("prediction basin set does not match the expected basins")

    expected_dates = pd.DatetimeIndex(expected_dates)
    ordered = frame.sort_values(["basin", "date"]).reset_index(drop=True)
    expected_index = pd.MultiIndex.from_product(
        [basin_ids, expected_dates], names=["basin", "date"]
    )
    actual_index = pd.MultiIndex.from_frame(ordered[["basin", "date"]])
    if not actual_index.equals(expected_index):
        raise ValueError("prediction basin-date keys are incomplete or unexpected")
    return ordered


def assert_matching_daily_targets(predictions_by_variant: dict[str, pd.DataFrame]) -> None:
    """Require identical daily keys and observed discharge across comparison arms."""
    reference_name = next(iter(predictions_by_variant))
    reference = predictions_by_variant[reference_name].sort_values(["basin", "date"])
    reference_keys = reference[["basin", "date"]].reset_index(drop=True)
    reference_qobs = reference["qobs"].to_numpy(dtype=np.float64)
    for name, frame in predictions_by_variant.items():
        ordered = frame.sort_values(["basin", "date"]).reset_index(drop=True)
        if not ordered[["basin", "date"]].equals(reference_keys):
            raise ValueError(f"daily prediction keys differ between {reference_name} and {name}")
        if not np.array_equal(ordered["qobs"].to_numpy(dtype=np.float64), reference_qobs):
            raise ValueError(f"observed discharge differs between {reference_name} and {name}")


def _validated_predictions(run_dir: Path, variant: str, seed: int) -> pd.DataFrame:
    manifest_path = run_dir / "manifest.json"
    predictions_path = run_dir / "predictions.csv"
    if not manifest_path.exists() or not predictions_path.exists():
        raise FileNotFoundError(f"missing manifest or predictions in {run_dir}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("status") != "complete":
        raise ValueError(f"run is not complete: {run_dir}")
    if manifest.get("variant") != variant or int(manifest.get("seed", -1)) != seed:
        raise ValueError(f"manifest identity mismatch: {run_dir}")
    required_artifacts = {
        "config.json", "checkpoint.pt", "predictions.csv", "per_basin_metrics.csv"
    }
    artifacts = manifest.get("artifacts", {})
    if not required_artifacts.issubset(artifacts):
        raise ValueError(f"manifest artifact list is incomplete: {run_dir}")
    for name, expected_hash in artifacts.items():
        artifact_path = run_dir / name
        if not artifact_path.exists() or _sha256(artifact_path) != expected_hash:
            raise ValueError(f"artifact hash mismatch for {name}: {run_dir}")
    predictions = pd.read_csv(predictions_path, dtype={"basin": str})
    expected_rows = EXPECTED_BASIN_COUNT * len(EXPECTED_VALIDATION_DATES)
    if int(manifest.get("n_validation_predictions", -1)) != expected_rows:
        raise ValueError(f"manifest validation row count is not {expected_rows}: {run_dir}")
    return validate_prediction_frame(predictions)

def analyze_results(results_root: str | Path) -> dict:
    """Recompute all metrics from daily predictions and write the frozen decision."""
    results_root = Path(results_root)
    results_root.mkdir(parents=True, exist_ok=True)
    missing = [
        run_name
        for run_name in _expected_runs()
        if not (results_root / run_name / "manifest.json").exists()
    ]
    if missing:
        summary = {
            "verdict": "INCOMPLETE",
            "missing_runs": missing,
            "expected_run_count": len(_expected_runs()),
        }
        _atomic_text(results_root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
        return summary

    seed_pairs = []
    expert_prediction_frames = []
    for seed in SEEDS:
        predictions_by_variant = {
            variant: _validated_predictions(
                results_root / f"{variant}_s{seed}",
                variant,
                seed,
            )
            for variant in VARIANTS
        }
        assert_matching_daily_targets(predictions_by_variant)
        metric_frames = {
            variant: per_basin_nse(predictions).rename(
                columns={"nse": f"nse_{variant}", "n_days": f"n_days_{variant}"}
            )
            for variant, predictions in predictions_by_variant.items()
        }
        expert_prediction_frames.append(predictions_by_variant["historical_band_experts"])

        paired = metric_frames["historical_band_experts"]
        for variant in ("multiscale_fusion", "mainstream_lstm"):
            paired = paired.merge(metric_frames[variant], on="basin", how="inner")
        paired["seed"] = seed
        paired["delta_expert_fusion"] = (
            paired["nse_historical_band_experts"] - paired["nse_multiscale_fusion"]
        )
        paired["delta_expert_mainstream"] = (
            paired["nse_historical_band_experts"] - paired["nse_mainstream_lstm"]
        )
        seed_pairs.append(paired)

    all_pairs = pd.concat(seed_pairs, ignore_index=True)
    per_seed_rows = []
    for seed, frame in all_pairs.groupby("seed", sort=True):
        delta = frame["delta_expert_fusion"].to_numpy(dtype=np.float64)
        per_seed_rows.append({
            "seed": int(seed),
            "median_delta_expert_fusion": float(np.nanmedian(delta)),
            "win_fraction_expert_fusion": float(np.nanmean(delta > 0)),
            "median_delta_expert_mainstream": float(
                np.nanmedian(frame["delta_expert_mainstream"].to_numpy(dtype=np.float64))
            ),
            "n_basins": int(np.isfinite(delta).sum()),
        })
    per_seed = pd.DataFrame(per_seed_rows)
    paired_per_basin = (
        all_pairs.groupby("basin", as_index=False)
        .agg(
            delta_expert_fusion_mean=("delta_expert_fusion", "mean"),
            delta_expert_mainstream_mean=("delta_expert_mainstream", "mean"),
            seeds=("seed", "nunique"),
        )
        .sort_values("basin")
        .reset_index(drop=True)
    )

    expert_predictions = pd.concat(expert_prediction_frames, ignore_index=True)
    weight_columns = {
        "recent": "weight_recent",
        "medium": "weight_medium",
        "old": "weight_old",
    }
    if not set(weight_columns.values()).issubset(expert_predictions.columns):
        raise ValueError("expert prediction tables do not contain all three weight columns")
    mean_weights = {
        name: float(expert_predictions[column].mean())
        for name, column in weight_columns.items()
    }
    summary = evaluate_continuation(per_seed, paired_per_basin, mean_weights)
    summary.update({
        "missing_runs": [],
        "expected_run_count": len(_expected_runs()),
        "completed_run_count": len(_expected_runs()),
        "basin_count": int(len(paired_per_basin)),
        "seeds": list(SEEDS),
    })

    _atomic_frame(results_root / "per_seed.csv", per_seed)
    _atomic_frame(results_root / "paired_per_basin.csv", paired_per_basin)
    _atomic_text(results_root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-root", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(analyze_results(args.results_root), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
