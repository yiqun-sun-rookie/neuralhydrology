# Modified Unscented Filter and Interacting Model Independent Audit

**Date:** 2026-07-14  
**Scope:** `sigma_filter.py`, `imm.py`, and focused tests  
**Reviewer access:** goal, source, tests, and hourly read-only reference; no implementer conclusion

## Filter review and verified fixes

The first filter review found two issues. Both were independently reproduced before code changes:

1. A fixed `-1e-10` covariance threshold rejected a mathematically positive-semidefinite fifteen-state covariance whose
   scale was about `1e9` and whose roundoff eigenvalue was `-3.31164364996055e-7`.
2. Scalar discharge observations were rejected although a one-element array was accepted.

New regression tests failed for both issues. Covariance acceptance now uses a dimension- and scale-relative roundoff
tolerance while still rejecting a true eigenvalue of `-1`. A one-dimensional observation now accepts a scalar and maps it
to a one-element vector. The regressions passed after the changes.

## Interacting-model review and verified fixes

A separate reviewer found five issues. Each supplied example was reproduced independently:

1. Pure cross-parameter transition probability caused a zero within-group incoming-state error.
2. Complete parameter tuples became a two-dimensional object array and were rejected as group labels.
3. A legal zero-probability unreachable candidate was rejected during prediction.
4. Two accepted `9e-13` input sum errors accumulated into a prior-probability sum error above `1e-12`.
5. A finite discharge observation of `2e154` overflowed the direct Mahalanobis quadratic form.

Five failing regressions were added. The implementation now keeps a destination's own state when no same-parameter state
can legally enter, stores complete parameter tuples as labels, permits zero mode mass, renormalizes accepted input
distributions before use, and computes the whitened norm with overflow saturation at the largest finite `float64` value.

## Current focused verification

Command:

`pytest test/test_hbv_joint_uncertainty_imm.py test/test_hbv_joint_uncertainty_sigma_filter.py test/test_hbv_joint_uncertainty_state_dimension.py test/test_hbv_joint_uncertainty_adapter.py -v`

Fresh result after all review fixes: 36 passed, 0 failed. The one-candidate interacting estimator matches the standalone
filter element by element. The repository-level `collect_ignore_glob` warning predates and is outside this prototype.

