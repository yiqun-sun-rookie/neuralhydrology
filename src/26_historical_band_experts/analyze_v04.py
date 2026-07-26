"""Strict staged analysis for persistent historical-context experiments."""
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
from train_v04 import validate_frozen_config_v04, validate_frozen_file_hash


EXPECTED_PARAMETER_COUNTS = {
    "classic_lstm_256": 297_217,
    "classic_lstm_261": 308_242,
    "classic_lstm_265": 317_206,
    "classic_lstm_270": 328_591,
    "late_concat": 308_401,
    "persistent_context": 316_937,
    "recent_conditioned_residual": 327_617,
}
NEW_CANDIDATE_CONTROLS = {
    "persistent_context": "classic_lstm_265",
    "recent_conditioned_residual": "classic_lstm_270",
}
REFERENCE_SEED100_VARIANTS = (
    "classic_lstm_256",
    "classic_lstm_261",
    "late_concat",
)
CONFIRMATION_VARIANTS = REFERENCE_SEED100_VARIANTS
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
    if manifest.get("data_access", {}).get("raw_observed_discharge_reads") != 0:
        raise ValueError(f"manifest records a raw observed-discharge read: {run_dir}")

    for name in ("config.json", "checkpoint.pt", "predictions.csv", "per_basin_metrics.csv"):
        artifact_path = run_dir / name
        expected_hash = manifest.get("artifacts", {}).get(name)
        if not artifact_path.exists() or not expected_hash:
            raise ValueError(f"manifest is missing artifact evidence for {name}: {run_dir}")
        if _sha256(artifact_path) != expected_hash:
            raise ValueError(f"artifact hash mismatch for {name}: {run_dir}")

    expected_rows = EXPECTED_BASIN_COUNT * len(VALIDATION_DATES)
    if int(manifest.get("n_validation_predictions", -1)) != expected_rows:
        raise ValueError(f"manifest validation row count is not {expected_rows}: {run_dir}")
    return validate_prediction_frame(
        pd.read_csv(predictions_path, dtype={"basin": str})
    )


def _renamed_metric(frame: pd.DataFrame, column: str) -> pd.DataFrame:
    return frame[["basin", "nse"]].rename(columns={"nse": column})


def _late_concat_frame(metrics: dict[str, pd.DataFrame]) -> pd.DataFrame:
    paired = _renamed_metric(metrics["classic_lstm_256"], "nse_classic_lstm_256")
    paired = paired.merge(
        _renamed_metric(metrics["classic_lstm_261"], "nse_control"),
        on="basin",
        how="inner",
    )
    return paired.merge(
        _renamed_metric(metrics["late_concat"], "nse_candidate"),
        on="basin",
        how="inner",
    )


def _new_candidate_frame(
    metrics: dict[str, pd.DataFrame],
    candidate: str,
    control: str,
) -> pd.DataFrame:
    paired = _renamed_metric(metrics["classic_lstm_256"], "nse_classic_lstm_256")
    paired = paired.merge(
        _renamed_metric(metrics[control], "nse_control"),
        on="basin",
        how="inner",
    )
    paired = paired.merge(
        _renamed_metric(metrics["late_concat"], "nse_late_concat"),
        on="basin",
        how="inner",
    )
    return paired.merge(
        _renamed_metric(metrics[candidate], "nse_candidate"),
        on="basin",
        how="inner",
    )


def evaluate_new_stage1_candidate(
    paired: pd.DataFrame,
    candidate: str,
    control: str,
) -> dict:
    """Apply the frozen one-seed screen to a new historical mechanism."""
    delta_exact = (
        paired["nse_candidate"] - paired["nse_classic_lstm_256"]
    ).to_numpy(dtype=np.float64)
    delta_control = (
        paired["nse_candidate"] - paired["nse_control"]
    ).to_numpy(dtype=np.float64)
    delta_late = (
        paired["nse_candidate"] - paired["nse_late_concat"]
    ).to_numpy(dtype=np.float64)
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
        "candidate": candidate,
        "control": control,
        "passed": bool(all(criteria.values())),
        "criteria": {name: bool(value) for name, value in criteria.items()},
        "median_delta_exact": median_exact,
        "median_delta_capacity_control": median_control,
        "median_delta_late_concat": median_late,
        "win_fraction_exact": win_fraction,
        "n_basins": int(np.isfinite(delta_exact).sum()),
    }


def conditional_new_run_names(passing_candidates: Iterable[str]) -> list[str]:
    """Return only new-candidate and control runs not already in confirmation."""
    candidates = sorted(set(passing_candidates))
    controls = sorted({NEW_CANDIDATE_CONTROLS[candidate] for candidate in candidates})
    names = []
    for seed in (200, 300):
        names.extend(f"{variant}_s{seed}" for variant in (*controls, *candidates))
    return names


def _multiseed_common(paired: pd.DataFrame) -> tuple[pd.DataFrame, dict]:
    aggregations = {
        "delta_exact": ("delta_exact", "mean"),
        "delta_control": ("delta_control", "mean"),
        "seeds": ("seed", "nunique"),
    }
    if "delta_late_concat" in paired:
        aggregations["delta_late_concat"] = ("delta_late_concat", "mean")
    per_basin = paired.groupby("basin", as_index=False).agg(**aggregations)
    median_exact = float(np.nanmedian(per_basin["delta_exact"]))
    median_control = float(np.nanmedian(per_basin["delta_control"]))
    win_fraction = float(np.nanmean(per_basin["delta_exact"] > 0))
    positive_seeds = int((paired.groupby("seed")["delta_exact"].median() > 0).sum())
    bootstrap_low, bootstrap_high = paired_bootstrap_interval(
        per_basin["delta_exact"].to_numpy(dtype=np.float64)
    )
    common = {
        "median_delta_exact": median_exact,
        "median_delta_capacity_control": median_control,
        "positive_seed_count": positive_seeds,
        "bootstrap_95_interval": [bootstrap_low, bootstrap_high],
        "win_fraction_exact": win_fraction,
        "n_basins": int(len(per_basin)),
    }
    return per_basin, common


def evaluate_late_concat_multiseed(paired: pd.DataFrame) -> dict:
    """Apply the original five frozen criteria to late concatenation."""
    _per_basin, result = _multiseed_common(paired)
    criteria = {
        "median_delta_exact_at_least_0_01": result["median_delta_exact"] >= MIN_MEDIAN_EFFECT,
        "median_delta_capacity_above_zero": result["median_delta_capacity_control"] > 0,
        "at_least_two_positive_seeds": result["positive_seed_count"] >= 2,
        "bootstrap_lower_above_zero": (
            np.isfinite(result["bootstrap_95_interval"][0])
            and result["bootstrap_95_interval"][0] > 0
        ),
        "win_fraction_exact_at_least_0_55": result["win_fraction_exact"] >= MIN_WIN_FRACTION,
    }
    result["criteria"] = {name: bool(value) for name, value in criteria.items()}
    result["passed"] = bool(all(criteria.values()))
    return result


def evaluate_new_multiseed_candidate(paired: pd.DataFrame) -> dict:
    """Apply six frozen criteria, including improvement over late concatenation."""
    per_basin, result = _multiseed_common(paired)
    median_late = float(np.nanmedian(per_basin["delta_late_concat"]))
    criteria = {
        "median_delta_exact_at_least_0_01": result["median_delta_exact"] >= MIN_MEDIAN_EFFECT,
        "median_delta_capacity_above_zero": result["median_delta_capacity_control"] > 0,
        "median_delta_late_concat_above_zero": median_late > 0,
        "at_least_two_positive_seeds": result["positive_seed_count"] >= 2,
        "bootstrap_lower_above_zero": (
            np.isfinite(result["bootstrap_95_interval"][0])
            and result["bootstrap_95_interval"][0] > 0
        ),
        "win_fraction_exact_at_least_0_55": result["win_fraction_exact"] >= MIN_WIN_FRACTION,
    }
    result["median_delta_late_concat"] = median_late
    result["criteria"] = {name: bool(value) for name, value in criteria.items()}
    result["passed"] = bool(all(criteria.values()))
    return result


def _load_seed_metrics(
    root: Path,
    variants: Iterable[str],
    seed: int,
) -> tuple[dict[str, pd.DataFrame], dict[str, pd.DataFrame]]:
    predictions = {
        variant: validated_predictions(root / f"{variant}_s{seed}", variant, seed)
        for variant in variants
    }
    assert_matching_daily_targets(predictions)
    metrics = {variant: per_basin_nse(frame) for variant, frame in predictions.items()}
    return predictions, metrics


def _metric_row(seed: int, variant: str, metrics: pd.DataFrame) -> dict:
    return {
        "seed": seed,
        "variant": variant,
        "median_nse": float(np.nanmedian(metrics["nse"].to_numpy(dtype=np.float64))),
        "n_basins": int(metrics["nse"].notna().sum()),
    }


def _write_analysis_tables(
    results_root: Path,
    per_seed_rows: list[dict],
    paired_rows: list[pd.DataFrame],
) -> None:
    _atomic_frame(results_root / "per_seed.csv", pd.DataFrame(per_seed_rows))
    _atomic_frame(
        results_root / "paired_per_basin.csv",
        pd.concat(paired_rows, ignore_index=True),
    )


def analyze_results_v04(
    results_root: str | Path,
    reference_root: str | Path,
) -> dict:
    """Recompute all scores and apply the frozen staged version 04 rules."""
    results_root = Path(results_root)
    reference_root = Path(reference_root)
    results_root.mkdir(parents=True, exist_ok=True)

    reference_names = [f"{variant}_s100" for variant in REFERENCE_SEED100_VARIANTS]
    result_names = [
        *(f"{variant}_s{seed}" for seed in (200, 300) for variant in CONFIRMATION_VARIANTS),
        "classic_lstm_265_s100",
        "persistent_context_s100",
        "classic_lstm_270_s100",
        "recent_conditioned_residual_s100",
    ]
    missing = [
        f"reference/{name}"
        for name in reference_names
        if not (reference_root / name / "manifest.json").exists()
    ]
    missing.extend(
        f"results/{name}"
        for name in result_names
        if not (results_root / name / "manifest.json").exists()
    )
    if missing:
        summary = {
            "status": "incomplete_base_runs",
            "missing_runs": missing,
            "required_reference_runs": reference_names,
            "required_result_runs": result_names,
        }
        _atomic_text(results_root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
        return summary

    _reference_predictions, reference_metrics = _load_seed_metrics(
        reference_root,
        REFERENCE_SEED100_VARIANTS,
        100,
    )
    confirmation_metrics = {100: reference_metrics}
    per_seed_rows = [
        _metric_row(100, variant, reference_metrics[variant])
        for variant in REFERENCE_SEED100_VARIANTS
    ]
    paired_rows = []
    late_pairs = []

    for seed in (100, 200, 300):
        if seed == 100:
            metrics = reference_metrics
        else:
            _predictions, metrics = _load_seed_metrics(
                results_root,
                CONFIRMATION_VARIANTS,
                seed,
            )
            confirmation_metrics[seed] = metrics
            per_seed_rows.extend(
                _metric_row(seed, variant, metrics[variant])
                for variant in CONFIRMATION_VARIANTS
            )
        paired = _late_concat_frame(metrics)
        paired["candidate"] = "late_concat"
        paired["control"] = "classic_lstm_261"
        paired["seed"] = seed
        paired["delta_exact"] = paired["nse_candidate"] - paired["nse_classic_lstm_256"]
        paired["delta_control"] = paired["nse_candidate"] - paired["nse_control"]
        paired["delta_late_concat"] = 0.0
        late_pairs.append(paired)
        paired_rows.append(paired)

    late_concat_confirmation = evaluate_late_concat_multiseed(
        pd.concat(late_pairs, ignore_index=True)
    )

    new_variants = (
        "classic_lstm_265",
        "persistent_context",
        "classic_lstm_270",
        "recent_conditioned_residual",
    )
    _new_predictions, new_metrics = _load_seed_metrics(results_root, new_variants, 100)
    combined_seed100 = {
        "classic_lstm_256": reference_metrics["classic_lstm_256"],
        "late_concat": reference_metrics["late_concat"],
        **new_metrics,
    }
    per_seed_rows.extend(
        _metric_row(100, variant, new_metrics[variant])
        for variant in new_variants
    )
    stage1 = {}
    new_seed100_pairs = {}
    for candidate, control in NEW_CANDIDATE_CONTROLS.items():
        paired = _new_candidate_frame(combined_seed100, candidate, control)
        stage1[candidate] = evaluate_new_stage1_candidate(paired, candidate, control)
        paired["candidate"] = candidate
        paired["control"] = control
        paired["seed"] = 100
        paired["delta_exact"] = paired["nse_candidate"] - paired["nse_classic_lstm_256"]
        paired["delta_control"] = paired["nse_candidate"] - paired["nse_control"]
        paired["delta_late_concat"] = paired["nse_candidate"] - paired["nse_late_concat"]
        new_seed100_pairs[candidate] = paired
        paired_rows.append(paired)

    passing = sorted(candidate for candidate, decision in stage1.items() if decision["passed"])
    required_conditional = conditional_new_run_names(passing)
    missing_conditional = [
        name
        for name in required_conditional
        if not (results_root / name / "manifest.json").exists()
    ]
    if missing_conditional:
        _write_analysis_tables(results_root, per_seed_rows, paired_rows)
        summary = {
            "status": "awaiting_conditional_runs",
            "missing_runs": missing_conditional,
            "late_concat_confirmation": late_concat_confirmation,
            "stage1": stage1,
            "passing_new_candidates": passing,
            "required_conditional_runs": required_conditional,
            "multiseed_new": {},
        }
        _atomic_text(results_root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
        return summary

    if not passing:
        _write_analysis_tables(results_root, per_seed_rows, paired_rows)
        go_models = ["late_concat"] if late_concat_confirmation["passed"] else []
        summary = {
            "status": "complete_no_new_candidate",
            "missing_runs": [],
            "late_concat_confirmation": late_concat_confirmation,
            "stage1": stage1,
            "passing_new_candidates": [],
            "required_conditional_runs": [],
            "multiseed_new": {},
            "go_models": go_models,
        }
        _atomic_text(results_root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
        return summary

    all_new_pairs = {candidate: [new_seed100_pairs[candidate]] for candidate in passing}
    for seed in (200, 300):
        conditional_variants = sorted({
            *(NEW_CANDIDATE_CONTROLS[candidate] for candidate in passing),
            *passing,
        })
        _predictions, conditional_metrics = _load_seed_metrics(
            results_root,
            conditional_variants,
            seed,
        )
        per_seed_rows.extend(
            _metric_row(seed, variant, conditional_metrics[variant])
            for variant in conditional_variants
        )
        combined = {
            "classic_lstm_256": confirmation_metrics[seed]["classic_lstm_256"],
            "late_concat": confirmation_metrics[seed]["late_concat"],
            **conditional_metrics,
        }
        for candidate in passing:
            control = NEW_CANDIDATE_CONTROLS[candidate]
            paired = _new_candidate_frame(combined, candidate, control)
            paired["candidate"] = candidate
            paired["control"] = control
            paired["seed"] = seed
            paired["delta_exact"] = paired["nse_candidate"] - paired["nse_classic_lstm_256"]
            paired["delta_control"] = paired["nse_candidate"] - paired["nse_control"]
            paired["delta_late_concat"] = paired["nse_candidate"] - paired["nse_late_concat"]
            all_new_pairs[candidate].append(paired)
            paired_rows.append(paired)

    multiseed_new = {
        candidate: evaluate_new_multiseed_candidate(
            pd.concat(all_new_pairs[candidate], ignore_index=True)
        )
        for candidate in passing
    }
    go_models = []
    if late_concat_confirmation["passed"]:
        go_models.append("late_concat")
    go_models.extend(
        candidate
        for candidate, decision in multiseed_new.items()
        if decision["passed"]
    )
    _write_analysis_tables(results_root, per_seed_rows, paired_rows)
    summary = {
        "status": "complete_multiseed",
        "missing_runs": [],
        "late_concat_confirmation": late_concat_confirmation,
        "stage1": stage1,
        "passing_new_candidates": passing,
        "required_conditional_runs": required_conditional,
        "multiseed_new": multiseed_new,
        "go_models": go_models,
    }
    _atomic_text(results_root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    validate_frozen_config_v04(config)
    reference_root = _REPO / config["reference_results_root"]
    validate_frozen_file_hash(
        reference_root / "summary.json",
        config["reference_summary_sha256"],
        "version 03 summary",
    )
    results_root = _REPO / config["results_root"]
    print(
        json.dumps(
            analyze_results_v04(results_root, reference_root),
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
