# full_531_basins

CAMELS-US 531 basins full training experiments.

## Directory Structure

```
src/full_531_basins/
├── configs/
│   ├── full_training/          # ★ Canonical configs (portable, relative paths)
│   │   ├── full_training_531_arlstm.yml
│   │   ├── full_training_531_ealstm.yml
│   │   ├── full_training_531_gru.yml
│   │   ├── full_training_531_mtslstm.yml
│   │   └── full_training_531_transformer.yml
│   └── camels_us/
│       ├── full_training/      # Early-stage configs (absolute paths, legacy)
│       │   ├── full_training_531_temporal_with_static.yml
│       │   ├── full_training_531_temporal_norm_base.yml
│       │   ├── reproduce_531_nse074.yml
│       │   └── ...
│       └── hpc/                # HPC submission configs
│           ├── hpc_full_training.yml
│           └── hpc_quick_test.yml
├── scripts/
├── hpc/
├── docs/
└── data/
```

## Config Selection

| Purpose | Config |
|---------|--------|
| Model comparison (LSTM/GRU/EA-LSTM/Transformer) | `configs/full_training/*.yml` |
| Historical reproduction (NSE 0.74 baseline) | `configs/camels_us/full_training/reproduce_531_nse074.yml` |
| With static attributes | `configs/camels_us/full_training/full_training_531_temporal_with_static.yml` |
| HPC submission | `configs/camels_us/hpc/*.yml` |

> Note: `configs/camels_us/full_training/` contains earlier configs with hardcoded absolute paths.
> Prefer `configs/full_training/` for new experiments.

## Quick Start

```bash
python -m neuralhydrology.nh_run train \
  --config-file src/full_531_basins/configs/full_training/full_training_531_ealstm.yml \
  --gpu 0
```

## Results

Output to `results/05_full_531_basins/`.
