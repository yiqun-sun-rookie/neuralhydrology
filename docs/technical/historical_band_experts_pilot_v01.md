# Historical-interval expert pilot: fixed first-round result

## Evidence qualification

The run is **PROTOCOL_INVALID** and cannot support a formal continuation decision. Its numerical
gate returned **NO_GO**, but the data loader read complete raw discharge files before discarding
the formal evaluation dates in memory. The formal scoring service was not used and the formal
evaluation values did not enter model inputs, targets, scaling, or reported metrics, but the
explicit no-read boundary was still violated.

An independent review also found unequal dropout placement between the expert model and the
equal-input multiscale fusion control. The numerical results below are retained as exploratory
diagnostics only. They do not establish that the tested mechanism, or every possible
historical-interval expert design, is ineffective.

## Frozen comparison

- Training target dates: 1999-10-01 through 2006-09-30.
- Internal validation target dates: 2006-10-01 through 2008-09-30.
- Basins: 60, selected deterministically using only the allowed 27 static attributes.
- Random seeds: 100, 200, and 300.
- Dynamic model inputs: Maurer meteorological forcing only; observed discharge was used only as
  the supervised training target and validation metric, never as a model input.
- Recent interval: lags 0-29 days, retained daily.
- Medium interval: lags 30-1824 days, aggregated into 60 equal-width mean bins.
- Old interval: lags 1825-3649 days, aggregated into 60 equal-width mean bins.
- Model sizes: mainstream long short-term memory network 83,073 parameters; equal-input
  multiscale fusion control 82,497; explicit historical-interval experts 82,758. The maximum
  spread was 0.69%.
- Each of the nine runs used 10 epochs, 153,420 training samples, and produced 43,860 validation
  predictions covering 60 basins.

The training code commit was 27a02bb0d97c01709891bd67fca2f02ee5678276.
The configuration SHA-256 was
0c1b34991d0e93bacb1e1ed4e05ed762788b84db429f79e89c0a3cf5a6eb2d0a.
The basin-list SHA-256 was
3160dad3b22200fdb596164c9f69e4fbe19cc156cfad768beb193efea7b26b65.

## Results

Median basin Nash-Sutcliffe efficiency by random seed:

| Model | Seed 100 | Seed 200 | Seed 300 |
|---|---:|---:|---:|
| Mainstream long short-term memory network | 0.6284 | 0.6272 | 0.6303 |
| Equal-input multiscale fusion control | 0.5872 | 0.6663 | 0.6664 |
| Explicit historical-interval experts | 0.6169 | 0.6397 | 0.6333 |

Paired expert-minus-fusion results:

| Seed | Median basin difference | Basin win fraction | Joint threshold result |
|---|---:|---:|---|
| 100 | 0.04055 | 0.6167 | Pass |
| 200 | 0.00110 | 0.5167 | Fail |
| 300 | -0.00734 | 0.4667 | Fail |

Only one of three seeds passed both the pre-registered median-effect threshold of 0.01 and basin
win-fraction threshold of 0.55; at least two passing seeds were required. The paired basin-level
bootstrap 95% interval for the mean-across-seeds expert-minus-fusion effect was
[-0.02122, 0.01370], which includes zero.

The expert model's median paired difference from the mainstream model was 0.01251, so the
mainstream non-inferiority condition passed. Mean gate weights were 0.1538 for the recent
interval, 0.7323 for the medium interval, and 0.1140 for the old interval; the maximum remained
below the frozen collapse limit of 0.95. These two passing conditions do not override the failed
mechanism-specific comparison against equal-input multiscale fusion.

## Frozen decision criteria

| Criterion | Result |
|---|---|
| Median expert-minus-fusion effect at least 0.01 in at least two seeds | Fail |
| Expert basin win fraction at least 0.55 in at least two seeds | Fail |
| Both thresholds met jointly in at least two seeds | Fail |
| Paired bootstrap 95% lower bound above zero | Fail |
| Expert not worse than mainstream model | Pass |
| No expert-weight collapse above 0.95 | Pass |

All six numerical criteria were required, so the computational gate returned **NO_GO**. The
protocol violation overrides that gate: the experiment-level status is **PROTOCOL_INVALID**,
not a valid **NO_GO**.

## Exact commands

Each training run used this command template:

    python src/26_historical_band_experts/train.py --config src/26_historical_band_experts/configs/pilot_v01.json --variant <mainstream_lstm|multiscale_fusion|historical_band_experts> --seed <100|200|300> --data-dir G:\github\pycharm\projects\neuralhydrology\data\camels_us --device cuda:0

The frozen analysis and implementation verification commands were:

    python src/26_historical_band_experts/analyze.py --results-root results/26_historical_band_experts/pilot_v01
    pytest src/26_historical_band_experts/tests -v

## Evidence locations and verification

- Run directories:
  results/26_historical_band_experts/pilot_v01/<variant>_s<seed>/.
- Frozen decision:
  results/26_historical_band_experts/pilot_v01/summary.json.
- Per-seed comparison:
  results/26_historical_band_experts/pilot_v01/per_seed.csv.
- Paired basin comparison:
  results/26_historical_band_experts/pilot_v01/paired_per_basin.csv.

Analysis-output SHA-256 hashes:

- summary.json:
  585e32407697e04c77623308f28bd45153941076d49a014a0f394b75c95ac349.
- per_seed.csv:
  67b195cb9056a55244c86339bf5236ded1edba076170b50681f7b2c347d510a2.
- paired_per_basin.csv:
  d867759acff51a78a9566790e448ebfd417f1d7330d962e97db3440116d6c702.

An independent recomputation verified all 9 manifests, all 36 artifact hashes, all 394,740
daily predictions, all stored per-basin Nash-Sutcliffe efficiencies, and the frozen decision.
The focused implementation suite completed with 33 passing tests and one pre-existing
configuration warning. A later independent code and data-access audit found the sealed-period
read and the unequal-dropout comparison described above; therefore reproducible arithmetic does
not make this run admissible benchmark evidence.
