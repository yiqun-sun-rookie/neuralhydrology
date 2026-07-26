from pathlib import Path
import copy
import hashlib
import json
import sys

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import analyze
from analyze import (
    analyze_results,
    evaluate_continuation,
    paired_bootstrap_interval,
)


def _passing_inputs():
    per_seed = pd.DataFrame(
        {
            "seed": [100, 200, 300],
            "median_delta_expert_fusion": [0.03, 0.02, 0.025],
            "win_fraction_expert_fusion": [0.70, 0.60, 0.65],
        }
    )
    paired = pd.DataFrame(
        {
            "basin": [f"{index:08d}" for index in range(20)],
            "delta_expert_fusion_mean": np.linspace(0.015, 0.04, 20),
            "delta_expert_mainstream_mean": np.linspace(0.001, 0.02, 20),
        }
    )
    weights = {"recent": 0.4, "medium": 0.35, "old": 0.25}
    return per_seed, paired, weights


def test_frozen_continuation_gate_passes_only_when_all_criteria_pass():
    per_seed, paired, weights = _passing_inputs()

    summary = evaluate_continuation(per_seed, paired, weights)

    assert summary["verdict"] == "GO"
    assert all(summary["criteria"].values())


@pytest.mark.parametrize(
    "criterion",
    [
        "median_effect",
        "basin_win_fraction",
        "two_seed_joint_consistency",
        "bootstrap_lower_above_zero",
        "not_worse_than_mainstream",
        "no_weight_collapse",
    ],
)
def test_each_failed_frozen_criterion_forces_no_go(criterion):
    per_seed, paired, weights = _passing_inputs()
    per_seed = per_seed.copy()
    paired = paired.copy()
    weights = copy.deepcopy(weights)
    if criterion == "median_effect":
        per_seed["median_delta_expert_fusion"] = [0.0, 0.0, 0.02]
    elif criterion == "basin_win_fraction":
        per_seed["win_fraction_expert_fusion"] = [0.2, 0.2, 0.8]
    elif criterion == "two_seed_joint_consistency":
        per_seed["median_delta_expert_fusion"] = [0.02, 0.0, 0.0]
        per_seed["win_fraction_expert_fusion"] = [0.8, 0.8, 0.2]
    elif criterion == "bootstrap_lower_above_zero":
        paired["delta_expert_fusion_mean"] = np.linspace(-0.05, 0.05, len(paired))
    elif criterion == "not_worse_than_mainstream":
        paired["delta_expert_mainstream_mean"] = -0.01
    elif criterion == "no_weight_collapse":
        weights = {"recent": 0.96, "medium": 0.02, "old": 0.02}

    summary = evaluate_continuation(per_seed, paired, weights)

    assert summary["verdict"] == "NO_GO"
    assert summary["criteria"][criterion] is False


def test_paired_bootstrap_is_deterministic():
    values = np.linspace(-0.01, 0.04, 30)

    first = paired_bootstrap_interval(values)
    second = paired_bootstrap_interval(values)

    assert first == second
    assert first[0] < first[1]


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write_run(root: Path, variant: str, seed: int, qsim_offset: float):
    run_dir = root / f"{variant}_s{seed}"
    run_dir.mkdir(parents=True)
    dates = pd.date_range("2006-10-01", "2008-09-30", freq="D")
    rows = []
    for basin_index in range(60):
        basin = f"{basin_index + 1:08d}"
        for day, date in enumerate(dates):
            observed = float(1.0 + basin_index / 10 + (day % 31) / 5)
            row = {
                "basin": basin,
                "date": date.strftime("%Y-%m-%d"),
                "qobs": observed,
                "qsim": observed + qsim_offset,
            }
            if variant == "historical_band_experts":
                row.update(
                    weight_recent=0.4,
                    weight_medium=0.35,
                    weight_old=0.25,
                )
            rows.append(row)
    predictions_path = run_dir / "predictions.csv"
    pd.DataFrame(rows).to_csv(predictions_path, index=False)
    (run_dir / "config.json").write_text("{}", encoding="utf-8")
    (run_dir / "checkpoint.pt").write_bytes(b"test checkpoint")
    (run_dir / "per_basin_metrics.csv").write_text("basin,nse,n_days\n", encoding="utf-8")
    artifacts = {
        name: _sha256(run_dir / name)
        for name in ("predictions.csv", "config.json", "checkpoint.pt", "per_basin_metrics.csv")
    }
    manifest = {
        "status": "complete",
        "variant": variant,
        "seed": seed,
        "n_validation_predictions": len(rows),
        "artifacts": artifacts,
    }
    (run_dir / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")


def _small_integrity_frame():
    return pd.DataFrame({
        "basin": ["00000001", "00000001", "00000002", "00000002"],
        "date": ["2007-01-01", "2007-01-02", "2007-01-01", "2007-01-02"],
        "qobs": [1.0, 2.0, 1.5, 2.5],
        "qsim": [1.1, 2.1, 1.6, 2.6],
    })


def test_prediction_integrity_rejects_duplicate_daily_key():
    frame = pd.concat([_small_integrity_frame(), _small_integrity_frame().iloc[[0]]], ignore_index=True)

    with pytest.raises(ValueError, match="duplicate"):
        analyze.validate_prediction_frame(
            frame, expected_basins=("00000001", "00000002"),
            expected_dates=pd.date_range("2007-01-01", "2007-01-02"),
        )


def test_prediction_integrity_rejects_missing_day():
    frame = _small_integrity_frame().iloc[:-1]

    with pytest.raises(ValueError, match="basin-date"):
        analyze.validate_prediction_frame(
            frame, expected_basins=("00000001", "00000002"),
            expected_dates=pd.date_range("2007-01-01", "2007-01-02"),
        )


def test_prediction_integrity_rejects_extra_basin():
    frame = _small_integrity_frame().copy()
    frame.loc[len(frame)] = ["00000003", "2007-01-01", 3.0, 3.0]

    with pytest.raises(ValueError, match="basin"):
        analyze.validate_prediction_frame(
            frame, expected_basins=("00000001", "00000002"),
            expected_dates=pd.date_range("2007-01-01", "2007-01-02"),
        )


def test_prediction_integrity_rejects_nonfinite_simulation():
    frame = _small_integrity_frame().copy()
    frame.loc[0, "qsim"] = np.nan

    with pytest.raises(ValueError, match="non-finite"):
        analyze.validate_prediction_frame(
            frame, expected_basins=("00000001", "00000002"),
            expected_dates=pd.date_range("2007-01-01", "2007-01-02"),
        )


def test_prediction_integrity_rejects_changed_observation_between_variants():
    first = _small_integrity_frame()
    second = first.copy()
    second.loc[0, "qobs"] = 99.0

    with pytest.raises(ValueError, match="observed"):
        analyze.assert_matching_daily_targets({"first": first, "second": second})


def test_validated_predictions_rejects_any_artifact_hash_mismatch(tmp_path):
    _write_run(tmp_path, "mainstream_lstm", 100, qsim_offset=0.6)
    run_dir = tmp_path / "mainstream_lstm_s100"
    (run_dir / "checkpoint.pt").write_bytes(b"corrupted")

    with pytest.raises(ValueError, match="artifact hash"):
        analyze._validated_predictions(run_dir, "mainstream_lstm", 100)

def test_end_to_end_analysis_recomputes_predictions_and_writes_go(tmp_path):
    for seed in (100, 200, 300):
        _write_run(tmp_path, "mainstream_lstm", seed, qsim_offset=0.6)
        _write_run(tmp_path, "multiscale_fusion", seed, qsim_offset=0.8)
        _write_run(tmp_path, "historical_band_experts", seed, qsim_offset=0.2)

    summary = analyze_results(tmp_path)

    assert summary["verdict"] == "GO"
    assert (tmp_path / "summary.json").exists()
    assert (tmp_path / "per_seed.csv").exists()
    assert (tmp_path / "paired_per_basin.csv").exists()


def test_missing_run_is_incomplete_not_go(tmp_path):
    _write_run(tmp_path, "mainstream_lstm", 100, qsim_offset=0.6)

    summary = analyze_results(tmp_path)

    assert summary["verdict"] == "INCOMPLETE"
    assert summary["missing_runs"]
