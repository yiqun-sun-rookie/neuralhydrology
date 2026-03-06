# Adversarial Robustness Assessment of LSTM-based Streamflow Prediction

**Date**: 2026-03-05
**Status**: Design Approved
**Scope**: Phase 1 — CudaLSTM only, no DA/KalmanNet

## 1. Motivation

Yang et al. (2026) published the first adversarial robustness study on hydrological models using FGSM on 1347 German catchments. Key gaps:

- Only FGSM (weakest single-step attack)
- Only untargeted attacks
- Only Lp-norm constraints (no physical/statistical constraints)
- No temporal structure exploitation
- No cross-basin universal attacks

We propose a comprehensive 6-method attack framework with 3-tier constraints.

## 2. Target Model

- **Model**: neuralhydrology CudaLSTM (hidden_size=128)
- **Dataset**: CAMELS-US, 10-20 representative basins
- **Input**: 5 dynamic features (prcp, srad, tmax, tmin, vp) + 13 static attributes
- **Sequence**: 365 days
- **Output**: streamflow (mm/d), single target
- **Checkpoint**: existing trained model in neuralhydrology/runs/

### Input batch structure:
```python
{
    'x_d': {feature_name: [B, 365]},  # 5 dynamic features, z-score normalized
    'x_s': [B, 13],                    # 13 static attributes, z-score normalized
    'y':   [B, 365, 1],               # observed streamflow
}
```

## 3. Attack Framework: 3 Axes × 6 Methods

```
Axis 1: Strength          Axis 2: Temporal         Axis 3: Stealth
┌─────────────┐          ┌─────────────┐          ┌─────────────────┐
│ A. Auto-PGD │          │ C. Sparse   │          │ E. Spectral     │
│ B. C&W-Reg  │          │ D. Causal   │          │ F. Dist-Preserv │
└─────────────┘          └─────────────┘          └─────────────────┘
  "How strong             "Where is the             "Can it evade
   to break it?"           weakest point?"           detection?"
```

### A. Auto-PGD (Baseline — existing method, upgraded from Yang's FGSM)

Multi-step PGD with adaptive step size. Replaces Yang's single-step FGSM.

```
Input: x = [P, Tmax, Tmin, srad, vp], shape [B, 365, 5]
Objective: max L_NSE(model(x + δ), y_obs)
Constraint: ||δ||_∞ ≤ ε, physical projection (P≥0, T reasonable)
Method: Auto-PGD with adaptive step size, k=50 iterations
ε sweep: 0.01, 0.02, 0.05, 0.1, 0.2, 0.5 (in normalized space)
```

### B. C&W-Regression (Adapted — minor innovation)

Find **minimum perturbation** to break the model. Adapted from C&W classification to regression.

```
min ||δ||₂ + c · max(0, NSE(model(x+δ), y) - τ)
where τ = target NSE threshold (e.g., 0.0)
```

Answers: "How small a perturbation suffices to make NSE < 0?"

### C. Sparse Temporal Attack (Original)

Learn which timesteps to perturb via differentiable binary mask.

```
max L(model(x + m ⊙ δ), y)
s.t. ||m||₀ ≤ k (at most k timesteps perturbed)
     ||δ||_∞ ≤ ε
```

Use Gumbel-Softmax relaxation for m. Key question: how few days out of 365 break the full-year prediction?

### D. Causal Trigger Attack (Original — core innovation)

Perturb only w days **before** a target event (flood peak), exploiting LSTM memory propagation.

```
Perturbation window: [t_peak - w, t_peak)   # w days before flood
Target window:       [t_peak, t_peak + d]    # flood period

max L(model(x + δ), y)  over target window only
s.t. δ non-zero only in perturbation window
```

Simulates: attacker tampers weather station data before a storm, causing flood warning failure.

Analysis: w vs attack success → LSTM "memory vulnerability half-life".

### E. Spectral Attack (Original)

Perturb in frequency domain, preserving time-domain statistics.

```
X_freq = FFT(x)
δ_freq = optimized frequency-domain perturbation (specific bands)
x_adv = IFFT(X_freq + δ_freq)

Guarantee: mean(x_adv) ≈ mean(x), std(x_adv) ≈ std(x)
```

Key question: which frequency components is the LSTM most sensitive to?

### F. Universal Adversarial Perturbation — UAP (Cross-domain transfer)

One fixed perturbation pattern δ* that works across all basins and all time periods.

```
δ* = argmax_δ  E_{x~D} [L(model(x + δ), y)]
s.t. ||δ||_∞ ≤ ε
```

Optimize on training set, evaluate on test set. If high success rate → LSTM has universal vulnerability patterns.

## 4. Three-Tier Constraint Hierarchy

Each method tested under three constraint levels:

| Level | Constraint | Meaning |
|:------|:-----------|:--------|
| L1: Lp-norm | `‖δ‖_∞ ≤ ε` | Pure math, comparable to CV literature |
| L2: Physical | L1 + P≥0, T∈[-40,50]°C, srad≥0, reasonable daily range | Physically plausible perturbation |
| L3: Statistical | L2 + preserve mean/var/autocorrelation, KS-test p>0.05 | Passes standard QC checks |

## 5. Attack Targets

### Untargeted
```python
L_untargeted = -NSE(y_pred, y_obs)  # maximize global error
```

### Targeted — Flood peaks
```python
mask_high = y_obs > Q90(y_obs)
L_flood = -NSE(y_pred[mask_high], y_obs[mask_high])
```

### Targeted — Low flow
```python
mask_low = y_obs < Q10(y_obs)
L_lowflow = -NSE(y_pred[mask_low], y_obs[mask_low])
```

## 6. Evaluation Metrics

| Metric | Description |
|:-------|:------------|
| ΔNSE | NSE degradation (primary) |
| ΔKGE | KGE degradation |
| ASR | Attack Success Rate: fraction of basins where NSE < 0 |
| min-ε | Minimum perturbation for NSE < 0 (from C&W) |
| Sparse ratio | % of timesteps perturbed (methods C/D) |
| Detectability | KS-test p-value (higher = harder to detect) |
| Peak error | Absolute/relative flood peak error (targeted attacks) |

## 7. Experiment Matrix

```
6 methods × 3 constraint levels × 3 targets × 6 ε values × 10-20 basins
≈ 3240 experiments
```

Each experiment: forward + backward pass iterations (seconds-level). Total compute manageable on single GPU.

## 8. Expected Figures & Tables

| ID | Content |
|:---|:--------|
| Fig 1 | Attack framework diagram (3 axes, 6 methods) |
| Fig 2 | ε vs ΔNSE curves (6 methods compared, including FGSM reproduction of Yang) |
| Fig 3 | ASR under three constraint tiers (L1/L2/L3 bar chart) |
| Fig 4 | Sparse Temporal: heatmap of most vulnerable timesteps |
| Fig 5 | Causal Trigger: window w vs flood peak error amplification |
| Fig 6 | UAP visualization: universal vulnerability pattern in time/frequency |
| Fig 7 | Spectral: LSTM frequency sensitivity analysis |
| Fig 8 | Basin characteristics vs vulnerability scatter/correlation |
| Table 1 | Full result matrix: 6 methods × 3 constraints × 3 targets |

## 9. Code Structure

```
src/adversarial/
├── __init__.py
├── attacks/
│   ├── __init__.py
│   ├── base.py              # BaseAttack ABC
│   ├── auto_pgd.py          # A. Auto-PGD
│   ├── cw_regression.py     # B. C&W-Regression
│   ├── sparse_temporal.py   # C. Sparse Temporal
│   ├── causal_trigger.py    # D. Causal Trigger
│   ├── spectral.py          # E. Spectral Attack
│   └── uap.py               # F. Universal Adversarial Perturbation
├── constraints/
│   ├── __init__.py
│   ├── lp_norm.py           # L1: Lp-norm projection
│   ├── physical.py          # L2: Physical feasibility projection
│   └── statistical.py       # L3: Distribution-preserving projection
├── evaluation/
│   ├── __init__.py
│   ├── metrics.py           # ΔNSE, ΔKGE, ASR, detectability
│   └── basin_selection.py   # Select 10-20 representative basins
├── model_wrapper.py          # Wrap neuralhydrology CudaLSTM for attack interface
└── config.py                 # Attack experiment configuration
scripts/
├── run_adversarial_eval.py   # Main entry point
└── plot_adversarial_results.py
configs/
└── adversarial_eval.yaml     # Experiment config (ε values, basins, methods)
```

## 10. Model Wrapper Interface

```python
class CudaLSTMWrapper:
    """Wraps neuralhydrology CudaLSTM for adversarial attack interface."""

    def __init__(self, run_dir: Path, device: str = 'cuda'):
        # Load config, model, scaler from run_dir
        ...

    def forward(self, x_d: Tensor, x_s: Tensor) -> Tensor:
        """
        Args:
            x_d: [B, T, 5] dynamic features (normalized)
            x_s: [B, 13] static attributes (normalized)
        Returns:
            y_hat: [B, T, 1] streamflow predictions (normalized)
        """
        ...

    def forward_real(self, x_d: Tensor, x_s: Tensor) -> Tensor:
        """Same as forward but returns real-scale streamflow (mm/d)."""
        ...

    def get_scaler(self) -> dict:
        """Return normalization scaler for denormalization."""
        ...
```

## 11. Base Attack Interface

```python
class BaseAttack(ABC):
    """Abstract base class for all adversarial attacks."""

    def __init__(self, model: CudaLSTMWrapper, constraint: BaseConstraint,
                 target: str = 'untargeted', epsilon: float = 0.1):
        ...

    @abstractmethod
    def attack(self, x_d: Tensor, x_s: Tensor, y_obs: Tensor) -> Tensor:
        """
        Generate adversarial perturbation.

        Returns:
            x_d_adv: [B, T, 5] perturbed dynamic features
        """
        ...

    def evaluate(self, x_d: Tensor, x_d_adv: Tensor,
                 x_s: Tensor, y_obs: Tensor) -> dict:
        """Compute all evaluation metrics."""
        ...
```

## 12. Basin Selection Strategy

Select 10-20 basins from CAMELS-US 531 to cover:
- Climate diversity: arid, semi-arid, humid, snow-dominated
- Size diversity: small (<100 km²) to large (>10,000 km²)
- Performance diversity: high-NSE and low-NSE basins under clean input
- Hydrological regime: rain-dominated, snowmelt, mixed

Use k-medoids clustering on static attributes to select representative basins.

## 13. Differentiation from Yang et al. (2026)

| Dimension | Yang et al. | Ours |
|:----------|:------------|:-----|
| Attack methods | 1 (FGSM) | 6 (incl. 3 original) |
| Attack targets | Untargeted only | Untargeted + Targeted (flood/low-flow) |
| Constraints | Lp-norm only | 3-tier: Lp → Physical → Statistical |
| Temporal structure | Uniform perturbation | Sparse + Causal trigger |
| Cross-basin | Per-basin independent | UAP (universal pattern) |
| Dataset | CAMELS-DE (1347) | CAMELS-US (10-20 representative) |
| Core innovation | Scale | Depth (attack diversity & constraint hierarchy) |
