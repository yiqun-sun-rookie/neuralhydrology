# HBV-lite State-Dimension Feasibility Audit

**Date:** 2026-07-14  
**Reviewer role:** independent, read-only review  
**Decision:** use 15 states for the unchanged modified unscented Kalman filter observation contract

## Question

With maximum routing lag 10, can daily HBV-lite use 14 states without changing the existing filter behavior, or must it
use 15?

## Independent review result

The general exact post-transition state is:

`[five hydrologic stores, qraw_t, qraw_t-1, ..., qraw_t-9]`.

It has 15 components. A 14-component post-transition state containing only nine routing values cannot distinguish two
histories that differ only in the omitted tenth value, although the ten-day observation weights that value by `1/55`.

The reviewer also identified a model-specific fourteen-state construction. Given post-transition upper and lower stores
`U` and `L`, define:

```
b = U / (1 - parK1)
q1 = parK1 * b
q0 = 0                                      if b <= parUZL
q0 = parK0 / (1 - parK0) * (b - parUZL)    otherwise
q2 = parK2 / (1 - parK2) * L
qraw = q0 + q1 + q2
```

This reconstructs deterministic one-step runoff, so five stores plus the previous nine runoff values are sufficient only
if that reconstructed value is declared to be the observation-time runoff.

The existing filter adds process covariance and then regenerates measurement sigma points. Those points are not required
to lie on the deterministic transition surface. Applying the inverse formula to the perturbed stores therefore creates a
new runoff value. Carrying the transition-side runoff instead would use the old sigma points and changes the filter gain;
for a one-dimensional identity observation with process variance 4 and observation variance 1, the existing definition
has gain `4 / (4 + 1) = 0.8`, whereas a constant transition-side auxiliary observation has gain 0.

## Separate verification of the findings

Two checks were run independently of the reviewer:

1. Two ten-day raw-runoff histories had identical newest nine values but oldest values 0 and 55. The actual
   `_half_triangular_lag` outputs at day 10 were 0 and 1. Their 14-component representations were identical; their
   15-component representations were different.
2. With deterministic seed `20260714`, 10,000 random one-day transitions drawn inside the `v1` bounds were checked against
   the inverse formula. The maximum absolute error was `3.979039320256561e-13`; 8,615 samples activated fast flow and
   1,385 did not. This confirms that the fourteen-state algebra is valid only for deterministic transition states and does
   not refute the process-noise objection.

## Bound-preset condition

The selected trained source uses the explicit `v1` bounds, where maximum `lag_time` is 10. The authoritative module's
environment-dependent default can select `v5`, where maximum `lag_time` is 15. Under `v5`, the direct representation
would require 20 states. The preflight configuration must therefore name `v1` and reject an implicit or inconsistent
preset.

## Verdict

Fifteen states are feasible, preserve the authoritative transition-produced runoff, and keep the existing
predict/add-process-noise/regenerate/observe definition. Fourteen states are a mathematically interesting alternative but
would change the physical meaning of observation after process noise. It is not used in this prototype.

