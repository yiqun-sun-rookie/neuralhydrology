"""Train a separate CudaLSTM for each well (per-well, like Pastas per-well calibration)."""
import sys
import shutil
import logging
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

import pandas as pd
import numpy as np

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
logger = logging.getLogger(__name__)


def train_single_well(well_id: str, data_dir: Path, run_base: Path, epochs: int = 30):
    """Train and evaluate a single well."""
    from neuralhydrology.nh_run import start_run, eval_run
    from neuralhydrology.utils.config import Config

    well_dir = data_dir / "per_well" / well_id
    run_dir = run_base / well_id

    # Skip if already evaluated
    metrics_path = run_dir / "test" / f"model_epoch{epochs:03d}" / "test_metrics.csv"
    if metrics_path.exists():
        logger.info("Skipping %s (already done)", well_id)
        return pd.read_csv(metrics_path)

    # Clean previous failed run
    if run_dir.exists():
        shutil.rmtree(run_dir)

    # Write config
    cfg_content = f"""
experiment_name: per_well_{well_id}
dataset: generic
data_dir: {data_dir.as_posix()}

train_basin_file: {(well_dir / 'train_basins.txt').as_posix()}
validation_basin_file: {(well_dir / 'val_basins.txt').as_posix()}
test_basin_file: {(well_dir / 'test_basins.txt').as_posix()}

train_start_date: 01/01/2001
train_end_date: 31/12/2017
validation_start_date: 01/01/2018
validation_end_date: 31/12/2020
test_start_date: 01/01/2021
test_end_date: 01/01/2025

dynamic_inputs:
  - P_mm
  - ET_mm
  - T_degC

target_variables:
  - gwl_m_nap

model: cudalstm
head: regression
hidden_size: 32

epochs: {epochs}
batch_size: 64
learning_rate:
  0: 0.001
  {epochs // 3}: 0.0005
  {epochs * 2 // 3}: 0.00025
optimizer: Adam
seq_length: 1825
predict_last_n: 365
clip_gradient_norm: 1.0

loss: NSE
metrics:
  - NSE
  - KGE
  - RMSE

log_interval: 10
save_weights_every: {epochs}
log_tensorboard: false
log_n_figures: 0
"""
    cfg_path = well_dir / "config.yml"
    cfg_path.write_text(cfg_content)

    # Train
    try:
        start_run(config_file=cfg_path, gpu=-1)
    except Exception as e:
        logger.error("Train failed for %s: %s", well_id, e)
        return None

    # Find run dir (created by NeuralHydrology)
    import glob
    runs = sorted(Path("runs").glob(f"per_well_{well_id}_*"))
    if not runs:
        logger.error("No run dir found for %s", well_id)
        return None
    actual_run = runs[-1]

    # Evaluate
    try:
        eval_run(run_dir=actual_run, period="test", epoch=epochs, gpu=-1)
    except Exception as e:
        logger.error("Eval failed for %s: %s", well_id, e)
        return None

    # Read metrics
    mp = actual_run / "test" / f"model_epoch{epochs:03d}" / "test_metrics.csv"
    if mp.exists():
        return pd.read_csv(mp)
    return None


def main():
    data_dir = Path("data/gwl_nl")
    run_base = Path("runs/per_well")
    run_base.mkdir(parents=True, exist_ok=True)

    test_ids = open(data_dir / "test_basins.txt").read().strip().split("\n")
    logger.info("Training %d per-well models...", len(test_ids))

    results = []
    for i, well_id in enumerate(test_ids):
        logger.info("=== [%d/%d] %s ===", i + 1, len(test_ids), well_id)
        metrics = train_single_well(well_id, data_dir, run_base, epochs=30)
        if metrics is not None:
            results.append(metrics)

    if results:
        all_metrics = pd.concat(results, ignore_index=True)
        all_metrics.to_csv(data_dir / "per_well_test_metrics.csv", index=False)
        valid = all_metrics.dropna(subset=["NSE"])
        logger.info("=== Per-well Results ===")
        logger.info("Wells with metrics: %d/%d", len(valid), len(test_ids))
        for col in ["NSE", "KGE", "RMSE"]:
            logger.info("  %s: median=%.3f, mean=%.3f", col, valid[col].median(), valid[col].mean())


if __name__ == "__main__":
    main()
