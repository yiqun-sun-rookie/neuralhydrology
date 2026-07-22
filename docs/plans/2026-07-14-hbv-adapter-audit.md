# HBV-lite Adapter Independent Audit

**Date:** 2026-07-14  
**Scope:** `hbv_adapter.py` and its two focused test files  
**Reviewer access:** goal, source, tests, and authoritative NumPy model; no implementer conclusion

## Review evidence

The reviewer found no serious state-order, routing-history, weight, or in-bound equivalence error. The reviewer ran the 13
then-existing focused tests and an additional 40,000-day randomized in-bound comparison. Reported maximum absolute errors
were `8.53e-13` for the five stores and `5.68e-14` for discharge.

## Findings and separate verification

### Finding 1: out-of-bound parameters could reach an arithmetic singularity

The first adapter version checked finiteness but not every `v1` parameter bound. With `parLP = -4e-8` and `parFC = 250`,
the evaporation denominator became zero and raised `ZeroDivisionError`.

Separate reproduction produced the same exception. A new regression test was then observed failing for the expected
reason. The implementation now freezes and validates every `v1` bound before transition. The focused suite passed after
the change.

**Status:** confirmed and fixed.

### Finding 2: non-integer lag and nonzero routing history lacked fixed regression tests

Inspection confirmed that the first suite used only `lag_time = 10` and a zero routing history. Tests were added for
`lag_time = 1.01`, `lag_time = 9.01`, and nonzero history shifting. These tests passed without a production-code change,
which supports the reviewer's statement that this was a coverage gap rather than a current calculation error.

**Status:** confirmed coverage gap; tests added; no algorithm change.

## Current focused verification

Command:

`pytest test/test_hbv_joint_uncertainty_state_dimension.py test/test_hbv_joint_uncertainty_adapter.py -v`

Fresh result after the fixes: 17 passed, 0 failed. The repository-level `collect_ignore_glob` warning predates and is
outside this isolated prototype.

