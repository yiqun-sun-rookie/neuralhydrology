from pathlib import Path
import hashlib
import json
import sys

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import analyze_v03


def _metric_frame(candidate_delta: float, control_delta: float, win_fraction: float = 1.0) -> pd.DataFrame:
    n_basins = 20
    exact = np.linspace(0.4, 0.8, n_basins)
    delta = np.full(n_basins, candidate_delta)
    if win_fraction < 1:
        losing = int(round(n_basins * (1 - win_fraction)))
        delta[:losing] = -abs(candidate_delta)
    candidate = exact + delta
    control = candidate - control_delta
    return pd.DataFrame({
        "basin": [f"{index + 1:08d}" for index in range(n_basins)],
        "nse_classic_lstm_256": exact,
        "nse_control": control,
        "nse_candidate": candidate,
    })


def test_v03_stage1_gate_requires_effect_capacity_and_win_fraction():
    passing = analyze_v03.evaluate_stage1_candidate(
        _metric_frame(candidate_delta=0.02, control_delta=0.005),
        candidate="late_concat",
        control="classic_lstm_261",
    )
    assert passing["passed"] is True
    assert all(passing["criteria"].values())

    failing_effect = analyze_v03.evaluate_stage1_candidate(
        _metric_frame(candidate_delta=0.009, control_delta=0.005),
        candidate="late_concat",
        control="classic_lstm_261",
    )
    assert failing_effect["criteria"]["median_delta_exact_at_least_0_01"] is False

    failing_capacity = analyze_v03.evaluate_stage1_candidate(
        _metric_frame(candidate_delta=0.02, control_delta=-0.001),
        candidate="late_concat",
        control="classic_lstm_261",
    )
    assert failing_capacity["criteria"]["median_delta_capacity_above_zero"] is False

    failing_wins = analyze_v03.evaluate_stage1_candidate(
        _metric_frame(candidate_delta=0.02, control_delta=0.005, win_fraction=0.50),
        candidate="late_concat",
        control="classic_lstm_261",
    )
    assert failing_wins["criteria"]["win_fraction_exact_at_least_0_55"] is False


def test_v03_conditional_run_list_is_exact_and_deduplicated():
    runs = analyze_v03.conditional_run_names(["late_concat", "initial_memory"])
    assert runs == [
        "classic_lstm_256_s200",
        "classic_lstm_261_s200",
        "classic_lstm_266_s200",
        "initial_memory_s200",
        "late_concat_s200",
        "classic_lstm_256_s300",
        "classic_lstm_261_s300",
        "classic_lstm_266_s300",
        "initial_memory_s300",
        "late_concat_s300",
    ]


def test_v03_multiseed_gate_uses_all_five_frozen_criteria():
    rows = []
    for seed in (100, 200, 300):
        for basin in range(30):
            rows.append({
                "seed": seed,
                "basin": f"{basin + 1:08d}",
                "delta_exact": 0.02 + basin * 0.0001,
                "delta_control": 0.004 + basin * 0.00005,
            })
    passing = analyze_v03.evaluate_multiseed_candidate(pd.DataFrame(rows))
    assert passing["passed"] is True
    assert all(passing["criteria"].values())

    rows[0]["delta_exact"] = -10
    frame = pd.DataFrame(rows)
    frame["delta_control"] = -0.001
    failing = analyze_v03.evaluate_multiseed_candidate(frame)
    assert failing["criteria"]["median_delta_capacity_above_zero"] is False
    assert failing["passed"] is False


def _small_integrity_frame() -> pd.DataFrame:
    return pd.DataFrame({
        "basin": ["00000001", "00000001", "00000002", "00000002"],
        "date": ["2007-01-01", "2007-01-02", "2007-01-01", "2007-01-02"],
        "qobs": [1.0, 2.0, 1.5, 2.5],
        "qsim": [1.1, 2.1, 1.6, 2.6],
    })


def test_v03_prediction_integrity_rejects_duplicate_missing_and_nonfinite_rows():
    kwargs = {
        "expected_basins": ("00000001", "00000002"),
        "expected_dates": pd.date_range("2007-01-01", "2007-01-02"),
    }
    duplicate = pd.concat([_small_integrity_frame(), _small_integrity_frame().iloc[[0]]])
    with pytest.raises(ValueError, match="duplicate"):
        analyze_v03.validate_prediction_frame(duplicate, **kwargs)

    with pytest.raises(ValueError, match="basin-date"):
        analyze_v03.validate_prediction_frame(_small_integrity_frame().iloc[:-1], **kwargs)

    nonfinite = _small_integrity_frame()
    nonfinite.loc[0, "qsim"] = np.nan
    with pytest.raises(ValueError, match="non-finite"):
        analyze_v03.validate_prediction_frame(nonfinite, **kwargs)


def test_v03_observations_must_match_across_arms():
    first = _small_integrity_frame()
    second = first.copy()
    second.loc[0, "qobs"] = 99
    with pytest.raises(ValueError, match="observed"):
        analyze_v03.assert_matching_daily_targets({"first": first, "second": second})


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write_run(root: Path, variant: str, seed: int, qsim_offset: float) -> None:
    run_dir = root / f"{variant}_s{seed}"
    run_dir.mkdir(parents=True)
    dates = pd.date_range("2006-10-01", "2008-09-30", freq="D")
    rows = []
    for basin_index in range(60):
        basin = f"{basin_index + 1:08d}"
        for day, date in enumerate(dates):
            observed = float(2 + basin_index / 10 + np.sin(day / 17))
            rows.append({
                "basin": basin,
                "date": date.strftime("%Y-%m-%d"),
                "qobs": observed,
                "qsim": observed + qsim_offset,
            })
    pd.DataFrame(rows).to_csv(run_dir / "predictions.csv", index=False)
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
        "parameter_count": analyze_v03.EXPECTED_PARAMETER_COUNTS[variant],
        "n_validation_predictions": len(rows),
        "data_access": {"raw_observed_discharge_reads": 0},
        "artifacts": artifacts,
    }
    (run_dir / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")


def test_v03_validated_run_rejects_hash_and_parameter_mismatch(tmp_path):
    _write_run(tmp_path, "classic_lstm_256", 100, qsim_offset=0.6)
    run_dir = tmp_path / "classic_lstm_256_s100"

    manifest_path = run_dir / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["parameter_count"] = 1
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(ValueError, match="parameter count"):
        analyze_v03.validated_predictions(run_dir, "classic_lstm_256", 100)

    manifest["parameter_count"] = analyze_v03.EXPECTED_PARAMETER_COUNTS["classic_lstm_256"]
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    (run_dir / "checkpoint.pt").write_bytes(b"corrupted")
    with pytest.raises(ValueError, match="artifact hash"):
        analyze_v03.validated_predictions(run_dir, "classic_lstm_256", 100)


def test_v03_seed100_analysis_recomputes_scores_and_emits_conditional_matrix(tmp_path):
    offsets = {
        "classic_lstm_256": 0.8,
        "classic_lstm_261": 0.7,
        "classic_lstm_266": 0.6,
        "late_concat": 0.2,
        "initial_memory": 0.9,
    }
    for variant, offset in offsets.items():
        _write_run(tmp_path, variant, 100, qsim_offset=offset)

    summary = analyze_v03.analyze_results_v03(tmp_path)

    assert summary["status"] == "awaiting_conditional_runs"
    assert summary["stage1"]["late_concat"]["passed"] is True
    assert summary["stage1"]["initial_memory"]["passed"] is False
    assert summary["passing_candidates"] == ["late_concat"]
    assert summary["required_conditional_runs"] == [
        "classic_lstm_256_s200",
        "classic_lstm_261_s200",
        "late_concat_s200",
        "classic_lstm_256_s300",
        "classic_lstm_261_s300",
        "late_concat_s300",
    ]
    assert (tmp_path / "summary.json").exists()
    assert (tmp_path / "per_seed.csv").exists()
    assert (tmp_path / "paired_per_basin.csv").exists()


def test_v03_missing_seed100_run_is_incomplete(tmp_path):
    _write_run(tmp_path, "classic_lstm_256", 100, qsim_offset=0.8)
    summary = analyze_v03.analyze_results_v03(tmp_path)
    assert summary["status"] == "incomplete_stage1"
    assert summary["missing_runs"]
