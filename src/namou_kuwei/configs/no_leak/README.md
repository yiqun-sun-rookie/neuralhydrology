# Nam Ou Kuwei - No Leak Configurations

## Experiment Hierarchy (Progressive Complexity)

| Level | Directory | Features | Purpose |
|-------|-----------|----------|---------|
| L1 | 01_baseline | Rain only | Baseline |
| L2 | 02_with_static | Rain + 24 Static | Test static contribution |
| L3 | 03_with_ar | Rain + AR | Test AR contribution (key!) |
| L4 | 04_full | Rain + Static + AR | Full model |

## Time Split (No Leak)

- Train: 2020
- Validation: 2021  
- Test: 2022

## Run Commands

L1: python -m neuralhydrology.nh_run train --config-file src/namou_kuwei/configs/no_leak/01_baseline/rain_only_LT1h.yml

L2: python -m neuralhydrology.nh_run train --config-file src/namou_kuwei/configs/no_leak/02_with_static/rain_static_LT1h.yml

L3: python -m neuralhydrology.nh_run train --config-file src/namou_kuwei/configs/no_leak/03_with_ar/rain_ar_LT1h.yml

L4: python -m neuralhydrology.nh_run train --config-file src/namou_kuwei/configs/no_leak/04_full/rain_ar_static_LT1h.yml

## Expected Results

| Level | NSE (expected) |
|-------|----------------|
| L1 | ~0.0-0.4 |
| L2 | approx L1 |
| L3 | ~0.8+ |
| L4 | >= L3 |
