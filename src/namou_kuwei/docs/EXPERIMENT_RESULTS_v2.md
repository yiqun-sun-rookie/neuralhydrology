# Nam Ou Kuwei - Experiment Results (v2)

> Updated: 2025-12-04

## 1. Overview

This document summarizes all deep learning experiments for streamflow forecasting at Nam Ou Kuwei station, with a focus on preventing data leakage.

## 2. Time Split Configuration

All experiments use the following **non-overlapping** time periods:

| Period | Start | End |
|--------|-------|-----|
| Training | 2020-01-01 | 2021-06-30 |
| Validation | 2021-07-01 | 2021-12-31 |
| Test | 2022-01-01 | 2022-12-31 |

## 3. Input Features and AR Lag Summary

| ID | Config File | Dynamic Inputs | Static | AR Input | Lag Time | predict_last_n |
|----|-------------|----------------|--------|----------|----------|----------------|
| L1 | `01_baseline/rain_only_LT1h.yml` | Rain (8 stations) | No | None | - | 1 |
| L1-Long | `01_baseline/rain_only_LT1h_Long720.yml` | Rain (8 stations) | No | None | - | 1 |
| L2 | `02_with_static/rain_static_LT1h.yml` | Rain (8 stations) | Yes (24) | None | - | 1 |
| L3 | `03_with_ar/rain_ar_LT1h.yml` | Rain + `qobs_shift1` | No | qobs(t-1) | **1 hour** | 1 |
| L4 | `04_full/rain_ar_static_LT1h.yml` | Rain + `qobs_shift1` | Yes | qobs(t-1) | **1 hour** | 1 |
| L5-6h | `05_leadtime/rain_ar_LT6h.yml` | Rain + `qobs_shift6` | No | qobs(t-6) | **6 hours** | 1 |
| L5-12h | `05_leadtime/rain_ar_LT12h.yml` | Rain + `qobs_shift12` | No | qobs(t-12) | **12 hours** | 1 |
| L5-24h | `05_leadtime/rain_ar_LT24h.yml` | Rain + `qobs_shift24` | No | qobs(t-24) | **24 hours** | 1 |
| L6-Rain | `06_seq2seq/seq2seq_rain_24h.yml` | Rain only | No | None | - | 24 |
| L6-AR24 | `06_seq2seq/seq2seq_ar24lag_24h.yml` | Rain + `qobs_shift24` | No | qobs(t-24) | **24 hours** | 24 |

### Key Points:
- **Seq-to-One** (`predict_last_n: 1`): Model outputs one time step per sample
- **Seq-to-Seq** (`predict_last_n: 24`): Model outputs 24 time steps per sample
- **AR Lag >= Lead Time**: Ensures no data leakage (e.g., 24h forecast uses flow from 24h ago)

## 4. Test Set Performance

| Experiment | NSE | KGE | RMSE | Peak-MAPE | Notes |
|------------|-----|-----|------|-----------|-------|
| L1 Rain Only | -0.250 | -0.310 | 79.34 | 85.5% | Baseline (no flow info) |
| L1-Long (720h) | -0.245 | -0.305 | 79.21 | 85.2% | Longer seq_length |
| L2 Rain + Static | -0.215 | -0.280 | 78.54 | 84.8% | Static attrs minimal help |
| **L3 Rain + AR (1h)** | **0.975** | **0.885** | **11.19** | **17.9%** | Best 1h forecast |
| L4 Rain + AR + Static (1h) | 0.969 | 0.877 | 12.50 | 19.2% | Static adds little |
| L5 Rain + AR (6h) | 0.763 | 0.575 | 34.52 | 53.2% | |
| L5 Rain + AR (12h) | 0.822 | 0.666 | 29.98 | 47.6% | |
| L5 Rain + AR (24h) | 0.735 | 0.546 | 36.54 | 52.2% | Seq-to-One 24h |
| L6 Seq2Seq Rain 24h | -0.274 | -0.333 | 80.17 | 85.3% | No flow, rain only |
| **L6 Seq2Seq AR24lag 24h** | **0.730** | **0.550** | **36.90** | 55.7% | **Best Seq2Seq 24h** |

## 5. Seq-to-Seq AR Lag Verification

For the 24-hour Seq-to-Seq model (`seq2seq_ar24lag_24h.yml`):

### Configuration
```yaml
lagged_features:
  qobs: [24]

autoregressive_inputs:
  - qobs_shift24

predict_last_n: 24
```

### How It Works
1. **Data Preparation** (`basedataset.py`):
   ```python
   df[f"{feature}_shift{s}"] = df[feature].shift(periods=s, freq="infer")
   ```
   At time `t`, `qobs_shift24` contains the observed flow from `t-24`.

2. **Model Forward** (`arlstm.py`):
   - AR-LSTM uses the shifted input directly
   - Only substitutes with predictions when AR input is NaN (missing)

3. **Result**: When predicting hours 1-24 from time `t`, the model only uses observed flow from `t-24` or earlier. **No future flow is ever used.**

## 6. Key Findings

### 6.1 AR Features are Critical
- Pure rainfall models (L1, L2) perform poorly (NSE < 0)
- Adding 1-hour lagged flow boosts NSE from -0.25 to 0.975
- AR contribution is far more significant than static attributes

### 6.2 Static Attributes Have Limited Value (Single-Basin)
- L2 vs L1: Minimal improvement (-0.25 �?-0.21)
- L4 vs L3: Slight degradation (0.975 �?0.969)
- Static attributes are constant for a single basin, providing little discriminative power

### 6.3 Accuracy Degrades with Lead Time
| Lead Time | Test NSE |
|-----------|----------|
| 1h | 0.975 |
| 6h | 0.763 |
| 12h | 0.822 |
| 24h | 0.735 |

Note: 12h performs better than 6h, possibly due to catchment concentration time (~12h).

### 6.4 Seq-to-One vs Seq-to-Seq at 24h
- Seq-to-One (L5-24h): NSE = 0.735
- Seq-to-Seq (L6-AR24): NSE = 0.730
- Nearly equivalent performance, Seq-to-Seq is more efficient for multi-step forecasts

## 7. Generalized Workflow

### Step 1: Prepare Site Configuration
Create `src/namou_kuwei/configs/templates/site_<name>.yml` with:
- Data paths
- Rainfall station list
- Time split (non-overlapping)
- Custom normalization

### Step 2: Generate Experiment Configs
```bash
# Rain only baseline
python src/namou_kuwei/scripts/gen_config.py --site namou_kuwei --type rain --lead 1

# Rain + AR with 6h lead time
python src/namou_kuwei/scripts/gen_config.py --site namou_kuwei --type ar --lead 6

# Seq-to-Seq 24h
python src/namou_kuwei/scripts/gen_config.py --site namou_kuwei --type seq2seq_ar --lead 24 --predict-steps 24
```

### Step 3: Validate (Leakage Check)
```bash
python src/namou_kuwei/scripts/validate_config.py src/namou_kuwei/configs/generated/
```

### Step 4: Train
```bash
python src/namou_kuwei/scripts/run_experiment.py train --config <config.yml>
```

### Step 5: Evaluate and Compare
```bash
python src/namou_kuwei/scripts/run_experiment.py evaluate --run-dir results/04_namou_kuwei/<run_dir>
python src/namou_kuwei/scripts/run_experiment.py compare --results-dir results/04_namou_kuwei
```

## 8. Config Locations

All validated configs are in:
```
src/namou_kuwei/configs/no_leak/
├── 01_baseline/          # Pure rainfall models
├── 02_with_static/       # Rain + static attributes
├── 03_with_ar/           # Rain + AR (correctly lagged)
├── 04_full/              # Rain + AR + Static
├── 05_leadtime/          # Multi-lead-time AR models
└── 06_seq2seq/           # Seq-to-Seq models
```

## 9. Tools Reference

| Tool | Purpose |
|------|---------|
| `src/namou_kuwei/scripts/gen_config.py` | Generate configs from site template |
| `src/namou_kuwei/scripts/validate_config.py` | Check for data leakage |
| `src/namou_kuwei/scripts/run_experiment.py` | Train, evaluate, compare results |

---

> All experiments have been verified for data leakage using `validate_config.py`

