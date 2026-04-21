from pathlib import Path

import pandas as pd

from src.xaj_global_pilot.scripts.run_conceptual_screening import build_parser, main


def test_screening_cli_exposes_expected_arguments():
    parser = build_parser()
    args = parser.parse_args(
        [
            "--manifest",
            "src/xaj_global_pilot/configs/conceptual_benchmark_15_basins.csv",
            "--output-version",
            "screening_test",
            "--primary-only",
        ]
    )

    assert args.manifest.endswith("conceptual_benchmark_15_basins.csv")
    assert args.output_version == "screening_test"
    assert args.primary_only is True

    default_args = parser.parse_args(
        [
            "--manifest",
            "src/xaj_global_pilot/configs/conceptual_benchmark_15_basins.csv",
        ]
    )
    assert default_args.output_version == "screening_v02"


def test_screening_cli_writes_summary_outputs(tmp_path: Path, monkeypatch):
    manifest_path = tmp_path / "conceptual_benchmark_15_basins.csv"
    pd.DataFrame(
        [
            {"basin_id": "b1", "regime": "humid", "region": "camels_us", "selection_note": "test"},
        ]
    ).to_csv(manifest_path, index=False)

    all_metrics = pd.DataFrame(
        [
            {
                "basin_id": "b1",
                "regime": "humid",
                "model": "xaj",
                "period": "test",
                "nse": 0.1,
                "kge": 0.2,
                "bias": 0.0,
                "peak_bias": 0.0,
                "lowflow_bias": 0.0,
                "parameter_count": 14,
                "solver_name": "explicit_euler",
                "family": "xaj",
                "run_status": "success",
                "error_message": "",
            },
            {
                "basin_id": "b1",
                "regime": "humid",
                "model": "xaj_pdd",
                "period": "test",
                "nse": 0.6,
                "kge": 0.7,
                "bias": 0.0,
                "peak_bias": 0.0,
                "lowflow_bias": 0.0,
                "parameter_count": 20,
                "solver_name": "explicit_euler",
                "family": "xaj",
                "run_status": "success",
                "error_message": "",
            },
            {
                "basin_id": "b1",
                "regime": "humid",
                "model": "hbv",
                "period": "test",
                "nse": 0.5,
                "kge": 0.6,
                "bias": 0.0,
                "peak_bias": 0.0,
                "lowflow_bias": 0.0,
                "parameter_count": 12,
                "solver_name": "implicit_euler",
                "family": "hbv",
                "run_status": "success",
                "error_message": "",
            },
            {
                "basin_id": "b1",
                "regime": "humid",
                "model": "gr4j",
                "period": "test",
                "nse": 0.3,
                "kge": 0.4,
                "bias": 0.0,
                "peak_bias": 0.0,
                "lowflow_bias": 0.0,
                "parameter_count": 4,
                "solver_name": "implicit_euler",
                "family": "gr4j",
                "run_status": "success",
                "error_message": "",
            },
            {
                "basin_id": "b1",
                "regime": "humid",
                "model": "gr4j_pdd",
                "period": "test",
                "nse": 0.4,
                "kge": 0.5,
                "bias": 0.0,
                "peak_bias": 0.0,
                "lowflow_bias": 0.0,
                "parameter_count": 10,
                "solver_name": "implicit_euler",
                "family": "gr4j",
                "run_status": "success",
                "error_message": "",
            },
        ]
    )
    by_regime = pd.DataFrame([{"regime": "humid", "model": "xaj_pdd", "median_nse": 0.6}])

    def fake_run_pilot_batch(selected_basins_csv, output_dir, data_root=None, calibration_trials=2000, include_ablations=True):
        output_dir = Path(output_dir)
        summary_dir = output_dir / "summary"
        summary_dir.mkdir(parents=True, exist_ok=True)
        all_metrics.to_csv(summary_dir / "all_basins_metrics.csv", index=False)
        by_regime.to_csv(summary_dir / "by_regime_metrics.csv", index=False)
        return all_metrics, by_regime

    monkeypatch.setattr(
        "src.xaj_global_pilot.scripts.run_conceptual_screening.run_pilot_batch",
        fake_run_pilot_batch,
    )

    output_root = tmp_path / "results"
    assert main(
        [
            "--manifest",
            str(manifest_path),
            "--output-dir",
            str(output_root),
            "--output-version",
            "screening_test",
            "--include-ablations",
        ]
    ) == 0

    summary_dir = output_root / "screening_test" / "summary"
    assert (summary_dir / "all_basins_metrics.csv").exists()
    assert (summary_dir / "by_regime_metrics.csv").exists()
    assert (summary_dir / "win_counts.csv").exists()
    assert (summary_dir / "ablation_deltas.csv").exists()


def test_screening_cli_overwrites_stale_summary_outputs(tmp_path: Path, monkeypatch):
    manifest_path = tmp_path / "conceptual_benchmark_15_basins.csv"
    pd.DataFrame(
        [
            {"basin_id": "b1", "regime": "humid", "region": "camels_us", "selection_note": "test"},
        ]
    ).to_csv(manifest_path, index=False)

    fresh_all_metrics = pd.DataFrame(
        [
            {
                "basin_id": "b1",
                "regime": "humid",
                "model": "hbv",
                "period": "test",
                "nse": 0.41,
                "kge": 0.52,
                "bias": 0.0,
                "peak_bias": 0.0,
                "lowflow_bias": 0.0,
                "parameter_count": 12,
                "solver_name": "implicit_euler",
                "family": "hbv",
                "run_status": "success",
                "error_message": "",
            },
        ]
    )
    fresh_by_regime = pd.DataFrame([{"regime": "humid", "model": "hbv", "median_nse": 0.41}])

    def fake_run_pilot_batch(selected_basins_csv, output_dir, data_root=None, calibration_trials=2000, include_ablations=True):
        output_dir = Path(output_dir)
        summary_dir = output_dir / "summary"
        summary_dir.mkdir(parents=True, exist_ok=True)
        pd.DataFrame(
            [
                {
                    "basin_id": "b1",
                    "regime": "humid",
                    "model": "hbv",
                    "period": "test",
                    "nse": pd.NA,
                    "kge": pd.NA,
                    "bias": pd.NA,
                    "peak_bias": pd.NA,
                    "lowflow_bias": pd.NA,
                    "parameter_count": 12,
                    "solver_name": "implicit_euler",
                    "family": "hbv",
                    "run_status": "failed",
                    "error_message": "stale failure",
                },
            ]
        ).to_csv(summary_dir / "all_basins_metrics.csv", index=False)
        pd.DataFrame([{"regime": "humid", "model": "hbv", "median_nse": pd.NA}]).to_csv(
            summary_dir / "by_regime_metrics.csv", index=False
        )
        return fresh_all_metrics, fresh_by_regime

    monkeypatch.setattr(
        "src.xaj_global_pilot.scripts.run_conceptual_screening.run_pilot_batch",
        fake_run_pilot_batch,
    )

    output_root = tmp_path / "results"
    assert main(
        [
            "--manifest",
            str(manifest_path),
            "--output-dir",
            str(output_root),
            "--output-version",
            "screening_test",
            "--include-ablations",
        ]
    ) == 0

    summary_dir = output_root / "screening_test" / "summary"
    written_all_metrics = pd.read_csv(summary_dir / "all_basins_metrics.csv")
    written_by_regime = pd.read_csv(summary_dir / "by_regime_metrics.csv")

    assert written_all_metrics.loc[0, "run_status"] == "success"
    assert written_all_metrics.loc[0, "nse"] == 0.41
    assert pd.isna(written_all_metrics.loc[0, "error_message"]) or written_all_metrics.loc[0, "error_message"] == ""
    assert written_by_regime.loc[0, "median_nse"] == 0.41
