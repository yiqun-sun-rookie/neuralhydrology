# Daily Joint Parameter and Process-Noise Preflight

This isolated prototype applies an interacting multiple-model estimator to the daily HBV-lite rainfall-runoff model.
Each basin uses nine candidates: three complete thirteen-parameter vectors crossed with three process-noise variance
scales. It is a six-basin engineering preflight, not a recalibration, a 531-basin benchmark, or a performance claim.

## State contract

The filter uses fifteen states: five hydrologic stores and ten newest-first raw-runoff values. Ten routing values are
required because the frozen parameter bounds allow a ten-day routing lag. A deterministic fourteen-state inverse exists
for transition-produced states, but it changes runoff meaning after process covariance is added and measurement sigma
points are regenerated; it is therefore not used.

## Commands

Run all isolated tests:

```powershell
pytest test/test_hbv_joint_uncertainty_state_dimension.py `
  test/test_hbv_joint_uncertainty_adapter.py `
  test/test_hbv_joint_uncertainty_sigma_filter.py `
  test/test_hbv_joint_uncertainty_imm.py `
  test/test_hbv_joint_uncertainty_contracts.py `
  test/test_hbv_joint_uncertainty_preflight.py `
  test/test_hbv_joint_uncertainty_experiment.py `
  test/test_hbv_joint_uncertainty_cli.py -q
```

Check frozen sources and live resources without writing an experiment:

```powershell
python src/hbv_joint_uncertainty/scripts/run_preflight.py `
  --experiment-id contract_check_v01 --dry-run
```

Run one basin for thirty days:

```powershell
python src/hbv_joint_uncertainty/scripts/run_preflight.py `
  --experiment-id smoke_12375900_30day_v01 `
  --basin-id 12375900 --max-days 30
```

Run the frozen six basins for 365 days and independently verify an existing result:

```powershell
python src/hbv_joint_uncertainty/scripts/run_preflight.py `
  --experiment-id preflight_6basin_365day_v01
python src/hbv_joint_uncertainty/scripts/run_preflight.py `
  --verify-output results/22_hbv_joint_uncertainty/preflight_6basin_365day_v01
```

Experiment identifiers are non-overwriting. Use a new identifier after any confirmed review defect.

## Reproducibility package

Every verified official package contains:

- daily observations, nine candidate predictions, observation-before-update probabilities, posterior probabilities, and
  fifteen-state trajectories;
- metrics and three-parameter-vector warm-up equivalence evidence;
- a frozen execution configuration and resource history;
- snapshots of this prototype, its tests, the authoritative HBV-lite and data-loading dependencies;
- the raw meteorological, discharge, basin-area, trained-parameter, and metadata inputs used by the selected basins;
- a path-to-hash manifest and a checksum for every saved artifact.

The verifier cross-checks the saved source and input snapshots against the current controlled workspace. A copied result
directory remains verifiable, but a changed source or input file is rejected instead of being silently treated as the
same experiment.
