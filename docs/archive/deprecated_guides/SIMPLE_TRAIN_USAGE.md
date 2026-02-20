# SIMPLE_TRAIN Usage (Deprecated)

`simple_train.py` is no longer available.

Use:

```bash
python -m neuralhydrology.nh_run train --config-file src/test_data/configs/test_config.yml --gpu -1
```

For 531-basin training:

```bash
python -m neuralhydrology.nh_run train --config-file src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml --gpu 0
```

