# Forecast-phase frozen transition — historical design, superseded

Date: 2026-07-25. Scope: `src/hbv_multilead_joint_uncertainty/`.

## Current contract

The former dual-mode forecast design from commit `55a9a65` is superseded by
`docs/plans/2026-07-25-remove-forecast-transition-design.md`.

Current forecasts have one behavior: candidate probabilities stay at the final
assimilation posterior. The copied forecast bank uses an identity model
transition matrix, so no candidate-probability drift or cross-candidate state
mixing occurs after the forecast origin. There is no forecast-mode configuration.
The model-switching transition matrix remains active during assimilation.

This contract applies to the study's 1-, 3-, and 7-day horizons, which are much
shorter than the 180-day truth-switching period. Long-range forecasts that cross
a known regime change are outside this study.

## Historical evidence retained

Commit `55a9a65` first introduced a selectable frozen path while preserving the
older drifting default. Its validation established the numerical behavior used
by the permanent contract:

- eight focused unit tests covered frozen weights, removal of forecast-phase
  state mixing, origin-weighted combinations, and input-bank immutability;
- 62 related regression tests preserved the then-current default behavior;
- the selectable frozen path reproduced the sealed no-interaction frozen
  forecast to maximum absolute difference `8.882e-16`.

The historical drifting path remains available from Git history only. It is not
a supported configuration in current experiments.

## Protection boundary

No sealed experiment or result is changed or rerun by the permanent forecast
contract. The previous sealed results remain historical evidence under their
original commits and checksums.
