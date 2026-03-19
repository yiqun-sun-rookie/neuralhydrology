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

- Encoder input includes **all dynamic forcings + observed streamflow Q_obs** (Q_obs not available to main model)
- Encoder also receives static attributes (same as main model) via concatenation to each timestep
- Proj: two separate Linear layers — `Proj_h(enc_hidden_size → main_hidden_size)` and `Proj_c(enc_hidden_size → main_hidden_size)`
- Gradients flow from both L_pred and L_cont back through the encoder via h_0/c_0

**Main model** (standard CudaLSTM, unmodified architecture):

```
Q_pred^(k), h^(k)(t), c^(k)(t) = LSTM_main(forcing_{predict_k}, h_0^(k), c_0^(k))
Q_pred^(k+1), h^(k+1)(t), c^(k+1)(t) = LSTM_main(forcing_{predict_k+1}, h_0^(k+1), c_0^(k+1))
```

**Loss function** (averaged over the overlap window):

```
L_cont = (1/T_ov) * Σ_{t ∈ overlap} (||h^(k)(t) - h^(k+1)(t)||² + ||c^(k)(t) - c^(k+1)(t)||²)

L = L_pred^(k) + L_pred^(k+1) + λ * L_cont
```

Where the sum runs over all `T_ov` timesteps in the overlap region (default 30 days). Both h and c terms are equally weighted; cell states may have larger magnitudes but the L2 penalty naturally scales with magnitude.

### 2.3 Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Encoder architecture | Independent small LSTM | Modular, clean ablation, no training coupling |
| State passing | None (soft constraint via loss) | Enables parallel training, novel formulation |
| Segment sampling | Pair sampling (adjacent overlapping) | Guarantees fresh SCL signal every step |
| Main model | CudaLSTM with h_0/c_0 injection (see 3.5) | Isolates contribution of training paradigm |
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

### 3.2 SCLDataset Sampling Algorithm

**Constraint**: all pairs use fixed geometry (`seg_length`, `context_length`, `overlap_length` are constants), so `overlap_idx = seg_length - overlap_length` is the same for every sample.

**Constraint**: `seg_length > overlap_length` (enforced in config validation).

**Lookup table construction** (at init):

```
For each basin b:
  Load full time series [t_start, t_end]
  For each valid pair start index i:
    seg_k predict window:   [i, i + seg_length)
    seg_k+1 predict window: [i + seg_length - overlap_length, i + 2*seg_length - overlap_length)
    seg_k context window:   [i - context_length, i)
    seg_k+1 context window: [i + seg_length - overlap_length - context_length, i + seg_length - overlap_length)

    Validate: no NaN in targets for both segments, all windows within data range
    If valid: add (basin_id, i) to lookup_table
```

**`__getitem__(idx)`** returns a dict with fixed-shape tensors. `overlap_idx` is NOT stored per-sample — it is a dataset-level constant computed as `seg_length - overlap_length`.

### 3.3 Data Flow (Single Training Step)

```
1. SCLDataset.__getitem__() returns:
   {
     'context_k':   [context_len, n_enc_features],    # all forcings + Q_obs + static
     'predict_k':   [seg_len, n_main_features],        # forcings only (no Q_obs)
     'context_k1':  [context_len, n_enc_features],
     'predict_k1':  [seg_len, n_main_features],
     'y_k':         [seg_len, n_targets],               # ground truth seg k
     'y_k1':        [seg_len, n_targets],               # ground truth seg k+1
     'x_s':         [n_static_features],                # static attributes (shared)
     'per_basin_target_stds': [n_targets],              # for NSE loss
   }

2. Collate into batch: all tensors get batch dim [B, ...]

3. Encoder forward (batched, 2B contexts):
   all_contexts = cat(context_k, context_k1, dim=0)      # [2B, context_len, n_enc_feat]
   enc_h, enc_c = encoder_lstm(all_contexts)              # [1, 2B, enc_hidden]
   h0 = proj_h(enc_h.squeeze(0))                          # [2B, main_hidden]
   c0 = proj_c(enc_c.squeeze(0))                          # [2B, main_hidden]
   h0 = h0.unsqueeze(0)                                   # [1, 2B, main_hidden] (PyTorch LSTM format)
   c0 = c0.unsqueeze(0)                                   # [1, 2B, main_hidden]

4. Main LSTM forward (batched, 2B segments):
   all_x = cat(predict_k, predict_k1, dim=0)              # [2B, seg_len, n_main_feat]
   x_embedded = embedding_net(all_x)                       # [seg_len, 2B, embed_size]
   lstm_output, _ = main_lstm(x_embedded, (h0, c0))        # [seg_len, 2B, hidden]
   lstm_output = lstm_output.transpose(0, 1)               # [2B, seg_len, hidden]
   output_k, output_k1 = lstm_output.chunk(2, dim=0)       # [B, seg_len, hidden] each
   y_hat = head(dropout(lstm_output))                       # [2B, seg_len, output_size]

5. Loss computation:
   overlap_start = seg_length - overlap_length             # constant, e.g., 150
   h_k_ov  = output_k[:, overlap_start:, :]               # [B, overlap_len, hidden]
   h_k1_ov = output_k1[:, :overlap_length, :]             # [B, overlap_len, hidden]
   L_cont = mean((h_k_ov - h_k1_ov)²)                    # scalar, averaged over B × overlap_len × hidden
   # (same for cell states if accessible; see Section 3.5)

   L_pred = NSE_loss(y_hat_k, y_k) + NSE_loss(y_hat_k1, y_k1)
   L_total = L_pred + λ * L_cont
```

### 3.4 Temporal Layout (daily, default config)

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

### 3.5 Main LSTM h_0/c_0 Injection

`CudaLSTM.forward()` does not accept initial states — it calls `self.lstm(input=x_d)` which defaults to zeros. `SCLCudaLSTM` solves this by **wrapping** (not modifying) CudaLSTM:

```python
class SCLCudaLSTM(nn.Module):
    def __init__(self, cfg):
        self.encoder = ObsEncoder(cfg)
        self.embedding_net = InputLayer(cfg)    # reuse NH InputLayer
        self.lstm = nn.LSTM(...)                # same config as CudaLSTM
        self.dropout = nn.Dropout(cfg.output_dropout)
        self.head = get_head(cfg, ...)

    def forward(self, predict_data, context_data):
        h0, c0 = self.encoder(context_data)     # [1, B, hidden]
        x = self.embedding_net(predict_data)     # [seq, B, embed]
        lstm_out, (h_n, c_n) = self.lstm(x, (h0, c0))  # inject h0/c0
        pred = self.head(self.dropout(lstm_out.transpose(0,1)))
        return {'y_hat': pred, 'lstm_output': lstm_out.transpose(0,1),
                'h_n': h_n, 'c_n': c_n}
```

This duplicates CudaLSTM's plumbing but keeps the NH package untouched. The LSTM/head/embedding configs are identical to CudaLSTM, ensuring fair comparison with E1.

**Note on cell state SCL**: PyTorch `nn.LSTM` returns `lstm_output` (hidden states at all timesteps) but NOT cell states at all timesteps. To compute SCL on cell states, either: (a) use only hidden states in L_cont (simpler, recommended for v1), or (b) unroll the LSTM manually step-by-step like ARLSTM to capture cell states. **We use option (a) for v1.**

### 3.6 Inference Protocol

At test time:

1. For each basin, the encoder processes the last `context_length` days of **observed Q + forcings** before the evaluation period start
2. This produces `(h_0, c_0)` for the main LSTM
3. The main LSTM runs forward on the evaluation period with this initial state
4. No SCL computed, no pairs needed — single segment evaluation
5. Prediction loss (NSE/KGE) computed on the evaluation period only

**For fair comparison with E1 (365d warm-up)**:
- E1 uses 365 days of **forcing-only** warm-up (no Q_obs)
- E3 uses 30 days of **forcing + Q_obs** context via the encoder
- This is NOT a confound — it reflects the real advantage of the method: using observations for state initialization is more efficient than long warm-up. The paper should discuss this as a feature, not a limitation.
- E5 (encoder-only, no SCL) isolates the encoder's contribution from the SCL's contribution.

### 3.7 Hyperparameters

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
| E7 | Encoder-only (single) | SCLCudaLSTM | single segment, encoder, no pairs, no SCL | Ablation: isolate encoder from pair/SCL effect |

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
| E3 vs E7 | Does pair sampling + SCL add value beyond the encoder alone? |
| E5 vs E7 | Does pair sampling help even without SCL? |

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
| Table 1 | Median NSE/KGE + GPU-hours + effective samples/sec (all methods) | Main results |
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
