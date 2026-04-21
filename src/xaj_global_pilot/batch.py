from pathlib import Path

import pandas as pd

from src.xaj_global_pilot.model_catalog import get_model_specs
from src.xaj_global_pilot.reporting import summarize_by_regime
from src.xaj_global_pilot.runner import run_single_model_basin


def run_pilot_batch(
    selected_basins_csv,
    output_dir,
    data_root=None,
    calibration_trials: int = 2000,
    include_ablations: bool = True,
):
    selected_path = Path(selected_basins_csv)
    output_path = Path(output_dir)
    summary_dir = output_path / "summary"
    summary_dir.mkdir(parents=True, exist_ok=True)

    selected = pd.read_csv(selected_path, dtype={"basin_id": str})
    all_rows = []
    model_specs = get_model_specs()
    model_names = tuple(model_specs["primary"].keys())
    if include_ablations:
        model_names += tuple(model_specs["ablations"].keys())
    for basin in selected.to_dict(orient="records"):
        basin_id = basin["basin_id"]
        regime = basin["regime"]
        for model in model_names:
            result = run_single_model_basin(
                basin_id,
                model,
                data_root=data_root,
                calibration_trials=calibration_trials,
            )
            row = {**result, "regime": regime}
            all_rows.append(row)
            _write_model_basin_row(output_path / model / f"{basin_id}.csv", row)

    all_metrics = pd.DataFrame(all_rows)
    all_metrics.to_csv(summary_dir / "all_basins_metrics.csv", index=False)

    summary = summarize_by_regime(all_metrics)
    summary.to_csv(summary_dir / "by_regime_metrics.csv", index=False)
    return all_metrics, summary


def _write_model_basin_row(path: Path, row: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame([row]).to_csv(path, index=False)
