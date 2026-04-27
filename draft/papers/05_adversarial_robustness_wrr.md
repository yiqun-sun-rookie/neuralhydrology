# Attack-Method Choice Changes Robustness Conclusions for a Standard LSTM Rainfall-Runoff Model

**Target Journal**: Water Resources Research

**Canonical source**: `draft/papers/05_adversarial_latex/main.tex`

**Status**: synchronized to the audited 531-basin epoch020 rerun. This Markdown file is a compact working summary only; use the LaTeX manuscript and SI for submission text.

---

## Abstract

Deep learning models, particularly Long Short-Term Memory (LSTM) networks, have demonstrated strong predictive skill in rainfall-runoff modeling. As these models move toward operational deployment, their robustness to input uncertainty becomes a critical concern. Yet existing assessments often rely on random noise or single-step adversarial methods (FGSM), which may underestimate worst-case vulnerability. Here we present a multi-level adversarial stress test of a 531-basin CAMELS-US temporal benchmark LSTM, employing a spectrum of perturbation methods from random noise through iterative optimization (Auto-PGD), three constraint levels of increasing plausibility, and targeted attacks on flood and pre-event windows. These perturbations are not intended to reproduce the empirical distribution of real-world forcing errors; rather, they serve as constrained worst-case stress tests within observation-error-scale uncertainty budgets.

At epsilon = 0.1, Auto-PGD causes a median NSE degradation of 0.408 across 514 finite basin metrics, compared to 0.023 for Gaussian noise, an adversarial-to-random ratio of 17.5:1. FGSM gives a similar but weaker median degradation of 0.358. Under Auto-PGD, 167 of 514 finite basins (32.5%) fall below NSE = 0. Perturbations that preserve input-feature means and standard deviations still cause substantial degradation (median delta-NSE = -0.193), showing that routine quality-control checks cannot detect all harmful input-error patterns.

## Key Points

1. Iterative adversarial perturbations reveal 17.5x greater median vulnerability than Gaussian random noise for the 531-basin benchmark LSTM at epsilon = 0.1.
2. The rerun covers 531 basin IDs, while NSE headline statistics use 514 finite basin metrics because 17 low-variance basins yield NaN NSE/delta-NSE.
3. Statistically constrained perturbations remain harmful, with median delta-NSE = -0.193 at epsilon = 0.1.

## Provenance

- Victim model: `results/05_adversarial_robustness/runs/reproduce_531_nse074_2025_1129_2145_ep30`
- Pinned checkpoint: `model_epoch020.pt`
- Adversarial config: `src/adversarial/configs/full_eval_531_epoch020.yaml`
- Basin list: `src/adversarial/data/531_basins.txt`
- Output root: `results/adversarial_eval/531_epoch020`
- Exp 1 merge: `results/adversarial_eval/531_epoch020/merged_exp1.json`
- Full merge: `results/adversarial_eval/531_epoch020/merged_all.json`
- Provenance note: `results/adversarial_eval/531_epoch020/README_provenance.txt`
- Decision note: `results/adversarial_eval/531_epoch020/RESULT_DIFF_NOTE.txt`

The full merged suite contains 17,523 unique experiment records across 531 unique basin IDs. Coverage checks passed for all 37 expected experiment cells. Smoke/debug files were excluded from the final merge.

## Target Model

The target model is a local reproduction of the Kratzert-style 531-basin CAMELS-US temporal benchmark. The same 531 basin list is used for training, validation, and testing with disjoint periods:

- Training: 1990-10-01 to 1995-09-30
- Validation: 1995-10-01 to 2000-09-30
- Test: 2000-10-01 to 2005-09-30

Model configuration:

- Architecture: LSTM (single-layer)
- Hidden size: 128
- Dynamic inputs: 5 Daymet variables
- Static attributes: 14 CAMELS attributes
- Optimizer: AdamW
- Loss: NSE
- Training epochs: 30
- Adversarial checkpoint: epoch 20

This is a 531 temporal benchmark result line, not the previous 520/674 spatial-split result line.

## Finite NSE Handling

All adversarial experiment blocks cover 531 basin IDs. NSE medians and IQRs use 514 finite basin metrics because 17 basin IDs yield NaN `nse_clean`, `nse_adv`, and `delta_nse`.

NaN basin IDs:

`04127997, 05120500, 06350000, 06404000, 06406000, 06409000, 06431500, 06447500, 06847900, 07142300, 07299670, 07301410, 08324000, 09306242, 09386900, 09447800, 09484600`

The raw streamflow and Daymet files exist for these basins, and the raw test-period streamflow records are complete. The NaN values arise because no candidate evaluation window satisfies the finite-metric guard: more than 100 valid observations and normalized observed-flow standard deviation greater than 0.1.

## Experiment Blocks

- Exp 1: attack comparison, 5 attacks x 4 epsilons x 531 basin IDs.
- Exp 2: constraint ablation, Auto-PGD x 3 constraints x 3 epsilons x 531 basin IDs.
- Exp 3: targeted attacks, Auto-PGD x 3 targets at epsilon = 0.1 x 531 basin IDs.
- Exp 4: causal trigger, 4 pre-event windows at epsilon = 0.1 x 531 basin IDs.
- Exp 5: C&W regression, epsilon = 0.1 x 531 basin IDs.

## Headline Results

### Exp 1: Attack Comparison

Median delta-NSE [Q25, Q75] over 514 finite basin metrics.

| Method | epsilon = 0.01 | epsilon = 0.05 | epsilon = 0.1 | epsilon = 0.2 |
|---|---:|---:|---:|---:|
| Auto-PGD | -0.026 [-0.044, -0.016] | -0.163 [-0.282, -0.092] | -0.408 [-0.731, -0.225] | -1.162 [-2.298, -0.567] |
| FGSM | -0.026 [-0.043, -0.016] | -0.154 [-0.267, -0.088] | -0.358 [-0.640, -0.194] | -0.824 [-1.672, -0.436] |
| Gaussian | -0.002 [-0.003, -0.001] | -0.010 [-0.018, -0.006] | -0.023 [-0.039, -0.012] | -0.054 [-0.095, -0.028] |
| Multiplicative bias | -0.001 [-0.003, -0.001] | -0.007 [-0.016, -0.003] | -0.015 [-0.035, -0.007] | -0.033 [-0.080, -0.016] |
| Temporal correlated noise | -0.002 [-0.003, -0.001] | -0.008 [-0.015, -0.004] | -0.016 [-0.031, -0.009] | -0.037 [-0.067, -0.020] |

APGD/Gaussian median ratios:

- epsilon = 0.01: 13.0x
- epsilon = 0.05: 15.6x
- epsilon = 0.1: 17.5x
- epsilon = 0.2: 21.6x

At epsilon = 0.1, APGD is 1.14x stronger than FGSM by median delta-NSE. FGSM is therefore a useful screen, but random-noise sensitivity analysis is the larger underestimation problem.

### Vulnerability

For Auto-PGD at epsilon = 0.1:

- Median delta-NSE: -0.408
- 10th percentile delta-NSE: -1.51
- 90th percentile delta-NSE: -0.12
- Adversarial NSE below zero: 167/514 finite basins (32.5%)
- Strict severe degradation delta-NSE < -1: 90/514 finite basins (17.5%)

### Exp 2: Constraint Ablation

Median (mean) delta-NSE over 514 finite basin metrics.

| Constraint | epsilon = 0.05 | epsilon = 0.1 | epsilon = 0.2 |
|---|---:|---:|---:|
| Lp | -0.163 (-0.278) | -0.408 (-0.713) | -1.162 (-2.169) |
| Physical | -0.148 (-0.226) | -0.370 (-0.622) | -1.083 (-1.991) |
| Statistical | -0.083 (-0.113) | -0.193 (-0.258) | -0.459 (-0.633) |

### Exp 3: Targeted Attacks

Median [Q25, Q75]. Delta-NSE uses 514 finite basin metrics; delta-KGE uses 531 basin IDs.

| Target | delta-NSE | delta-KGE |
|---|---:|---:|
| Untargeted | -0.408 [-0.731, -0.225] | -0.380 [-0.819, -0.133] |
| Flood | -0.332 [-0.602, -0.182] | -0.344 [-0.716, -0.132] |
| Low-flow | -0.021 [-0.092, 0.003] | -0.049 [-0.236, 0.024] |

### Exp 4: Causal Trigger

Median delta-NSE over 514 finite basin metrics:

| Pre-event window | Median delta-NSE |
|---:|---:|
| 1 day | -0.011 |
| 3 days | -0.028 |
| 7 days | -0.050 |
| 14 days | -0.085 |

### Exp 5: C&W Regression

- Basin IDs evaluated: 531
- Non-negligible solutions using L2 > 0.01: 369/531 (69.5%)
- Median minimum L2 among non-negligible solutions: 1.244
- Near-zero cases: 162/531
- Median delta-NSE over finite metrics: -0.174

## Figures

The LaTeX figure directory has been synchronized from `results/adversarial_eval/531_epoch020/figures`:

- `fig1_epsilon_curve.pdf`
- `fig2_basin_vulnerability.pdf`
- `fig3_causal_window.pdf`
- `fig4_cw_perturbation.pdf`
- `fig5_detectability.pdf`

Old attribution/static-ablation figures are not used in the 531 manuscript because they were not regenerated for this audited result line.

## Current Interpretation

The 531 result line is technically defensible for the paper. The main claim survives, but its emphasis changes:

- Strongest supported claim: gradient-based attacks reveal much larger vulnerability than random/noise-like perturbations.
- Weaker than the old 520 line: Auto-PGD is only modestly stronger than FGSM at epsilon = 0.1.
- Still important: iterative Auto-PGD remains the conservative check and becomes more separated from FGSM at larger epsilon.
- Required wording: say "531 basin IDs covered; NSE headlines over 514 finite basin metrics."

## References

Use `draft/papers/05_adversarial_latex/references.bib` as the canonical bibliography.
