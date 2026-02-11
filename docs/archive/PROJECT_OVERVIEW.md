# NeuralHydrology Project Overview

> Quick reference to understand and navigate this repository. Intended for fast onboarding and for tooling (assistants) to recall core concepts without re-reading the entire tree.

## 1. Purpose
A framework to train and evaluate deep learning models (LSTM variants, others) for hydrological time-series modeling (e.g., streamflow prediction) using datasets like CAMELS-US. Emphasis on configuration-driven (YAML) experiments and reproducible basin splits.

## 2. High-Level Architecture
- `neuralhydrology/nh_run.py`: Entry point orchestrating training / evaluation via subcommands (e.g., `train`).
- `neuralhydrology/datasetzoo/`: Dataset implementations (e.g., `camelsus.py`) providing standardized access to forcing, attributes, targets.
- `neuralhydrology/modelzoo/`: Model architectures (e.g., LSTM family, transformers, mamba variants, multi-timescale models, forecasting heads).
- `neuralhydrology/training/`: Trainer logic (`basetrainer.py`, loss application, optimization loops, logging, checkpointing).
- `neuralhydrology/evaluation/`: Metrics and evaluation utilities (NSE, KGE, etc.).
- `neuralhydrology/utils/`: Helper functions (scaling, time handling, file IO, logging, etc.).
- `examples/`: Canonical YAML configs, basin lists, and tutorials.
- `environments/`: Conda environment definitions (CPU, CUDA, clean GPU).

## 3. Configuration Workflow
- Experiments defined by YAML: model hyperparams, data paths, basin split files, time ranges, metrics, logging.
- Official launcher `nh_run.py` (CLI: `nh-run`) loads YAML configs and orchestrates training / evaluation. Legacy wrappers have been removed.
- Prefer editing / copying YAML rather than generating them inside Python scripts to avoid drift.

## 4. Key Models
| Family | Examples | Notes |
|--------|----------|-------|
| LSTM Variants | `cudalstm`, `ealstm`, `customlstm`, `mclstm`, `arlstm`, `mtslstm` | `cudalstm` is GPU-optimized; others add attention, memory, or adaptive gates. |
| RNN Alt | `gru` | Simpler recurrent baseline. |
| Transformers | `transformer` | Sequence modeling with attention. |
| State Space / Modern | `mamba` | Efficient long-sequence modeling. |
| Forecasting Heads | `handoff_forecast_lstm`, `sequential_forecast_lstm`, `multihead_forecast_lstm`, `stacked_forecast_lstm` | Multi-step or structured forecasting. |

## 5. Output Heads
- `regression`: Standard deterministic point predictions.
- Probabilistic (in repo but not always used): e.g., GMM, UMAL, CMAL (if enabled via heads or configs).

## 6. Loss Functions
- Deterministic: MSE, RMSE, NSE (implemented as scaled MSE minimization), Alpha-NSE variants.
- Probabilistic: Negative log-likelihood variants (e.g., GMM), mixture adaptive losses.
- NSE Minimization: Achieved by weighting squared errors by variance scaling; no manual sign flip needed.

## 7. Metrics (examples)
- `NSE`, `KGE`, `Alpha-NSE`, `RMSE`.
- Configurable via YAML `metrics:` list.

## 8. Basin Splits
- Basin list files (*.txt) enumerate USGS gage IDs.
- Spatial generalization: train/val/test use disjoint basin sets.
- Temporal generalization: same basin list but non-overlapping time windows.
- Mixed evaluation: train+val share basins (time-split) + disjoint test basins.

## 9. Current Training Scripts Status
Legacy scripts (`run_training.py`, `gpu_training.py`, `run_gpu*.py`, etc.) are deprecated. Use `python -m neuralhydrology.nh_run ...` (or the installed `nh-run` CLI) for all training / evaluation flows.

## 10. Data Layout Expectations (CAMELS-US)
- `data/CAMELS_US/` contains `basin_mean_forcing/<forcing_name>/...` and `usgs_streamflow/<gauge>_streamflow_qc.txt` plus attributes.
- Demo subset `data/camels_us_demo` only has a handful of basins (4) for quick sanity checks.
- Full training requires pointing `data_dir` to full dataset, otherwise FileNotFoundErrors or missing basins occur.

## 11. Typical Full-Data Config Highlights (example: `full_training.yml`)
- `model: cudalstm`
- `loss: NSE`
- `batch_size`: 256–1024 depending on GPU memory.
- `seq_length: 365` (1-year context). `predict_last_n: 1`.
- Validation uses `validate_n_random_basins` to subsample for performance (set higher for stability: ~30–50).

## 12. Performance & Scaling Tips
- Increase `num_workers` for IO bound speedups (monitor Windows spawn overhead; on Linux 8–16 typical).
- Larger batches improve throughput until GPU memory saturates; watch gradient scaling & divergence.
- Adjust `log_interval` and `save_weights_every` higher for large multi-basin runs to reduce IO overhead.

## 13. Reproducibility
- Set `seed` in YAML (already present).
- Basin lists and explicit date ranges provide deterministic splits.
- Avoid in-script random basin sampling; pre-generate lists instead.

## 14. Planned / Next Improvements
- Unified launcher replacing multiple training scripts.
- Optional GPU auto-optimization (batch size, hidden size) writes a derived YAML (never overwrites original).
- Clear deprecation warnings in legacy runners.
- Potential stratified basin split utilities (by aridity / area / climate class).

## 15. Common Pitfalls
| Issue | Cause | Fix |
|-------|-------|-----|
| `FileNotFoundError` for basin | Using demo `data_dir` with full basin list | Switch to full dataset path or reduce basin list |
| `cuda available: False` | CPU torch build or wrong env | Install GPU build in dedicated env |
| Slow training | CPU fallback; huge logging frequency | Use GPU env; raise `log_interval` |
| Over-optimistic metrics | Same file for train/val/test | Use disjoint basin or temporal splits |

## 16. Minimal GPU Environment (See `environments/environment_gpu_clean.yml`)
Create and activate:
```
conda env create -f environments/environment_gpu_clean.yml
conda activate nh-gpu
```
Verify:
```
python -c "import torch;print(torch.__version__, torch.version.cuda, torch.cuda.is_available())"
```

## 17. Quick Command Cheatsheet
```
# Train (GPU)
python -m neuralhydrology.nh_run train --config-file examples/01-Introduction/full_training.yml --gpu 0

# Train (CPU fallback)
python -m neuralhydrology.nh_run train --config-file examples/01-Introduction/full_training.yml --gpu -1

# TensorBoard
tensorboard --logdir runs
```

---
_Last updated: 2025-10-05_
