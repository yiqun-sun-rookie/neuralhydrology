# G3 state-weight factorial formal attempt v01 — pre-result failure

Date: 2026-07-26.

## Status

`g3_state_weight_factorial_param_switch_v01` failed before producing a
scientific result. Its output directory and incomplete output directory were
never created. The external preregistration and both process logs are retained
and must not be deleted, overwritten, or reused.

## Frozen attempt identity

- Git commit: `143f6313e18ab762634199c2886941437cb118f3`
- Config SHA-256:
  `9286a7407bd6d35cd400dcbe6dcab18d1bc7107c2da870dbf15d7c0bca54a2a0`
- Preregistration SHA-256:
  `ee8aee4099ea2913c8773f68da36c1ec136a39185e53e1436e591ff7698070a0`
- Standard-error log SHA-256:
  `bea99453c8fdd0fd7a4ca229c38af324d773b508a70971e7b5d1c28a0aac4f28`
- Empty standard-output log SHA-256:
  `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`
- Machine-readable failure record:
  `results/23_hbv_multilead_joint_uncertainty/g3_state_weight_factorial_param_switch_v01.failed.json`

## Failure and root cause

The formal run stopped at the frozen-probability runtime guard:

```text
RuntimeError: forecast probabilities must equal the final posterior
```

Only the fifth matched block, second truth trial, and no-state-interaction
assimilation path triggered the guard. Its final posterior summed to
`0.9999999999999999`. The identity-transition forecast path defensively
renormalized that vector, producing a maximum absolute difference of
`1.1102230246251565e-16`. The combined forecast changed by at most
`8.881784197001252e-16`.

This is a validation-precision mismatch, not candidate-probability drift,
cross-candidate state mixing, a parameter-identification failure, or a
scientific result. The approved frozen-forecast contract uses
`rtol=0, atol=1e-12`; the new diagnostic had incorrectly strengthened that
contract to bitwise equality.

## Recovery boundary

The replacement experiment is
`g3_state_weight_factorial_param_switch_v02`. It keeps all truth inputs,
candidate definitions, assimilation settings, forecast settings, seeds,
bootstrap resamples, comparison baselines, and decision rules unchanged.
Only the numerical validation is repaired:

- accept a maximum absolute frozen-probability difference no larger than
  `1e-12`;
- reject any larger difference;
- save the observed maximum difference in raw evidence, cross-checks, and the
  summary.

The v01 registry status remains `failed` permanently. The v02 run must use a
new preregistration and output directory and must protect all v01 failure
sidecars.
