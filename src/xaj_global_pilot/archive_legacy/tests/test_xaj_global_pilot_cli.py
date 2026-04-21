from pathlib import Path

import pandas as pd

from src.xaj_global_pilot.scripts.run_xaj_global_pilot import build_parser, main


def test_cli_exposes_registry_and_selection_subcommands():
    parser = build_parser()
    subparsers = parser._subparsers._group_actions[0]
    names = set(subparsers.choices.keys())
    assert {"build-registry", "select-basins", "summarize-metrics", "run-pilot"} <= names


def test_cli_can_build_registry_and_select_basins(tmp_path):
    candidate_rows = []
    regimes = [
        ("snow-dominated", 0.3, -2.0, 0.3, 2.0),
        ("humid", 0.0, 5.0, 0.1, 0.8),
        ("semi-humid", 0.0, 5.0, 0.1, 1.2),
        ("semi-arid/arid", 0.0, 5.0, 0.1, 1.8),
    ]
    for regime, snow_fraction, cold_temp, cold_precip, aridity in regimes:
        for idx in range(20):
            candidate_rows.append(
                {
                    "basin_id": f"{regime}-{idx}",
                    "region": f"region-{idx % 6}",
                    "continent": f"continent-{idx % 3}",
                    "snow_fraction": snow_fraction,
                    "temp_coldest_quarter": cold_temp,
                    "cold_season_precip_fraction": cold_precip,
                    "aridity_index": aridity,
                    "missing_rate": 0.0,
                    "human_impact_flag": False,
                    "split_coverage_ok": True,
                    "area_km2": 100 + idx,
                    "seasonality_index": idx / 20,
                }
            )

    candidates_path = tmp_path / "candidates.csv"
    registry_path = tmp_path / "basin_registry.csv"
    selected_path = tmp_path / "pilot_60_basins.csv"
    pd.DataFrame(candidate_rows).to_csv(candidates_path, index=False)

    assert main(
        [
            "build-registry",
            "--input-csv",
            str(candidates_path),
            "--output-csv",
            str(registry_path),
        ]
    ) == 0
    assert registry_path.exists()

    assert main(
        [
            "select-basins",
            "--registry-csv",
            str(registry_path),
            "--output-csv",
            str(selected_path),
        ]
    ) == 0
    selected = pd.read_csv(selected_path)
    assert len(selected) == 60


def test_cli_can_build_registry_from_caravan_root(tmp_path):
    subdataset_dir = tmp_path / "Caravan" / "attributes" / "camels"
    subdataset_dir.mkdir(parents=True)
    (subdataset_dir / "climate.csv").write_text(
        "\n".join(
            [
                "gauge_id,p_mean,pet_mean,aridity_ERA5_LAND,frac_snow",
                "camels_01022500,3.0,2.0,0.7,0.1",
                "camels_02064000,4.0,3.0,1.2,0.3",
            ]
        ),
        encoding="utf-8",
    )

    registry_path = tmp_path / "basin_registry.csv"

    assert main(
        [
            "build-registry",
            "--caravan-root",
            str(tmp_path / "Caravan"),
            "--output-csv",
            str(registry_path),
        ]
    ) == 0
    registry = pd.read_csv(registry_path)
    assert len(registry) == 2
    assert "regime" in registry.columns


def test_cli_can_summarize_metrics(tmp_path):
    metrics_path = tmp_path / "all_basins_metrics.csv"
    summary_path = tmp_path / "by_regime_metrics.csv"
    pd.DataFrame(
        [
            {
                "basin_id": "b1",
                "regime": "humid",
                "model": "xaj",
                "period": "test",
                "nse": 0.5,
                "kge": 0.4,
                "bias": 0.1,
                "peak_bias": 0.2,
                "lowflow_bias": -0.1,
                "run_status": "success",
                "error_message": "",
            },
            {
                "basin_id": "b2",
                "regime": "humid",
                "model": "hbv",
                "period": "test",
                "nse": 0.7,
                "kge": 0.6,
                "bias": 0.0,
                "peak_bias": 0.1,
                "lowflow_bias": -0.2,
                "run_status": "success",
                "error_message": "",
            },
        ]
    ).to_csv(metrics_path, index=False)

    assert main(
        [
            "summarize-metrics",
            "--metrics-csv",
            str(metrics_path),
            "--output-csv",
            str(summary_path),
        ]
    ) == 0
    summary = pd.read_csv(summary_path)
    assert "delta_nse_vs_xaj" in summary.columns


def test_cli_can_run_pilot_batch(tmp_path, monkeypatch):
    selected_path = tmp_path / "pilot_60_basins.csv"
    output_dir = tmp_path / "outputs"
    pd.DataFrame([{"basin_id": "b1", "regime": "humid"}]).to_csv(selected_path, index=False)

    def fake_run_pilot_batch(selected_basins_csv, output_dir, data_root=None, calibration_trials=200):
        output_dir = Path(output_dir)
        (output_dir / "summary").mkdir(parents=True, exist_ok=True)
        pd.DataFrame([{"basin_id": "b1"}]).to_csv(output_dir / "summary" / "all_basins_metrics.csv", index=False)
        pd.DataFrame([{"regime": "humid", "model": "xaj"}]).to_csv(
            output_dir / "summary" / "by_regime_metrics.csv", index=False
        )
        return pd.DataFrame([{"basin_id": "b1"}]), pd.DataFrame([{"regime": "humid", "model": "xaj"}])

    monkeypatch.setattr("src.xaj_global_pilot.scripts.run_xaj_global_pilot.run_pilot_batch", fake_run_pilot_batch)

    assert main(
        [
            "run-pilot",
            "--selected-basins-csv",
            str(selected_path),
            "--output-dir",
            str(output_dir),
            "--data-root",
            "data/Caravan",
        ]
    ) == 0
    assert (output_dir / "summary" / "all_basins_metrics.csv").exists()
