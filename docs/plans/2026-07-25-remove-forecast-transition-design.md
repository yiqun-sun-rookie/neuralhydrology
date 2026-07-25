# Remove forecast-phase model switching — design

Date: 2026-07-25. Scope: `src/hbv_multilead_joint_uncertainty/`.

## Decision

Forecasts in this study always hold candidate probabilities at the final
assimilation posterior. The model-switching transition matrix remains active
during assimilation, but it is never applied after the forecast origin.

The public `forecast_transition="markov"|"frozen"` option is removed. The
forecast implementation deep-copies the posterior bank and replaces the copy's
transition matrix with the identity before the first forecast step. Therefore:

- candidate probabilities do not drift without new observations;
- forecast-phase cross-candidate state mixing disappears;
- the input posterior bank is not mutated;
- all forecast callers share one scientifically valid behavior.

This applies to the study's 1-, 3-, and 7-day horizons, which are much shorter
than the 180-day truth-switching period. It is not a universal claim about
long-range forecasts that cross a known regime change.

## Alternatives considered

1. **Remove the option and always freeze (chosen).** There is no invalid
   configuration path in current experiments. Historical behavior remains
   available from Git history.
2. **Keep the option but change the default.** Rejected because callers can
   still accidentally request an unsupported forecast assumption.
3. **Move the drifting behavior to a legacy helper.** Rejected because no
   planned experiment needs it, so the extra code has no current purpose.

## Code changes

- `forecast.py`: remove `forecast_transition`; always install an identity
  transition matrix on the copied forecast bank.
- `three_stage_switching_validation.py`: remove the unused forwarding argument.
- `interaction_value_comparison.py`: remove the argument and its validation.
- Tests: make frozen probabilities and no state mixing the only forecast
  contract; assert the removed keyword is rejected by Python's function
  signature.
- Existing plan and handoff: mark the former dual-mode design as superseded.

## Protection and verification

No sealed experiment or result is changed or rerun. Tests are run with
`PYTHONIOENCODING=utf-8` and `PYTHONPATH=src`. Only files under the candidate
identifiability study plus its focused tests and plans are staged.
