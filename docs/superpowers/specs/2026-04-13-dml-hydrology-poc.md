# DML for Hydrology — 1-Week POC Spec

**Date**: 2026-04-13
**Owner**: yiqun.sun
**Strategic line**: 主线 B (外领域方法引入水文) / B1 成熟方法 / DML 分支
**Related memory**: `method_dml_for_hydrology.md`, `external_methods_import.md`, `methods_cross_domain_assessment.md`

---

## 1. Purpose

**The single question this POC answers**: Is it worth investing 2-3 months on a "DML in hydrologic attribution" paper as the first output of 主线 B?

**Not the purpose**:
- Publication-ready benchmark
- Complete stress-test of DML across all failure modes
- Final answer on any hydrologic attribution question

**Definition of success**: At end of Day 7, a 2-page report ending with one of three decisions:
1. ✅ **Go**: DML shows clear advantage on semi-synthetic + runs on real CAMELS → start paper
2. ⚠️ **Go with downgraded narrative**: DML has coverage advantage but not bias advantage → start paper with "正确不确定性量化" framing
3. ❌ **Stop**: DML does not show advantage under CAMELS-like structure → pivot 主线 B

---

## 2. Background (from pre-search done 2026-04-13)

Pre-search (`external_methods_import.md`, this session's web search) established:

- **Streamflow / runoff / rainfall-runoff**: 0 DML applications found
- **Groundwater level**: 0 DML applications found
- **CAMELS**: 0 DML applications found
- **Climate vs land-use attribution**: 0 DML, all SWAT+LSTM+SHAP/Sobol
- **Coastal water quality**: 1 paper (Sun et al. 2025, Water Research, Hong Kong) — **uses DML but on water quality, not hydrology core**

**Implication**: Core hydrology (streamflow, groundwater) is a genuine blank space for DML. Sun 2025 serves as feasibility precedent, not competition. The 主线 B "方法转移" narrative is supported by literature reality.

---

## 3. Scope Decisions (explicit, so future-me doesn't re-debate)

These were settled in the planning conversation 2026-04-12/13. Do **not** re-open unless a hard blocker appears.

### Included
- **1 semi-synthetic DGP** using real CAMELS W structure with learned g(W), m(W)
- **1 θ_true value** (-0.05, small effect)
- **1 noise level** (signal-to-noise ~ 0.2)
- **100 repetitions**
- **4 baselines** covering 3 hydrology paradigms:
  1. OLS with controls (classical statistics)
  2. Partial correlation (classical statistics)
  3. RF + mean(|SHAP|) (ML interpretability)
  4. CausalForestDML (causal ML — the method under evaluation)
- **1 real CAMELS application**: T = `frac_forest`, Y = `runoff_coeff`, W = 12 confounders
- **Sensitivity analysis** on real CAMELS (ML swap, propensity trim, synthetic hidden confounder)
- **1 mandatory slack day** (Day 6)

### Explicitly excluded
- Level 0 smoke test as a separate day (rolled into Day 3 development testing)
- Level 1 (hidden confounder stress test) — paper phase only
- Level 2 (overlap violation stress test) — paper phase only
- Multi-θ power curve — paper phase only
- Multi-noise-level scan — paper phase only
- Additional baselines (Sobol, permutation importance, LinearDML) — paper phase only
- 200+ repetitions — paper phase only
- GWL / GROW application — deferred to Phase 1 after POC passes
- Formal DoWhy DAG engine — hand-drawn DAG is sufficient for POC

**Rationale**: POC exists to produce a go/no-go decision in 1 week. Anything that does not change the decision is scope creep.

---

## 4. Risk Register

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Semi-synthetic DGP has RF bias favoring DML (RF used in both DGP and DML nuisance) | Medium | Medium | Day 4 cross-check: re-run DML with XGBoost nuisance, verify coverage stable |
| R2 | Real CAMELS has no ground truth for θ | Certain | Unavoidable | Frame real application as "can-it-run-and-stay-stable" evidence, not "is-the-number-right" |
| R3 | Day 4 benchmark shows no clear DML advantage | Medium | High (kills go) | **This is the POC's job** — produce the answer, even if it's negative |
| R4 | Code bugs in baselines (especially SHAP-to-θ conversion) | Medium | Medium | Day 3 trivial-DGP unit test for each baseline before main run |
| R5 | EconML API surface changes or bug on latest version | Low | Medium | Pin EconML version in `requirements-dml.txt`, use tested release |
| R6 | Real CAMELS `runoff_coeff` requires non-trivial computation (Q/P over period) | Medium | Low | Use CAMELS `q_mean` / `p_mean` attribute if available, else compute from streamflow file |
| R7 | RF nuisance fits trivially on real CAMELS (CV R² > 0.9) making synthetic Y noise-free | Medium | Medium | Day 2 check: ensure model_y CV R² is in [0.5, 0.7]. If too high, regularize (larger min_samples_leaf) |

**Absent-by-design risks** (acknowledged as unfixable within POC):
- Unobserved confounders in real CAMELS (fundamental limit of any non-experimental method)
- Reverse causation in forest→runoff (weak mitigation: use temporal lag if time permits)

---

## 5. Day-by-Day Plan

### Day 1 — Foundation (6h)

**Morning (3h)**
- Create conda env: `conda create -n dml python=3.10`
- Install: `econml`, `scikit-learn`, `statsmodels`, `pingouin`, `shap`, `pandas`, `matplotlib`, `seaborn`, `pyarrow`
- Freeze `requirements-dml.txt`
- Create directory structure under `src/method_dml/` (see §6)
- Smoke-import all libraries in a notebook

**Afternoon (3h)**
- Read Chernozhukov et al. 2018 Sections 1-2 (intro + setup), skim Sections 3-4 (theory) — ~60 min
- Read EconML CausalForestDML tutorial end-to-end — ~30 min
- Draw water-causal DAG: T = `frac_forest`, Y = `runoff_coeff`, W = climate/topo/soil/geology, list unobserved U candidates (land management history, fire history, policy) — ~60 min
- Save DAG as `src/method_dml/notebooks/01_dag.ipynb` with inline graphviz

**Day 1 deliverables**
- [ ] `requirements-dml.txt`
- [ ] `src/method_dml/` directory structure
- [ ] DAG notebook with named W/U variables
- [ ] Hand-written confounder list matching CAMELS attributes

**Day 1 exit check**: Can `python -c "from econml.dml import CausalForestDML; print('ok')"` run clean.

---

### Day 2 — Data Preparation (6h)

**Morning (3h) — Real CAMELS data**
- Load CAMELS attributes (`camels_attributes_v2.0.csv`)
- Compute `runoff_coeff` from `q_mean / p_mean` (or daily streamflow / daily precip) — 1990-2010 window
- Select W columns (12 confounders): `p_mean`, `pet_mean`, `aridity`, `elev_mean`, `slope_mean`, `area_gages2`, `clay_frac`, `sand_frac`, `soil_depth_pelletier`, `geol_permeability`, `geol_porosity`, `snow_frac`
- T column: `frac_forest`
- Drop basins with any NaN in (Y, T, W)
- Save as `src/method_dml/results/real_clean.parquet`
- **Check**: N ≥ 450 after cleaning (need this for DML stability)

**Afternoon (3h) — Semi-synthetic DGP**
- Train `rf_g` on (W_real, Y_real): RF with `n_estimators=500`, `min_samples_leaf=10`
  - **Control CV R² to [0.5, 0.7]** — if too high, increase `min_samples_leaf`; if too low, decrease
- Train `rf_m` on (W_real, T_real) with same params
  - **Control CV R² to [0.5, 0.7]**
- Store `g_learned = rf_g.predict(W_real)` and `m_learned = rf_m.predict(W_real)` — these are frozen across 100 reps
- Write `generate_semi_synthetic(seed)` function:
  ```
  T_syn = m_learned + 0.1 * rng.standard_normal(N)
  Y_syn = theta_true * T_syn + g_learned + 0.1 * rng.standard_normal(N)
  ```
  where `theta_true = -0.05`
- Save 100 reps as `src/method_dml/results/semi_synthetic.parquet` (rep_id, basin_id, Y, T, W cols)

**Day 2 deliverables**
- [ ] `real_clean.parquet` with documented row count
- [ ] `semi_synthetic.parquet` with 100 reps
- [ ] CV R² report for `rf_g` and `rf_m` (documented in notebook)

**Day 2 exit check**: Both parquet files open, reps have correct shape, `g_learned` / `m_learned` frozen.

---

### Day 3 — Baselines Implementation + Code-Level Smoke Test (6h)

**Each baseline gets a function with unified signature**:
```python
def estimate(Y, T, W) -> dict:
    return {
        'theta_hat': float,
        'ci_low': float or None,       # None if method doesn't provide CI
        'ci_high': float or None,
        'method_name': str,
    }
```

**Four baselines to implement**:

1. **OLS** (`src/method_dml/baselines/ols.py`, ~50 lines)
   - `statsmodels.OLS(Y, add_constant([T, *W]))`
   - Extract T coefficient, its SE, construct 95% CI

2. **Partial correlation** (`baselines/partial_corr.py`, ~40 lines)
   - `pingouin.partial_corr(data=df, x='T', y='Y', covar=W_cols)`
   - Convert correlation to pseudo-θ via `r * std(Y)/std(T)` — **document this is not an unbiased causal estimator**, just how hydrology papers report it

3. **RF + SHAP** (`baselines/rf_shap.py`, ~80 lines)
   - Train RF on `Y ~ [T, W]`
   - Compute SHAP values for all samples
   - `theta_hat = mean(shap_values[:, T_index])` — this is the "SHAP-as-causal" interpretation used in hydrology
   - No CI (document this explicitly)

4. **CausalForestDML** (`baselines/causal_forest_dml.py`, ~60 lines)
   - `CausalForestDML(model_y=RF, model_t=RF, n_estimators=2000, min_samples_leaf=10, cv=5)`
   - `.ate(X)` and `.ate_interval(X)` for θ and CI

**Code-level unit test (the "smoke test" that replaces Level 0 as a separate day)**:

Write `tests/test_baselines_trivial.py`:
```python
def test_trivial_linear():
    """All methods should recover theta on a trivial linear DGP."""
    n, d = 2000, 5
    np.random.seed(0)
    W = np.random.randn(n, d)
    T = W[:, 0] + 0.3 * np.random.randn(n)
    theta_true = -0.5
    Y = theta_true * T + W[:, 1] + 0.1 * np.random.randn(n)

    for baseline in [ols, partial_corr, rf_shap, causal_forest_dml]:
        result = baseline.estimate(Y, T, W)
        assert abs(result['theta_hat'] - theta_true) < 0.1, \
            f"{baseline.__name__} bias too large"
```

**Day 3 deliverables**
- [ ] 4 baseline modules with unified interface
- [ ] `test_baselines_trivial.py` passing all 4
- [ ] Notebook demo showing all 4 running on one real CAMELS sample

**Day 3 exit check**: `pytest src/method_dml/tests/` passes. Any baseline that fails trivial test has a bug — fix before Day 4.

---

### Day 4 — Semi-synthetic Benchmark Main Run (6h)

**Morning (3h) — Main loop**
```python
results = []
for rep in range(100):
    Y, T, W = load_rep(rep)
    for baseline in [ols, partial_corr, rf_shap, causal_forest_dml]:
        r = baseline.estimate(Y, T, W)
        results.append({
            'rep': rep,
            'method': r['method_name'],
            'theta_hat': r['theta_hat'],
            'ci_low': r['ci_low'],
            'ci_high': r['ci_high'],
            'theta_true': -0.05,
        })
df = pd.DataFrame(results)
df.to_parquet('results/benchmark_raw.parquet')
```

**Expected runtime**: OLS + partial_corr fast, RF+SHAP slow (~30s per rep), CausalForestDML medium (~20s per rep). Total ≈ 2 hours. Parallelize with `joblib` if needed.

**Metrics computation**:
```python
for method, grp in df.groupby('method'):
    bias = grp['theta_hat'].mean() - theta_true
    var = grp['theta_hat'].var()
    rmse = np.sqrt(((grp['theta_hat'] - theta_true) ** 2).mean())
    if grp['ci_low'].notna().all():
        coverage = ((grp['ci_low'] <= theta_true) & (theta_true <= grp['ci_high'])).mean()
        power = ((grp['ci_low'] > 0) | (grp['ci_high'] < 0)).mean()
    else:
        coverage = power = None
    print(method, bias, var, rmse, coverage, power)
```

**Afternoon (3h) — Figures and cross-check**

Figures:
1. **Bias-coverage scatter** (x=|bias|, y=coverage, 4 points)
2. **θ̂ violin plot** (4 violins, red line at θ_true)
3. **Summary table** (bias, var, RMSE, coverage, power)

**Cross-check for R1 (RF bias)**: Re-run CausalForestDML with `model_y` and `model_t` set to `XGBRegressor`. Verify coverage within ±5% of RF version. If coverage drops >10%, DGP bias is real — document and adjust interpretation.

**Day 4 deliverables**
- [ ] `benchmark_raw.parquet`
- [ ] Figure 1: bias-coverage scatter → `results/fig1_bias_coverage.png`
- [ ] Figure 2: violin plot → `results/fig2_violin.png`
- [ ] Table 1: metrics summary → `results/table1_metrics.csv`
- [ ] XGBoost cross-check result documented

**Day 4 decision point** (CRITICAL):
- ✅ **Green**: CausalForestDML coverage ≥ 85% AND bias smaller than all baselines → proceed to Day 5
- ⚠️ **Yellow**: coverage ≥ 85% BUT bias comparable to OLS → proceed to Day 5 with downgraded narrative
- ❌ **Red**: coverage < 70% OR bias worse than OLS → do NOT proceed to Day 5 real CAMELS; use Day 5 to diagnose (DGP design? bug? method limitation?) and write "null result POC report"

---

### Day 5 — Real CAMELS Application + Sensitivity (6h)

**Precondition**: Day 4 ended green or yellow. If red, this day becomes diagnosis day instead.

**Morning (3h) — Core application**
```python
df = pd.read_parquet('results/real_clean.parquet')
Y = df['runoff_coeff'].values
T = df['frac_forest'].values
W = df[W_cols].values

est = CausalForestDML(
    model_y=RandomForestRegressor(n_estimators=500, min_samples_leaf=10),
    model_t=RandomForestRegressor(n_estimators=500, min_samples_leaf=10),
    n_estimators=2000,
    min_samples_leaf=10,
    cv=5,
    random_state=0,
)
est.fit(Y, T, X=W, W=W)  # X = W for simplicity

ate = est.ate(X=W)
ate_ci = est.ate_interval(X=W, alpha=0.05)
cate = est.effect(W)
feature_importance = est.feature_importances_
```

Save: `results/real_camels_main.json` with ate, ci, cate array, feature_importance.

Figures:
- CATE histogram
- CATE vs aridity scatter (heterogeneity along a key dimension)
- Feature importance bar chart

**Afternoon (3h) — Sensitivity analysis**

**S1 — ML swap** (1h)
- Re-run DML with XGBoost as model_y/model_t
- Re-run DML with Ridge regression as model_y/model_t
- Record θ̂ variation

**S2 — Propensity trim** (1h)
- Compute `m_hat = rf_m.predict(W)`
- Drop basins where `|T - m_hat|` is in bottom 5% (extreme propensity)
- Re-run DML on trimmed set
- Record θ̂ change

**S3 — Synthetic hidden confounder** (1h)
- For r in [0.1, 0.2, 0.3]:
  - Generate `U = r*T + sqrt(1-r²)*N(0,1)`
  - Add U to W as if it were observed (fake "revealing" a hidden confounder)
  - Re-run DML
  - Record θ̂ shift
- This answers: "how strong would an unobserved U need to be to flip the sign?"

**Day 5 deliverables**
- [ ] `real_camels_main.json`
- [ ] 3 figures (CATE hist, CATE vs aridity, feature importance)
- [ ] Sensitivity table with 3 rows (S1, S2, S3 variants)

---

### Day 6 — Slack / Debug Buffer (6h reserved, variable usage)

**This day is mandatory, not optional.**

Historical pattern from previous POCs (adversarial, SCL-LSTM, kuwei): every one hit a ~0.5-1 day blocker somewhere. Planning 7 days without slack = planning to be late.

**Allowed uses (in priority order)**:
1. Fix bugs discovered on Days 3-5
2. Re-run failed experiments
3. Complete any Day 5 sensitivity variants that didn't finish
4. Compute additional diagnostics (propensity histogram, residual plots)
5. Polish figures (labels, fonts, legends)
6. Start drafting POC report outline

**NOT allowed**:
- Adding new experiments (scope creep)
- Adding new baselines (scope creep)
- Expanding to GWL data (scope creep)
- Writing paper-quality prose (that's post-POC)

If Day 6 finishes by noon with nothing to fix, **use the afternoon to start Day 7 report** — never invent new work.

---

### Day 7 — Report and Decision (4h)

Write `src/method_dml/reports/poc_report_2026-04-XX.md` (2 pages max):

```markdown
# DML for Hydrology — POC Report

## Question
Can DML provide a methodologically improved causal attribution framework
for hydrology compared to current practice (OLS, partial correlation, SHAP)?

## Method
- Semi-synthetic benchmark: real CAMELS W structure, learned nuisance,
  injected θ_true = -0.05, 100 reps
- Real application: T = forest cover, Y = runoff coefficient, 531 basins
- Sensitivity: ML swap, propensity trim, synthetic hidden confounder

## Benchmark Results
[Table 1]
[Figure 1 and Figure 2]

## Real CAMELS Results
ATE = X ± Y (95% CI)
Interpretation: [one paragraph]
[Figures]

## Sensitivity
[Table of sensitivity results]
Robust to: [list]
Not robust to: [list]

## Decision
□ GO: proceed to 2-3 month paper with full narrative
□ GO (downgraded): proceed with "correct uncertainty quantification" narrative
□ STOP: pivot main line B to another method

Chosen decision: [circle one]

## Next Steps (if GO)
- Week 2-4: [specific actions]
- Month 2: [specific actions]
- Target journal: [HESS / WRR / Environmental Modelling & Software]

## Next Steps (if STOP)
- Update memory with what didn't work
- Evaluate alternative B1 methods from pool
```

**Day 7 deliverable**
- [ ] 2-page report with explicit decision checkbox ticked
- [ ] Memory update: append POC outcome to `method_dml_for_hydrology.md`

---

## 6. Directory Structure

```
src/method_dml/
├── README.md
├── requirements-dml.txt
├── baselines/
│   ├── __init__.py
│   ├── ols.py
│   ├── partial_corr.py
│   ├── rf_shap.py
│   └── causal_forest_dml.py
├── dgp/
│   ├── __init__.py
│   └── semi_synthetic.py
├── benchmark/
│   ├── __init__.py
│   ├── run_benchmark.py
│   ├── metrics.py
│   └── plots.py
├── real_camels/
│   ├── __init__.py
│   ├── load_data.py
│   ├── run_dml.py
│   └── sensitivity.py
├── tests/
│   └── test_baselines_trivial.py
├── notebooks/
│   ├── 01_dag.ipynb
│   ├── 02_benchmark_results.ipynb
│   └── 03_real_camels_results.ipynb
├── results/
│   ├── real_clean.parquet
│   ├── semi_synthetic.parquet
│   ├── benchmark_raw.parquet
│   ├── real_camels_main.json
│   ├── fig1_bias_coverage.png
│   ├── fig2_violin.png
│   ├── table1_metrics.csv
│   └── sensitivity_table.csv
└── reports/
    └── poc_report_2026-04-XX.md
```

---

## 7. Pre-Registered Predictions

Recording these **before** running to prevent hindsight bias. Day 7 report should compare actual outcomes to these.

| Quantity | Predicted value | Confidence |
|---|---|---|
| CausalForestDML coverage on semi-synthetic | 85-92% | Medium-high |
| OLS coverage on semi-synthetic | 40-60% | High |
| CausalForestDML bias smaller than OLS by factor | 2-4× | Medium |
| SHAP "θ̂" dramatically different from θ_true (off by > 50%) | Yes | High |
| Real CAMELS CausalForestDML gives statistically significant negative ATE | 70% probability | Low |
| Day 5 sensitivity S3: r=0.2 flips sign | 50% probability | Low |

**If predictions are systematically wrong** (e.g., DML coverage < 70% on semi-synthetic where I predicted 85-92%), this is itself a research finding and should be noted in the report.

---

## 8. Go/No-Go Decision Matrix (final)

Apply at end of Day 4 (benchmark decision) and end of Day 7 (overall POC decision).

| Day 4 benchmark | Day 5 real CAMELS | Day 7 decision |
|---|---|---|
| Green (coverage ≥85, bias < baselines) | Significant effect, robust sensitivity | ✅ GO full |
| Green | Significant effect, weak sensitivity | ✅ GO with explicit limits section |
| Green | Non-significant effect | ⚠️ GO with "null real result is itself a finding" |
| Yellow (coverage OK, bias ≈ OLS) | Any | ⚠️ GO downgraded to "uncertainty quantification" narrative |
| Red (coverage <70 or bias worse) | N/A (skipped) | ❌ STOP, pivot 主线 B |

---

## 9. Post-POC (not in scope of this spec but documented for continuity)

**If GO**: three-stage pipeline to GROW global attribution (2026-04-14 integrated from friend's proposal, see `gwl_global_project.md` X branch):

### Stage 1 — Week 1: this POC (CAMELS semi-synthetic + forest→runoff)

### Stage 2 — Week 2-3: GROW mini-POC (mandatory bridge, new)

**Why mandatory**: CAMELS POC passing ≠ DML usable on GROW. CAMELS is 531 US basins, relatively homogeneous; GROW is 204K wells across 55 countries, highly heterogeneous. Three technical traps identified in the friend's proposal must be validated on a real GROW subset before committing to global analysis:

1. **Multi-treatment overlap collapse** — pumping and climate strongly correlated; arid wells simultaneously high-pumping and low-rainfall create propensity mass collapse → DML CI explodes
2. **Missing temporal precedence** — cross-sectional design cannot distinguish "pumping → GWL drop" from "low GWL → more pumping"; requires panel / lagged DML
3. **GROW well selection bias** — 204K wells are non-random (drilled where water use exists); "global sample" ≠ "global population", Berkson-style bias

**Plan**: Pick 1 regional aquifer (Ogallala preferred: dense literature, clear pumping-vs-climate contrast; alternatives: North China Plain, Indian Punjab). Pull GROW subset (hundreds to thousands of wells). Run three diagnostic checks:
- **Overlap**: compute `m_hat = E[T|W]`, plot propensity distribution, detect mass collapse
- **Temporal**: if multi-year data available, compare cross-sectional vs panel DML; if lagged DML θ̂ differs materially from cross-sectional, cross-sectional is unreliable
- **Selection**: compare aggregated GROW trend to GRACE trend on the same region; check whether well sample is representative

**Go/no-go**: If traps are mitigable → proceed to Stage 3 global. If not mitigable → downgrade to "regional attribution only" narrative and target WRR instead of Nature-level.

### Stage 3 — Month 2-4: Global GROW attribution (paper main)
- Full stress-test (Levels 1 and 2, multi-θ, multi-noise)
- 3-tier paper pipeline: benchmark paper (HESS) → application paper (WRR) → GROW GWL paper (Nature Comms / GRL default, Nature Water stretch)
- DAG formalization with DoWhy
- Panel DML design if temporal trap required it in Stage 2
- Must address in intro: Rodell 2018 (GRACE), Famiglietti 2014, Jasechko 2024, Bierkens & Wada 2019, Clark 2025 (SHAP rival)
- Submission preparation

**Journal target reality check**: Nature Water is stretch (~20-30% probability), not default. Default target is Nature Communications / GRL (~60%). Do not let the team anchor on Nature Water.

---

**If STOP** (Day 7 red): update `external_methods_import.md` and `method_dml_for_hydrology.md` with failure mode, then evaluate next B1 candidate (Synthetic Controls? IV? Causal Forests as standalone?). Stages 2-3 are cancelled; friend's GROW proposal returns to backlog.

---

## 10. Spec Update Log

- 2026-04-13: Initial spec written after multi-round scoping conversation. Settled on semi-synthetic + 4 baselines + 1 θ + 100 reps + mandatory slack day.
- 2026-04-14: §9 Post-POC restructured into three-stage pipeline. Friend's DML-GWL proposal (GROW + Nolte 2025 + ERA5, Nature Water target) integrated with objective analysis: 3 technical traps flagged (overlap / temporal / selection bias), journal target downgraded from Nature Water to Nature Comms / GRL default, GROW mini-POC (Week 2-3, Ogallala candidate) inserted as mandatory bridge between CAMELS POC and global application. See `gwl_global_project.md` X branch for full detail.
