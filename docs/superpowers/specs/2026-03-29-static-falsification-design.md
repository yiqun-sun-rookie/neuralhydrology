# Static Attribute Falsification — Design Spec

## Metadata

- **Idea ID**: 11
- **Slug**: `static_falsification`
- **Date**: 2026-03-29
- **Target journal**: WRR / HESS
- **Title direction**: "Do LSTM Rainfall-Runoff Models Actually Use Static Catchment Attributes? A Falsification Study via Attribute Permutation"

## 1. Research Question & Hypotheses

**Core question**: Does the EALSTM actually extract meaningful physical information from static catchment attributes, or does it merely use them as basin identifiers or ignore them entirely?

**H0 (null)**: EALSTM's input gate extracts physically meaningful information from static attributes; shuffling attributes across basins causes significant performance degradation.

**H1 (alternative)**: EALSTM performance does not significantly degrade after attribute shuffling, indicating the model does not depend on the physical content of static attributes.

## 2. Experimental Design

### 2.1 Experiment Matrix

| ID | Train static | Test static | Variable name | Models to train |
|----|-------------|-------------|---------------|-----------------|
| E1 | Correct | Correct | baseline | 5 (5-fold) |
| E2 | Correct | Shuffled | test_shuffle | 0 (reuse E1) |
| E3 | Shuffled | Shuffled (same mapping) | train_shuffle | 5 |
| E4 | Constant (global mean) | Constant | no_static | 5 |

**Total**: 15 trained models + 5 zero-cost E2 evaluations.

### 2.2 Key Comparisons

- **E1 vs E2**: Does the model depend on static attributes at inference time?
- **E1 vs E4**: How much information gain do static attributes provide?
- **E3 vs E4**: Can random static attributes serve as basin encoding?
- **E1 vs E3**: Correct physical information vs. wrong physical information?

## 3. Data & Splits

### 3.1 Dataset

CAMELS-US, 531 basins.

### 3.2 Time Periods (aligned with Kratzert 2019 HESS)

- Train: 1999-10-01 to 2008-09-30
- Validation: 1980-10-01 to 1989-09-30
- Test: 1989-10-01 to 1999-09-30

### 3.3 Static Attributes

27 standard CAMELS attributes, z-score normalized using training set statistics.

### 3.4 5-Fold PUB Split

- 531 basins randomly partitioned into 5 groups (~106 basins/fold)
- Each fold: 4 groups for training (~425 basins), 1 group for testing (~106 basins, completely unseen)
- 10% of training basins held out for validation (early stopping)
- Fixed random seed for reproducibility

### 3.5 Shuffle Mechanism

- Generate a fixed-point-free permutation pi per fold: basin_i -> basin_pi(i)
- E2: at test time, replace basin_i's static with basin_pi(i)'s static
- E3: use the same pi mapping for both training and testing
- Constraint: pi has no fixed points (every basin gets a "wrong" static vector)
- Different pi per fold to avoid lucky matches

### 3.6 E4 Constant Static

- All basins receive the global mean static vector from the training set
- After z-score normalization this is the all-zeros vector

## 4. Model & Training

### 4.1 Architecture

EALSTM (Entity-Aware LSTM) from neuralhydrology, chosen because its input gate is explicitly designed to modulate based on static attributes (Kratzert et al. 2019 HESS).

### 4.2 Hyperparameters (aligned with Kratzert 2019 HESS)

- hidden_size: 256
- Dynamic inputs: 5 DAYMET forcing variables (prcp, srad, tmax, tmin, vp)
- static_attributes: 27 CAMELS attributes
- seq_length: 365
- batch_size: 256
- epochs: 30
- optimizer: Adam, lr=1e-3
- loss: NSE loss
- clip_gradient_norm: 1.0
- early_stopping: patience=10, based on validation median NSE

### 4.3 Training Budget

- 15 models total (3 conditions x 5 folds)
- ~4h per model on GPU
- HPC parallel: wall-clock ~12h (3 rounds of 5 parallel jobs)

### 4.4 Reproducibility

- Fixed global random seeds (numpy, torch, python)
- Saved artifacts: 5-fold split files, per-fold shuffle mapping pi, all config YAMLs

## 5. Evaluation & Statistics

### 5.1 Metrics

- **NSE** (primary): per-basin, report 5-fold aggregated median
- **KGE** (auxiliary): same aggregation
- Per-basin NSE distributions across folds (box plots)

### 5.2 Evaluation Scenarios

- **PUB** (held-out ~106 basins per fold): core result
- **Temporal** (training basins on test period): auxiliary reference

### 5.3 Statistical Tests

- Paired Wilcoxon signed-rank test on per-basin NSE (531 paired samples)
- Key comparisons: E1 vs E2, E1 vs E4, E3 vs E4
- Significance threshold alpha=0.05, Bonferroni correction (3 comparisons -> alpha=0.017)

### 5.4 Core Figures & Tables

| ID | Content | Type |
|----|---------|------|
| Fig 1 | E1-E4 PUB NSE box plots | Main figure |
| Fig 2 | E1 vs E2 per-basin NSE scatter (diagonal = no difference) | Main figure |
| Fig 3 | Stratified E1 vs E2 by basin type (snow/arid/humid) | Analysis figure |
| Table 1 | 4 experiments x {PUB, Temporal} median NSE/KGE + p-values | Main table |

### 5.5 Interpretation Criteria

| Result | E1 vs E2 (temporal) | E1 vs E2 (PUB) | Conclusion |
|--------|---------------------|-----------------|------------|
| Both no drop | LSTM ignores static | Static useless for generalization | **Strong falsification** |
| Temporal no drop, PUB drops | Not needed for gauged | Needed for ungauged | Static only useful for PUB (expected) |
| Both drop | Model depends on static | Static aids generalization | Falsification fails (still valuable confirmation) |

## 6. Code Architecture

### 6.1 Project Scaffold

```
src/static_falsification/
    configs/
        base_ealstm.yml              # shared hyperparameters template
        ealstm_e1_fold{0-4}.yml      # E1: correct static
        ealstm_e3_fold{0-4}.yml      # E3: shuffled static
        ealstm_e4_fold{0-4}.yml      # E4: constant static
    scripts/
        generate_splits.py            # 5-fold basin split + shuffle mapping pi
        generate_configs.py           # batch-generate 15 configs from template
        run_training.py               # batch training entry (calls nh_run train)
        run_eval_e2.py                # E2: load E1 model, replace static, evaluate
        analyze_results.py            # aggregate metrics, stats tests, figures
    hpc/
        submit_all.slurm              # master submission script
        submit_fold.slurm             # per-fold template
    data/
        fold_splits.json              # 5-fold basin groups
        shuffle_maps.json             # per-fold pi mappings
```

### 6.2 Shuffle Injection (Key Implementation)

Subclass `CamelsUS` to remap `self._attributes[basin]` after loading. No modification to neuralhydrology core code.

```python
class ShuffledStaticDataset(CamelsUS):
    def __init__(self, cfg, shuffle_map, ...):
        super().__init__(cfg, ...)
        self._apply_shuffle(shuffle_map)

    def _apply_shuffle(self, shuffle_map):
        original = dict(self._attributes)
        for basin, target in shuffle_map.items():
            self._attributes[basin] = original[target]
```

E4: same subclass, assign all-zeros vector to every basin.

### 6.3 E2 Evaluation

Load E1 checkpoint, construct `ShuffledStaticDataset`, run `RegressionTester` from neuralhydrology.

### 6.4 Isolation

All changes contained within `src/static_falsification/`. Zero modifications to `neuralhydrology/` core package.

## 7. Literature Context

| Paper | What they did | Gap this fills |
|-------|--------------|----------------|
| Kratzert 2019 WRR | with/without static binary comparison | No shuffle/mismatch test |
| Kratzert 2019 HESS (EALSTM) | Designed input gate for static; added noise to static | Noise perturbation, not full shuffle |
| Lees 2022 HESS | Shuffled hidden states across basins | Probed internal states, not input attributes |
| Bayati 2026 WRR | Found LSTM misattributes T/PET roles | Functional realism, not static attribute utility |
| Nearing 2024 Nature | Global LSTM + HydroATLAS static, no ablation | Never tested static attribute contribution |

**This work**: First systematic falsification test of whether EALSTM extracts physical information from static attributes, using attribute permutation across basins.

## 8. Risk & Mitigation

| Risk | Mitigation |
|------|-----------|
| E1 ≈ E2 only because EALSTM learns to ignore static during training | E3 vs E4 comparison isolates this: if E3 > E4, random static still provides signal |
| Shuffle accidentally preserves hydro-similarity | Fixed-point-free permutation + different pi per fold |
| Results only hold for CAMELS-US | Acknowledge as limitation; Caravan extension as future work |
| EALSTM with constant static degenerates poorly | Constant = global mean (zeros after normalization) is the most neutral choice |
