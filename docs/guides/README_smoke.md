# Smoke Test Commands

This file provides quick, reproducible smoke-test commands for core ideas.

## Prerequisites

- Run from repo root: `g:\github\pycharm\projects\neuralhydrology`
- Use CPU for fast validation (`--gpu -1`)
- Datasets must exist locally (`data/CAMELS_US`, `data/camelsh`, `data/Caravan`)

## Latest Verified (2026-02-19)

- `01_caravan_global`: `results/01_caravan_global/caravan_daily_smoke_2basins_ep1_2026_0219_1642_ep1/` (NSE=0.44622, KGE=0.50352)
- `02_mamba_camels_us`: `results/02_mamba_camels_us/mamba_daily_smoke_2basins_ep1_2026_0219_1649_ep1/` (NSE=0.05126, KGE=0.15290)
- `03_mamba_camelsh`: `results/03_mamba_camelsh/camelsh_lstm_smoke_2basins_ep1_2026_0219_1652_ep1/` (NSE=0.29982, KGE=0.41511)
- `mts_mamba_global_transfer`: `results/41_mts_mamba_global_transfer/41_caravan_daily_smoke_2basins_ep1_2026_0219_1716_ep1/` (NSE=0.44622, KGE=0.50352)

## 01 caravan_global

```bash
python -m neuralhydrology.nh_run train --config-file src/caravan_global/configs/caravan_daily_smoke_2basins_ep1.yml --gpu -1
python -m neuralhydrology.nh_run train --config-file src/caravan_global/configs/caravan_daily_smoke_10basins_ep3.yml --gpu -1
```

- Config: `src/caravan_global/configs/caravan_daily_smoke_2basins_ep1.yml`
- Basins: `src/caravan_global/data/smoke_2_basins.txt`
- Config (10x3): `src/caravan_global/configs/caravan_daily_smoke_10basins_ep3.yml`
- Basins (10): `src/caravan_global/data/smoke_10_basins.txt`
- Output root: `results/01_caravan_global/`

## 02 mamba_camels_us

```bash
python -m neuralhydrology.nh_run train --config-file src/mamba_camels_us/configs/mamba_daily_smoke_2basins_ep1.yml --gpu -1
python -m neuralhydrology.nh_run train --config-file src/mamba_camels_us/configs/mamba_daily_smoke_10basins_ep3.yml --gpu -1
```

- Config: `src/mamba_camels_us/configs/mamba_daily_smoke_2basins_ep1.yml`
- Basins: `src/mamba_camels_us/data/smoke_2_basins.txt`
- Config (10x3): `src/mamba_camels_us/configs/mamba_daily_smoke_10basins_ep3.yml`
- Basins (10): `src/mamba_camels_us/data/smoke_10_basins.txt`
- Output root: `results/02_mamba_camels_us/`

## 03 mamba_camelsh

```bash
python -m neuralhydrology.nh_run train --config-file src/mamba_camelsh/configs/camelsh_lstm_smoke_2basins_ep1.yml --gpu -1
python -m neuralhydrology.nh_run train --config-file src/mamba_camelsh/configs/camelsh_lstm_smoke_10basins_ep3.yml --gpu -1
```

- Config: `src/mamba_camelsh/configs/camelsh_lstm_smoke_2basins_ep1.yml`
- Basins: `src/mamba_camelsh/data/smoke_2_basins.txt`
- Config (10x3): `src/mamba_camelsh/configs/camelsh_lstm_smoke_10basins_ep3.yml`
- Basins (10): `src/mamba_camelsh/data/smoke_10_basins.txt`
- Output root: `results/03_mamba_camelsh/`

## 41 mts_mamba_global_transfer

```bash
python -m neuralhydrology.nh_run train --config-file src/mts_mamba_global_transfer/configs/caravan_daily_smoke_2basins_ep1.yml --gpu -1
python -m neuralhydrology.nh_run train --config-file src/mts_mamba_global_transfer/configs/caravan_daily_smoke_10basins_ep3.yml --gpu -1
```

- Config: `src/mts_mamba_global_transfer/configs/caravan_daily_smoke_2basins_ep1.yml`
- Basins: `src/mts_mamba_global_transfer/data/smoke_2_basins.txt`
- Config (10x3): `src/mts_mamba_global_transfer/configs/caravan_daily_smoke_10basins_ep3.yml`
- Basins (10): `src/mts_mamba_global_transfer/data/smoke_10_basins.txt`
- Output root: `results/41_mts_mamba_global_transfer/`

## Quick Non-Training Checks

```bash
python src/namou_kuwei/scripts/run_experiment.py --help
python src/full_531_basins/scripts/full_train.py --help
python src/haihe_river/scripts/01_filter_hydrobasins.py --help
python src/hydroagent/tests/test_env.py
```

## Notes

- Expected run directory pattern:
  - `results/<ID>_<idea>/<experiment_name>_<timestamp>_ep1/`
  - `results/<ID>_<idea>/<experiment_name>_<timestamp>_ep3/`
- If PowerShell prints `conda-script.py ... invalid choice ''`, treat it as local shell noise unless training itself fails.

