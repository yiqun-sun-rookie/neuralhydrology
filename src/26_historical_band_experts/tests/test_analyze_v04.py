from pathlib import Path
import hashlib
import json
import sys

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import analyze_v04


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


def test_v04_new_stage1_requires_effect_capacity_late_concat_and_win_fraction():
    passing = analyze_v04.evaluate_new_stage1_candidate(
        _stage1_frame(0.02, 0.005, 0.003),
        candidate="persistent_context",
        control="classic_lstm_265",
    )
    assert passing["passed"] is True
    assert all(passing["criteria"].values())

    cases = [
        (_stage1_frame(0.009, 0.005, 0.003), "median_delta_exact_at_least_0_01"),
        (_stage1_frame(0.02, -0.001, 0.003), "median_delta_capacity_above_zero"),
        (_stage1_frame(0.02, 0.005, -0.001), "median_delta_late_concat_above_zero"),
        (_stage1_frame(0.02, 0.005, 0.003, 0.50), "win_fraction_exact_at_least_0_55"),
    ]
    for frame, failed_criterion in cases:
        decision = analyze_v04.evaluate_new_stage1_candidate(
            frame,
            candidate="persistent_context",
            control="classic_lstm_265",
        )
        assert decision["criteria"][failed_criterion] is False
        assert decision["passed"] is False


def _multiseed_frame(include_late: bool) -> pd.DataFrame:
    rows = []
    for seed in (100, 200, 300):
        for basin in range(30):
            row = {
                "seed": seed,
                "basin": f"{basin + 1:08d}",
                "delta_exact": 0.02 + basin * 0.0001,
                "delta_control": 0.004 + basin * 0.00005,
            }
            if include_late:
                row["delta_late_concat"] = 0.003 + basin * 0.00001
            rows.append(row)
    return pd.DataFrame(rows)


def test_v04_late_concat_confirmation_uses_original_five_multiseed_criteria():
    decision = analyze_v04.evaluate_late_concat_multiseed(_multiseed_frame(include_late=False))
    assert decision["passed"] is True
    assert all(decision["criteria"].values())


def test_v04_new_multiseed_confirmation_adds_late_concat_criterion():
    passing = analyze_v04.evaluate_new_multiseed_candidate(_multiseed_frame(include_late=True))
    assert passing["passed"] is True
    assert all(passing["criteria"].values())

    failing = _multiseed_frame(include_late=True)
    failing["delta_late_concat"] = -0.001
    decision = analyze_v04.evaluate_new_multiseed_candidate(failing)
    assert decision["criteria"]["median_delta_late_concat_above_zero"] is False
    assert decision["passed"] is False


def test_v04_conditional_run_list_reuses_exact_and_late_concat_runs():
    runs = analyze_v04.conditional_new_run_names(
        ["persistent_context", "recent_conditioned_residual"]
    )
    assert runs == [
        "classic_lstm_265_s200",
        "classic_lstm_270_s200",
        "persistent_context_s200",
        "recent_conditioned_residual_s200",
        "classic_lstm_265_s300",
        "classic_lstm_270_s300",
        "persistent_context_s300",
        "recent_conditioned_residual_s300",
    ]


def _small_integrity_frame() -> pd.DataFrame:
    return pd.DataFrame({
        "basin": ["00000001", "00000001", "00000002", "00000002"],
        "date": ["2007-01-01", "2007-01-02", "2007-01-01", "2007-01-02"],
        "qobs": [1.0, 2.0, 1.5, 2.5],
        "qsim": [1.1, 2.1, 1.6, 2.6],
    })


def test_v04_prediction_integrity_rejects_duplicate_missing_and_nonfinite_rows():
    kwargs = {
        "expected_basins": ("00000001", "00000002"),
        "expected_dates": pd.date_range("2007-01-01", "2007-01-02"),
    }
    duplicate = pd.concat([_small_integrity_frame(), _small_integrity_frame().iloc[[0]]])
    with pytest.raises(ValueError, match="duplicate"):
        analyze_v04.validate_prediction_frame(duplicate, **kwargs)

    with pytest.raises(ValueError, match="basin-date"):
        analyze_v04.validate_prediction_frame(_small_integrity_frame().iloc[:-1], **kwargs)

    nonfinite = _small_integrity_frame()
    nonfinite.loc[0, "qsim"] = np.nan
    with pytest.raises(ValueError, match="non-finite"):
        analyze_v04.validate_prediction_frame(nonfinite, **kwargs)


def test_v04_observations_must_match_across_arms():
    first = _small_integrity_frame()
    second = first.copy()
    second.loc[0, "qobs"] = 99
    with pytest.raises(ValueError, match="observed"):
        analyze_v04.assert_matching_daily_targets({"first": first, "second": second})


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
        "parameter_count": analyze_v04.EXPECTED_PARAMETER_COUNTS[variant],
        "n_validation_predictions": n_rows,
        "data_access": {"raw_observed_discharge_reads": 0},
        "artifacts": artifacts,
    }
    (run_dir / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    return run_dir


def test_v04_validated_run_rejects_hash_and_parameter_mismatch(tmp_path):
    run_dir = _write_run(tmp_path, "persistent_context", 100)
    manifest_path = run_dir / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["parameter_count"] = 1
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(ValueError, match="parameter count"):
        analyze_v04.validated_predictions(run_dir, "persistent_context", 100)

    manifest["parameter_count"] = analyze_v04.EXPECTED_PARAMETER_COUNTS["persistent_context"]
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    (run_dir / "checkpoint.pt").write_bytes(b"corrupted")
    with pytest.raises(ValueError, match="artifact hash"):
        analyze_v04.validated_predictions(run_dir, "persistent_context", 100)


def test_v04_missing_base_runs_are_reported_without_opening_predictions(tmp_path):
    reference_root = tmp_path / "reference"
    results_root = tmp_path / "results"
    summary = analyze_v04.analyze_results_v04(results_root, reference_root)
    assert summary["status"] == "incomplete_base_runs"
    assert summary["missing_runs"]
