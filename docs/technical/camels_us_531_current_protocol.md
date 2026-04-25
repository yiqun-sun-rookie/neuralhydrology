# CAMELS-US 531 Current Protocol (Frozen Exploratory Baseline)

**Status:** Frozen as `camels_us_531_v02` exploratory baseline. Do NOT mutate or overwrite results under this protocol.

**Purpose:** Capture, in code-verified detail, exactly what the current 531-basin conceptual benchmark protocol was so that future cross-study comparisons against the published Newman/Kratzert benchmark are not confused with true protocol-aligned reproduction.

---

## Basin List

- File: `src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531.txt`
- Inherited from the canonical CAMELS-US 531 manifest as used in `src/xaj_global_pilot`.

## Forcing

- CAMELS-US `daymet`, loaded via `src.hydroagent.data_loading.load_camels_basin` from the runner.
- PET column resolution order in `runner._extract_rain_pet`: `ep` → `pet` → `evap`; missing column ⇒ zeros.

## Time Splits

Defined in `src/xaj_global_pilot/config.py`:

| Split        | Start         | End           | Used by calibration?                                  |
|--------------|---------------|---------------|-------------------------------------------------------|
| `train`      | 1990-10-01    | 1995-09-30    | Yes — calibration window                              |
| `validation` | 1995-10-01    | 2000-09-30    | **No — never consumed by `runner.run_single_model_basin`** |
| `test`       | 2000-10-01    | 2005-09-30    | Yes — evaluation window                               |

`runner._load_period` is only called for `train` and `test`. `split_periods()` exposes a `validation` entry but no code path loads it for calibration or model selection.

State propagation: `runner._run_numpy_*` simulates the full train window first, then uses the train end-state as the test-period initial state. Superflex models do not propagate hidden state across splits (each `_build_env` call resets states).

## Warmup

- `WARMUP_DAYS = 365` declared in `config.py`.
- Not actively trimmed in `runner.run_single_model_basin`; metrics are computed over the entire `test` window in `runner._run_*` paths via `compute_metrics(test_obs, test_sim)`.

## Calibration Budget

### What the HPC entrypoint records vs what actually runs

`src/xaj_global_pilot/hpc/run_conceptual_benchmark_chunk.py`:

- CLI defaults: `--trials = DEFAULT_CALIBRATION_TRIALS = 5000`, `--restarts = DEFAULT_RESTARTS = 3`.
- Both values are written into `summary/{model}_{chunk}.metadata.json` as `trials` and `restarts`.
- **Only `args.trials` is forwarded** to `run_single_model_basin(..., calibration_trials=args.trials)`. `args.restarts` is **never plumbed through to the calibration call**.

### XAJ family (NumPy path)

`src/xaj_global_pilot/xaj_model.py::_cmaes_multi_restart`:

- All XAJ calibrators (`calibrate_xaj`, `calibrate_pdd_xaj`, `calibrate_xaj_smooth_et`, `calibrate_xaj_power_runoff`, `calibrate_pdd_xaj_smooth_et`, `calibrate_pdd_xaj_power_runoff`) accept `n_trials` and `n_restarts`.
- `runner._run_numpy_xaj` / `_run_numpy_pdd_xaj` / `_run_numpy_xaj_smooth_et` pass only `n_trials=calibration_trials`.
- Therefore the **function-default `n_restarts=3` is what actually runs** for XAJ models.
- Per-restart seed: `42 + restart * 1000`. CMA-ES initial sigma = 0.3, normalized [0, 1] search space, `maxfevals = n_trials`.

### Superflex family (HBV / GR4J path)

`src/hydroagent/environment.py::SuperflexEnv._calibrate_sfpy`:

- Function signature: `(forcing_data, obs_data, n_trials=2000)`. **No `n_restarts` parameter.**
- Single CMA-ES run with fixed `seed=42`, `sigma=0.3`, `x0=[0.5]*ndim`, `bounds=[[0]*ndim, [1]*ndim]`, `maxfevals=n_trials`.
- `runner._run_superflexpy` calls `_calibrate_sfpy(train_forcing, train_obs, n_trials=calibration_trials)` exactly once.
- Therefore HBV and GR4J effectively run **1 restart**, regardless of the value of `--restarts` recorded in metadata.

### Net effect under the production HPC defaults (`--trials 5000 --restarts 3`)

| Model family | Trials per restart | Restarts (actual) | Restarts (metadata says) |
|--------------|--------------------|-------------------|--------------------------|
| `xaj_pdd`    | 5000               | 3                 | 3                        |
| `hbv`        | 5000               | **1**             | 3 (misleading)           |
| `gr4j_pdd`   | 5000               | **1**             | 3 (misleading)           |

This budget asymmetry favors the XAJ family in any internal comparison and is one of the reasons the current results cannot support a strict head-to-head claim against an externally calibrated SAC-SMA benchmark.

## Failed Basin Handling

`runner.run_single_model_basin`: any exception during data loading, calibration, or simulation ⇒ row written with `run_status="failed"`, metric columns set to `pd.NA`, and `error_message` populated. No retry, no fallback model.

`runner._run_superflexpy` additionally guards against degenerate Superflex calibration via `_select_best_params`: if train NSE is `-inf`/`<= -900` or any best-param is non-finite, the test simulation falls back to a default-parameter run.

## Output Locations (Frozen)

The following directories represent immutable exploratory outputs and must not be overwritten by future reruns:

- `results/10_xaj_global_pilot/model_all_xaj_pdd.csv`
- `results/10_xaj_global_pilot/model_all_hbv.csv`
- `results/10_xaj_global_pilot/model_all_gr4j_pdd.csv`
- `results/10_global_conceptual_model_benchmark/camels_us_531_v02/` (per-model and per-chunk artifacts)
- `logs/10_global_conceptual_model_benchmark/camels_us_531_v02/`

## Cross-Study Limitation (Hard Statement)

This protocol is **not** directly aligned with the Newman et al. 2015 / Kratzert et al. 2019 published 531-basin SAC-SMA benchmark. Differences include — at minimum — non-matching forcing version assumptions, an unused validation split that hides the calibration window definition, and an asymmetric calibration budget across model families. The current results therefore **cannot support claims of the form "outperforms the SAC-SMA benchmark" or "beats the Kratzert baseline."** Any comparison against the published benchmark using these results is a cross-study comparison only.
