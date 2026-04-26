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

## 3. Splits — Two Segments Only (LOCKED 2026-04-25)

| Segment       | Start         | End           | Role                                |
|---------------|---------------|---------------|-------------------------------------|
| `calibration` | 1999-10-01    | 2008-09-30    | Parameter calibration window (9 WY) |
| `evaluation`  | 1989-10-01    | 1999-09-30    | Out-of-sample metric computation (10 WY) |

Constants: `REPRO_CALIBRATION_START_DATE` / `REPRO_CALIBRATION_END_DATE` / `REPRO_EVALUATION_START_DATE` / `REPRO_EVALUATION_END_DATE` in `config.py`.

Function: `repro_split_periods()` in `config.py` — returns `OrderedDict` with only `calibration` and `evaluation`. **No `validation` entry.**

These windows come from the published CAMELS benchmark on CUAHSI HydroShare (resource `474ecc37e7db45baa425cdb4fc1b61e1`) and are confirmed bit-for-bit by `kratzert/ealstm_regional_modeling/main.py` `GLOBAL_SETTINGS`. They are **the same windows Kratzert 2019 used for both LSTM training and conceptual-benchmark comparison**. See `camels_us_531_published_target.md` §1.2–§1.3 for source citations.

Note: the calibration window (1999–2008) is LATER than the evaluation window (1989–1999). This reverse split-sample is deliberate in Kratzert 2019 — we preserve it because re-anchoring would break the published-benchmark comparison.

## 4. Forcing — Maurer (LOCKED 2026-04-25)

- CAMELS-US `maurer` (NOT `daymet`), loaded via `src.hydroagent.data_loading.load_camels_basin(forcing="maurer")`.
- Constant: `REPRO_FORCING = "maurer"` in `config.py`.
- File path: `data/camels_us/basin_mean_forcing/maurer/<huc>/<basin>_lump_maurer_forcing_leap.txt`.
- Column-name handling is case-insensitive in `load_camels_basin` (Daymet uses lowercase column headers like `prcp(mm/day)`, Maurer uses uppercase `PRCP(mm/day)`); the loader resolves both.
- Required because the published SAC-SMA / VIC / FUSE / HBV / mHM benchmark NSE numbers we are aligning against were computed on Maurer (HydroShare README explicit). Switching to Daymet would break the head-to-head comparison.

**Note on `maurer` vs `maurer_extended`.** Kratzert 2019 ealstm code (`papercode/utils.py::load_forcing`) reads from `basin_mean_forcing/maurer_extended`. `maurer_extended` is the same Maurer et al. 2002 dataset extended in time to 2014. In the 1980-2008 overlap window — which fully covers BOTH our calibration (1999-2008) and evaluation (1989-1999) — the two subdirs are byte-equivalent. We point at `maurer` because the project's local + HPC data tree ships `maurer/` (verified locally: 1980-01-01 to 2008-12-31, 18 HUC subdirs). Override via `--forcing maurer_extended` if a future env ships only the extended variant.

**HPC pre-flight:** `data/camels_us/basin_mean_forcing/maurer/` must exist with the 531-basin set. The smoke / full SLURM scripts assert this directory before launching.

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
- Median **and mean** NSE across the basin set, per Kratzert 2019 Table 3.
- Two basin sets are reported:
  - **531 superset:** our full successful basin set (failed basins counted into median, no silent drop).
  - **447 common subset (strict head-to-head):** intersection with the basins where all 5 published benchmark models report finite NSE; this is the basin set Kratzert 2019 Table 3 statistics use. The 447 list must be derived from the HydroShare benchmark NetCDF outputs before the final comparison table is built (see `camels_us_531_published_target.md` §5).
- Auxiliary metrics (KGE, bias, peak bias, low-flow bias) are still computed and logged but are not the alignment-target metric.

## 8. Required Metadata Per Run

Every chunk's metadata.json (written by the HPC runner) must include, at minimum:

- `protocol`: `"repro_v01"`
- `protocol_version`: `"camels_us_531_repro_v01"`
- `model`
- `forcing`: `"maurer_extended"` (the runner derives this from the protocol when `--forcing` is not explicitly passed)
- `calibration_start` / `calibration_end` (must be `1999-10-01` / `2008-09-30`)
- `evaluation_start` / `evaluation_end` (must be `1989-10-01` / `1999-09-30`)
- `trials`: actual value forwarded to the calibration call
- `restarts`: actual value forwarded to the calibration call
- `n_basins`, `n_executed`, `n_skipped_existing`
- `data_root`

If any of these are missing or numerically inconsistent with the protocol constants, the run is invalid and must not feed the comparison table.

## 9. What This Protocol Does And Does Not Claim

`repro_v01` claims:

- protocol-internal fairness across XAJ / HBV / GR4J (uniform restart budget, same forcing, same calibration/evaluation windows)
- two-segment calibration/evaluation semantics with no unused split
- alignment with the published CAMELS benchmark on the must-align dimensions (basin list, periods, forcing, metric)
- defensible head-to-head comparison against the published SAC-SMA + Snow-17 ladder (median NSE 0.603, mean 0.564 on the 447 common subset) — once the 447-basin intersection is derived

`repro_v01` does NOT claim:

- equivalence between PDD and Snow-17 (structural difference, disclosed)
- equivalence between CMA-ES and SCE-UA (optimizer difference, disclosed)
- alignment with Kratzert 2019 LSTM numbers (cross-study reference only — different model class)
- that any single basin's NSE matches the published per-basin number bit-for-bit

Allowed claim language remains as defined in `camels_us_531_published_target.md` §4.
