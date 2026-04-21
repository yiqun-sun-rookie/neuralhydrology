import json
from pathlib import Path

import pandas as pd

from src.xaj_global_pilot.scripts.summarize_conceptual_benchmark import main


def test_paper_summary_exports_tables_without_mutating_raw_inputs(tmp_path: Path):
    raw_summary_dir = tmp_path / "screening_v02" / "summary"
    raw_summary_dir.mkdir(parents=True, exist_ok=True)

    all_metrics = pd.DataFrame(
        [
            {
                "basin_id": "00000001",
                "regime": "humid",
                "model": "xaj_pdd",
                "period": "test",
                "nse": 0.70,
                "kge": 0.60,
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
                "basin_id": "00000001",
                "regime": "humid",
                "model": "hbv",
                "period": "test",
                "nse": 0.50,
                "kge": 0.40,
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
                "basin_id": "00000002",
                "regime": "snow-dominated",
                "model": "xaj_pdd",
                "period": "test",
                "nse": 0.60,
                "kge": 0.50,
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
                "basin_id": "00000002",
                "regime": "snow-dominated",
                "model": "hbv",
                "period": "test",
                "nse": 0.80,
                "kge": 0.70,
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
    all_metrics.to_csv(raw_summary_dir / "all_basins_metrics.csv", index=False)
    original_raw = all_metrics.copy(deep=True)

    output_dir = tmp_path / "paper_exports"
    assert main(
        [
            "--summary-dir",
            str(raw_summary_dir),
            "--output-dir",
            str(output_dir),
        ]
    ) == 0

    overall = pd.read_csv(output_dir / "table_overall_metrics.csv")
    efficiency = pd.read_csv(output_dir / "table_parameter_efficiency.csv")
    manifest = json.loads((output_dir / "figure_manifest.json").read_text(encoding="utf-8"))
    best_model = pd.read_csv(output_dir / "table_best_model_by_basin.csv", dtype={"basin_id": str})

    assert overall["model"].tolist() == ["hbv", "xaj_pdd"]
    assert efficiency.loc[efficiency["model"] == "hbv", "median_nse_per_parameter"].iloc[0] == round(0.65 / 12, 6)
    assert efficiency.loc[efficiency["model"] == "xaj_pdd", "median_nse_per_parameter"].iloc[0] == round(0.65 / 20, 6)
    assert best_model["best_model"].tolist() == ["xaj_pdd", "hbv"]

    assert manifest["table_overall_metrics"] == "table_overall_metrics.csv"
    assert manifest["table_parameter_efficiency"] == "table_parameter_efficiency.csv"
    assert manifest["table_best_model_by_basin"] == "table_best_model_by_basin.csv"
    assert manifest["table_by_regime_metrics"] == "table_by_regime_metrics.csv"

    raw_after = pd.read_csv(
        raw_summary_dir / "all_basins_metrics.csv",
        dtype={"basin_id": str},
        keep_default_na=False,
    )
    pd.testing.assert_frame_equal(raw_after, original_raw)
