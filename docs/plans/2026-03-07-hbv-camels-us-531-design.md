# CAMELS-US 531 Fixed-Structure HBV Baseline Design

**Date**: 2026-03-07
**Status**: Design Approved
**Scope**: Phase 1 - CAMELS-US only, 531 basins, daily timestep, fixed structure

## 1. Goal

Build a traditional hydrological baseline for the same CAMELS-US 531-basin benchmark used by the existing LSTM runs, targeting a robust mean test NSE near or above 0.6 with a single fixed HBV-style structure.

The baseline must:

- use the same 531 basin list as [`src/full_531_basins/data/531_basin_list.txt`](G:\github\pycharm\projects\neuralhydrology\src\full_531_basins\data\531_basin_list.txt),
- use the same temporal split as [`src/full_531_basins/configs/camels_us/full_training/reproduce_531_nse074.yml`](G:\github\pycharm\projects\neuralhydrology\src\full_531_basins\configs\camels_us\full_training\reproduce_531_nse074.yml),
- stay in daily scale,
- keep one fixed model structure for all basins,
- allow per-basin parameter calibration under one shared parameter schema.

## 2. Constraints And Existing Assets

### Existing benchmark alignment

The reference deep-learning benchmark uses:

- train: 1990-10-01 to 1995-09-30
- validation: 1995-10-01 to 2000-09-30
- test: 2000-10-01 to 2005-09-30
- same basin set for train, validation, and test; only time is split

### Existing reusable code

The repository already contains reusable components in [`src/hydroagent`](G:\github\pycharm\projects\neuralhydrology\src\hydroagent):

- [`src/hydroagent/data_loading.py`](G:\github\pycharm\projects\neuralhydrology\src\hydroagent\data_loading.py): CAMELS-US forcing and discharge loading
- [`src/hydroagent/environment.py`](G:\github\pycharm\projects\neuralhydrology\src\hydroagent\environment.py): SuperflexPy-backed calibration and simulation environment
- vendored SuperflexPy under `external/superflexpy`

Important dependency reality:

- the vendored SuperflexPy is **not** exactly tag `1.3.2`
- current local state is commit `75d93c3c1294181ee157c1002a38ff1b1136f617`
- `git describe` reports `1.3.2-15-g75d93c3`
- `setup.py` still says `version="1.3.2"`

This must be documented in the baseline outputs so results remain reproducible.

### Workspace boundary

`src/hydroagent/` currently has user-side uncommitted work. The new baseline must therefore:

- avoid modifying existing `hydroagent` files unless proven necessary,
- treat `hydroagent` as an internal dependency,
- place new baseline orchestration code in a separate module.

## 3. Model Choice

The baseline model will be a fixed HBV-style structure:

`SnowReservoir -> UnsaturatedReservoir -> PowerReservoir + LinearReservoir -> HalfTriangularLag`

Interpretation:

- `SnowReservoir`: partition rainfall/snow and release melt water
- `UnsaturatedReservoir`: soil moisture accounting and runoff generation
- `PowerReservoir`: fast nonlinear response
- `LinearReservoir`: slow groundwater/baseflow response
- `HalfTriangularLag`: simple routing delay on the fast pathway or combined outflow

This is deliberately conservative:

- more flexible than XAJ for multi-climate CAMELS-US use
- simpler than agent-discovered adaptive topologies
- more general than a no-snow lumped model

## 4. Architecture

New code will live in a separate experiment-oriented module, preferably:

`src/hbv_camels_us_531/`

Planned components:

- `config.py`: benchmark constants, split dates, paths, parameter defaults
- `structure.py`: fixed HBV structure JSON builder
- `runner.py`: single-basin calibration/evaluation orchestration
- `batch.py`: 531-basin batch execution and summary aggregation
- `reporting.py`: summary statistics and output tables
- `scripts/run_hbv_camels_us_531.py`: CLI entrypoint

The new module will call into `hydroagent` rather than reimplement:

- data loading
- SuperflexPy model construction
- Optuna-based parameter search
- NSE-based calibration objective

## 5. Data Flow

Per basin:

1. load forcing and discharge for one period with `hydroagent.data_loading`
2. build the fixed HBV structure JSON
3. calibrate on the train window
4. evaluate with locked parameters on validation and test windows
5. persist metrics and selected parameters

Batch level:

1. iterate over all basins in the canonical 531 list
2. continue on per-basin failures instead of aborting the full run
3. write one row per basin with train/val/test metrics and metadata
4. compute aggregate statistics:
   - mean NSE
   - median NSE
   - fraction with NSE >= 0.5
   - fraction with NSE >= 0.6
   - failed basin count

## 6. Error Handling

The batch runner must explicitly handle:

- missing basin files
- missing temperature forcing required by `SnowReservoir`
- calibration failures
- non-finite simulated discharge
- invalid parameter combinations or SuperflexPy topology errors

Failure policy:

- mark basin as failed
- record error message in output table
- proceed to next basin

## 7. Testing Strategy

Testing is split into three layers:

- unit tests for structure builder and config invariants
- integration tests for one-basin run with real CAMELS-US data, if available locally
- smoke batch test over 1-3 basins to verify summary output format

The first implementation target is not the full 531-basin experiment itself. It is a correct, repeatable runner that can later be scaled to all basins.

## 8. Deliverables

Phase 1 deliverables:

- reusable `src/hbv_camels_us_531/` module
- CLI runner for single basin and batch modes
- CSV summary aligned with the existing benchmark split
- reproducibility note recording SuperflexPy commit `75d93c3`
- tests covering structure, runner contract, and batch summary contract

Phase 1 explicitly excludes:

- Caravan support
- hourly modeling
- adaptive topology search
- regionalized parameter networks
- integration into `python -m neuralhydrology.nh_run`

## 9. Recommendation

Use a fixed-structure HBV-style baseline as a dedicated experiment module that reuses `hydroagent` internals but remains isolated from ongoing HydroAgent feature work. This is the lowest-risk path to a credible traditional multi-basin baseline on the CAMELS-US 531 benchmark.
