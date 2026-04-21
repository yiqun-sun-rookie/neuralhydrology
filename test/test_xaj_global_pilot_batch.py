from pathlib import Path

import pandas as pd

from src.xaj_global_pilot.batch import run_pilot_batch


def test_run_pilot_batch_writes_metrics_and_summary(tmp_path: Path, monkeypatch):
    selected = pd.DataFrame(
        [
            {"basin_id": "b1", "regime": "humid"},
            {"basin_id": "b2", "regime": "semi-humid"},
        ]
    )
    selected_path = tmp_path / "pilot_60_basins.csv"
    selected.to_csv(selected_path, index=False)
    output_dir = tmp_path / "outputs"

    def fake_runner(basin_id, model, data_root=None, calibration_trials=200):
        return {
            "basin_id": basin_id,
            "model": model,
            "period": "test",
            "nse": 0.5 if model in {"xaj", "gr4j"} else 0.6,
            "kge": 0.4 if model in {"xaj", "gr4j"} else 0.5,
            "bias": 0.0,
            "peak_bias": 0.1,
            "lowflow_bias": -0.1,
            "parameter_count": 14 if model == "xaj" else 4 if model == "gr4j" else 12,
            "solver_name": "explicit_euler" if model == "xaj" else "implicit_euler",
            "family": "xaj" if model.startswith("xaj") else "hbv" if model == "hbv" else "gr4j",
            "run_status": "success",
            "error_message": "",
        }

    monkeypatch.setattr("src.xaj_global_pilot.batch.run_single_model_basin", fake_runner)

    all_metrics, summary = run_pilot_batch(selected_path, output_dir=output_dir, data_root="data/Caravan")

    assert len(all_metrics) == 10
    assert (output_dir / "summary" / "all_basins_metrics.csv").exists()
    assert (output_dir / "summary" / "by_regime_metrics.csv").exists()
    assert (output_dir / "xaj" / "b1.csv").exists()
    assert (output_dir / "gr4j_pdd" / "b1.csv").exists()
    assert "delta_nse_vs_xaj" in summary.columns


def test_run_pilot_batch_preserves_zero_padded_basin_ids_from_manifest(tmp_path: Path, monkeypatch):
    selected = pd.DataFrame(
        [
            {"basin_id": "01022500", "regime": "humid"},
        ]
    )
    selected_path = tmp_path / "screening_manifest.csv"
    selected.to_csv(selected_path, index=False)
    seen_basin_ids = []

    def fake_runner(basin_id, model, data_root=None, calibration_trials=200):
        seen_basin_ids.append(basin_id)
        return {
            "basin_id": basin_id,
            "model": model,
            "period": "test",
            "nse": 0.5,
            "kge": 0.4,
            "bias": 0.0,
            "peak_bias": 0.1,
            "lowflow_bias": -0.1,
            "parameter_count": 14 if model == "xaj" else 4 if model == "gr4j" else 12,
            "solver_name": "explicit_euler" if model == "xaj" else "implicit_euler",
            "family": "xaj" if model.startswith("xaj") else "hbv" if model == "hbv" else "gr4j",
            "run_status": "success",
            "error_message": "",
        }

    monkeypatch.setattr("src.xaj_global_pilot.batch.run_single_model_basin", fake_runner)

    run_pilot_batch(selected_path, output_dir=tmp_path / "outputs")

    assert seen_basin_ids
    assert all(basin_id == "01022500" for basin_id in seen_basin_ids)
