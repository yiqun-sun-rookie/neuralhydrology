# Complete closed synthetic-truth validation synthesis

## Conclusion

The validation goal is complete and the numerical chain is validated. The scientific conclusion remains **HOLD** for broad joint-method superiority: no tested final condition passed joint identification, and no one-, three-, or seven-day target established added value beyond both single-factor methods.

## Supported numerical chain

- State propagation maximum absolute difference: `5.684341886080802e-14`.
- Same-filter observation updating improved state in `20/24` trials and one-day flow in `24/24` trials.
- Isolated complete-parameter identification: `24/24`.
- Isolated projected process-scale identification: `23/24`.
- Joint probability accuracy improved from `0.894863` to `0.931849` in its registered validation.
- Independent full interaction and observation-free forecast checks passed their numerical gates.

## Final conditions and boundaries

- Fixed labels with 7, 21 and 45 assimilation days all failed the preregistered joint-identification rule. At 45 days, the complete-parameter-label accuracy was `43/72`, below the `48/72` threshold; longer durations are unknown.
- In the fixed 45-day condition, only origin state and seven-day forecast were effective relative to the fixed filter, and neither established added value beyond both single-factor methods.
- In the seven-day simultaneous-switch condition, current candidate accuracy was `10/72`; no forecast lead was effective relative to the fixed filter. This applies only to the registered seven-day switch period, factor-level stay probability 0.98, three current-label observations at origin, and a further switch at forecast lead five.

## Unknown

Real-basin behavior, more than 45 assimilation days, other switch periods or transition priors, other observation uncertainty, forcing error, and exact post-projection additive Gaussian recovery were not tested.
