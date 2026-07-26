"""Strict staged analysis for the classic LSTM historical-context pilot."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Iterable

import numpy as np
import pandas as pd

from metrics import per_basin_nse
from models_v03 import VARIANTS_V03


EXPECTED_PARAMETER_COUNTS = {
    "classic_lstm_256": 297_217,
    "classic_lstm_261": 308_242,
    "classic_lstm_266": 319_467,
    "late_concat": 308_401,
    "initial_memory": 320_897,
}
CANDIDATE_CONTROLS = {
    "late_concat": "classic_lstm_261",
    "initial_memory": "classic_lstm_266",
}
VALIDATION_DATES = pd.date_range("2006-10-01", "2008-09-30", freq="D")
EXPECTED_BASIN_COUNT = 60
MIN_MEDIAN_EFFECT = 0.01
MIN_WIN_FRACTION = 0.55
BOOTSTRAP_SEED = 260726
BOOTSTRAP_RESAMPLES = 10_000


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
    """Load one run only after verifying identity, size, access ledger, and hashes."""
    manifest_path = run_dir / "manifest.json"
    predictions_path = run_dir / "predictions.csv"
    if not manifest_path.exists() or not predictions_path.exists():
        raise FileNotFoundError(f"missing manifest or predictions in {run_dir}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("status") != "complete":
        raise ValueError(f"run is not complete: {run_dir}")
    if manifest.get("variant") != variant or int(manifest.get("seed", -1)) != seed:
        raise ValueError(f"manifest identity mismatch: {run_dir}")
    expected_parameters = EXPECTED_PARAMETER_COUNTS[variant]
    if int(manifest.get("parameter_count", -1)) != expected_parameters:
        raise ValueError(f"manifest parameter count mismatch: {run_dir}")
    if int(manifest.get("data_access", {}).get("raw_observed_discharge_reads", -1)) != 0:
        raise ValueError(f"raw observed-discharge access is not zero: {run_dir}")

    required_artifacts = {
        "config.json",
        "checkpoint.pt",
        "predictions.csv",
        "per_basin_metrics.csv",
    }
    artifacts = manifest.get("artifacts", {})
    if not required_artifacts.issubset(artifacts):
        raise ValueError(f"manifest artifact list is incomplete: {run_dir}")
    for name, expected_hash in artifacts.items():
        artifact_path = run_dir / name
        if not artifact_path.exists() or _sha256(artifact_path) != expected_hash:
            raise ValueError(f"artifact hash mismatch for {name}: {run_dir}")

    expected_rows = EXPECTED_BASIN_COUNT * len(VALIDATION_DATES)
    if int(manifest.get("n_validation_predictions", -1)) != expected_rows:
        raise ValueError(f"manifest validation row count is not {expected_rows}: {run_dir}")
    return validate_prediction_frame(
        pd.read_csv(predictions_path, dtype={"basin": str})
    )


def _generic_candidate_frame(
    metrics: dict[str, pd.DataFrame],
    candidate: str,
    control: str,
) -> pd.DataFrame:
    renamed = {}
    for variant in ("classic_lstm_256", control, candidate):
        renamed[variant] = metrics[variant][["basin", "nse"]].rename(
            columns={"nse": {
                "classic_lstm_256": "nse_classic_lstm_256",
                control: "nse_control",
                candidate: "nse_candidate",
            }[variant]}
        )
    paired = renamed["classic_lstm_256"]
    paired = paired.merge(renamed[control], on="basin", how="inner")
    paired = paired.merge(renamed[candidate], on="basin", how="inner")
    return paired


def evaluate_stage1_candidate(
    paired: pd.DataFrame,
    candidate: str,
    control: str,
) -> dict:
    """Apply the frozen one-seed screen to one candidate."""
    delta_exact = (
        paired["nse_candidate"] - paired["nse_classic_lstm_256"]
    ).to_numpy(dtype=np.float64)
    delta_control = (
        paired["nse_candidate"] - paired["nse_control"]
    ).to_numpy(dtype=np.float64)
    median_exact = float(np.nanmedian(delta_exact))
    median_control = float(np.nanmedian(delta_control))
    win_fraction = float(np.nanmean(delta_exact > 0))
    criteria = {
        "median_delta_exact_at_least_0_01": median_exact >= MIN_MEDIAN_EFFECT,
        "median_delta_capacity_above_zero": median_control > 0,
        "win_fraction_exact_at_least_0_55": win_fraction >= MIN_WIN_FRACTION,
    }
    return {
        "candidate": candidate,
        "control": control,
        "passed": bool(all(criteria.values())),
        "criteria": {name: bool(value) for name, value in criteria.items()},
        "median_delta_exact": median_exact,
        "median_delta_capacity_control": median_control,
        "win_fraction_exact": win_fraction,
        "n_basins": int(np.isfinite(delta_exact).sum()),
    }


def conditional_run_names(passing_candidates: Iterable[str]) -> list[str]:
    """Return the exact deduplicated seed-200/300 run matrix."""
    candidates = sorted(set(passing_candidates))
    controls = sorted({CANDIDATE_CONTROLS[candidate] for candidate in candidates})
    names = []
    for seed in (200, 300):
        variants = ["classic_lstm_256", *controls, *candidates]
        names.extend(f"{variant}_s{seed}" for variant in variants)
    return names


def evaluate_multiseed_candidate(paired: pd.DataFrame) -> dict:
    """Apply all five frozen continuation rules to one candidate."""
    per_basin = (
        paired.groupby("basin", as_index=False)
        .agg(
            delta_exact=("delta_exact", "mean"),
            delta_control=("delta_control", "mean"),
            seeds=("seed", "nunique"),
        )
    )
    median_exact = float(np.nanmedian(per_basin["delta_exact"]))
    median_control = float(np.nanmedian(per_basin["delta_control"]))
    win_fraction = float(np.nanmean(per_basin["delta_exact"] > 0))
    positive_seeds = int(
        (
            paired.groupby("seed")["delta_exact"].median() > 0
        ).sum()
    )
    bootstrap_low, bootstrap_high = paired_bootstrap_interval(
        per_basin["delta_exact"].to_numpy(dtype=np.float64)
    )
    criteria = {
        "median_delta_exact_at_least_0_01": median_exact >= MIN_MEDIAN_EFFECT,
        "median_delta_capacity_above_zero": median_control > 0,
        "at_least_two_positive_seeds": positive_seeds >= 2,
        "bootstrap_lower_above_zero": np.isfinite(bootstrap_low) and bootstrap_low > 0,
        "win_fraction_exact_at_least_0_55": win_fraction >= MIN_WIN_FRACTION,
    }
    return {
        "passed": bool(all(criteria.values())),
        "criteria": {name: bool(value) for name, value in criteria.items()},
        "median_delta_exact": median_exact,
        "median_delta_capacity_control": median_control,
        "positive_seed_count": positive_seeds,
        "bootstrap_95_interval": [bootstrap_low, bootstrap_high],
        "win_fraction_exact": win_fraction,
        "n_basins": int(len(per_basin)),
    }


def _load_seed_metrics(
    results_root: Path,
    variants: Iterable[str],
    seed: int,
) -> tuple[dict[str, pd.DataFrame], dict[str, pd.DataFrame]]:
    predictions = {
        variant: validated_predictions(
            results_root / f"{variant}_s{seed}",
            variant,
            seed,
        )
        for variant in variants
    }
    assert_matching_daily_targets(predictions)
    metrics = {
        variant: per_basin_nse(frame)
        for variant, frame in predictions.items()
    }
    return predictions, metrics


def analyze_results_v03(results_root: str | Path) -> dict:
    """Recompute metrics and apply the frozen staged decision rules."""
    results_root = Path(results_root)
    results_root.mkdir(parents=True, exist_ok=True)
    stage1_runs = [f"{variant}_s100" for variant in VARIANTS_V03]
    missing_stage1 = [
        name
        for name in stage1_runs
        if not (results_root / name / "manifest.json").exists()
    ]
    if missing_stage1:
        summary = {
            "status": "incomplete_stage1",
            "missing_runs": missing_stage1,
            "required_stage1_runs": stage1_runs,
        }
        _atomic_text(results_root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
        return summary

    _predictions, metrics = _load_seed_metrics(results_root, VARIANTS_V03, seed=100)
    per_seed_rows = [{
        "seed": 100,
        "variant": variant,
        "median_nse": float(np.nanmedian(frame["nse"].to_numpy(dtype=np.float64))),
        "n_basins": int(frame["nse"].notna().sum()),
    } for variant, frame in metrics.items()]
    paired_rows = []
    stage1 = {}
    for candidate, control in CANDIDATE_CONTROLS.items():
        paired = _generic_candidate_frame(metrics, candidate, control)
        decision = evaluate_stage1_candidate(paired, candidate, control)
        stage1[candidate] = decision
        paired["candidate"] = candidate
        paired["control"] = control
        paired["seed"] = 100
        paired["delta_exact"] = paired["nse_candidate"] - paired["nse_classic_lstm_256"]
        paired["delta_control"] = paired["nse_candidate"] - paired["nse_control"]
        paired_rows.append(paired)

    passing_candidates = sorted(
        candidate
        for candidate, decision in stage1.items()
        if decision["passed"]
    )
    paired_all = pd.concat(paired_rows, ignore_index=True)
    _atomic_frame(results_root / "per_seed.csv", pd.DataFrame(per_seed_rows))
    _atomic_frame(results_root / "paired_per_basin.csv", paired_all)
    if not passing_candidates:
        summary = {
            "status": "no_go_stage1",
            "missing_runs": [],
            "stage1": stage1,
            "passing_candidates": [],
            "required_conditional_runs": [],
        }
        _atomic_text(results_root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
        return summary

    required_conditional = conditional_run_names(passing_candidates)
    missing_conditional = [
        name
        for name in required_conditional
        if not (results_root / name / "manifest.json").exists()
    ]
    if missing_conditional:
        summary = {
            "status": "awaiting_conditional_runs",
            "missing_runs": missing_conditional,
            "stage1": stage1,
            "passing_candidates": passing_candidates,
            "required_conditional_runs": required_conditional,
        }
        _atomic_text(results_root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
        return summary

    all_pair_parts = [paired_all.loc[paired_all["candidate"].isin(passing_candidates)]]
    for seed in (200, 300):
        variants = {
            "classic_lstm_256",
            *passing_candidates,
            *(CANDIDATE_CONTROLS[candidate] for candidate in passing_candidates),
        }
        _predictions, seed_metrics = _load_seed_metrics(results_root, sorted(variants), seed)
        for variant, frame in seed_metrics.items():
            per_seed_rows.append({
                "seed": seed,
                "variant": variant,
                "median_nse": float(np.nanmedian(frame["nse"].to_numpy(dtype=np.float64))),
                "n_basins": int(frame["nse"].notna().sum()),
            })
        for candidate in passing_candidates:
            control = CANDIDATE_CONTROLS[candidate]
            paired = _generic_candidate_frame(seed_metrics, candidate, control)
            paired["candidate"] = candidate
            paired["control"] = control
            paired["seed"] = seed
            paired["delta_exact"] = paired["nse_candidate"] - paired["nse_classic_lstm_256"]
            paired["delta_control"] = paired["nse_candidate"] - paired["nse_control"]
            all_pair_parts.append(paired)

    all_pairs = pd.concat(all_pair_parts, ignore_index=True)
    decisions = {
        candidate: evaluate_multiseed_candidate(
            all_pairs.loc[all_pairs["candidate"] == candidate]
        )
        for candidate in passing_candidates
    }
    _atomic_frame(results_root / "per_seed.csv", pd.DataFrame(per_seed_rows))
    _atomic_frame(results_root / "paired_per_basin.csv", all_pairs)
    summary = {
        "status": "go_internal" if any(item["passed"] for item in decisions.values()) else "no_go_multiseed",
        "missing_runs": [],
        "stage1": stage1,
        "passing_candidates": passing_candidates,
        "required_conditional_runs": required_conditional,
        "multiseed": decisions,
    }
    _atomic_text(results_root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-root", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(analyze_results_v03(args.results_root), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
