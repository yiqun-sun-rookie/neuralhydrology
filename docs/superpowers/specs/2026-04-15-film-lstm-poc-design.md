# FiLM-LSTM POC Design

**Date:** 2026-04-15
**Author:** yiqun (with Claude Opus 4.7 as collaborator)
**Status:** Design approved, pending implementation plan
**Workspace:** `src/static_falsification/` (extended in-place)

---

## 1. Purpose

Test whether **Feature-wise Linear Modulation (FiLM)** on LSTM gates can overcome the "static-attribute-as-basin-ID" problem identified by Heudorfer et al. (2025, GRL) in EA-LSTM, without resorting to heavyweight hypernetworks.

This is a **signal-scouting POC**, not a full paper. Its output is a go/no-go decision on whether to scale to a full 5-fold PUB experiment.

### 1.1 Scientific question

> In an LSTM rainfall-runoff framework, does widening the static-to-dynamics decoding channel (EA-LSTM → FiLM-LSTM) let the model go beyond basin-ID-style use of static attributes?

### 1.2 Why FiLM, not Hypernet-LSTM

Prior brainstorming (this session) concluded:

- **Hypernet-LSTM** (Ha 2017 mechanism, dPL-like regionalization on LSTM) has ~O(H²) static-control bandwidth and is prone to amplifying basin-ID memorization. Novelty is also soft: HyperGPA (2022), HyperEnergy (2025), HyperLSTM (2019) already cover hypernet+LSTM in adjacent TSF domains.
- **FiLM-LSTM** (Perez 2018 mechanism) has O(H) bandwidth, is a natural intermediate step between EA-LSTM (single-gate modulation) and Hypernet (full-weight modulation), has a cleaner identity-initialization training recipe, and is **genuinely unoccupied in hydrology** (3-round literature check: Google Scholar / WebSearch / arXiv — zero hits for FiLM + LSTM + streamflow/rainfall-runoff).

Both fit under the same scientific question ("is the bottleneck in the decoder or in the attribute source?"), but FiLM gives a cleaner diagnostic with less ID-memorization risk.

---

## 2. Scope

### 2.1 In scope

- Implement `FiLMLSTM` model in `neuralhydrology/modelzoo/filmlstm.py`.
- Register in modelzoo factory.
- Generate configs and HPC scripts for a **2 × 2 × 2 × 3 = 24-run** experiment:
  - 2 models: `{EALSTM, FiLMLSTM}`
  - 2 static conditions: `{real static, shuffled static}`
  - 2 folds: `{fold 0, fold 1}` from existing 5-fold PUB split
  - 3 random seeds each
- Analysis script to compute ΔArch, ΔPhys_FiLM, ΔPhys_EA and apply go/no-go thresholds.
- Unit tests + smoke test.

### 2.2 Out of scope

- Full 5-fold PUB experiment (deferred until after POC passes).
- Hyperparameter grid search on FiLM generator width/depth (use defaults).
- Alternative FiLM variants (post-activation FiLM, cell-state FiLM) — rejected in brainstorming.
- Per-gate independent FiLM generators (single shared MLP with 4H output is sufficient).
- Cross-dataset transfer (CAMELS-US only for POC).

### 2.3 Assumptions

- The `src/static_falsification/` workspace (5-fold PUB splits, `shuffled_dataset.py`, EA-LSTM configs, HPC infrastructure) is usable and correct.
- CAMELS-US Daymet forcings + 24 static attributes are consistent with the existing `base_ealstm.yml`.
- HPC at `hpcbh.hhu.edu.cn` has sufficient GPU queue capacity for 24 parallel jobs.

---

## 3. Architecture

### 3.1 FiLM-LSTM cell

The key modification vs. a standard LSTM cell is that the pre-activation of all four gates is affinely modulated by `(γ, β)` generated from static attributes:

```
Standard LSTM cell:
    z         = h @ W_hh + x @ W_ih + bias      # pre-activation, shape [B, 4H]
    i, f, g, o = z.chunk(4, dim=-1)
    i, f, o   = σ(i), σ(f), σ(o)
    g         = tanh(g)
    c_t       = f ⊙ c_{t-1} + i ⊙ g
    h_t       = o ⊙ tanh(c_t)

FiLM-LSTM cell:
    γ, β      = FiLMGenerator(s)                # shape [B, 4H] each, computed ONCE per sample
    z         = h @ W_hh + x @ W_ih + bias      # same as above
    z         = γ ⊙ z + β                       # <<<< FiLM modulation applied here
    i, f, g, o = z.chunk(4, dim=-1)
    ... (rest identical)
```

### 3.2 FiLM generator

```python
class _FiLMGenerator(nn.Module):
    """
    Input:  s ∈ R^{B × S}    (static attributes, S=24 for CAMELS-US default)
    Output: γ, β ∈ R^{B × 4H}
    """
    def __init__(self, cfg):
        super().__init__()
        S   = cfg.statics_output_size        # after neuralhydrology's InputLayer
        H   = cfg.hidden_size
        mid = cfg.film_generator_hidden_size  # new config key, default 64

        self.mlp_gamma = nn.Sequential(
            nn.Linear(S, mid), nn.ReLU(),
            nn.Linear(mid, 4 * H),
        )
        self.mlp_beta = nn.Sequential(
            nn.Linear(S, mid), nn.ReLU(),
            nn.Linear(mid, 4 * H),
        )
        self._identity_init()

    def _identity_init(self):
        # γ: final layer weight=0, bias=1  →  γ ≡ 1 at init
        nn.init.zeros_(self.mlp_gamma[-1].weight)
        nn.init.ones_(self.mlp_gamma[-1].bias)
        # β: final layer weight=0, bias=0  →  β ≡ 0 at init
        nn.init.zeros_(self.mlp_beta[-1].weight)
        nn.init.zeros_(self.mlp_beta[-1].bias)

    def forward(self, s):
        return self.mlp_gamma(s), self.mlp_beta(s)
```

**Identity initialization is load-bearing.** At init, γ ≡ 1 and β ≡ 0, so the FiLM layer is an identity map and the whole model behaves as a vanilla LSTM. This lets the FiLM generator *learn* conditioning during training rather than immediately destabilizing it. If we drop this and use default PyTorch init, training is likely to be unstable in early epochs.

### 3.3 Relation to EA-LSTM

| Property | EA-LSTM | FiLM-LSTM |
|---|---|---|
| Static control object | Pre-activation of input gate only | Pre-activation of all 4 gates |
| Static control form | Input gate replaced by a static-only path `σ(W_s · s + b_s)` | Affine modulation `γ ⊙ z + β` on each gate's pre-activation |
| Static contribution, time-varying? | No (constant i) | No (γ, β constant per sample) |
| Gate still in [0, 1]? | ✅ | ✅ (because FiLM acts before σ) |
| Bandwidth | O(H) | O(H) in γ and β, but covers 4 gates each |
| Does dynamic input feed input gate? | No | Yes |

**FiLM-LSTM is not a strict functional superset of EA-LSTM** (EA's input gate is static-only, FiLM's input gate receives x_t + h_t + FiLM). But the *expressivity* of FiLM-LSTM strictly covers EA-LSTM: any mapping EA-LSTM can represent, FiLM-LSTM can too. The paper framing uses "FiLM is a generalization of EA" rather than "EA is a special case of FiLM."

---

## 4. Components

| Component | Type | Path |
|---|---|---|
| `FiLMLSTM` model class | **new** | `neuralhydrology/modelzoo/filmlstm.py` |
| Modelzoo registry entry | **new (1 line)** | `neuralhydrology/modelzoo/__init__.py` |
| Config key `film_generator_hidden_size` | **new** | `neuralhydrology/utils/config.py` (optional; falls back to default 64 if missing) |
| Base FiLM config | **new** | `src/static_falsification/configs/base_filmlstm.yml` |
| Per-fold/seed FiLM configs (12 YAML) | **new** | `src/static_falsification/configs/film_fold{0,1}_seed{0,1,2}_{real,shuffle}.yml` |
| Per-fold/seed EA configs (12 YAML) | **new** | reuse `base_ealstm.yml` + generator script → `ealstm_fold{0,1}_seed{0,1,2}_{real,shuffle}.yml` |
| Shuffle dataset | **reuse** | `src/static_falsification/shuffled_dataset.py` |
| Fold splits | **reuse** | `src/static_falsification/data/fold{0,1}_*.txt` |
| HPC submission script | **new** | `src/static_falsification/hpc/submit_filmlstm_poc.slurm` |
| Config generator | **new** | `src/static_falsification/scripts/generate_film_poc_configs.py` |
| Analysis script | **new** | `src/static_falsification/scripts/analyze_film_poc.py` |
| Unit tests | **new** | `test/test_filmlstm.py` |

---

## 5. Data Flow

```
CAMELS-US (data/CAMELS_US/)
      │
      ├─ fold0_{train,validation,test}.txt   (PUB split, 383/42/106 basins)
      └─ fold1_{train,validation,test}.txt   (PUB split, different partition)
      │
      ▼
CamelsUS dataset
      ├─ (real static)    → direct feed to model
      └─ (shuffled static) → ShuffledDataset wrapper (shuffle_maps.json fixed per fold)
      │
      ▼
Model ∈ {EALSTM, FiLMLSTM}           ← 2×2 ablation main variable
      │
      ▼
Training (30 epochs, NSE loss, Adam 1e-3, seq_length=365)
      │
      ▼
Per-basin test NSE / KGE → runs/<run_dir>/test/test_results.p
      │
      ▼
analyze_film_poc.py
      ├─ Aggregate 24 runs
      ├─ Compute per-config median NSE across basins
      ├─ Compute ΔArch    = NSE(FiLM, real)   − NSE(EA, real)
      ├─ Compute ΔPhys_F  = NSE(FiLM, real)   − NSE(FiLM, shuffle)
      ├─ Compute ΔPhys_EA = NSE(EA, real)     − NSE(EA, shuffle)
      ├─ Per-fold breakdown + cross-fold consistency
      └─ Apply go/no-go thresholds → print verdict
```

---

## 6. Success Criteria — Pre-Registered (POC Threshold B)

**Go** if both conditions hold on the aggregated result:

1. **ΔArch ≥ +0.02** (median basin NSE improvement, averaged across folds and seeds)
2. **ΔPhys_FiLM > ΔPhys_EA** (FiLM utilizes physical info more than EA does)
3. **Folds don't contradict**: no fold shows ΔArch > +0.05 while the other shows ΔArch < −0.03 (sign and magnitude must be compatible)

**No-go / reconsider** if:
- ΔArch < 0 consistently → FiLM underperforms EA → architecture wrong or implementation bug
- ΔArch ≈ 0 and ΔPhys_FiLM ≈ ΔPhys_EA → FiLM changes nothing meaningful → bottleneck is in attribute source, not decoder
- ΔArch > 0 but ΔPhys_FiLM ≤ ΔPhys_EA → FiLM improved performance but not via physical info → ID memorization hypothesis gains weight

**This threshold is frozen before running.** Post-hoc lowering of thresholds for publication is p-hacking.

---

## 7. Error Handling and Numerical Stability

### 7.1 Handled

- **Early-training instability**: identity initialization of FiLM generator → epoch 0 ≡ vanilla LSTM. Verified by unit test.
- **Shuffle seed contamination**: use `shuffle_maps.json` fixed mapping per fold. Random seed for training does not affect which shuffle is applied. This separates "random static" variance from seed variance.
- **Gradient explosion**: inherit `clip_gradient_norm: 1.0` from base config.
- **NaN propagation monitoring**: log γ, β L2 norms + min/max per epoch to log file. Inspect during/after training; neuralhydrology's basetrainer halts on NaN loss but not on NaN intermediates, so manual inspection is the safety net for γ collapse.

### 7.2 Not handled (YAGNI)

- No grid search on `film_generator_hidden_size` — default 64.
- No depth tuning on FiLM generator MLP — fixed 2-layer (Linear → ReLU → Linear).
- No per-gate independent MLPs — single shared MLP with 4H-dim output.
- No alternative FiLM variants (post-activation, cell-state).

---

## 8. Testing Strategy

### 8.1 Unit tests (`test/test_filmlstm.py`)

1. **`test_identity_initialization`**: untrained FiLMLSTM forward output ≈ vanilla LSTM forward output (same weights, same input). Tolerance: `torch.allclose(..., atol=1e-5)`.
2. **`test_forward_shape`**: input dynamic `(B, T, D)`, static `(B, S)` → output `y_hat (B, T, 1)`, `h_n (B, T, H)`, `c_n (B, T, H)`.
3. **`test_gradient_flow`**: `loss.backward()` produces non-None gradients for every parameter (FiLM generator + LSTM core + head).

### 8.2 Smoke test

- Add FiLM-LSTM to existing `pytest --smoke-test` mechanism.
- Run: 100 basins × 3 epochs × FiLMLSTM + EALSTM, verify both finish without crashing.

### 8.3 Integration sanity

- fold0 + real static + 1 seed → full 30 epochs → NSE ≥ 0.55 (Heudorfer 2025 "EA_ablated" OOS baseline). Below this → implementation is likely broken.

---

## 9. Timeline

| Phase | Work | Duration |
|---|---|---|
| D1–D2 | Implement `filmlstm.py` + unit tests + local smoke test | 2 days |
| D3 | Generate 12 FiLM configs + HPC script + local 3-epoch short run | 1 day |
| D4 | Submit 24 jobs to HPC (2 folds × 3 seeds × 4 configs) | 0.5–1.5 days (HPC queue + ~4–8 h per run) |
| D5–D6 | Download results + `analyze_film_poc.py` + apply threshold B | 2 days |
| D7 | Write POC result memo → decide: upgrade to full 5-fold / pivot / stop | 1 day |

**Total: ~7 working days (≈1.5 calendar weeks).**

---

## 10. Decision Branches After POC

| POC Outcome | Next Action |
|---|---|
| **Pass threshold B** on both folds | Upgrade to full 5-fold × 5 seeds (100 runs), target HESS / JoH method paper with threshold A (stricter) |
| **Pass B on one fold only** | Investigate fold sensitivity (what differs across folds?), decide whether to add folds 2–4 as tie-breakers |
| **Fail with ΔArch < 0** | Debug implementation. If no bug → architecture likely wrong, pivot to alternatives (post-act FiLM as diagnostic, or shift focus to attribute source: remote sensing / finer catchment descriptors) |
| **Fail with ΔArch ≈ 0, ΔPhys_FiLM ≈ ΔPhys_EA** | Strong evidence that decoder is not the bottleneck. Write a short negative-result note, then pivot toward the "attribute-source-is-poor" hypothesis (Li 2022 line) |
| **ΔArch > 0 but ΔPhys_FiLM ≤ ΔPhys_EA** | Most interesting negative result — FiLM wins but via ID, not physics. Publishable as a cautionary methodological paper |

All 5 branches lead to publishable output of some form. This is **deliberately designed so the POC is not a gamble** — any outcome produces an actionable next step and a defensible writeup.

---

## 11. Journal Target (Realistic)

**Primary target:** HESS methods track, or JoH method paper.
**Not suitable for:** WRR Tier-1 or Nature MI — not a paradigm-level innovation (Hypernet in time series is already occupied, dPL already covers regionalized parameterization of process models).
**Narrative pitch:** *"We show that widening the static-to-dynamics decoding channel, via a FiLM layer on LSTM gate pre-activations, is necessary but not sufficient for LSTMs to use catchment attributes as physical information rather than basin identity."*

---

## 12. Open Questions to Revisit After POC

- Whether to add Factor Hypernet-LSTM as a third rung of the ablation ladder (currently excluded from POC scope).
- Whether to add random-Gaussian static (RNDint) as a second ablation beyond shuffled-real (RNDreal).
- Whether to cross-check on a second dataset (CAMELS-GB, CAMELS-BR, Caravan subset) after POC.
- Whether per-gate independent FiLM generators would help if single-MLP version shows signs of under-parameterization.
