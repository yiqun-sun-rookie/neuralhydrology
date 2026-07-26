"""Strict staged analysis for hierarchical rich historical context."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path

import numpy as np
import pandas as pd

from metrics import per_basin_nse
from train_v05 import validate_frozen_config_v05, validate_frozen_file_hash


EXPECTED_PARAMETER_COUNTS = {
    "classic_lstm_256": 297_217,
    "classic_lstm_320": 453_441,
    "late_concat": 308_401,
    "hierarchical_rich_history": 455_105,
}
VALIDATION_DATES = pd.date_range("2006-10-01", "2008-09-30", freq="D")
EXPECTED_BASIN_COUNT = 60
MIN_MEDIAN_EFFECT = 0.01
MIN_WIN_FRACTION = 0.55
BOOTSTRAP_SEED = 260726
BOOTSTRAP_RESAMPLES = 10_000
_REPO = Path(__file__).resolve().parents[2]


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _atomic_text(path: Path, content: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8")
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
    """Return a deterministic percentile interval for a paired median effect."""
    values = np.asarray(values, dtype=np.float64)
    values = values[np.isfinite(values)]
    if len(values) < 2:
        return float("nan"), float("nan")
    generator = np.random.default_rng(seed)
    sample_indices = generator.integers(0, len(values), size=(n_resamples, len(values)))
    medians = np.median(values[sample_indices], axis=1)
    return float(np.quantile(medians, 0.025)), float(np.quantile(medians, 0.975))


def validate_prediction_frame(
    predictions: pd.DataFrame,
    expected_basins: tuple[str, ...] | None = None,
    expected_dates: pd.DatetimeIndex = VALIDATION_DATES,
) -> pd.DataFrame:
    """Reject incomplete, duplicate, non-finite, or unexpected daily predictions."""
    required = {"basin", "date", "qobs", "qsim"}
    missing = required - set(predictions.columns)
    if missing:
        raise ValueError(f"prediction table is missing columns: {sorted(missing)}")
    frame = predictions.copy()
    frame["basin"] = frame["basin"].astype(str).str.zfill(8)
    frame["date"] = pd.to_datetime(frame["date"], errors="raise")
    if frame.duplicated(["basin", "date"]).any():
        raise ValueError("prediction table contains a duplicate basin-date key")
    if not np.isfinite(frame[["qobs", "qsim"]].to_numpy(dtype=np.float64)).all():
        raise ValueError("prediction table contains non-finite observed or simulated discharge")

    actual_basins = tuple(sorted(frame["basin"].unique()))
    if expected_basins is None:
        if len(actual_basins) != EXPECTED_BASIN_COUNT:
            raise ValueError(
                f"prediction basin count must be {EXPECTED_BASIN_COUNT}, got {len(actual_basins)}"
            )
        basin_ids = actual_basins
    else:
        basin_ids = tuple(sorted(str(basin).zfill(8) for basin in expected_basins))
        if set(actual_basins) != set(basin_ids):
            raise ValueError("prediction basin set does not match the expected basins")

    ordered = frame.sort_values(["basin", "date"]).reset_index(drop=True)
    expected_index = pd.MultiIndex.from_product(
        [basin_ids, pd.DatetimeIndex(expected_dates)],
        names=["basin", "date"],
    )
    actual_index = pd.MultiIndex.from_frame(ordered[["basin", "date"]])
    if not actual_index.equals(expected_index):
        raise ValueError("prediction basin-date keys are incomplete or unexpected")
    return ordered


def assert_matching_daily_targets(predictions_by_variant: dict[str, pd.DataFrame]) -> None:
    """Require identical keys and observations across every compared arm."""
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


def validated_predictions(run_dir: Path, variant: str, seed: int) -> pd.DataFrame:
    """Load one run after checking identity, access ledger, artifacts, and metrics."""
    manifest_path = run_dir / "manifest.json"
    predictions_path = run_dir / "predictions.csv"
    if not manifest_path.exists() or not predictions_path.exists():
        raise FileNotFoundError(f"missing manifest or predictions in {run_dir}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("status") != "complete":
        raise ValueError(f"run is not complete: {run_dir}")
    if manifest.get("variant") != variant or int(manifest.get("seed", -1)) != seed:
        raise ValueError(f"manifest identity mismatch: {run_dir}")
    if int(manifest.get("parameter_count", -1)) != EXPECTED_PARAMETER_COUNTS[variant]:
        raise ValueError(f"manifest parameter count mismatch: {run_dir}")
    if manifest.get("data_access", {}).get("raw_observed_discharge_reads") != 0:
        raise ValueError(f"manifest records a raw observed-discharge read: {run_dir}")

    artifact_names = ("config.json", "checkpoint.pt", "predictions.csv", "per_basin_metrics.csv")
    for name in artifact_names:
        path = run_dir / name
        expected_hash = manifest.get("artifacts", {}).get(name)
        if not path.exists() or not expected_hash:
            raise ValueError(f"manifest is missing artifact evidence for {name}: {run_dir}")
        if _sha256(path) != expected_hash:
            raise ValueError(f"artifact hash mismatch for {name}: {run_dir}")

    expected_rows = EXPECTED_BASIN_COUNT * len(VALIDATION_DATES)
    if int(manifest.get("n_validation_predictions", -1)) != expected_rows:
        raise ValueError(f"manifest validation row count is not {expected_rows}: {run_dir}")
    predictions = validate_prediction_frame(
        pd.read_csv(predictions_path, dtype={"basin": str})
    )
    saved_metrics = pd.read_csv(run_dir / "per_basin_metrics.csv", dtype={"basin": str})
    recomputed_metrics = per_basin_nse(predictions)
    try:
        pd.testing.assert_frame_equal(saved_metrics, recomputed_metrics, check_exact=True)
    except AssertionError as error:
        raise ValueError(f"saved per-basin metrics do not match predictions: {run_dir}") from error
    return predictions


def _renamed_metric(frame: pd.DataFrame, column: str) -> pd.DataFrame:
    return frame[["basin", "nse"]].rename(columns={"nse": column})


def _paired_frame(metrics: dict[str, pd.DataFrame]) -> pd.DataFrame:
    paired = _renamed_metric(metrics["classic_lstm_256"], "nse_classic_lstm_256")
    paired = paired.merge(
        _renamed_metric(metrics["classic_lstm_320"], "nse_control"),
        on="basin",
        how="inner",
    )
    paired = paired.merge(
        _renamed_metric(metrics["late_concat"], "nse_late_concat"),
        on="basin",
        how="inner",
    )
    return paired.merge(
        _renamed_metric(metrics["hierarchical_rich_history"], "nse_candidate"),
        on="basin",
        how="inner",
    )


def evaluate_stage1(paired: pd.DataFrame) -> dict:
    """Apply the four frozen one-seed screening criteria."""
    delta_exact = (paired["nse_candidate"] - paired["nse_classic_lstm_256"]).to_numpy(float)
    delta_control = (paired["nse_candidate"] - paired["nse_control"]).to_numpy(float)
    delta_late = (paired["nse_candidate"] - paired["nse_late_concat"]).to_numpy(float)
    median_exact = float(np.nanmedian(delta_exact))
    median_control = float(np.nanmedian(delta_control))
    median_late = float(np.nanmedian(delta_late))
    win_fraction = float(np.nanmean(delta_exact > 0))
    criteria = {
        "median_delta_exact_at_least_0_01": median_exact >= MIN_MEDIAN_EFFECT,
        "median_delta_capacity_above_zero": median_control > 0,
        "median_delta_late_concat_above_zero": median_late > 0,
        "win_fraction_exact_at_least_0_55": win_fraction >= MIN_WIN_FRACTION,
    }
    return {
        "passed": bool(all(criteria.values())),
        "criteria": {name: bool(value) for name, value in criteria.items()},
        "median_delta_exact": median_exact,
        "median_delta_capacity_control": median_control,
        "median_delta_late_concat": median_late,
        "win_fraction_exact": win_fraction,
        "n_basins": int(np.isfinite(delta_exact).sum()),
    }


def evaluate_multiseed(paired: pd.DataFrame) -> dict:
    """Apply the frozen multi-seed criteria to one candidate."""
    per_basin = paired.groupby("basin", as_index=False).agg(
        delta_exact=("delta_exact", "mean"),
        delta_control=("delta_control", "mean"),
        delta_late_concat=("delta_late_concat", "mean"),
        seeds=("seed", "nunique"),
    )
    median_exact = float(np.nanmedian(per_basin["delta_exact"]))
    median_control = float(np.nanmedian(per_basin["delta_control"]))
    median_late = float(np.nanmedian(per_basin["delta_late_concat"]))
    win_fraction = float(np.nanmean(per_basin["delta_exact"] > 0))
    positive_seeds = int((paired.groupby("seed")["delta_exact"].median() > 0).sum())
    interval = paired_bootstrap_interval(per_basin["delta_exact"].to_numpy(float))
    criteria = {
        "median_delta_exact_at_least_0_01": median_exact >= MIN_MEDIAN_EFFECT,
        "median_delta_capacity_above_zero": median_control > 0,
        "median_delta_late_concat_above_zero": median_late > 0,
        "at_least_two_positive_seeds": positive_seeds >= 2,
        "bootstrap_lower_above_zero": np.isfinite(interval[0]) and interval[0] > 0,
        "win_fraction_exact_at_least_0_55": win_fraction >= MIN_WIN_FRACTION,
    }
    return {
        "passed": bool(all(criteria.values())),
        "criteria": {name: bool(value) for name, value in criteria.items()},
        "median_delta_exact": median_exact,
        "median_delta_capacity_control": median_control,
        "median_delta_late_concat": median_late,
        "positive_seed_count": positive_seeds,
        "bootstrap_95_interval": [float(interval[0]), float(interval[1])],
        "win_fraction_exact": win_fraction,
        "n_basins": int(len(per_basin)),
    }


def conditional_run_names() -> list[str]:
    """Return only new runs needed after the one-seed candidate passes."""
    return [
        f"{variant}_s{seed}"
        for seed in (200, 300)
        for variant in ("classic_lstm_320", "hierarchical_rich_history")
    ]


def _load_metrics(root: Path, variants: tuple[str, ...], seed: int) -> dict[str, pd.DataFrame]:
    predictions = {
        variant: validated_predictions(root / f"{variant}_s{seed}", variant, seed)
        for variant in variants
    }
    assert_matching_daily_targets(predictions)
    return {variant: per_basin_nse(frame) for variant, frame in predictions.items()}


def _metric_rows(seed: int, metrics: dict[str, pd.DataFrame]) -> list[dict]:
    return [{
        "seed": seed,
        "variant": variant,
        "median_nse": float(np.nanmedian(frame["nse"].to_numpy(float))),
        "n_basins": int(frame["nse"].notna().sum()),
    } for variant, frame in metrics.items()]


def _annotate_pairs(paired: pd.DataFrame, seed: int) -> pd.DataFrame:
    paired = paired.copy()
    paired["seed"] = seed
    paired["candidate"] = "hierarchical_rich_history"
    paired["control"] = "classic_lstm_320"
    paired["delta_exact"] = paired["nse_candidate"] - paired["nse_classic_lstm_256"]
    paired["delta_control"] = paired["nse_candidate"] - paired["nse_control"]
    paired["delta_late_concat"] = paired["nse_candidate"] - paired["nse_late_concat"]
    return paired


def _write_tables(results_root: Path, per_seed_rows: list[dict], pairs: list[pd.DataFrame]) -> None:
    _atomic_frame(results_root / "per_seed.csv", pd.DataFrame(per_seed_rows))
    _atomic_frame(results_root / "paired_per_basin.csv", pd.concat(pairs, ignore_index=True))


def analyze_results_v05(
    results_root: str | Path,
    reference_v03_root: str | Path,
    reference_v04_root: str | Path,
) -> dict:
    """Recompute version 05 metrics and apply staged frozen gates."""
    results_root = Path(results_root)
    reference_v03_root = Path(reference_v03_root)
    reference_v04_root = Path(reference_v04_root)
    results_root.mkdir(parents=True, exist_ok=True)

    base_locations = {
        "v03/classic_lstm_256_s100": reference_v03_root / "classic_lstm_256_s100",
        "v03/late_concat_s100": reference_v03_root / "late_concat_s100",
        "results/classic_lstm_320_s100": results_root / "classic_lstm_320_s100",
        "results/hierarchical_rich_history_s100": results_root / "hierarchical_rich_history_s100",
    }
    missing = [
        name for name, run_dir in base_locations.items()
        if not (run_dir / "manifest.json").exists()
    ]
    if missing:
        summary = {"status": "incomplete_base_runs", "missing_runs": missing}
        _atomic_text(results_root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
        return summary

    reference_metrics = _load_metrics(
        reference_v03_root,
        ("classic_lstm_256", "late_concat"),
        100,
    )
    new_metrics = _load_metrics(
        results_root,
        ("classic_lstm_320", "hierarchical_rich_history"),
        100,
    )
    seed100_metrics = {**reference_metrics, **new_metrics}
    seed100_pairs = _annotate_pairs(_paired_frame(seed100_metrics), 100)
    stage1 = evaluate_stage1(seed100_pairs)
    per_seed_rows = _metric_rows(100, seed100_metrics)
    pairs = [seed100_pairs]

    if not stage1["passed"]:
        _write_tables(results_root, per_seed_rows, pairs)
        summary = {
            "status": "complete_stage1_no_go",
            "missing_runs": [],
            "stage1": stage1,
            "required_conditional_runs": [],
            "multiseed": {},
            "go_models": [],
        }
        _atomic_text(results_root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
        return summary

    required = conditional_run_names()
    missing_conditional = [
        name for name in required
        if not (results_root / name / "manifest.json").exists()
    ]
    if missing_conditional:
        _write_tables(results_root, per_seed_rows, pairs)
        summary = {
            "status": "awaiting_conditional_runs",
            "missing_runs": missing_conditional,
            "stage1": stage1,
            "required_conditional_runs": required,
            "multiseed": {},
            "go_models": [],
        }
        _atomic_text(results_root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
        return summary

    for seed in (200, 300):
        old_metrics = _load_metrics(
            reference_v04_root,
            ("classic_lstm_256", "late_concat"),
            seed,
        )
        conditional_metrics = _load_metrics(
            results_root,
            ("classic_lstm_320", "hierarchical_rich_history"),
            seed,
        )
        metrics = {**old_metrics, **conditional_metrics}
        per_seed_rows.extend(_metric_rows(seed, metrics))
        pairs.append(_annotate_pairs(_paired_frame(metrics), seed))

    all_pairs = pd.concat(pairs, ignore_index=True)
    multiseed = evaluate_multiseed(all_pairs)
    _write_tables(results_root, per_seed_rows, pairs)
    summary = {
        "status": "complete_multiseed",
        "missing_runs": [],
        "stage1": stage1,
        "required_conditional_runs": required,
        "multiseed": multiseed,
        "go_models": ["hierarchical_rich_history"] if multiseed["passed"] else [],
    }
    _atomic_text(results_root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    validate_frozen_config_v05(config)
    reference_v03_root = _REPO / config["reference_v03_results_root"]
    reference_v04_root = _REPO / config["reference_v04_results_root"]
    validate_frozen_file_hash(
        reference_v03_root / "summary.json",
        config["reference_v03_summary_sha256"],
        "version 03 summary",
    )
    validate_frozen_file_hash(
        reference_v04_root / "summary.json",
        config["reference_v04_summary_sha256"],
        "version 04 summary",
    )
    print(json.dumps(
        analyze_results_v05(
            _REPO / config["results_root"],
            reference_v03_root,
            reference_v04_root,
        ),
        indent=2,
        sort_keys=True,
    ))


if __name__ == "__main__":
    main()
