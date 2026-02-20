# CAMELS-US Data Usage Guide

This guide summarizes the required CAMELS-US layout for NeuralHydrology experiments.

## Data Location

```text
neuralhydrology/
  data/
    CAMELS_US/
      basin_mean_forcing/
      basin_metadata/
      camels_attributes_v2.0/
      discharge/
```

## Prepare Data

Download CAMELS-US from official sources and extract into `data/CAMELS_US`.

## Config Usage

```yaml
dataset: camels_us
data_dir: data/CAMELS_US
```

Typical configs:
- `src/mamba_camels_us/configs/mamba_daily.yml`
- `src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml`

## Notes

- Keep folder naming exact on Linux/macOS.
- Dataset is local-only and should not be committed.