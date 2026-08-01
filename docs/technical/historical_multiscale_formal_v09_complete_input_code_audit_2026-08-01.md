# Historical Continuous Multiscale Model Version 09 Complete-Input Code Audit

Date: 2026-08-01

## Conclusion

**Code implementation stage: GO. Formal complete-input generation: NO-GO until a separate exact authorization is supplied. Training, formal prediction generation, and scoring: NO-GO.**

The implementation can later seal the complete Maurer meteorological forcing, the 27 static attributes, and the already sealed training targets for 531 basins. This phase created code, documentation, and synthetic tests only. It did not create a production authorization, consume an authorization, create a formal complete-input directory, train a model, generate a formal prediction, or call a scoring process.

## Frozen scope and scientific contract

- Meteorological product: Maurer only.
- Dynamic columns, in order: `PRCP(mm/day)`, `Tmin(C)`, `Tmax(C)`, `SRAD(W/m2)`, `Vp(Pa)`.
- Static attributes: the frozen set of 27 columns, ordered alphabetically to reproduce the historical loader.
- Basin set: the frozen 531-basin list.
- Forcing period: 1980-01-01 through 2008-09-30.
- Training-target and normalization period: 1999-10-01 through 2008-09-30.
- Static normalization: `float64`, sample standard deviation with one degree of freedom, followed by one cast to `float32`.
- Dynamic and target normalization: training dates only, population standard deviation.
- The frozen equality of the named minimum- and maximum-temperature columns is reported without repair.
- Formal evaluation observations remain inaccessible.

## Implemented controls

- The contract binds the protocol, basin list, static table, target files, source inventory, periods, shapes, scientific column order, and output paths by SHA-256.
- The builder streams one Maurer basin and one target basin at a time into memory-mapped arrays; it does not materialize the complete forcing or target table in memory.
- The future production entry has no path or resource bypass parameters. It requires a fixed one-use authorization, a clean source tree, a fixed global serial lock, and a live task-specific resource capability.
- The final directory is promoted by a non-overwriting rename only after a complete independent pre-promotion audit.
- Authorization, consumption, source, building, and final paths are checked component by component for symbolic links and Windows directory connections before and after the sensitive operations. The complete artifact tree is also checked without following links.
- The post-seal audit independently rereads every Maurer value, all static values, all target values, normalization values, array payloads, file hashes, inventories, environment data, source-tree evidence, authorization evidence, and resource evidence.
- Synthetic builders can write only below the current user temporary directory and cannot publish into any formal version 09 result tree.
- A source-boundary scan covered nine production modules and found zero prohibited observed-discharge interfaces.

## Verification evidence

- Focused regression after the final Windows directory-connection repair: 26 passed.
- Complete local suite command: `pytest src/26_historical_band_experts/tests -q`.
- Complete local suite result: **500 passed, 1 existing configuration warning, 58.69 seconds**.
- The warning is `PytestConfigWarning: Unknown config option: collect_ignore_glob`; it is pre-existing and did not fail collection or execution.
- Available physical memory before the preceding full run was 11.960 GiB; Windows committed-memory headroom was 60.338 GiB. Tests ran serially.
- Analytical complete-input sealing peak: 484,029,488 bytes (461.606 MiB).
- Peak after the required 1.25 safety factor: 605,036,860 bytes (577.008 MiB).
- A future production run must still retain at least 2 GiB available physical memory and 2 GiB committed-memory headroom after subtracting the guarded peak.

## Independent review

Four read-only review rounds were used to challenge the implementation.

1. The first review rejected self-consistency-only source checks, incomplete path protection, weak source-boundary scanning, an atomic-JSON race, and import-time temporary-directory probing. These findings were fixed and tested.
2. The second review rejected an injectable lock identity, late provenance checks, a shared temporary JSON name, and incomplete formal path checks. These findings were fixed and tested.
3. The third review rejected incomplete handling of Windows directory connections, missing pre/post-promotion path rechecks, and an early return that could miss a broken directory connection. These findings were fixed and tested.
4. The final independent read-only review reported **code implementation stage GO** and found no blocking or high-priority issue.

## Frozen artifact check

The formal result directory still contains only:

- `inputs/training_targets.csv`, SHA-256 `6abadf7172f1c8ebd48122a8abf68985d7d4f94b8c894371270208eeb45f2ebb`.
- `inputs/training_targets.manifest.json`, SHA-256 `3061d548fa0b9c81c8e3e25f0dbdd8cfbdb347aaea965ac6f6400c5f09da13e8`.

The production authorization file, authorization-consumption file, building directory, and final complete-input directory do not exist.

## Remaining unknowns

- No real 531-basin complete-input artifact exists, so its final file hashes and exact dynamic and target normalization values cannot yet be reported.
- The real sequence of authorization consumption, 531-basin streaming, audit, and directory promotion has not run.
- Component checks narrow Windows path-replacement races but cannot mathematically eliminate a concurrent replacement between a status check and the following open or rename without handle-relative operating-system primitives.
- Scientific model performance is unchanged and remains unknown for the untrained version 09 candidates.

## Exact next condition

The smallest next action is a separately authorized, resource-gated generation of the one formal complete-input package. The required authorization sentence is:

`批准版本09正式完整输入封存生成；不批准训练、正式预测或评分。`

That future authorization would permit only the fixed complete-input generation attempt. It would not permit training, prediction generation, random holdout derivation, or scoring.
