# CAMELSH Hourly Model Experiment Log

## Overview
Dataset: CAMELSH (Hourly CAMELS)
Target: Streamflow prediction
Reference: CAMELS-US daily model (NSE=0.74)

---

## Experiment 1: Baseline (v1)
**Config**: `src/mamba_camelsh/configs/legacy/camelsh_hourly_optimized.yml`
**Run Dir**: `runs/camelsh_hourly_optimized_2025_1201_1339_ep30`
**Date**: 2025-12-01

### Settings
| Parameter | Value |
|-----------|-------|
| train_period | 2010-2014 (5 years) |
| val_period | 2015-2017 |
| test_period | 2018-2020 |
| seq_length | 168 (7 days) |
| hidden_size | 128 |
| batch_size | 256 |
| epochs | 30 |
| learning_rate | 0.003->0.001->0.0005 |
| output_dropout | 0.0 |
| num_basins | 455 |

### Results
| Metric | Validation (Best) | Test |
|--------|-------------------|------|
| NSE | 0.587 (Epoch 18) | 0.558 |
| KGE | 0.648 (Epoch 24) | 0.610 |

### Training Curve
```
Epoch  NSE     KGE
   2   0.14    0.09
   4   0.21    0.35
   8   0.48    0.51
  12   0.56    0.59
  16   0.29    0.38  <- Anomaly
  18   0.59    0.62  <- Best NSE
  24   0.54    0.65  <- Best KGE
  30   0.55    0.63
```

### Notes
- Training time: ~15 hours
- Observed anomaly at Epoch 16
- Model recovered quickly after anomaly

---

## Experiment 2: More Training Data (v2)
**Config**: `src/mamba_camelsh/configs/legacy/camelsh_v2_more_data.yml`
**Run Dir**: `runs/camelsh_v2_more_data_2025_1204_2011_ep30`
**Date**: 2025-12-04
**Status**: 🔄 训练中

### Settings
| Parameter | Value | Change from v1 |
|-----------|-------|----------------|
| train_period | 2002-2014 (13 years) | +8 years |
| seq_length | 336 (14 days) | +168 hours |
| learning_rate | 0.002->0.001->0.0005 | Lower initial |
| Other | Same as v1 | - |

### Expected Improvements
- More training data should improve generalization
- Longer sequence captures more temporal patterns
- Lower initial LR may reduce training instability

### Results
| Metric | Validation (Best) | Test |
|--------|-------------------|------|
| NSE | TBD | TBD |
| KGE | TBD | TBD |

### Notes
- TBD

---

## Future Experiments

### v3: Larger Model
- hidden_size: 256
- num_layers: 2
- Expected: +5% if not overfitting

### v4: EA-LSTM
- Use Entity-Aware LSTM
- Better static attribute integration
- Expected: +3-5%

### v5: Multi-scale
- Combine hourly and daily features
- Expected: +5-10%

---

## Summary Table

| Version | Config | Train Period | Seq Length | Val NSE | Test NSE | Test KGE |
|---------|--------|--------------|------------|---------|----------|----------|
| v1 | camelsh_hourly_optimized | 2010-2014 | 168h | 0.587 | 0.558 | 0.610 |
| v2 | camelsh_v2_more_data | 2002-2014 | 336h | TBD | TBD | TBD |
| v3 | TBD | - | - | - | - | - |



