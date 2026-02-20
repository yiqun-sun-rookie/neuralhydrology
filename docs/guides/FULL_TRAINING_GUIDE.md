# Full 531 Basins Training Guide

This guide covers the canonical training entrypoints for idea `05_full_531_basins`.

## Paths

- Code: `src/full_531_basins/`
- Configs: `src/full_531_basins/configs/`
- Scripts: `src/full_531_basins/scripts/`
- Results: `results/05_full_531_basins/`

## Recommended Configs

- `src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml`
- `src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_norm_base.yml`

## Start Training

```bash
python -m neuralhydrology.nh_run train --config-file src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml --gpu 0
```

## Utility Scripts

```bash
python src/full_531_basins/scripts/full_train.py --help
python src/full_531_basins/scripts/monitor_training.py --help
python src/full_531_basins/scripts/training_recovery.py --help
```

## HPC Quick Test

```bash
python -m neuralhydrology.nh_run train --config-file src/full_531_basins/configs/camels_us/hpc/hpc_quick_test.yml --gpu 0
```

## Notes

- Prefer writing outputs to `results/05_full_531_basins/`.
- Keep experiment logs in `logs/05_full_531_basins/`.
- For cluster jobs use `src/full_531_basins/hpc/` plus `docs/hpc/HPC_WORKFLOW_FINAL.md`.