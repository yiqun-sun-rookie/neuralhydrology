# Implementation Plan: ERA5-Land Hourly Support and Validation

## Stage 1 – Extend GEE Export to Support ERA5-Land Hourly Data
- Add an hourly export mode to the existing `projects/haihe/scripts/03_ee_export_era5l.py` (or a dedicated companion script) that targets `ECMWF/ERA5_LAND/HOURLY`.
- Allow users to select the desired band set, including variables required to derive CAMELS-standard features (`temperature_2m`, `temperature_2m_max`, `temperature_2m_min`, `dewpoint_temperature_2m`, accumulative fluxes, wind components, etc.).
- Preserve existing daily export functionality via CLI flags to avoid breaking current workflows.
- Ensure batching, task submission, and logging remain compatible with GEE quota constraints.

## Stage 2 – Implement Local Daily Aggregation and CAMELS Feature Derivation
- Introduce a new processing module (e.g., `projects/haihe/scripts/11b_process_hourly_to_daily.py`) or extend existing post-processing to:
  - Disaggregate hourly accumulative variables to instantaneous hourly values.
  - Convert UTC timestamps to local time per basin and compute daily aggregates (max/min/mean/sum).
  - Derive secondary variables such as `tmax`, `tmin`, and vapor pressure from dew point temperature.
  - Output CAMELS-compliant forcing `.txt` files alongside updated QA reports and attributes.
- Reuse/port reusable routines from `external/Caravan/code/caravan_utils.py` where appropriate to minimise duplication.

## Stage 3 – Validation & Documentation
- Create a reproducible validation case (single basin) executing both the official Caravan pipeline and the new script path, comparing resulting CAMELS variables for numerical equivalence.
- Automate the comparison (e.g., via a small pytest or CLI tool) and store summary statistics.
- Update documentation (`docs/haihe_caravan_pipeline.md`, README snippets) to describe the new hourly workflow, configuration flags, and validation procedure.

## Stage 1: Extend GEE export to support hourly ERA5-Land
**Goal**: Update `projects/haihe/scripts/03_ee_export_era5l.py` (or companion module) so users can choose between daily aggregation and hourly ERA5-Land exports, including the additional bands required to derive CAMELS variables.
**Success Criteria**: Command line accepts a new mode flag; hourly mode selects the correct dataset/band set and constructs export tasks without breaking existing daily workflow.
**Tests**: Unit tests for helper functions that resolve dataset IDs and band lists (no external EE calls).
**Status**: In Progress

## Stage 2: Implement hourly→daily aggregation utilities
**Goal**: Create reusable Python module to convert hourly ERA5-Land CSV exports into local-time daily CAMELS features (`prcp`, `srad`, `tmax`, `tmin`, `vp`, etc.), handling accumulation differencing and unit conversions.
**Success Criteria**: Module exposes pure functions with docstrings; given synthetic hourly data it returns expected daily metrics.
**Tests**: Parameterized tests with small fabricated hourly datasets comparing against known daily aggregates.
**Status**: Not Started

## Stage 3: Integrate aggregation into forcing writer
**Goal**: Modify forcing writing pipeline to optionally consume aggregated outputs, emit CAMELS-style `.txt` with extended variable set, and keep legacy daily path working.
**Success Criteria**: New CLI flag or workflow produces files containing `Year/Mnth/Day` + extended variables; existing tests/scripts continue to function.
**Tests**: Unit tests validating column ordering, value computation (including vapor pressure) on sample data.
**Status**: Not Started

## Stage 4: Validation against Caravan reference
**Goal**: Add regression test or script that compares our aggregation results with Caravan official utilities on a shared sample to ensure equivalence.
**Success Criteria**: Test/command prints pass when our output matches (within tolerance) Caravan-derived expectations for a small fixture.
**Tests**: Automated test using fixture data processed via both pipelines.
**Status**: Not Started

## Stage 5: Documentation & usage updates
**Goal**: Update `docs/haihe_caravan_pipeline.md` (and related docs) with hourly workflow instructions, new commands, and validation guidance.
**Success Criteria**: Documentation describes both daily and hourly paths, including how to run new scripts and interpret outputs.
**Tests**: N/A (documentation only).
**Status**: Not Started


