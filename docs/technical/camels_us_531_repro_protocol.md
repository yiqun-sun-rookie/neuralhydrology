# CAMELS-US 531 `repro_v01` Protocol — Benchmark-Aligned Track

**Status:** New track parallel to the frozen `camels_us_531_v02` exploratory baseline. Implementation: Tasks 3–6 of `docs/plans/2026-04-24-camels-531-benchmark-alignment.md`.

**Goal:** Provide the closest feasible alignment with the Newman et al. 2015 / Kratzert et al. 2019 published 531-basin SAC-SMA + Snow-17 benchmark, so that comparisons against the published median NSE ≈ 0.64 are defensible as cross-study (not strict reproduction).

**Companion docs:**
- Frozen baseline: `camels_us_531_current_protocol.md`
- Alignment target: `camels_us_531_published_target.md`

---

## 1. Identifier And Storage

- Protocol name: `camels_us_531_repro_v01`
- Constant: `REPRO_VERSION` in `src/xaj_global_pilot/config.py`
- Result root: `results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/`
- Log root: `logs/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/`
- Smoke output: `results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_smoke/`

`repro_v01` outputs must NOT overwrite or merge with `camels_us_531_v02` artifacts.

## 2. Basin List

- File: `src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531_repro.txt`
- Bit-identical copy of `conceptual_benchmark_camels_us_531.txt` (verified by `diff` at creation time, 2026-04-25).
- The duplicate file exists so that the aligned-track config never has to point at the v02 manifest and so that any future divergence (after canonical 531-list verification) can be made independently.

## 3. Splits — Two Segments Only

| Segment       | Start         | End           | Role                                |
|---------------|---------------|---------------|-------------------------------------|
| `calibration` | 1990-10-01    | 1995-09-30    | Parameter calibration window        |
| `evaluation`  | 2000-10-01    | 2005-09-30    | Out-of-sample metric computation    |

Constants: `REPRO_CALIBRATION_START_DATE` / `REPRO_CALIBRATION_END_DATE` / `REPRO_EVALUATION_START_DATE` / `REPRO_EVALUATION_END_DATE` in `config.py`.

Function: `repro_split_periods()` in `config.py` — returns `OrderedDict` with only `calibration` and `evaluation`. **No `validation` entry.**

### Open issue (placeholder dates)

The four date constants above are **inherited from the v02 train/test windows pending source-PDF verification** of Newman 2015 §3 and Kratzert 2019 §4 / Table 2 (see `camels_us_531_published_target.md` §2.1). When verification completes, only the four constants need updating; no protocol structure or runner change is required. Until then, `repro_v01` is "closest feasible alignment," not "strict reproduction."

## 4. Forcing

- CAMELS-US `daymet`, loaded via `src.hydroagent.data_loading.load_camels_basin`.
- Same column resolution as v02 (`prcp`, `ep|pet|evap`, `tmean`).
- Forcing version is part of the must-align set (`camels_us_531_published_target.md` §1.3); any future change here breaks alignment and must be re-justified.

## 5. Models In Scope

- `xaj_pdd` — XAJ + Positive Degree-Day snow (NumPy, Numba)
- `hbv` — SuperflexPy HBV
- `gr4j_pdd` — SuperflexPy GR4J + PDD

Other variants (`xaj`, `xaj_smooth_et`, etc.) are not part of `repro_v01` — they remain in the exploratory v02 track.

## 6. Calibration Budget — Uniform Across Models

The single most important asymmetry in v02 was that XAJ ran with `n_restarts=3` while HBV/GR4J ran with `n_restarts=1` (despite metadata claiming otherwise). `repro_v01` fixes this by:

- Running every model family with the same explicit `n_restarts`.
- Default: `n_restarts = DEFAULT_RESTARTS = 3`, `n_trials = DEFAULT_CALIBRATION_TRIALS = 5000` per restart.
- The `--restarts` CLI flag in the HPC chunk runner must actually be plumbed through to the calibration call (Task 4 step 3).
- Per-restart seed schedule: `42 + restart * 1000` (already used by XAJ; will be applied to Superflex via the new `n_restarts` parameter on `SuperflexEnv.auto_calibrate` / `_calibrate_sfpy`).

Optimizer family (CMA-ES) and trial budget intentionally differ from Newman 2015's SCE-UA — this is in the nice-to-align bucket and will be disclosed in the comparison table (Task 7).

## 7. Metric

- NSE per basin on the `evaluation` segment.
- Median across all 531 basins; failed basins counted into the median (no silent drop), per `camels_us_531_published_target.md` §1.5.
- Auxiliary metrics (KGE, bias, peak bias, low-flow bias) are still computed and logged but are not the alignment-target metric.

## 8. Required Metadata Per Run

Every chunk's metadata.json (written by the HPC runner) must include, at minimum:

- `protocol`: `"camels_us_531_repro_v01"`
- `model`
- `forcing`: `"daymet"`
- `calibration_start` / `calibration_end`
- `evaluation_start` / `evaluation_end`
- `trials`: actual value forwarded to the calibration call
- `restarts`: actual value forwarded to the calibration call
- `n_basins`, `n_executed`, `n_skipped_existing`
- `data_root`

If any of these are missing or numerically inconsistent with the protocol constants, the run is invalid and must not feed the comparison table.

## 9. What This Protocol Does And Does Not Claim

`repro_v01` claims:

- protocol-internal fairness across XAJ / HBV / GR4J (uniform restart budget)
- two-segment calibration/evaluation semantics with no unused split
- defensible "cross-study comparison" against the published 0.64 median NSE

`repro_v01` does NOT claim:

- bit-for-bit reproduction of Newman 2015 numbers
- equivalence between PDD and Snow-17
- equivalence between CMA-ES and SCE-UA
- that strict head-to-head against the published SAC-SMA result is established

Allowed claim language remains as defined in `camels_us_531_published_target.md` §4.
