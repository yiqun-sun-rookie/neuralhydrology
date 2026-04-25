# CAMELS-US 531 Published Benchmark — Alignment Target

**Status:** Defines the published benchmark we are trying to align against. Companion doc to `camels_us_531_current_protocol.md`. Implementation work happens under `camels_us_531_repro_v01`.

**Target sources:**
- Newman, A. J., et al. (2015). Development of a large-sample watershed-scale hydrometeorological data set for the contiguous USA. *Hydrol. Earth Syst. Sci.*, 19, 209–223.
- Kratzert, F., et al. (2019). Towards learning universal, regional, and local hydrological behaviors via machine learning applied to large-sample datasets. *Hydrol. Earth Syst. Sci.*, 23, 5089–5110.
- (Cross-check) Kratzert, F., et al. (2019). NeuralHydrology — interpreting LSTMs in hydrology. arXiv:1903.07903 / WRR.

**Key alignment number:** Published median SAC-SMA + Snow-17 NSE on the 531-basin subset is reported by Kratzert et al. 2019 at **≈ 0.64** (median over basins, Daymet forcing, per-basin calibration). This is the single number the aligned-protocol rerun is benchmarked against.

---

## 1. Confidently Known Targets

These items are stated in the published sources and must be matched verbatim.

### 1.1 Basin list
- The canonical 531-basin subset of CAMELS-US, as filtered from Newman et al. 2015's 671-basin set (Kratzert 2019 documents the 531 sub-selection criteria).
- Source: Kratzert 2019 supplementary lists / NeuralHydrology repo `531_basin_list.txt`.
- **Action:** Bit-for-bit reuse the existing `src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531.txt` only after diff-verifying it against the canonical NeuralHydrology 531 basin list. If a diff is found, rebuild the manifest from the canonical source.

### 1.2 Hydrological model
- SAC-SMA coupled with Snow-17.
- Per-basin calibration (one parameter set per basin).
- Newman 2015 used Shuffled Complex Evolution (SCE-UA) for SAC-SMA + Snow-17 calibration.

### 1.3 Forcing
- Daymet (the version actually used by Newman 2015 for the published SAC-SMA numbers; Maurer and NLDAS are alternatives reported in the same paper).
- For alignment: use the Daymet forcing already shipped with the CAMELS-US v1.2 dataset and currently consumed by `runner._load_period`.

### 1.4 Metric
- Nash–Sutcliffe Efficiency (NSE) per basin, then median over basins.
- NSE definition: standard `1 - sum((obs - sim)^2) / sum((obs - obs_mean)^2)` over the evaluation window.
- Compare medians at the basin level, not aggregated over time.

### 1.5 Failed-basin handling
- Newman 2015 / Kratzert 2019 keep all 531 basins in the median; failed/degenerate basins are not silently dropped.
- For alignment: any failed basin counts as a basin in the median — do not exclude failures from `median(NSE)`.

---

## 2. Items Requiring Source-PDF Verification Before Locking

These items are described qualitatively in the published sources but the numeric details I do not have at hand. They must be verified against the source PDFs before `repro_v01` can claim "strict reproduction." Until verified, this protocol is "closest feasible alignment" only.

### 2.1 Calibration / evaluation periods
- Newman 2015 split-sample structure (calibration vs evaluation windows, including warm-up).
- Kratzert 2019 uses a different period for LSTM training vs the SAC-SMA benchmark numbers it cites; the SAC-SMA NSE = 0.64 number must be paired with its corresponding evaluation window.
- **Open question:** Whether the published 0.64 number is computed on calibration-period flow, evaluation-period flow, or full-record flow.
- **Action:** Read Newman 2015 §3 and Kratzert 2019 Table 2 / §4 to confirm exact `(calibration_start, calibration_end, evaluation_start, evaluation_end)`.

### 2.2 Warm-up handling
- How many years of warm-up are dropped before computing NSE in the published benchmark.
- **Action:** Verify against Newman 2015.

---

## 3. Must-Align vs Nice-to-Align

### Must align (otherwise the comparison is not defensible)
- Basin list (§1.1)
- Hydrological model class (§1.2)
- Forcing version (§1.3)
- Metric definition (§1.4)
- Failed-basin handling (§1.5)
- Calibration/evaluation period boundaries (§2.1, after verification)
- Warm-up window (§2.2, after verification)

### Nice to align (differences here are tolerable but must be disclosed)
- **Exact optimizer family.** Newman 2015 uses SCE-UA; our protocol uses CMA-ES. This is a documented difference, not a defect.
- **Exact per-basin restart count.** We will run a uniform `n_restarts` for all three model families in `repro_v01`; the published SAC-SMA may use a different schedule.
- **Internal snow-routine structure.** Snow-17 vs PDD differ in formulation. This is precisely the model-family comparison we want, so the difference is a feature, not a bug — but it must be described in any comparison table.
- **Trial budget per restart.** We use 5000 CMA-ES evaluations; the published SAC-SMA SCE-UA budget is not directly comparable in evaluation count.

---

## 4. Hard Decision On Claim Language

If after verification (§2) the calibration/evaluation periods or forcing version cannot be matched exactly, all paper text must use **"cross-study comparison"** language — not "strict benchmark reproduction." Allowed:

- `numerically above the published SAC-SMA benchmark`
- `comparable to the published SAC-SMA benchmark`

Disallowed unless every must-align item in §3 is matched:

- `outperforms the SAC-SMA benchmark`
- `beats the Kratzert baseline`
- `surpasses Newman et al. 2015`

---

## 5. What `repro_v01` Will And Will Not Solve

`repro_v01` (defined in `camels_us_531_repro_protocol.md`, to be written in Task 3) will:

- collapse the unused validation split into a clean `calibration` / `evaluation` two-segment design
- enforce the same `n_restarts` across XAJ / HBV / GR4J so internal comparison is fair
- record forcing, period boundaries, trials, restarts in metadata for every basin run

`repro_v01` will not:

- match SCE-UA optimizer behavior bit-for-bit
- replace PDD with Snow-17 inside our XAJ/HBV implementations
- reproduce Newman 2015's exact numerical output

Therefore even after `repro_v01` reruns, the comparison against the published 0.64 is still a "cross-study with aligned protocol" comparison, not a strict reproduction.
