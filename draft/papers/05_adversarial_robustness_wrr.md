# How Fragile Are LSTM Rainfall-Runoff Models? A Multi-Level Adversarial Robustness Assessment

**Target Journal**: Water Resources Research

---

## Abstract

Deep learning models, particularly Long Short-Term Memory (LSTM) networks, have demonstrated remarkable predictive skill in rainfall-runoff modeling. As these models move toward operational deployment, their robustness to input uncertainty becomes a critical concern. Yet existing assessments rely on random noise or single-step adversarial methods (FGSM), which may underestimate worst-case vulnerability. Here we present a multi-level adversarial stress test of a CudaLSTM model across 520 CAMELS-US catchments, employing a spectrum of perturbation methods from random noise through iterative optimization (Auto-PGD), three constraint levels of increasing plausibility, and targeted attacks on flood and pre-event windows. We find that LSTM rainfall-runoff models are substantially more fragile than conventional testing suggests: at observation-error-scale perturbation budgets (epsilon = 0.1), Auto-PGD causes a median NSE degradation of 0.59, compared to 0.03 for random noise — an adversarial-to-random ratio of 21:1. Nearly one-third of catchments (32.5%) experience catastrophic performance loss (delta-NSE < -1) under iterative attack. Furthermore, perturbations that preserve the statistical properties of input features (mean and standard deviation) still cause significant degradation (median delta-NSE = -0.35), suggesting that standard quality-control procedures cannot detect all harmful input error patterns. These results demonstrate that robustness assessment for deployment-critical hydrological models requires multi-level stress testing: random noise and single-step adversarial methods substantially underestimate the vulnerability that iterative attacks reveal.

**Key Points**:
1. Iterative adversarial perturbations (Auto-PGD) reveal 1.5x greater LSTM vulnerability than single-step attacks (FGSM) and 21x greater than random noise at observation-error-scale budgets.
2. One-third of 520 CAMELS-US catchments experience catastrophic performance loss (delta-NSE < -1) under iterative attack at epsilon = 0.1, a proportion not apparent from FGSM-based assessment.
3. Statistically undetectable perturbations — preserving input feature means and standard deviations — still degrade model performance significantly, eluding standard quality-control checks.

---

## 1. Introduction

Long Short-Term Memory (LSTM) networks have transformed hydrological prediction over the past decade. Beginning with the pioneering work of Kratzert et al. (2018), deep learning models have consistently matched or exceeded the performance of process-based hydrological models on standardized benchmarks such as CAMELS (Addor et al., 2017), achieving median Nash-Sutcliffe Efficiency (NSE) values above 0.7 across hundreds of catchments (Kratzert et al., 2019; Gauch et al., 2021). These advances have catalyzed growing interest in deploying LSTM-based models in operational forecasting systems (Nearing et al., 2021).

As deployment moves forward, a fundamental question demands attention: how reliable are these models when confronted with imperfect input data? In practice, meteorological forcings are never exactly known. Rain gauge measurements carry systematic biases of 5–15% (Sevruk, 1982; Groisman & Legates, 1994). Gridded products such as Daymet, ERA5, and CHIRPS introduce additional uncertainty through spatial interpolation, with temperature errors of 1–2 °C and precipitation errors that can exceed 2 mm/day in complex terrain (Thornton et al., 2021; Hersbach et al., 2020). Sensor drift, data transmission failures, and quality-control artifacts further contribute to input noise. If model predictions are highly sensitive to such perturbations, then predictive accuracy on clean benchmarks may overstate operational reliability.

The conventional approach to testing input sensitivity — adding random Gaussian noise — provides a measure of average-case robustness. However, random perturbations explore the input space isotropically and are unlikely to find the directions of maximum sensitivity. Adversarial robustness analysis, borrowed from the machine learning security literature (Goodfellow et al., 2015; Madry et al., 2018), offers a more systematic alternative: by using gradient information to identify the input perturbation that maximizes prediction error within a given budget, adversarial methods provide a lower bound on worst-case performance.

Yang et al. (2026) applied adversarial robustness analysis to hydrological models using the Fast Gradient Sign Method (FGSM; Goodfellow et al., 2015), evaluating LSTM and HBV models across 1,347 German catchments from the CAMELS-DE dataset. Their findings were encouraging: LSTMs demonstrated greater robustness than HBV models (median delta-KGE of -0.105 vs. -0.164 at epsilon = 0.2), catastrophic failure was rare, and model responses scaled approximately linearly with perturbation magnitude.

However, FGSM is a single-step attack that computes the perturbation direction from a single gradient evaluation and takes a maximally sized step in the sign direction. While computationally efficient, it is well established in the adversarial machine learning literature that single-step methods systematically overestimate model robustness. Iterative methods such as Projected Gradient Descent (PGD; Madry et al., 2018) and Auto-PGD (Croce & Hein, 2020) refine the perturbation over multiple optimization steps, consistently finding more effective adversarial examples. The gap between single-step and iterative attacks is not merely quantitative — it can qualitatively change conclusions about whether a model is "robust" or "vulnerable" (Carlini et al., 2019). Yang et al. themselves acknowledged this limitation, noting the need for "additional test scenarios and perturbation methods."

This raises a fundamental question: **how fragile are LSTM rainfall-runoff models when subjected to systematic, multi-level adversarial stress testing?**

To answer this question, we construct a multi-level adversarial stress-testing framework and apply it to a CudaLSTM model across 520 CAMELS-US catchments. The framework comprises three components: (i) a *perturbation spectrum* spanning five methods of increasing optimization strength — from random noise through single-step FGSM to iterative Auto-PGD; (ii) a *constraint hierarchy* controlling perturbation plausibility, including a statistical constraint that preserves input feature means and standard deviations; and (iii) *operationally motivated analyses* — a Carlini-Wagner (C&W) attack quantifying the minimum perturbation to break the model, targeted flood/low-flow attacks, and a causal trigger analysis restricting perturbations to pre-event windows.

While Yang et al. (2026) focused on comparing model architectures (LSTM vs. HBV) under a single attack method, our study takes a complementary perspective: we fix the model and systematically vary the attack, asking how much the strength and structure of the stress test affect the conclusions drawn about model robustness.

---

## 2. Methods

### 2.1 Study Area and Target Model

We evaluate a CudaLSTM model (Kratzert et al., 2018) implemented in the neuralhydrology framework (Kratzert et al., 2022). The model uses a single-layer LSTM with 128 hidden units, trained for 50 epochs on the CAMELS-US dataset (Newman et al., 2015; Addor et al., 2017) with five dynamic input features from the Daymet forcing product: precipitation (mm/day), shortwave radiation (W/m^2), maximum temperature (°C), minimum temperature (°C), and vapor pressure (Pa). No static catchment attributes are used. The model is evaluated on the held-out test period (1 October 2008 to 30 September 2014), with predictions generated for 520 catchments that have sufficient data coverage.

This configuration represents one of the most widely used benchmark setups in the hydrological deep learning literature, enabling direct comparison with prior work. Since the model uses no static catchment attributes, it learns a single set of LSTM weights shared across all catchments — predictions depend solely on the dynamic input sequence, not on catchment identity. The primary adversarial evaluation uses 520 catchments from the model's training basin split. Because the model shares a single set of weights across all catchments (no per-basin parameters), there is no in-sample advantage that would inflate vulnerability estimates. We verified this by running Auto-PGD on the 67 validation and 68 test basins: the median delta-NSE across splits is -0.49 (val), -0.60 (test), and -0.59 (train), with no significant difference (Kruskal-Wallis p = 0.32; see Supporting Information). We deliberately evaluate a single model architecture to isolate the effect of attack method and constraint level on robustness conclusions.

### 2.2 Perturbation Methods

We employ five perturbation methods that span a spectrum of increasing optimization strength (Table 1). All methods operate on the standardized (zero-mean, unit-variance) input tensor and are constrained to an L-infinity ball of radius epsilon around the clean input.

**Table 1: Perturbation methods used in this study, ordered by optimization strength.**

| Method | Type | Gradient info | Iterations | Role in this study |
|--------|------|--------------|------------|-------------------|
| Gaussian noise | Random baseline | None | 0 | Traditional noise sensitivity |
| Multiplicative bias | Random baseline | None | 0 | Simulates systematic sensor bias |
| Temp. correlated noise | Random baseline | None | 0 | Simulates realistic temporal error |
| FGSM | Single-step adversarial | Single gradient | 1 | Bridge; method used by Yang et al. (2026) |
| Auto-PGD | Iterative adversarial | Iterative gradient | 50 | Worst-case lower bound (recommended standard) |
| C&W regression | Minimum perturbation | Iterative gradient | 200 | Safety margin quantification |
| Causal trigger | Temporally constrained | Iterative gradient | 100 | Pre-event vulnerability analysis |

#### 2.2.1 Random Noise Baselines

Three random perturbation methods serve as baselines, representing the traditional noise sensitivity analysis approach:

- **Gaussian noise**: Independent samples from N(0, epsilon^2) clipped to [-epsilon, epsilon], applied elementwise to the input tensor.
- **Multiplicative bias**: Each input feature is scaled by a random factor drawn from U(1 - epsilon, 1 + epsilon), simulating systematic measurement bias.
- **Temporally correlated noise**: An AR(1) process with lag-1 autocorrelation of 0.7, scaled to respect the epsilon bound, simulating realistic temporal error structure.

These methods use no gradient information and perturb the input isotropically (or along random directions). They provide the "average-case" robustness baseline.

#### 2.2.2 FGSM (Single-Step Adversarial)

The Fast Gradient Sign Method (Goodfellow et al., 2015) computes the gradient of the loss function with respect to the input and takes a single step of size epsilon in the sign direction:

x_adv = x + epsilon * sign(grad_x L(f(x), y))

where L is the negative NSE loss, f is the model, and y is the observed streamflow. FGSM requires only one forward and one backward pass, making it computationally efficient. This is the method used by Yang et al. (2026) and serves as a bridge between our random baselines and iterative attacks.

#### 2.2.3 Auto-PGD (Iterative Adversarial)

Auto-PGD (Croce & Hein, 2020) is a variant of Projected Gradient Descent that iteratively refines the perturbation over multiple steps:

x_{t+1} = Pi_{B(x, epsilon)} [ x_t + alpha_t * sign(grad_x L(f(x_t), y)) ]

where Pi denotes projection onto the epsilon-ball and alpha_t is an adaptive step size. We use 50 iterations with 1 restart. Auto-PGD is considered a standard evaluation tool in the adversarial ML literature and consistently finds stronger adversarial examples than FGSM, providing a tighter lower bound on model robustness.

In addition to these three tiers, we employ two specialized methods:

#### 2.2.4 C&W Regression Attack

The Carlini-Wagner attack (Carlini & Wagner, 2017), adapted for regression, searches for the minimum L2-norm perturbation that degrades NSE below a target threshold (NSE < 0). Rather than fixing epsilon and measuring degradation, C&W answers the complementary question: "how small a perturbation suffices to cause model failure?" We use 200 iterations with binary search over the regularization parameter (5 steps, learning rate 0.01).

#### 2.2.5 Causal Trigger Attack

The causal trigger attack restricts perturbations to a temporal window preceding flood peak events (identified as local maxima exceeding the 90th percentile of observed discharge). We test pre-event windows of 1, 3, 7, and 14 days with iterative optimization (100 steps). This attack probes the operationally critical question: how much can data errors in the run-up to a flood event affect the forecast?

### 2.3 Constraint Hierarchy

To control the plausibility of perturbations, we define three levels of increasingly restrictive constraints:

1. **Lp constraint**: Perturbations are bounded by ||delta||_inf <= epsilon. This is the minimal constraint, limiting only magnitude.

2. **Physical constraint**: In addition to the Lp bound, physically implausible values are corrected: precipitation is clipped to non-negative values, and temperatures are constrained to climatologically reasonable ranges. This mirrors the approach of Yang et al. (2026).

3. **Statistical constraint**: In addition to the Lp bound, perturbations are required to preserve the mean and standard deviation of each input feature over the evaluation period. This simulates a scenario where input data passes standard quality-control checks (distributional statistics appear normal) but contains structured errors that are harmful to the model.

### 2.4 Mapping Epsilon to Physical Units

To ground our perturbation budgets in realistic observation uncertainty, we convert epsilon values from standardized units to physical units using the training-period standard deviations of each feature (Table 2). At epsilon = 0.1, perturbations correspond to approximately +/-0.8 mm/day for precipitation and +/-1.1 °C for temperature — values within the typical error range of gridded meteorological products such as Daymet (Thornton et al., 2021). Our primary analyses focus on epsilon = 0.1 as a realistic worst-case scenario, with epsilon = {0.01, 0.05, 0.2} providing context across the perturbation spectrum.

**Table 2: Mapping between standardized perturbation budget (epsilon) and physical units for each input feature. Training-period standard deviations (sigma) are used for conversion. Typical observation errors from gauge networks and gridded products are listed for reference.**

| Feature | Training sigma | eps=0.05 | eps=0.1 | eps=0.2 | Typical obs. error |
|---------|---------------|----------|---------|---------|-------------------|
| Precipitation (mm/day) | 7.73 | +/-0.4 | +/-0.8 | +/-1.5 | Gauge: 0.2-0.5; Daymet: 2-4 |
| Max. temperature (°C) | 11.21 | +/-0.6 | +/-1.1 | +/-2.2 | Station: 0.2-0.5; Daymet: 1-1.5 |
| Min. temperature (°C) | 10.27 | +/-0.5 | +/-1.0 | +/-2.1 | Station: 0.2-0.5; Gridded: 1-2 |
| Shortwave radiation (W/m^2) | 132.34 | +/-6.6 | +/-13.2 | +/-26.5 | Pyranometer: 5-10; ERA5: 20-40 |
| Vapor pressure (Pa) | 652.05 | +/-32.6 | +/-65.2 | +/-130 | Hygrometer: 20-50; Reanalysis: 50-150 |

### 2.5 Evaluation Metrics

Our primary robustness metric is delta-NSE = NSE_adv - NSE_clean, where NSE_adv is the Nash-Sutcliffe Efficiency computed on adversarially perturbed predictions and NSE_clean is the baseline (unperturbed) value. Negative values indicate degradation. We report medians and interquartile ranges (IQR) across catchments, as the distribution is heavy-tailed and means are strongly influenced by outliers.

Supplementary metrics include delta-KGE (Kling-Gupta Efficiency change), peak error (mean relative error on discharge values above the 90th percentile), and a Kolmogorov-Smirnov (KS) test p-value measuring the statistical detectability of the perturbation in input space.

### 2.6 Experimental Design

We organize experiments into five blocks:

- **Experiment 1 (Attack comparison)**: Five methods x four epsilon values {0.01, 0.05, 0.1, 0.2}, Lp constraint, untargeted. 520 catchments. This is the core experiment addressing our research question.
- **Experiment 2 (Constraint ablation)**: Auto-PGD x three constraints {Lp, physical, statistical} x three epsilon values {0.05, 0.1, 0.2}. 490 catchments.
- **Experiment 3 (Targeted attacks)**: Auto-PGD x three targets {untargeted, flood, low-flow}, epsilon = 0.1. 490 catchments.
- **Experiment 4 (Causal trigger)**: Causal trigger x four windows {1, 3, 7, 14 days}, epsilon = 0.1. 520 catchments.
- **Experiment 5 (Minimum perturbation)**: C&W attack, epsilon = 0.1. 523 catchments.

All experiments were executed on GPU nodes via SLURM array jobs, with catchments partitioned into chunks of approximately 50. Results were merged and deduplicated, yielding 16,563 individual experiment records across 524 unique catchments.

---

## 3. Results

### 3.1 Attack Method Strongly Affects Robustness Conclusions

Table 3 presents the median delta-NSE across catchments for each combination of attack method and epsilon value, with interquartile ranges. Figure 1 visualizes these results as epsilon-response curves.

**Table 3: Median delta-NSE [Q25, Q75] across catchments for each attack method and perturbation budget (Lp constraint, untargeted). The amplification ratio (APGD/Gaussian) quantifies how much more effective adversarial perturbations are compared to random noise.**

| Method | N | eps=0.01 | eps=0.05 | eps=0.1 | eps=0.2 |
|--------|---|----------|----------|---------|---------|
| Auto-PGD | 520 | -0.045 [-0.084, -0.024] | -0.270 [-0.542, -0.143] | -0.587 [-1.481, -0.303] | -1.282 [-5.077, -0.631] |
| FGSM | 520 | -0.043 [-0.082, -0.024] | -0.216 [-0.429, -0.120] | -0.394 [-0.858, -0.223] | -0.639 [-1.828, -0.385] |
| Gaussian | 490 | -0.003 [-0.005, -0.001] | -0.013 [-0.026, -0.007] | -0.027 [-0.053, -0.014] | -0.057 [-0.109, -0.030] |
| Mult. Bias | 490 | -0.002 [-0.003, -0.001] | -0.008 [-0.018, -0.004] | -0.018 [-0.037, -0.009] | -0.038 [-0.079, -0.018] |
| Temp. Corr. | 490 | -0.002 [-0.004, -0.001] | -0.011 [-0.020, -0.005] | -0.022 [-0.041, -0.011] | -0.046 [-0.081, -0.024] |
| **Ratio APGD/Gaussian** | | **16.9x** | **20.2x** | **21.4x** | **22.3x** |

The results reveal a clear hierarchy: at every epsilon level, Auto-PGD causes the largest degradation, followed by FGSM, with all three random baselines clustered near zero. At our primary analysis point of epsilon = 0.1, the median delta-NSE under Auto-PGD is -0.587, compared to -0.394 for FGSM (ratio 1.49) and -0.027 for Gaussian noise (ratio 21.4).

Several features of these results warrant discussion. First, the adversarial-to-random gap is large and grows with epsilon: the amplification ratio increases from 16.9x at epsilon = 0.01 to 22.3x at epsilon = 0.2. This indicates that random noise sensitivity analysis increasingly underestimates worst-case vulnerability at higher perturbation budgets.

Second, the gap between FGSM and Auto-PGD (1.5x) is much smaller than between either adversarial method and random noise (>14x). This suggests that FGSM captures the majority of adversarial vulnerability — it correctly identifies the general direction of maximum sensitivity — but iterative refinement finds perturbations that are 50% more effective. This 50% gap may appear modest in relative terms, but in absolute terms it corresponds to an additional 0.19 NSE units of degradation, which is operationally significant.

Third, the three random baselines produce remarkably similar results despite their different structures (isotropic, multiplicative, temporally correlated), confirming that the dominant effect is the use of gradient information rather than the specific noise structure.

### 3.2 Vulnerability Is Widespread, Not Limited to Outlier Catchments

Figure 2 shows the distribution of per-catchment delta-NSE under Auto-PGD at epsilon = 0.1. The distribution is strongly right-skewed, with most catchments experiencing moderate degradation but a substantial tail of severe cases.

Key statistics:
- Median delta-NSE: **-0.59**
- 10th percentile: -4.61
- 90th percentile: -0.15
- Catchments with delta-NSE < -1: **169 (32.5%)**
- Catchments with delta-NSE < -0.5: 271 (52.1%)

Nearly one-third of catchments experience catastrophic performance loss (delta-NSE < -1, meaning the perturbed NSE is more than 1 unit below the clean value) under observation-error-scale perturbations. The corresponding proportion under FGSM is 22.5%, and under Gaussian noise only 1.2%. The gap between Auto-PGD and FGSM is thus most consequential in the distribution tail: while the median difference is 1.5x, the fraction of catchments crossing the catastrophic-failure threshold increases by nearly half (from 22.5% to 32.5%) when moving from single-step to iterative attack.

Having established that iterative attacks reveal substantially greater vulnerability than single-step or random methods (Sections 3.1–3.2), we now characterize the *nature* of this vulnerability along three dimensions: perturbation plausibility (Section 3.3), temporal and target structure (Section 3.4), and minimum perturbation budget (Section 3.5).

### 3.3 Statistically Undetectable Perturbations Remain Effective

Table 4 presents the constraint ablation results for Auto-PGD.

**Table 4: Constraint ablation results for Auto-PGD (untargeted). Values are median (mean) delta-NSE. The gap between median and mean reflects the heavy-tailed nature of the degradation distribution.**

| Constraint | N | eps=0.05 | eps=0.1 | eps=0.2 |
|------------|---|----------|---------|---------|
| Lp | 520 | -0.270 (-0.924) | -0.587 (-2.549) | -1.282 (-7.853) |
| Physical | 490 | -0.251 (-0.870) | -0.552 (-2.393) | -1.563 (-8.295) |
| Statistical | 490 | -0.148 (-0.451) | -0.347 (-1.127) | -0.747 (-3.059) |

Values are median (mean) delta-NSE. Mean values are reported in parentheses for comparison, illustrating the strong influence of heavy-tailed outliers.

Physical constraints reduce median degradation by only 6% relative to the Lp-only baseline (from -0.587 to -0.552 at epsilon = 0.1), indicating that enforcing non-negative precipitation and reasonable temperature ranges has little constraining effect — the most effective adversarial perturbations are already physically plausible.

Statistical constraints are more restrictive, reducing median degradation by 41% (from -0.587 to -0.347). However, the residual degradation of 0.347 NSE units remains operationally significant. This finding has a practical implication: input data that passes standard quality-control checks — showing normal means and standard deviations for each meteorological variable — can still contain error patterns that substantially degrade model performance. The harmful information resides in higher-order statistical structure (correlations, temporal patterns) that routine QC does not examine.

### 3.4 Targeted Attacks and Pre-Event Vulnerability

Table 5 presents the results of targeted attacks (Auto-PGD, epsilon = 0.1, Lp constraint).

**Table 5: Targeted attack results (Auto-PGD, epsilon = 0.1, Lp constraint). Median [Q25, Q75] across catchments.**

| Target | N | Median delta-NSE [IQR] | Median delta-KGE [IQR] |
|--------|---|------------------------|------------------------|
| Untargeted | 520 | -0.587 [-1.481, -0.303] | -0.556 [-1.274, -0.176] |
| Flood | 490 | -0.501 [-1.129, -0.250] | -0.553 [-1.259, -0.214] |
| Low-flow | 490 | -0.019 [-0.100, 0.016] | -0.018 [-0.203, 0.080] |

Flood-targeted attacks produce degradation comparable to, though slightly less than, untargeted attacks (median delta-NSE of -0.501 vs. -0.587), while low-flow-targeted attacks are largely ineffective (median delta-NSE of -0.019). The fact that flood-targeted delta-NSE is slightly smaller than untargeted delta-NSE is expected: the untargeted attack optimizes over all timesteps, while the flood-targeted attack concentrates its loss on high-flow periods, which constitute a minority of the time series. The global NSE metric is thus naturally less affected. However, the contrast with low-flow targeting is striking: the flood/low-flow ratio exceeds 26:1, indicating that the model's vulnerability is overwhelmingly concentrated in high-flow regimes. This is physically intuitive — high-flow events involve nonlinear processes (threshold-driven runoff generation, saturation excess) that create steeper gradients in the loss landscape.

Figure 3 shows the causal trigger results. Restricting perturbations to progressively longer pre-event windows yields a monotonic increase in degradation:

| Pre-event window | Median delta-NSE |
|-----------------|-----------------|
| 1 day | -0.013 |
| 3 days | -0.034 |
| 7 days | -0.070 |
| 14 days | -0.122 |

Even perturbations limited to the 14 days preceding flood peaks cause a median delta-NSE of -0.122 — a non-trivial degradation concentrated precisely in the period most critical for flood early warning systems. The approximately linear scaling with window length suggests that each additional day of perturbed input contributes roughly equally to forecast degradation.

### 3.5 Safety Margins: How Small a Perturbation Suffices?

The C&W attack identifies the minimum L2-norm perturbation required to push NSE below zero. Figure 4 shows the distribution of minimum perturbation magnitudes. Of 523 catchments evaluated, 351 (67%) yielded converged solutions with a median minimum L2 perturbation of 1.276. The remaining 172 catchments (33%) returned near-zero L2 values. Investigation reveals that this group predominantly consists of catchments with poor baseline performance: 116 of 172 (67%) have clean NSE below zero, and 125 of 172 (73%) have clean NSE below 0.3. These catchments were already poorly modeled before any perturbation was applied; the C&W result simply confirms that they have no meaningful safety margin to lose.

For the 351 catchments where C&W converged (median clean NSE = 0.545), the median minimum L2 perturbation of 1.276 provides a quantitative safety margin: this is the smallest perturbation in standardized input space that reduces NSE below zero. While not directly comparable to the L-infinity epsilon used in other experiments, it indicates that a non-trivial but finite perturbation budget is needed to cause complete model failure in reasonably well-modeled catchments.

### 3.6 Detectability of Adversarial Perturbations

Figure 5 plots the absolute degradation (|delta-NSE|) against the KS test p-value measuring statistical detectability of the perturbation in input space. A clear pattern emerges: adversarial methods (Auto-PGD, FGSM) achieve large degradation across a wide range of detectability levels. Many highly effective perturbations have KS p-values above 0.05, meaning they would not be flagged as statistically anomalous by a two-sample test comparing perturbed and clean inputs. Random noise methods, by contrast, cluster at low degradation values regardless of detectability.

### 3.7 Which Catchments Are Most Vulnerable?

Figure 6 shows the relationship between baseline model performance (clean NSE) and adversarial vulnerability (delta-NSE under Auto-PGD, epsilon = 0.1). Catchments are grouped into three performance tiers:

| Baseline NSE | N | Median delta-NSE | Fraction with delta-NSE < -1 |
|-------------|---|-----------------|------------------------------|
| High [0.7, 1.0) | 118 | -0.53 | 17% |
| Medium [0.4, 0.7) | 175 | -0.57 | 25% |
| Low [-1.0, 0.4) | 168 | -0.69 | 44% |

Catchments with low baseline performance are substantially more vulnerable: 44% experience catastrophic failure, compared to 17% of well-modeled catchments. However, the key finding is that **even among the best-modeled catchments (clean NSE > 0.7), nearly one in five (17%) still exhibits catastrophic vulnerability**. High predictive skill on clean data does not guarantee robustness to input perturbation.

The overall correlation between clean NSE and delta-NSE is weak (r = -0.04), indicating that while baseline performance provides some indication of robustness, it is far from deterministic. Identifying the catchment characteristics that govern adversarial vulnerability — such as aridity, flashiness, or dominant runoff generation mechanisms — is an important direction for future work.

---

## 4. Discussion

### 4.1 Single-Step vs. Iterative Assessment

Under FGSM — the method used by Yang et al. (2026) — the robustness picture is relatively reassuring. Under iterative Auto-PGD, however, a qualitatively different picture emerges: median degradation increases by 50%, and the fraction of catchments crossing the catastrophic-failure threshold rises from 22.5% to 32.5%. The practical implication is clear: single-step assessment provides a necessary but insufficient robustness check. Deployment decisions informed solely by FGSM-scale results may underestimate tail risk. We recommend iterative attacks as the standard for robustness evaluation.

### 4.2 Why Does the Attack Method Matter?

The gap between FGSM and Auto-PGD arises because FGSM's single gradient step provides only a first-order approximation of the loss landscape. In regions where the loss surface has curvature, the sign of the gradient at the clean input may not point toward the global maximum within the epsilon-ball. Iterative methods can follow the loss surface around such curvatures, finding perturbations that exploit nonlinearities in the model's input-output mapping.

The finding that this gap widens with epsilon (from 1.0x at epsilon = 0.01 to 2.0x at epsilon = 0.2) is consistent with this interpretation: at very small perturbation budgets, the loss landscape is approximately linear and FGSM's first-order approximation is adequate; at larger budgets, curvature effects become more pronounced and iterative refinement provides greater advantage.

It is notable that the adversarial-to-random gap (21x) far exceeds the FGSM-to-Auto-PGD gap (1.5x). This indicates that the dominant source of underestimation in traditional sensitivity analysis is not the absence of iterative refinement but rather the failure to use gradient information at all. FGSM, despite being a single-step method, captures approximately 67% of the worst-case vulnerability (0.394 / 0.587). This suggests that even computationally cheap adversarial methods provide substantially more informative stress tests than random noise.

### 4.3 Implications for Operational Deployment

Our results should not be interpreted as evidence against the deployment of LSTM models in hydrological forecasting. LSTMs remain the most accurate available models for many prediction tasks, and accuracy is the primary criterion for most applications. However, our findings highlight three considerations for deployment:

First, **robustness should be evaluated alongside accuracy** in model selection. A model with slightly lower clean-input NSE but substantially smaller adversarial sensitivity may be preferable for safety-critical applications. We suggest reporting adversarial delta-NSE at epsilon = 0.1 (corresponding to typical gridded-product uncertainty) as a standard supplementary metric.

Second, **standard quality-control procedures are insufficient** to guarantee input data quality from the model's perspective. Our statistical constraint experiment shows that input perturbations preserving feature-level means and standard deviations — perturbations that would pass routine QC checks — can still cause significant degradation. Higher-order input validation (e.g., temporal consistency checks, cross-variable correlation monitoring) may be needed.

Third, **the pre-event period is disproportionately vulnerable**. Our causal trigger analysis shows that data errors concentrated in the 14 days preceding flood peaks cause meaningful degradation. This is precisely the period when data quality is most operationally important and, in many regions, most uncertain (due to gauge undercatch during intense rainfall, satellite retrieval challenges in heavy cloud cover, etc.).

### 4.4 Limitations and Future Work

Several limitations of this study should be acknowledged. First, we evaluate only a single model architecture (CudaLSTM with 128 hidden units and no static attributes). Different architectures — including Entity-Aware LSTMs (Kratzert et al., 2019), Transformers, and Mamba-based models — may exhibit different robustness characteristics. The comparison across architectures has been partly addressed by Yang et al. (2026) for LSTM vs. HBV; extending this to modern DL architectures is an important direction.

Second, our analysis is limited to the CAMELS-US dataset and daily timestep. Robustness characteristics may differ in other hydroclimatic regimes, at sub-daily temporal resolution, or for global-scale models.

Third, we do not evaluate defense strategies (e.g., adversarial training, input denoising, ensemble methods). Demonstrating that these techniques can improve robustness — and quantifying the accuracy-robustness trade-off — is a natural next step.

Fourth, while we anchor epsilon to observation uncertainty, our adversarial perturbations are optimized to maximize model error, which is not how real-world observation errors arise. The adversarial framework provides a worst-case bound, not a prediction of typical operational performance. The gap between this worst case and typical performance (quantified by the adversarial-to-random ratio) reflects the model's sensitivity to the specific direction of input error, not the probability of encountering such errors in practice.

---

## 5. Conclusions

We investigated how the choice of perturbation method affects adversarial robustness conclusions for LSTM rainfall-runoff models, evaluating five methods spanning the spectrum from random noise to iterative gradient-based optimization across 520 CAMELS-US catchments.

Our principal findings are:

1. **Attack method choice has a decisive influence on robustness assessment.** Iterative adversarial perturbations (Auto-PGD) reveal 1.5 times greater vulnerability than single-step attacks (FGSM) and 21 times greater than random noise at observation-error-scale perturbation budgets (epsilon = 0.1). Conclusions drawn from any single method may not generalize across the perturbation spectrum.

2. **Vulnerability is widespread under iterative attack.** At epsilon = 0.1, one-third of catchments (32.5%) experience catastrophic performance loss (delta-NSE < -1). This proportion is not apparent from FGSM- or random-noise-based assessment and has direct implications for deployment risk assessment.

3. **Statistically undetectable perturbations remain harmful.** Perturbations that preserve input feature means and standard deviations — and would pass standard quality-control checks — still cause median delta-NSE of -0.35 under Auto-PGD, suggesting that routine QC is insufficient to ensure input data quality from the model's perspective.

4. **Pre-event data quality is disproportionately important.** Perturbations restricted to the 14 days preceding flood peaks cause median delta-NSE of -0.12, concentrated in the operationally critical forecasting window.

Our results establish that hydrological model robustness assessment requires multi-level stress testing that goes beyond random noise and single-step adversarial methods. We recommend iterative adversarial evaluation at observation-error-scale budgets as a standard component of deployment checklists for safety-critical applications.

---

## Open Research

All code for adversarial attacks, evaluation, and analysis is available at [repository URL]. The CudaLSTM model was trained using the open-source neuralhydrology framework (Kratzert et al., 2022). CAMELS-US data are publicly available from the USGS (Newman et al., 2015; Addor et al., 2017).

---

## References

Addor, N., Newman, A. J., Mizukami, N., & Clark, M. P. (2017). The CAMELS data set: Catchment attributes and meteorology for large-sample studies. Hydrology and Earth System Sciences, 21(10), 5293-5313.

Carlini, N., & Wagner, D. (2017). Towards evaluating the robustness of neural networks. IEEE Symposium on Security and Privacy, 39-57.

Carlini, N., Athalye, A., Papernot, N., Brendel, W., Rauber, J., Tsipras, D., ... & Kurakin, A. (2019). On evaluating adversarial robustness. arXiv preprint arXiv:1902.06705.

Croce, F., & Hein, M. (2020). Reliable evaluation of adversarial robustness with an ensemble of attacks. International Conference on Machine Learning, 2206-2216.

Gauch, M., Kratzert, F., Klotz, D., Nearing, G., Lin, J., & Hochreiter, S. (2021). Rainfall-runoff prediction at multiple timescales with a single Long Short-Term Memory network. Hydrology and Earth System Sciences, 25(4), 2045-2062.

Goodfellow, I. J., Shlens, J., & Szegedy, C. (2015). Explaining and harnessing adversarial examples. International Conference on Learning Representations.

Groisman, P. Y., & Legates, D. R. (1994). The accuracy of United States precipitation data. Bulletin of the American Meteorological Society, 75(2), 215-228.

Hersbach, H., Bell, B., Berrisford, P., et al. (2020). The ERA5 global reanalysis. Quarterly Journal of the Royal Meteorological Society, 146(730), 1999-2049.

Kratzert, F., Klotz, D., Brenner, C., Schulz, K., & Herrnegger, M. (2018). Rainfall-runoff modelling using Long Short-Term Memory (LSTM) networks. Hydrology and Earth System Sciences, 22(11), 6005-6022.

Kratzert, F., Klotz, D., Shalev, G., Klambauer, G., Hochreiter, S., & Nearing, G. (2019). Towards learning universal, regional, and local hydrological behaviors via machine learning applied to large-sample datasets. Hydrology and Earth System Sciences, 23(12), 5089-5110.

Kratzert, F., Gauch, M., Nearing, G., & Klotz, D. (2022). NeuralHydrology — A Python library for Deep Learning research in hydrology. Journal of Open Source Software, 7(71), 4050.

Madry, A., Makelov, A., Schmidt, L., Tsipras, D., & Vladu, A. (2018). Towards deep learning models resistant to adversarial attacks. International Conference on Learning Representations.

Nearing, G. S., Kratzert, F., Sampson, A. K., et al. (2021). What role does hydrological science play in the age of machine learning? Water Resources Research, 57(1), e2020WR028091.

Newman, A. J., Clark, M. P., Sampson, K., et al. (2015). Development of a large-sample watershed-scale hydrometeorological data set for the contiguous USA. Water Resources Research, 51(12), 10040-10066.

Sevruk, B. (1982). Methods of correction for systematic error in point precipitation measurement for operational use. WMO Operational Hydrology Report No. 21.

Thornton, M. M., Shrestha, R., Wei, Y., Thornton, P. E., Kao, S., & Wilson, B. E. (2021). Daymet: Daily surface weather data on a 1-km grid for North America, Version 4 R1. ORNL DAAC.

Yang, Y., Janssen, J., Gupta, H., & Chui, T. F. M. (2026). On the adversarial robustness of hydrological models. arXiv preprint arXiv:2602.05237.

---

## Figure Captions

**Figure 1.** Median delta-NSE as a function of perturbation budget (epsilon) for five perturbation methods, with interquartile range (IQR) shown as shaded bands. (a) Adversarial attacks: Auto-PGD (red) and FGSM (orange). (b) Random noise baselines: Gaussian (green), multiplicative bias (blue), and temporally correlated noise (purple). Note the different y-axis scales between panels, reflecting the order-of-magnitude gap between adversarial and random perturbation effects. All results use Lp constraint with untargeted objective. [File: fig1_epsilon_curve.pdf]

**Figure 2.** Distribution of per-catchment delta-NSE under Auto-PGD attack at epsilon = 0.1 (Lp constraint, untargeted, N = 520 catchments). Blue histogram shows the frequency distribution (clipped to [-20, 0.5] for readability; 14 catchments with delta-NSE below -20 are not shown). Red line shows the cumulative distribution function (CDF, right axis). Dashed vertical lines mark the 10th percentile (-4.61), median (-0.59), and 90th percentile (-0.15). [File: fig2_basin_vulnerability.pdf]

**Figure 3.** Effect of pre-event perturbation window length on model degradation under the causal trigger attack (epsilon = 0.1). Box plots show the distribution of delta-NSE across catchments for windows of 1, 3, 7, and 14 days preceding flood peak events. Individual catchment results are shown as jittered dots (subsampled to 200 per window for clarity). Median values are annotated. Clipped to [-5, 0.5]. [File: fig3_causal_window.pdf]

**Figure 4.** Distribution of minimum L2-norm perturbation required to reduce NSE below zero, obtained from the C&W regression attack (N = 523 catchments). Only converged solutions (L2 > 0.01, N = 351) are shown; 172 catchments with near-zero perturbation (already at or below NSE = 0, or trivially attackable) are noted in the annotation. Dashed line indicates the median L2 norm of 1.276 among converged cases. [File: fig4_cw_perturbation.pdf]

**Figure 5.** Relationship between attack effectiveness (|delta-NSE|, x-axis, log scale) and statistical detectability (KS test p-value, y-axis) for all attack methods. Each point represents one catchment-attack-epsilon combination. The red dashed line at p = 0.05 indicates the conventional significance threshold: points above this line represent perturbations that would not be flagged as statistically anomalous. Adversarial methods (Auto-PGD, FGSM) achieve high degradation across a wide range of detectability, while random methods cluster at low degradation values. [File: fig5_detectability.pdf]

**Figure 6.** Relationship between baseline model performance (clean NSE, x-axis) and adversarial vulnerability (delta-NSE under Auto-PGD at epsilon = 0.1, y-axis) for 461 catchments with clean NSE > -1. Each point represents one catchment. Annotations show median delta-NSE and catastrophic failure rate (delta-NSE < -1) for three performance tiers. Catchments with low baseline performance are more vulnerable on average, but even well-modeled catchments (clean NSE > 0.7) exhibit a 17% catastrophic failure rate. [File: fig6_attribution.pdf]
