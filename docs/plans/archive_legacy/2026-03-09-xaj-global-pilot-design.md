# XAJ Global Pilot Design

**Date**: 2026-03-09
**Status**: Design Approved
**Scope**: Kill-or-go pilot for climate-conditioned global XAJ

## 1. Goal

Define a first-stage pilot that decides whether a climate-conditioned global XAJ paper is worth pursuing. The pilot must determine whether the dominant limitation of globalized XAJ is mainly missing snow processes or a broader runoff-generation structural mismatch across hydroclimates.

This pilot explicitly does not implement `cc-XAJ`. It exists to decide whether `cc-XAJ` should be built at all.

## 2. Scientific Positioning

The locked paper direction is not "global XAJ as a baseline". The target contribution is a global large-sample diagnosis of where the single-mechanism Xinanjiang model works, where it fails, and whether an interpretable climate-conditioned structural extension is justified.

The pilot therefore excludes the following as main research claims:

- original XAJ globalized without structural change
- `PDD + XAJ` as the main novelty
- adding a simple infiltration branch as a standalone contribution
- numerical stabilization alone as the paper contribution

The pilot asks a narrower question: is there stable regime-dependent evidence that XAJ needs more than a cold-region patch?

## 3. Models To Run

The first-stage pilot will run exactly three models:

- `XAJ`
- `XAJ + PDD`
- `HBV`

Roles in the pilot:

- `XAJ`: baseline that represents the single saturation-excess runoff-generation hypothesis
- `XAJ + PDD`: tests whether missing snow and cold-region processes explain most of the gap
- `HBV`: fixed-structure benchmark that is already considered more flexible than XAJ across climates

No `cc-XAJ` variant will be run in the first round.

## 4. Pilot Question And Decision Boundary

The core pilot question is:

> In a global large-sample setting, is the main shortcoming of XAJ primarily a missing snow process, or does the remaining gap indicate a broader runoff-generation structural mismatch that persists across non-snow hydroclimate regimes?

The pilot is designed to support or reject a future `cc-XAJ` direction. It is not designed to prove a final new mechanism on its own.

## 5. Alternative Explanations And Diagnostic Guardrails

Remaining performance gaps after adding `PDD` must not be automatically attributed to runoff-generation mismatch. The pilot must track competing explanations and use diagnostic metrics to reduce over-interpretation.

Candidate explanations to preserve:

- snow and cold-region process deficiency
- runoff-generation structural mismatch
- soil-moisture and evapotranspiration deficiency
- baseflow, recession, or routing deficiency
- data quality or human-impact confounding

At minimum, summary outputs must allow diagnosis using:

- `NSE`
- `KGE`
- `Bias`
- `peak_bias`
- `lowflow_bias`
- `failed_runs`

If feasible, a recession-related metric may be added later, but it is not required for the first pilot table.

Interpretation guardrails:

- if improvement is concentrated in `snow-dominated` basins, prioritize a snow-process explanation
- if non-snow `semi-humid` and `semi-arid/arid` basins remain behind `HBV`, and the mismatch is event-response-oriented, runoff-generation mismatch becomes a stronger candidate explanation
- if the main gap is low-flow or recession behavior, prioritize baseflow or soil-moisture explanations over runoff-generation claims
- if failure patterns cluster in high-missing or human-affected basins, do not use them to support strong mechanism claims

## 6. Basin Selection Protocol

### Target sample

The pilot sample size is fixed at `60` basins, with `15` basins in each of four hydroclimate regimes:

- `snow-dominated`
- `humid`
- `semi-humid`
- `semi-arid/arid`

The sampling goal is representative and interpretable coverage, not strict random sampling.

### Classification priority

Regime assignment uses a snow-first workflow:

1. classify `snow-dominated` basins first
2. classify non-snow basins by aridity index

### Snow-dominated rule

A basin is `snow-dominated` if either condition is met:

- `snow_fraction >= 0.20`
- `temp_coldest_quarter < 0°C` and cold-season precipitation is substantial

### Non-snow aridity classes

For non-snow basins, classify using `PET / P`:

- `humid`: `PET / P < 1.0`
- `semi-humid`: `1.0 <= PET / P < 1.5`
- `semi-arid/arid`: `PET / P >= 1.5`

### Quality control

Candidate basins must satisfy:

- complete daily meteorological forcing and discharge series
- consistent coverage across the shared train, validation, and test windows
- `missing_rate <= 5%`
- obvious strongly human-regulated basins should be excluded when possible

If human-impact metadata are incomplete, keep a `human_impact_flag` and treat it as a screening field rather than a hard proof of naturalness.

### Sampling balance constraints

Within each regime, the selected `15` basins should be geographically and physically diverse:

- avoid concentrating in a single region
- cap one region at `5` basins when feasible
- cover multiple continents when feasible
- include a range of basin sizes
- include both stronger and weaker seasonality

When representativeness conflicts with randomness, prefer representativeness. When balance conflicts with mechanism clarity, prefer basins that make regime-dependent behavior interpretable and record the reason in `selection_note`.

## 7. Outputs And File Contracts

### Directory layout

The pilot will use the following directory structure:

- `src/xaj_global_pilot/`
- `results/xaj_global_pilot/pilot_v01/`
- `logs/xaj_global_pilot/pilot_v01/`

### Basin registry

`results/xaj_global_pilot/pilot_v01/summary/basin_registry.csv`

Recommended columns:

- `basin_id`
- `dataset`
- `country`
- `region`
- `continent`
- `area_km2`
- `elevation_mean`
- `forest_frac`
- `aridity_index`
- `precip_mean`
- `pet_mean`
- `snow_fraction`
- `temp_coldest_quarter`
- `seasonality_index`
- `human_impact_flag`
- `missing_rate`
- `data_ok`
- `regime`
- `selected_for_pilot`
- `selection_note`

Minimum required columns:

- `basin_id`
- `region`
- `aridity_index`
- `snow_fraction`
- `missing_rate`
- `regime`
- `selected_for_pilot`

### Pilot basin list

`results/xaj_global_pilot/pilot_v01/summary/pilot_60_basins.csv`

Recommended columns:

- `basin_id`
- `dataset`
- `country`
- `region`
- `continent`
- `regime`
- `area_km2`
- `precip_mean`
- `pet_mean`
- `aridity_index`
- `snow_fraction`
- `temp_coldest_quarter`
- `seasonality_index`
- `missing_rate`
- `human_impact_flag`
- `selection_note`

### Per-basin model metrics

`results/xaj_global_pilot/pilot_v01/{model}/{basin_id}.csv`

Minimum columns:

- `basin_id`
- `model`
- `period`
- `nse`
- `kge`
- `bias`
- `peak_bias`
- `lowflow_bias`
- `run_status`
- `error_message`

### Combined basin metrics

`results/xaj_global_pilot/pilot_v01/summary/all_basins_metrics.csv`

Suggested format: one row per `model x basin x period`.

Recommended columns:

- `basin_id`
- `regime`
- `model`
- `period`
- `nse`
- `kge`
- `bias`
- `peak_bias`
- `lowflow_bias`
- `run_status`
- `error_message`

### Regime summary table

`results/xaj_global_pilot/pilot_v01/summary/by_regime_metrics.csv`

One row per `model x regime`.

Recommended columns:

- `regime`
- `model`
- `n_basins`
- `n_success`
- `n_failed`
- `median_nse`
- `mean_nse`
- `median_kge`
- `mean_kge`
- `median_bias`
- `mean_bias`
- `median_peak_bias`
- `median_lowflow_bias`
- `delta_nse_vs_xaj`
- `delta_kge_vs_xaj`
- `iqr_nse`
- `iqr_kge`

## 8. Run Protocol

All selected basins must use a shared train, validation, and test time split. The split must remain fixed across all basins and all three models.

Execution sequence:

1. build `basin_registry.csv`
2. select the final `pilot_60_basins.csv`
3. run `XAJ`, `XAJ + PDD`, and `HBV` on the selected basins
4. write basin-level metrics
5. aggregate `all_basins_metrics.csv`
6. aggregate `by_regime_metrics.csv`
7. decide whether to continue to `cc-XAJ`

Failure handling requirements:

- failed basins must remain visible in outputs
- every failed run must carry a status flag and error message
- batch execution must continue after basin-level failures

## 9. Go / No-Go Criteria

Continue toward `cc-XAJ` only if all of the following are supported by the pilot table:

- `XAJ + PDD` clearly improves over `XAJ` in `snow-dominated` basins
- `XAJ + PDD` still lags behind `HBV` in `semi-humid` and/or `semi-arid/arid` regimes
- the remaining gap is stable across multiple basins rather than driven by a few anomalies
- the remaining gap is diagnostically compatible with runoff-generation mismatch rather than low-flow-only, recession-only, or data-quality artifacts

Pause or stop the `cc-XAJ` line if any of the following is true:

- `XAJ + PDD` is already close to `HBV` in most regimes
- non-snow regimes do not show stable regime-dependent failure
- the pilot table cannot support the claim that failure depends on hydroclimate regime

## 10. Non-Goals

The first-stage pilot will not:

- implement `cc-XAJ`
- add more model families
- treat `PDD + XAJ` as the main novelty
- turn single-basin anecdotes into global mechanism claims
- write the final paper narrative before the pilot table exists

## 11. Recommendation

The next deliverable should be a pilot execution plan and implementation plan that operationalize this design into three concrete phases:

1. construct `basin_registry.csv`
2. finalize `pilot_60_basins.csv`
3. run the three-model pilot and generate the regime summary table used for the go/no-go decision
