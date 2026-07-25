# Forecast-phase frozen transition (no P in forecast) — infrastructure

Date: 2026-07-25. Scope: ID23 (`src/hbv_multilead_joint_uncertainty/`). Not an
experiment — no sealed results, no preregistration. TDD + default-preserving.

## Line being implemented

User ruling (咬准这条线): **during the forecast horizon the model-switching matrix P
is not applied.** The forecast weights are held at the final assimilation posterior.
Rationale: the forecast window (leads 1/3/7 days) is far shorter than the true
switching period (180 days), so "no switch within the window" holds and the belief
over which candidate is active does not evolve → P must not multiply the weights.

Boundary (kept, not erased): this is correct only when the forecast window ≪ switching
period. It would not hold for an origin sitting right before a likely switch with a
window long enough to cross it — outside this study and outside short-range hydrologic
forecasting.

## What changed

A single new keyword, `forecast_transition`, with two values:

- `"markov"` (default) — historical behaviour: propagate the model probabilities and
  conditional state mixing through P each forecast day (weight drift).
- `"frozen"` — hold the forecast transition at the identity matrix.

Why identity = "no P in forecast", for every interaction mode:
- `predict_model_probabilities(I, w) = Iᵀ w = w` → weights frozen at the posterior.
- Mixing weights degenerate: `incoming = I[:, j]·w = e_j·w`, so `weights = e_j`,
  `mean = state[j]` → no cross-candidate mixing during the forecast.

So `frozen` freezes the weights AND removes forecast-phase state mixing, self-consistently.

### Files
- `forecast.py` — `forecast_from_posterior(..., forecast_transition="markov")`; when
  `"frozen"`, the deepcopied branch's `estimator.transition_matrix` is set to identity.
  The input bank is untouched (deepcopy).
- `three_stage_switching_validation.py` — `_assimilate_record_then_forecast` and
  `run_three_stage_switching_validation` forward the keyword.
- `interaction_value_comparison.py` — `assimilate_family_arm`, `static_mixing_arm`,
  `oracle_arm`, `compare_interaction_arms` forward the keyword. Note: `compare_interaction_arms`
  reuses the result's stored `full` forecast, so `forecast_transition` must match the mode
  used to produce that result (frozen comparison ⇒ frozen `run_three_stage_...` run).

## Reproducibility guard

Default is `"markov"` everywhere, so every existing/sealed config reproduces bit-for-bit.
Sealed experiments (G3 gate, phase 2, drift round) are never rerun or modified; their
configs do not carry the keyword and therefore keep drifting behaviour. New comparison
configs opt into `"frozen"` explicitly. This drops the drift-vs-frozen factor from future
comparison matrices (halving that dimension) with no accuracy cost (drift shown negligible
in the 2026-07-24 drift round).

## Verification

- 8 new unit tests (`test/test_hbv_forecast_frozen_transition.py`): frozen holds weights,
  markov drifts, default == markov bit-for-bit, frozen full == frozen none (mixing removed),
  frozen combined == frozen-weight combination of candidate paths, markov ≠ frozen, invalid
  value rejected, input bank transition matrix untouched.
- Regression: existing forecast / three-stage / interaction-value / drift / imm suites pass
  unchanged (default preserved).
- Sealed cross-check (8 blocks × 3 truths, truths reconstructed bit-for-bit): the new
  `assimilate_family_arm(none, forecast_transition="frozen")` path reproduces the drift
  round's sealed `forecast_none_frozen` to **max abs diff 8.882e-16** (NOT bit-exact).
  Cause: the identity-transition path re-normalizes the held weights through
  `predict_model_probabilities` (`predicted /= total`), whereas the drift round combined
  with the raw posterior directly — a machine-epsilon summation-order difference, the same
  magnitude the drift round itself recorded for its drifting-combination identity.
  Scientifically identical; the unit test confirms the held weights equal the posterior to
  within 1e-12.
