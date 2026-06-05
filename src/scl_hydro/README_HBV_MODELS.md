# Which HBV is which (disambiguation) — `src/scl_hydro/`

There are **multiple HBV implementations** in this repo. They are NOT interchangeable.
This note exists so future work (esp. the kalmannet DA migration) does not grab the wrong one.

## ✅ HBV-lite — THE benchmark model (use this)
- **NumPy/Numba (authoritative):** `hbv_lite_numpy.py` → `simulate_hbv_lite`
- **PyTorch (differentiable twin):** `hbv_lite.py` → `class DifferentiableHBVLite`
- **Calibrators:** `hbv_lite_cma_calibrate.py` (CMA-ES, used for the published runs), `hbv_lite_calibrate.py`
- **Runner/scripts:** `scripts/run_hbv_lite_cma_repro_v01.py`, `scripts/run_hbv_lite_repro_v01.py`, `scripts/sanity_check_hbv_lite.py`
- **Structure:** hydroDL2 HBV-light port. **5 states** `[SNOWPACK, MELTWATER, SM, SUZ, SLZ]`, **13 params**
  `parTT, parCFMAX, parCFR, parCWH, parFC, parBETA, parLP, parK0, parK1, parUZL, parPERC, parK2, lag_time`.
- **Benchmark:** CAMELS-US 531, repro_v01 protocol → **median eval NSE 0.5995 (single v5) / 0.6227 (9-way ensemble)**.
  This is the ONLY HBV with a 531 summary CSV (`results/.../camels_us_531_repro_v01*/summary/hbv_lite_cma_local_full.csv`).
- **This is the model used for the kalmannet large-scale DA migration**
  (`kalmannet/docs/plans/2026-06-05-hbv-lite-da-migration.md`). Caveat: the torch lag is RISING-half;
  the numpy production uses RECESSION-half — fix the torch `_triangular_lag_batch` before relying on it.

## ⚠️ DifferentiableHBV (`hbv_torch.py`) — the OLD HBV, kept ONLY for SCL-LSTM
- **PyTorch:** `hbv_torch.py` → `class DifferentiableHBV`; **NumPy twin:** the package `hbv_camels_us_531`,
  archived 2026-06-05 to `src/_archive/hbv_camels_us_531_20260605/hbv_camels_us_531/` but **kept on disk** as
  the equivalence reference for `test/test_scl_hydro_hbv_torch.py` (which now imports it from the archive path).
- **Calibrator:** `hbv_calibrate_torch.py`. Scripts: `scripts/pilot_coupled.py`, `scripts/tango_*.py`.
- **Structure:** older Snow→Soil→Fast(power)+Slow(linear)→Lag model. **4 states** `[S_snow, S_soil, S_fast, S_slow]`,
  **10 params** `t0, k_snow, Smax, Ce, beta, split, k_fast, alpha, k_slow, lag_time`.
- **DO NOT use for the conceptual benchmark or the DA migration** — it did NOT produce the 0.6227 number.
- **Still ACTIVE** because the **SCL-LSTM project** (`coupled_model.py` → `CoupledHydroModel`) uses
  `DifferentiableHBV` as its physics core. Archiving it would break SCL-LSTM. Test: `test/test_scl_hydro_hbv_torch.py`.

## 🗄️ HBV96P1 — ARCHIVED 2026-06-05
- Was `hbv96_p1.py` + `hbv96_p1_calibrate.py` + `scripts/{run_hbv96_p1_repro_v01,sanity_check_hbv96_p1,chain_b_then_a}.py`.
- Intermediate "upgrade over DifferentiableHBV" experiment; **did not win the 531 benchmark** (no summary CSV, no results).
- Moved to `src/_archive/scl_hydro_hbv96_20260605/` to avoid confusion with HBV-lite. Self-contained (no other code imported it).

## 🗄️ hbv_camels_us_531 — ARCHIVED 2026-06-05
- The NumPy old-HBV (10-param, same lineage as `hbv_torch.py`), from the Idea-10 15-basin conceptual benchmark era.
- It was the **SuperflexPy "hbv" model** of the OLD xaj_global_pilot benchmark (`model_catalog` → `runner.py` /
  HPC conceptual-benchmark pipeline), superseded by the standalone NumPy+Numba `hbv_lite` repro_v01 runner.
- Archived (package + its 4 tests + `benchmark_conceptual_models.py` + results/logs) to
  `src/_archive/hbv_camels_us_531_20260605/`. Removed the `"hbv"` entry from `model_catalog.py` and
  `build_hbv_structure` from `structures.py`; catalog now = xaj_pdd / gr4j_pdd / xaj / gr4j.
- Still imported (from the archive path) by `test/test_scl_hydro_hbv_torch.py` as the equivalence reference for
  the KEPT `DifferentiableHBV` (SCL-LSTM). That is intentional.

---
*One-line rule: for the conceptual benchmark and the DA process model, use **HBV-lite** (`hbv_lite*.py`).
`hbv_torch.py`'s `DifferentiableHBV` belongs to **SCL-LSTM**. `hbv96_p1` is archived.*
