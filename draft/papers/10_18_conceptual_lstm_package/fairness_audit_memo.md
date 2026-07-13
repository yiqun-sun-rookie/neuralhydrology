# Structure and calibration fairness audit

## Verdict

Under the documented 531-basin split, forcing, calibration budget, and snow-module distinctions, the package supports comparison of the three conceptual models as structure references. GR4J and XAJ external PDD front ends match on the tested zero-ice input sequences. HBV-lite keeps an intrinsic HBV snow routine; this is a disclosed model-structure difference, not a shared external module. These checks do not establish identical model structures or information channels.

## Structure fairness

- GR4J+PDD uses the shared no-ice PDD reference path with 4 active snow parameters.
- XAJ+PDD keeps the historical 6-parameter full PDD wrapper, but the two ice parameters are inactive because ice storage starts at zero and no process creates ice storage.
- HBV-lite uses internal snow states and parameters (`SNOWPACK`, `MELTWATER`, `parTT`, `parCFMAX`, `parCFR`, `parCWH`). It should be described as an HBV-family structural choice.

## Calibration fairness

- The final conceptual headline uses the same 531-basin repro_v01 split, Maurer forcing, PT PET, warmup-year evaluation initialization, NSE metric, and CMA-ES budget.
- The optimizer policy is aligned: 5000 trials x 3 restarts, seeds `42 + 1000 * restart`, normalized box search, init mean 0.5, sigma 0.3, and best calibration objective retained.
- Bounds and structural constraints remain model-specific and must be disclosed as such.

## Fixed or controlled issues

- Added a shared `pdd_noice_step_mm` reference implementation.
- Added `test/test_id10_pdd_fairness.py` to check GR4J/XAJ external snow front-end agreement on explicit zero-ice sequences and XAJ ice-parameter inactivity on those sequences.
- Added nominal/effective parameter accounting to the evidence package.
- Added the full-531 saved-parameter replay audit (`audit/R01_saved_parameter_replay_current_code`) to verify the final parameter artifacts still reproduce the headline NSE table under the current code.
- Added future-run metadata fields for `parameter_count` and `effective_active_parameter_count` in GR4J/XAJ/HBV conceptual runners.

## Manuscript wording rule

Do not write that all three conceptual models share an identical snow module. The correct wording is: GR4J and XAJ external snow front ends are controlled as effective-equivalent under zero initial ice; HBV snow handling is intrinsic to the HBV-lite model structure.
