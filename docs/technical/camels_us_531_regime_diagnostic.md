# XAJ-PDD on CAMELS-US 531: Hydroclimatic-Regime Diagnostic

**Source data:** `results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/xaj_pdd_local_full.csv`
**Per-basin (ours + 5 published):** `results/.../diagnostic/cross_method_per_basin_nse.csv`
**Figures:**
- `xaj_pdd_regime_breakdown.png` — XAJ-PDD self-diagnostic (regime, aridity, snow, seasonality)
- `cross_method_regime_comparison.png` — XAJ-PDD vs 5 published benchmarks × regime (heatmap + grouped bar)
**Generated:** 2026-04-29 (regime self-diagnostic), updated 2026-04-30 (cross-method comparison after pulling Kratzert 2019 ealstm `all_metrics.p` per-basin NSE)

This document is the regime-stratified diagnostic of XAJ-PDD on the protocol-aligned CAMELS-US 531 benchmark, replacing the misleading 15-basin median 0.637 narrative with an honest, mechanistically grounded picture.

---

## 1. Headline numbers (531 success / 531 total)

| Pool | Median NSE | Mean NSE |
|------|------------|----------|
| Full 531 (XAJ-PDD, ours) | **0.4458** | -0.0113 |
| Published SAC-SMA + Snow-17 (Kratzert 2019 Table 3, 447 common basins) | **0.68** | 0.62 |
| Gap (apples-to-oranges, different basin sets) | -0.23 | — |

A strict apples-to-apples comparison on the 447 common-basin subset is still pending and is the right context for the gap. But even the full-set median already tells the main story: **XAJ-PDD's overall performance is well below the published conceptual baseline.**

## 2. Regime breakdown (the actual finding)

Regime classification follows the thresholds already encoded in `src/xaj_global_pilot/config.py`:

- `snow-dominated`: `frac_snow ≥ 0.20`
- `humid`: `aridity < 1.0` (and not snow-dominated)
- `semi-humid`: `1.0 ≤ aridity < 1.5`
- `semi-arid/arid`: `aridity ≥ 1.5`

| Regime | n | Median NSE | Mean NSE | % NSE > 0.7 | % NSE > 0.5 | % NSE < 0 | % NSE < -1 |
|--------|---|------------|----------|-------------|-------------|-----------|------------|
| snow-dominated  | 152 | **0.509** | 0.228 | **21.1%** | 55.3% | 6.6% | 3.9% |
| humid           | 282 | 0.444 | 0.445 | 13.1% | 31.9% | 3.9% | 0.4% |
| semi-humid      |  54 | 0.406 | 0.104 | 3.7% | 14.8% | 11.1% | 5.6% |
| semi-arid/arid  |  43 | **-0.029** | **-3.99** | **0.0%** | 18.6% | **51.2%** | **16.3%** |

**Reading the table top-to-bottom:** XAJ-PDD's median NSE drops monotonically with aridity, from 0.51 in snow-dominated basins to -0.03 in semi-arid/arid basins. The fraction of NSE>0.7 ("good fit") drops from 21% to 0% across the same gradient.

## 3. Spearman rank correlations (NSE vs CAMELS climate attributes)

| Attribute | Spearman ρ | Sign | Interpretation |
|-----------|------------|------|---------------|
| `aridity` (PET / P) | **-0.443** | strong neg | drier → worse |
| `p_seasonality` | **-0.550** | strong neg | stronger seasonality → worse |
| `p_mean` | +0.454 | strong pos | wetter → better |
| `frac_snow` | +0.152 | weak pos | snowier → marginally better (PDD doing some work) |

The strongest correlation is precipitation seasonality (-0.55), which captures both the snowmelt-driven Western basins (negative seasonality) and the monsoon-driven Southwestern basins (strong positive seasonality). XAJ's saturation-excess assumption struggles at both extremes, but for opposite reasons.

## 4. Where do the failures live?

**The 17 catastrophic failures (NSE < -1):**

| Regime | Sample share (n / 531) | Blow-up share (n / 17) | Over-representation |
|--------|------------------------|------------------------|---------------------|
| semi-arid/arid | 8% (43)  | **41%** (7) | **5.0×** |
| semi-humid | 10% (54) | 18% (3) | 1.7× |
| snow-dominated | 29% (152) | 35% (6) | 1.2× |
| humid | 53% (282) | 6% (1) | 0.1× |

Semi-arid/arid basins are **5× over-represented** as catastrophic failures. The 6 snow-dominated blow-ups are an unexpected secondary finding worth a closer look (likely high-elevation arid basins where snow + low precipitation co-occur).

**The 71 high-skill basins (NSE ≥ 0.7):**

| Regime | n / 71 | Share |
|--------|--------|-------|
| humid | 37 | 52% |
| snow-dominated | 32 | 45% |
| semi-humid | 2 | 3% |
| semi-arid/arid | **0** | **0%** |

**No semi-arid/arid basin in our 531 set achieves NSE ≥ 0.7.** This is not a sampling artifact — it is a structural limit of the model class on this regime.

## 5. The mechanistic interpretation

XAJ is a **saturation-excess (Dunne) runoff model**: streamflow is generated when soil moisture exceeds the catchment storage capacity. This is well-suited to humid and snowmelt-driven basins where soils saturate frequently.

Semi-arid/arid basins, by contrast, generate runoff predominantly via **infiltration-excess (Hortonian) overland flow**: short, intense rainfall events exceed the soil's infiltration capacity and run off the surface without ever filling the soil column. XAJ's storage-capacity formulation has no representation for this mechanism.

The 0.4458 → -0.029 collapse from humid to arid is therefore **not a calibration deficiency** that more CMA-ES restarts could fix. It is a **structural assumption violation**, and the 17 blow-up basins are where CMA-ES still tries to find a parameter set that reproduces a runoff regime the model fundamentally cannot produce.

## 6. What this means for the paper

### Claims that are now supported

1. *"XAJ-PDD performance correlates strongly with hydroclimatic regime (Spearman ρ = -0.44 vs aridity, -0.55 vs precipitation seasonality)."*
2. *"In humid + snow-dominated regimes, XAJ-PDD reaches median NSE 0.44–0.51, comparable to mid-tier conceptual baselines."*
3. *"In semi-arid/arid regimes, XAJ-PDD systematically fails (median NSE -0.03; 0% of basins reach NSE ≥ 0.7), consistent with the model's saturation-excess assumption being violated."*
4. *"Catastrophic failures (NSE < -1) are 5× over-represented in arid basins, identifying a structural limit rather than a calibration deficiency."*
5. *"Protocol alignment with the published CAMELS benchmark (Kratzert 2019) reveals that prior 15-basin reports of median NSE 0.637 substantially overstate XAJ-PDD's general capability."*

### Claims that are NOT supported (do not write)

- *"XAJ-PDD is a first-tier conceptual benchmark."* — Disproven on the 531 set.
- *"XAJ-PDD outperforms / is comparable to SAC-SMA + Snow-17."* — Even on humid + snow regimes the gap to published 0.68 median is ~0.15–0.25 NSE.
- *"XAJ-PDD is suitable for global conceptual benchmarking without regime stratification."* — Counter-evidence here.

## 7. Cross-method comparison (XAJ-PDD vs 5 published benchmarks)

Per-basin NSE for SAC-SMA / VIC / FUSE / HBV / mHM was extracted from
`kratzert/ealstm_regional_modeling/notebooks/all_metrics.p` (the same
NSE values published in Kratzert 2019), filtered to our 531 set, and
merged with our regime classification.

### 7.1 Median NSE: model × regime (our 531 set)

| Model | snow-dominated | humid | semi-humid | semi-arid/arid | ALL 531 |
|-------|---------------:|------:|-----------:|---------------:|--------:|
| **XAJ-PDD (ours)**     | 0.509 | 0.444 | 0.406 | **-0.029** | **0.446** |
| SAC-SMA + Snow-17      | 0.607 | 0.627 | 0.573 | 0.385 | 0.607 |
| VIC (basin-cal)        | 0.574 | 0.578 | 0.471 | 0.225 | 0.554 |
| mHM (basin-cal)        | 0.676 | 0.681 | 0.610 | 0.354 | 0.665 |
| **HBV (upper)** — best in every regime | **0.715** | **0.684** | **0.610** | **0.377** | **0.678** |
| FUSE-902               | 0.690 | 0.662 | 0.593 | 0.311 | 0.654 |

### 7.2 Strict head-to-head on the 447 common subset

The 6-way intersection (XAJ-PDD + 5 published, all with finite NSE) on
our 531 set yields **exactly 447 basins** — independently reproducing
the 447 figure quoted in Kratzert 2019.

| Model | Median NSE on 447 |
|-------|-------------------|
| **XAJ-PDD (ours)** | **0.4382** |
| SAC-SMA + Snow-17 | 0.6028 |
| VIC (basin-cal) | 0.5513 |
| mHM (basin-cal) | 0.6659 |
| HBV (upper) | 0.6756 |
| FUSE-902 | 0.6505 |

**Gap on the strict 447 subset:**
- XAJ-PDD vs SAC-SMA: **-0.16 NSE units** (apples-to-apples, same basins, same protocol)
- XAJ-PDD vs HBV upper: -0.24
- XAJ-PDD is the lowest of all six tested benchmarks in every regime.

Our median almost does not change between 531 and 447 (0.4458 → 0.4382, drop of 0.008). The 84 basins removed by the intersection filter are NOT a subset where XAJ-PDD is uniquely bad — they are basins where some published model also failed.

### 7.3 The "regime gradient" is shared across the conceptual family

All conceptual benchmarks lose ~0.24-0.35 NSE going from humid to semi-arid/arid:

| Model | Humid median | Arid median | Drop |
|-------|-------------:|------------:|-----:|
| SAC-SMA + Snow-17 | 0.627 | 0.385 | -0.24 |
| VIC | 0.578 | 0.225 | -0.35 |
| mHM | 0.681 | 0.354 | -0.33 |
| HBV upper | 0.684 | 0.377 | -0.31 |
| FUSE-902 | 0.662 | 0.311 | -0.35 |
| **XAJ-PDD (ours)** | **0.444** | **-0.029** | **-0.47** |

**This reframes the §5 mechanistic interpretation.** The saturation-excess regime collapse is a property of the *whole conceptual family*, not a XAJ-specific defect. XAJ-PDD's collapse is **degree, not kind** — but it is the most severe (-0.47 vs the -0.24 to -0.35 of the published five). XAJ-PDD's storage-capacity formulation has less flexibility than HBV's lower-zone or SAC-SMA's lower-zone tension storage to absorb the structural mismatch in arid basins.

## 8. Updated paper claims

### Newly supported (after cross-method analysis)

1. *"On the protocol-aligned 531-basin benchmark, XAJ-PDD reaches median NSE 0.45, the lowest of six tested conceptual benchmarks (SAC-SMA 0.61, VIC 0.55, mHM 0.67, HBV upper 0.68, FUSE-902 0.65)."*
2. *"All six conceptual benchmarks show a strong regime gradient (humid → arid drop of 0.24–0.47 NSE units), confirming that saturation-excess collapse in arid basins is a property of the conceptual family rather than an XAJ-specific deficiency."*
3. *"XAJ-PDD's collapse is the most severe of the six (-0.47 humid → arid), pointing to lower flexibility in its storage-capacity formulation compared with SAC-SMA / mHM / HBV."*
4. *"Strict head-to-head on the 447 basins where all six models converge: XAJ-PDD median NSE 0.438 vs SAC-SMA 0.603, gap -0.16 NSE units."*

### Reframed (after cross-method analysis)

The earlier framing "*XAJ structural assumption violated in arid regimes*" was correct but incomplete — **all** these models share that limitation. The honest framing is: "*XAJ-PDD ranks below the published conceptual family across every hydroclimatic regime, with the gap widest in arid regimes where the saturation-excess assumption is violated by all family members*."

## 9. Open follow-ups

1. **Snow-dominated blow-ups.** Inspect the 6 snow-regime catastrophic failures — likely high-elevation arid basins where the snow-fraction threshold misclassifies them.
2. **HBV / GR4J ours under same protocol.** When the HPC sbatch returns our own HBV / GR4J results, compare them against the published HBV / GR4J on the regime grid. Do our implementations recover comparable performance? This is the test of whether the gap is "model class" vs "implementation".
3. **Per-basin paired comparison.** For each basin, compute (XAJ-PDD - SAC-SMA), and map the spatial pattern. Are the worst gaps concentrated in particular HUC2 regions or attribute combinations? This could identify a structural amendment direction (e.g., add an infiltration-excess fast-runoff component for arid basins).
