# SCL-LSTM: State Continuity Loss for Deep Learning Hydrological Models

**Date:** 2026-03-17
**Status:** Design approved, pending implementation
**Target journal:** WRR / HESS
**Workspace:** `src/scl_hydro/`

---

## 1. Problem Statement

Current deep learning hydrological models (LSTM) use **stateless training**: each training sample is randomly sampled, initialized with h_0=0, and relies on a 365-day warm-up period to mitigate the influence of zero initialization. This approach has three limitations:

1. **Computational waste**: ~50% of each sequence (the warm-up) does not contribute to the loss
2. **No cross-sample state continuity**: the model never learns long-term state evolution across training samples (e.g., multi-year drought)
3. **Train-deploy mismatch**: trained with warm-up, but operational forecasting requires rapid state initialization from observations

HydroLSTM (De la Fuente et al., 2024, HESS) addressed state continuity via hard state passing (serial processing), but this is incompatible with efficient multi-basin training.

## 2. Proposed Method

### 2.1 Overview

**SCL-LSTM** combines three components:

1. **Observation Encoder**: a small LSTM that encodes recent observations `[P, T, Q_obs]` into initial hidden/cell states `(h_0, c_0)` for the main model
2. **Overlapping Segment Pairs**: two temporally overlapping segments from the same basin, each independently forward-passed through the main model
3. **State Continuity Loss (SCL)**: an L2 penalty on hidden state differences at the temporal overlap point, forcing the model to produce consistent states regardless of initialization path

### 2.2 Mathematical Formulation

Given basin $b$, sample two overlapping segments:

- **Seg k**: context window `[t_0, t_s)` + prediction window `[t_s, t_T]`
- **Seg k+1**: context window `[t_c, t_s')` + prediction window `[t_s', t_{T'}]`
- **Overlap**: `[t_s', t_T]` where both segments have predictions

**Encoder** (shared across both segments, independent context windows):

```
h_0^(k), c_0^(k) = Proj(LSTM_enc([P, T, Q_obs]_{context_k}))
h_0^(k+1), c_0^(k+1) = Proj(LSTM_enc([P, T, Q_obs]_{context_k+1}))
```

- Encoder input includes **observed streamflow Q_obs** (not available to main model)
- Proj: Linear(enc_hidden_size → main_hidden_size) for both h and c

**Main model** (standard CudaLSTM, unmodified architecture):

```
Q_pred^(k), h^(k)(t), c^(k)(t) = LSTM_main(forcing_{predict_k}, h_0^(k), c_0^(k))
Q_pred^(k+1), h^(k+1)(t), c^(k+1)(t) = LSTM_main(forcing_{predict_k+1}, h_0^(k+1), c_0^(k+1))
```

**Loss function**:

```
L = L_pred^(k) + L_pred^(k+1) + λ * (||h^(k)(t*) - h^(k+1)(t*)||² + ||c^(k)(t*) - c^(k+1)(t*)||²)
```

Where `t*` is a time point within the overlap region.

### 2.3 Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Encoder architecture | Independent small LSTM | Modular, clean ablation, no training coupling |
| State passing | None (soft constraint via loss) | Enables parallel training, novel formulation |
| Segment sampling | Pair sampling (adjacent overlapping) | Guarantees fresh SCL signal every step |
| Main model | Unmodified CudaLSTM | Isolates contribution of training paradigm |
| Encoder input | [P, T, Q_obs] | Q_obs provides direct state information (learned DA) |
| Main model input | [P, T, ...] (no Q_obs) | Standard, no data leakage |

### 2.4 Training vs Inference

| Aspect | Training | Inference |
|--------|----------|-----------|
| Input | Overlapping segment pairs | Single segment |
| Encoder | Encodes h_0 from Q_obs context | Same (Q_obs available up to forecast time) |
| SCL | Computed | Not computed |
| Parallelism | Full batch parallelism | Standard forward pass |

## 3. Architecture

### 3.1 Module Inventory

| Module | Class | Responsibility |
|--------|-------|----------------|
| Observation Encoder | `ObsEncoder` | Small LSTM + Linear projection → (h_0, c_0) |
| Main model wrapper | `SCLCudaLSTM` | Wraps encoder + CudaLSTM, handles pair forward |
| Dataset | `SCLDataset` | Samples overlapping segment pairs from same basin |
| Trainer | `SCLTrainer` | Pair forward pass + SCL loss computation |
| Loss | `StateContinuityLoss` | ||h_k(t*) - h_{k+1}(t*)||² + ||c_k(t*) - c_{k+1}(t*)||² |
| Config | `SCLConfig` | Extends NH Config with SCL-specific parameters |

### 3.2 Data Flow (Single Training Step)

```
1. SCLDataset.__getitem__() returns:
   {
     'context_k':   [context_len, n_enc_features],    # includes Q_obs
     'predict_k':   [seg_len, n_main_features],        # no Q_obs
     'context_k1':  [context_len, n_enc_features],
     'predict_k1':  [seg_len, n_main_features],
     'y_k':         [seg_len, n_targets],               # ground truth
     'y_k1':        [seg_len, n_targets],
     'overlap_idx':  int,                                # index in predict where overlap starts
   }

2. Collate into batch: all tensors get batch dimension [B, ...]

3. Encoder forward (batched, 2B contexts):
   all_contexts = concat(context_k, context_k1)         # [2B, context_len, n_enc_feat]
   all_h0, all_c0 = encoder(all_contexts)               # [2B, 1, main_hidden_size]
   h0_k, h0_k1 = split(all_h0)                          # [B, ...] each

4. Main LSTM forward (batched, 2B segments):
   all_pred_input = concat(predict_k, predict_k1)       # [2B, seg_len, n_main_feat]
   all_h0 = concat(h0_k, h0_k1)                         # [2B, 1, hidden]
   all_output = main_lstm(all_pred_input, all_h0, all_c0)
   output_k, output_k1 = split(all_output)

5. Loss computation:
   L_pred = NSE_loss(output_k, y_k) + NSE_loss(output_k1, y_k1)
   h_k_overlap = output_k['lstm_output'][:, overlap_idx:, :]
   h_k1_overlap = output_k1['lstm_output'][:, :overlap_len, :]
   L_cont = mean(||h_k_overlap - h_k1_overlap||²)       # compare at overlap
   L_total = L_pred + λ * L_cont
```

### 3.3 Temporal Layout (daily, default config)

```
Seg k:
  context_k (30d)         predict_k (180d)
  [====ctx====]           [===============predict===============]
  t=-30      t=0                                  t=150       t=180

Seg k+1:
                                    context_k+1 (30d)     predict_k+1 (180d)
                                    [====ctx====]         [===============predict===============]
                                    t=120      t=150                              t=330

Overlap in predict space: seg_k [t=150..180] ↔ seg_k+1 [t=0..30]
  → 30 timesteps where both segments produce hidden states
  → SCL computed on these 30 hidden state pairs
```

### 3.4 Hyperparameters

| Parameter | Config key | Default | Range for ablation |
|-----------|------------|---------|-------------------|
| Prediction segment length | `seg_length` | 180 days | {30, 90, 180, 365} |
| Encoder context length | `context_length` | 30 days | {7, 14, 30, 60} |
| Overlap length | `overlap_length` | 30 days | {7, 14, 30} |
| SCL weight | `scl_weight` | 0.1 | {0.01, 0.1, 0.5, 1.0} |
| Encoder hidden size | `enc_hidden_size` | 64 | {32, 64, 128} |
| Main hidden size | `hidden_size` | 256 | fixed |
| Batch size | `batch_size` | 128 (pairs) | fixed |
| Loss function | `loss` | NSE | fixed |

## 4. File Structure

```
src/scl_hydro/
├── __init__.py
├── config.py              # SCLConfig: wraps NH Config + SCL params
├── dataset.py             # SCLDataset: overlapping pair sampling
├── model.py               # ObsEncoder + SCLCudaLSTM
├── trainer.py             # SCLTrainer: pair forward + loss
├── loss.py                # StateContinuityLoss
├── configs/
│   ├── baseline_standard.yml     # E1: standard CudaLSTM + 365d warm-up
│   ├── baseline_no_warmup.yml    # E2: CudaLSTM, no warm-up
│   ├── scl_default.yml           # E3: SCL-LSTM full method
│   ├── ablation_no_encoder.yml   # E4: SCL without encoder
│   ├── ablation_no_scl.yml       # E5: encoder without SCL
│   ├── baseline_ar.yml           # E6: ARLSTM
│   └── ablation/                 # hyperparameter sweeps
├── scripts/
│   ├── run_experiment.py         # training entry point
│   ├── evaluate.py               # evaluation
│   └── analyze_states.py         # hidden state interpretability
└── hpc/
    └── submit_scl.slurm          # SLURM submission script
```

## 5. Experimental Design

### 5.1 Experiment Matrix

| ID | Name | Model | Training | Purpose |
|----|------|-------|----------|---------|
| E1 | Standard Baseline | CudaLSTM | stateless, 365d warm-up | Upper-bound reference |
| E2 | No Warm-up | CudaLSTM | stateless, no warm-up | Lower-bound reference |
| E3 | **SCL-LSTM** | SCLCudaLSTM | pair sampling, encoder, SCL | **Proposed method** |
| E4 | SCL-no-encoder | CudaLSTM | pair sampling, h_0=0, SCL | Ablation: encoder contribution |
| E5 | Encoder-no-SCL | SCLCudaLSTM | pair sampling, encoder, no SCL | Ablation: SCL contribution |
| E6 | AR Baseline | ARLSTM | stateless, Q_obs as input | Compare with Nearing 2022 |

### 5.2 Evaluation

**Metrics**: median NSE, mean NSE, median KGE (531 basins)

**Stratified analysis**:
- High-flow vs low-flow periods (by flow quantile threshold)
- Arid vs humid basins (by aridity index)
- Seasonal breakdown

### 5.3 Ablation Studies

| Comparison | Question |
|------------|----------|
| E3 vs E4 | How much does the encoder contribute? |
| E3 vs E5 | How much does SCL contribute? |
| E3 vs E1 | Does SCL-LSTM match/beat standard training? |
| E3 vs E2 | How much better than no warm-up? |
| E3 vs E6 | How does it compare to autoregression? |

### 5.4 Hyperparameter Sensitivity

Sweep seg_length × scl_weight (4×4 = 16 runs), report as heatmap.

### 5.5 Interpretability Analysis

- Extract hidden state time series from E1 and E3
- Correlate with CAMELS-provided soil moisture / SWE
- Hypothesis: SCL-trained states have higher correlation with slow processes

## 6. Paper Mapping

| Figure/Table | Content | Source |
|-------------|---------|--------|
| Fig 1 | Method overview diagram | Manual |
| Fig 2 | NSE CDF curves (E1-E6, 531 basins) | Overall evaluation |
| Fig 3 | Low-flow vs high-flow NSE boxplot | **Key result** |
| Fig 4 | Time series comparison on representative basin | Case study |
| Fig 5 | Hidden state vs soil moisture/SWE correlation | Interpretability |
| Fig 6 | seg_length × λ ablation heatmap | Sensitivity |
| Table 1 | Median NSE/KGE + training time (all methods) | Main results |
| Table 2 | Ablation results (E3-E5) | Component contribution |

## 7. Related Work

| Work | Approach | Difference from SCL-LSTM |
|------|----------|------------------------|
| Standard (Kratzert 2018) | stateless, 365d warm-up | Wastes computation, no state continuity |
| HydroLSTM (De la Fuente 2024) | Hard state passing, sequential | Serial, single-basin only, modified architecture |
| AR-LSTM (Nearing 2022) | Q_obs as per-step input | Exposure bias, error accumulation in forecasting |
| TBPTT (general ML) | Detached state passing | No explicit loss, no gradient across segments |
| State-Reg RNN (Wang 2019) | Discrete state centroids | Different goal (interpretability), not continuity |
| Predictive-State Decoder (2017) | Predict future from state | Different target (future obs, not cross-segment consistency) |

**SCL-LSTM is novel**: no prior work uses an L2 loss on hidden states at overlapping time points between independently-processed segments to enforce state continuity.

## 8. Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| SCL improves very little over standard warm-up | Focus narrative on low-flow improvement + interpretability |
| λ too sensitive | Extensive sweep + report sensitivity analysis |
| Encoder overfits to Q_obs | Dropout on encoder, compare with/without encoder (E4) |
| Overlap too short → states not comparable | Ablate overlap_length, use multiple comparison points |
| Training slower than standard | Report wall-clock time, show efficiency per effective training step |
