from pathlib import Path
import hashlib
import json
import sys

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import analyze_v05


def _stage1_frame(
    candidate_delta: float,
    control_delta: float,
    late_delta: float,
    win_fraction: float = 1.0,
) -> pd.DataFrame:
    n_basins = 20
    exact = np.linspace(0.4, 0.8, n_basins)
    delta = np.full(n_basins, candidate_delta)
    if win_fraction < 1:
        losing = int(round(n_basins * (1 - win_fraction)))
        delta[:losing] = -abs(candidate_delta)
    candidate = exact + delta
    return pd.DataFrame({
        "basin": [f"{index + 1:08d}" for index in range(n_basins)],
        "nse_classic_lstm_256": exact,
        "nse_control": candidate - control_delta,
        "nse_late_concat": candidate - late_delta,
        "nse_candidate": candidate,
    })


def test_v05_stage1_requires_all_four_frozen_criteria():
    passing = analyze_v05.evaluate_stage1(
        _stage1_frame(0.02, 0.005, 0.003)
    )
    assert passing["passed"] is True
    assert all(passing["criteria"].values())

    cases = [
        (_stage1_frame(0.009, 0.005, 0.003), "median_delta_exact_at_least_0_01"),
        (_stage1_frame(0.02, -0.001, 0.003), "median_delta_capacity_above_zero"),
        (_stage1_frame(0.02, 0.005, -0.001), "median_delta_late_concat_above_zero"),
        (_stage1_frame(0.02, 0.005, 0.003, 0.50), "win_fraction_exact_at_least_0_55"),
    ]
    for frame, failed in cases:
        decision = analyze_v05.evaluate_stage1(frame)
        assert decision["passed"] is False
        assert decision["criteria"][failed] is False


def _multiseed_frame() -> pd.DataFrame:
    rows = []
    for seed in (100, 200, 300):
        for basin in range(30):
            rows.append({
                "seed": seed,
                "basin": f"{basin + 1:08d}",
                "delta_exact": 0.02 + basin * 0.0001,
                "delta_control": 0.004 + basin * 0.00005,
                "delta_late_concat": 0.003 + basin * 0.00001,
            })
    return pd.DataFrame(rows)


def test_v05_multiseed_requires_effect_capacity_late_seeds_interval_and_wins():
    passing = analyze_v05.evaluate_multiseed(_multiseed_frame())
    assert passing["passed"] is True
    assert all(passing["criteria"].values())

    failing = _multiseed_frame()
    failing["delta_late_concat"] = -0.001
    decision = analyze_v05.evaluate_multiseed(failing)
    assert decision["criteria"]["median_delta_late_concat_above_zero"] is False
    assert decision["passed"] is False


def test_v05_conditional_runs_include_only_new_candidate_and_capacity_control():
    assert analyze_v05.conditional_run_names() == [
        "classic_lstm_320_s200",
        "hierarchical_rich_history_s200",
        "classic_lstm_320_s300",
        "hierarchical_rich_history_s300",
    ]


def _small_integrity_frame() -> pd.DataFrame:
    return pd.DataFrame({
        "basin": ["00000001", "00000001", "00000002", "00000002"],
        "date": ["2007-01-01", "2007-01-02", "2007-01-01", "2007-01-02"],
        "qobs": [1.0, 2.0, 1.5, 2.5],
        "qsim": [1.1, 2.1, 1.6, 2.6],
    })


def test_v05_prediction_integrity_rejects_duplicate_missing_and_nonfinite_rows():
    kwargs = {
        "expected_basins": ("00000001", "00000002"),
        "expected_dates": pd.date_range("2007-01-01", "2007-01-02"),
    }
    duplicate = pd.concat([_small_integrity_frame(), _small_integrity_frame().iloc[[0]]])
    with pytest.raises(ValueError, match="duplicate"):
        analyze_v05.validate_prediction_frame(duplicate, **kwargs)

    with pytest.raises(ValueError, match="basin-date"):
        analyze_v05.validate_prediction_frame(_small_integrity_frame().iloc[:-1], **kwargs)

    nonfinite = _small_integrity_frame()
    nonfinite.loc[0, "qsim"] = np.nan
    with pytest.raises(ValueError, match="non-finite"):
        analyze_v05.validate_prediction_frame(nonfinite, **kwargs)


def test_v05_observations_must_match_across_arms():
    first = _small_integrity_frame()
    second = first.copy()
    second.loc[0, "qobs"] = 99
    with pytest.raises(ValueError, match="observed"):
        analyze_v05.assert_matching_daily_targets({"first": first, "second": second})


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write_run(root: Path, variant: str, seed: int) -> Path:
    run_dir = root / f"{variant}_s{seed}"
    run_dir.mkdir(parents=True)
    dates = pd.date_range("2006-10-01", "2008-09-30", freq="D")
    basins = [f"{index + 1:08d}" for index in range(60)]
    n_rows = len(dates) * len(basins)
    day = np.tile(np.arange(len(dates), dtype=np.float64), len(basins))
    basin_offset = np.repeat(np.arange(len(basins), dtype=np.float64) / 10, len(dates))
    observed = 2 + basin_offset + np.sin(day / 17)
    pd.DataFrame({
        "basin": np.repeat(basins, len(dates)),
        "date": np.tile(dates.strftime("%Y-%m-%d"), len(basins)),
        "qobs": observed,
        "qsim": observed + 0.1,
    }).to_csv(run_dir / "predictions.csv", index=False)
    (run_dir / "config.json").write_text("{}", encoding="utf-8")
    (run_dir / "checkpoint.pt").write_bytes(b"checkpoint")
    (run_dir / "per_basin_metrics.csv").write_text("basin,nse,n_days\n", encoding="utf-8")
    artifacts = {
        name: _sha256(run_dir / name)
        for name in ("config.json", "checkpoint.pt", "predictions.csv", "per_basin_metrics.csv")
    }
    manifest = {
        "status": "complete",
        "variant": variant,
        "seed": seed,
        "parameter_count": analyze_v05.EXPECTED_PARAMETER_COUNTS[variant],
        "n_validation_predictions": n_rows,
        "data_access": {"raw_observed_discharge_reads": 0},
        "artifacts": artifacts,
    }
    (run_dir / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    return run_dir


def test_v05_validated_run_rejects_hash_and_parameter_mismatch(tmp_path):
    run_dir = _write_run(tmp_path, "hierarchical_rich_history", 100)
    manifest_path = run_dir / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["parameter_count"] = 1
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(ValueError, match="parameter count"):
        analyze_v05.validated_predictions(run_dir, "hierarchical_rich_history", 100)

    manifest["parameter_count"] = analyze_v05.EXPECTED_PARAMETER_COUNTS["hierarchical_rich_history"]
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    (run_dir / "checkpoint.pt").write_bytes(b"corrupted")
    with pytest.raises(ValueError, match="artifact hash"):
        analyze_v05.validated_predictions(run_dir, "hierarchical_rich_history", 100)


def test_v05_missing_base_runs_are_reported_without_opening_predictions(tmp_path):
    summary = analyze_v05.analyze_results_v05(
        results_root=tmp_path / "results",
        reference_v03_root=tmp_path / "v03",
        reference_v04_root=tmp_path / "v04",
    )
    assert summary["status"] == "incomplete_base_runs"
    assert summary["missing_runs"]
