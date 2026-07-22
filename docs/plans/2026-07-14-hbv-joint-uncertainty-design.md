# Daily HBV Joint-Uncertainty Prototype Design

**Date:** 2026-07-14  
**Status:** Goal approved; exact state dimension awaiting independent audit  
**Workspace:** `G:\github\pycharm\projects\neuralhydrology`

## Goal and boundary

Build an isolated daily prototype that applies an interacting multiple-model estimator to the existing NumPy HBV-lite
implementation. The model bank must vary both a complete HBV-lite parameter vector and a process-noise level. The current
goal ends after an auditable six-basin preflight; it does not authorize recalibration, a 531-basin run, paper claims, or
changes to the hourly repository.

New code and durable outputs use:

- code: `src/hbv_joint_uncertainty/`
- tests: `test/test_hbv_joint_uncertainty_*.py`
- results: `results/22_hbv_joint_uncertainty/`
- logs: `logs/22_hbv_joint_uncertainty/`

The existing dirty files, `src/scl_hydro/`, and the hourly repository are read-only dependencies. No commit or push is
part of this goal.

## Evidence already present

- `src/scl_hydro/hbv_lite_numpy.py` is the authoritative daily forward model. It has five hydrologic stores and a
  recession-half triangular routing operator.
- The frozen parameter bound allows `lag_time` through 10 days. The selected 531-basin trained-parameter table contains
  11 basins with `lag_time > 9`, so the ten-day case is not hypothetical.
- The canonical trained-parameter source contains 531 successful rows, 13 parameters per basin, and five warm-up-end
  states. It does not contain routing memory.
- The existing modified unscented Kalman filter regenerates sigma points from the predicted mean and covariance before
  applying the observation function. Consequently the observation must be computable from the post-transition state.

## Exact-state alternatives

### Recommended: fifteen post-transition states

After day `t`, define

`x_t = [SNOWPACK, MELTWATER, SM, SUZ, SLZ, qraw_t, qraw_t-1, ..., qraw_t-9]`.

There are five hydrologic states and ten raw-runoff routing values. For `n = ceil(lag_time)`, the observation function
uses the first `n` routing values with weights `n, n-1, ..., 1`, normalized by their sum. The next transition computes
`qraw_t+1` and shifts the ten-value queue. This is Markov and keeps the existing predict-then-regenerate-then-observe
filter definition unchanged.

### Rejected: fourteen pre-transition states

Five stores plus nine historical raw-runoff values can produce a ten-day routed observation only while the transition
still holds the newly computed raw runoff and the oldest history value. Once the post-transition state is returned, one
required value has been dropped. Preserving it would require the filter update to consume a transition-side auxiliary
observation instead of applying the observation function to regenerated predicted sigma points. That is a different
filter definition.

For this particular deterministic HBV-lite transition, today's raw runoff can also be algebraically reconstructed from
the post-transition `SUZ` and `SLZ` stores because `parK0`, `parK1`, and `parK2` are below one. That permits a special
fourteen-state representation containing the five stores plus only the previous nine raw-runoff values. It is rejected
here because process noise is added to the stores before measurement sigma points are regenerated: reconstructing runoff
from those perturbed stores defines a new runoff value instead of preserving the transition-produced runoff used by the
authoritative model. Fifteen states preserve that value explicitly and assign it zero independent process noise.

### Rejected: five states plus external routing memory

Keeping routing history outside the stochastic state makes covariance, interaction, and process-noise propagation ignore
information that directly determines discharge. Two histories could have identical five stores and different discharge,
so the five-state representation is not Markov.

Implementation starts only after an independent audit confirms or refutes this argument. A refutation must include a
counterexample implementation that reproduces the ten-day routing output after sigma-point regeneration.

## Architecture

- `hbv_adapter.py`: exact one-day HBV-lite transition, fifteen-state packing, warm-up replay, routing observation, and
  physical-state projection.
- `sigma_filter.py`: local modified unscented Kalman filter using the hourly algorithm as a read-only reference. It returns
  prior observation, posterior state, covariance, and log likelihood.
- `imm.py`: probability interaction across the complete bank and state/covariance interaction only within candidates that
  share the full 13-parameter tuple.
- `candidates.py`: load one already-trained central parameter vector, derive two frozen bound-relative stress vectors, and
  cross the three vectors with three frozen process-noise levels.
- `resource_monitor.py`: record memory, processor, graphics-memory, and disk observations before and during costly runs.
- `preflight.py`: replay warm-up state, execute six basins, calculate diagnostics, and write atomic registered artifacts.
- `scripts/run_preflight.py`: command-line entry point with a dry-run resource estimate.

The first preflight bank has nine candidates: one trained central vector, a vector moved 10% from the center toward every
`v1` lower bound, a vector moved 10% from the center toward every `v1` upper bound, crossed with three process-noise
levels. This is a deterministic engineering stress bank, not three independently calibrated truths. The one source table
uses Maurer forcing, Priestley-Taylor potential evaporation, `v1` bounds, and the frozen calibration window. Its table and
metadata checksums are stored in the run configuration rather than modified.

## State and noise rules

- Hydrologic and routing states are finite and nonnegative.
- Soil moisture is at most the candidate's `parFC` capacity.
- Meltwater is at most `parCWH * SNOWPACK` after a model transition.
- Process noise acts on the five hydrologic stores only. The ten routing-memory entries are deterministic shifted history
  and receive zero independent process noise.
- State interaction is allowed only among noise candidates with the same complete parameter tuple. Candidate probability
  prediction and observation-based probability updating still operate across all nine candidates.
- Likelihoods are accumulated in log space and normalized with a shifted exponential, preventing numerical underflow.

## Warm-up and data contract

The saved five warm-up-end states are insufficient to initialize routing. For each parameter candidate, replay
1988-10-01 through 1989-09-30 from the authoritative default state, retain the last ten `qraw` values, and compare the five
replayed stores with the saved warm-up-end stores. The maximum absolute difference must not exceed `1e-8`; otherwise the
run stops as a provenance mismatch.

The run must explicitly select the `v1` parameter-bound preset, whose maximum `lag_time` is 10. The module's environment-
dependent default can select `v5`, whose maximum is 15; accepting that default would require twenty states and therefore
must fail configuration validation.

The bounded engineering preflight uses 1989-10-01 through 1990-09-30 and the already frozen Maurer forcing plus
Priestley-Taylor potential evaporation. Existing parameters were calibrated on 1999-10-01 through 2008-09-30, so this
preflight can establish numerical and engineering feasibility only. It cannot support a chronological generalization or
forecast-skill claim.

The frozen basin set is:

- `12375900` and `09035800`: snow-dominated cases from the existing stratified pilot list.
- `01580000` and `11481200`: humid cases from the existing stratified pilot list.
- `08109700`: semi-arid/arid case from the existing stratified pilot list.
- `04213075`: the trained table's maximum-lag stress case (`lag_time = 9.97233665946842`, hence ten routing days).

## Artifacts and resource gate

Every run has one experiment identifier, frozen configuration, output directory, registry row, log, metrics file, state
diagnostic file, probability file, resource record, and SHA-256 checksums. Existing output directories are never
overwritten.

Before a costly command, do not start if estimated peak memory exceeds 70% of available memory. During a run, sample at
least every 60 seconds and stop launching work if available memory drops below 15% of physical memory. Keep one logical
processor unused. Require at least 20 GiB free disk and twice the estimated new output size. The preflight defaults to one
basin at a time and does not require a graphics processor.

## Verification and completion gates

1. Sequential adapter output and all five stores match `simulate_hbv_lite` within maximum absolute error `1e-8`, including
   `lag_time = 10`.
2. A one-candidate interacting estimator matches the same standalone modified unscented Kalman filter element by element.
3. Every model probability is finite and nonnegative, and its sum differs from one by at most `1e-12`.
4. All new tests pass and the six registered real-basin runs complete without non-finite state, covariance, discharge, or
   probability values.
5. An independent reviewer audits source changes and saved artifacts without receiving the implementer's conclusions.
   Each finding is then reproduced or rejected by a separate minimal test or rerun before any fix.
6. The final report distinguishes direct artifact evidence, supported inference, and claims that remain untested.
