# CAMELS-US 531 Published Benchmark — Alignment Target

**Status:** Verified against CUAHSI HydroShare resource and Kratzert 2019 supplementary code (2026-04-25). Companion doc to `camels_us_531_current_protocol.md` and `camels_us_531_repro_protocol.md`. Implementation under `repro_v01`.

**Target sources (verified):**
- Newman, A. J., et al. (2015). *Hydrol. Earth Syst. Sci.* 19, 209–223. CAMELS-US dataset.
- Kratzert, F., et al. (2019). Towards learning universal, regional, and local hydrological behaviors via machine learning applied to large-sample datasets. *Hydrol. Earth Syst. Sci.* 23, 5089–5110.
- CUAHSI HydroShare resource `474ecc37e7db45baa425cdb4fc1b61e1`: "CAMELS benchmark models" — official SAC-SMA / VIC / FUSE / HBV / mHM benchmark outputs.
- `kratzert/ealstm_regional_modeling` GitHub repo: `main.py` `GLOBAL_SETTINGS`, `papercode/utils.py::load_forcing`.

---

## 1. Verified Alignment Target (locked)

### 1.1 Basin list — 531 basins (verified)
- File on our side: `src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531_repro.txt`.
- Cross-checked against `kratzert/ealstm_regional_modeling/data/basin_list.txt`: **set-difference = 0 (bit-equivalent)**, verified 2026-04-25.

### 1.2 Calibration period — 1 Oct 1999 → 30 Sep 2008 (9 water years)
- HydroShare README: "calibrated using the same forcing data (Maurer)".
- Kratzert 2019 §3 / `ealstm_regional_modeling/main.py` `GLOBAL_SETTINGS`: `train_start = "01101999"`, `train_end = "30092008"`.
- Both LSTM training and conceptual-benchmark calibration use this same 9-year window — that is the deliberate design of Kratzert 2019.

### 1.3 Evaluation period — 1 Oct 1989 → 30 Sep 1999 (10 water years)
- HydroShare README: "model outputs of the validation period (1 Oct 1989 until 30 Sep 1999) only".
- `main.py` `GLOBAL_SETTINGS`: `val_start = "01101989"`, `val_end = "30091999"`.

### 1.4 Forcing — `maurer_extended` (NOT Daymet)
- HydroShare README: "the same forcing data (Maurer)".
- `papercode/utils.py::load_forcing` reads from `basin_mean_forcing/maurer_extended`.
- Daymet is the published *dataset* in Newman 2015 but the **published benchmark NSE numbers we are aligning against are computed on Maurer**.

### 1.5 Metric — NSE per basin, then median / mean over basins
- Standard `1 - sum((obs - sim)^2) / sum((obs - obs_mean)^2)`, evaluated on the evaluation segment.
- Kratzert 2019 reports both **median** and **mean** across the basin set; the published comparison ladder uses both.

### 1.6 Failed-basin handling — 447 common basins (Kratzert 2019 Table 3)
- The published Table 3 statistics are computed over the **447 basins where all benchmark models successfully calibrated**, not over the full 531.
- For strict head-to-head, our XAJ / HBV / GR4J results must be evaluated on the **same 447-basin intersection**.
- For protocol-aligned but superset evaluation, we can also report the median over our successful 531 — but that is a different number from Kratzert's Table 3.

## 2. The Comparison Ladder (Kratzert 2019 Table 3, 447 basins)

| Model | Mean NSE | Median NSE | Notes |
|-------|----------|------------|-------|
| **SAC-SMA + Snow-17** | **0.564** | **0.603** | Primary conceptual baseline |
| mHM (basin) | 0.627 | — | Regional conceptual benchmark |
| HBV (upper bound) | 0.631 | — | Conceptual benchmark |
| FUSE 902 | — | 0.650 | One of three FUSE structures |
| EA-LSTM | (higher) | (higher) | ML reference, not in our head-to-head scope |

This ladder replaces the earlier ≈ 0.64 single-number target. Use the **0.603 SAC-SMA median** as the primary alignment number for any "comparable to / numerically above SAC-SMA" claim.

## 3. Must-Align vs Nice-to-Align

### Must align (verified locked)
- Basin list (§1.1) ✅
- Calibration period (§1.2) ✅
- Evaluation period (§1.3) ✅
- Forcing (§1.4) ✅
- Metric definition (§1.5) ✅
- Failed-basin treatment / 447 common basins (§1.6) — **action: derive intersection list before final comparison table**

### Nice to align (documented gaps, disclosed in paper)
- **Optimizer family.** Newman/HydroShare benchmark used SCE-UA; ours uses CMA-ES. Disclose in methods.
- **Per-basin restart count.** We run uniform `n_restarts = DEFAULT_RESTARTS` for fairness across XAJ / HBV / GR4J; the published benchmark may use a different restart schedule.
- **Snow-routine.** Snow-17 vs PDD differ in formulation. Document as a known structural difference.
- **Trial budget.** 5000 CMA-ES evaluations vs the published SCE-UA budget — not directly comparable in evaluation count.

## 4. Claim Language

Allowed (after `repro_v01` rerun completes):

- `numerically above the published SAC-SMA NSE median of 0.603 on the 447-basin common subset`
- `comparable to mHM / HBV / FUSE within the published conceptual ladder`
- `cross-study comparison against the Kratzert 2019 LSTM benchmark`

Disallowed (regardless of result):

- `outperforms the SAC-SMA benchmark` (without disclosing optimizer / snow-routine / 447-vs-531 distinction)
- `beats the Kratzert baseline`
- `surpasses Newman et al. 2015`
- Any single-number "0.64" claim — that number was a misremembered approximation; the verified target is 0.603 (median) or 0.564 (mean).

## 5. Open Action Items (post-rerun)

- Pull the 447 common-basin list from the HydroShare benchmark NetCDF outputs (intersection of basins where all 5 published models report finite NSE).
- Compute our XAJ / HBV / GR4J medians on the 447 intersection; report alongside the 531-superset numbers.
- Verify whether HydroShare benchmark uses a warm-up year inside 1999-2008 or treats the full 9 years as calibration. If a 1-yr warm-up is used (1999-10 → 2000-09 as warm-up, 2000-10 → 2008-09 as calibration), our setup must match.
