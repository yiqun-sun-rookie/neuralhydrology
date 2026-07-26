# Historical-interval expert pilot protocol repair design

## Decision

Create a new experiment family, historical_band_pilot_v02. Preserve v01 unchanged as
protocol_invalid. Version 02 keeps the scientific question, historical intervals, basin list,
random seeds, training budget, parameter budget, validation period, metrics, and continuation
thresholds fixed. Only protocol defects found by independent review are repaired.

The user approved this route with "go" after the required controlled target bundle, fair
dropout placement, analyzer strengthening, and same nine-run comparison were stated.

## Considered approaches

1. Recommended: a trusted preparation step writes a target-only bundle containing 1999-10-01
   through 2008-09-30 for the frozen 60 basins. Candidate training reads that bundle and never
   opens raw observed-streamflow files. This preserves the question and gives an auditable
   separation between data stewardship and model training.
2. Keep the full-file loader and prove that an in-memory mask discards early values. Rejected:
   it still violates the explicit no-read boundary.
3. Change the split or dataset to avoid the protected period. Rejected: this changes the
   scientific comparison and would not answer the approved pilot question.

## Data boundary

The trusted preparation command is the only component allowed to open raw observed-streamflow
files. It emits:

- a deterministic comma-separated target table with basin, date, and observed discharge;
- dates restricted to 1999-10-01 through 2008-09-30;
- exactly the frozen basin list;
- a manifest with row count, date bounds, basin-list hash, bundle hash, and access counts.

The candidate data loader accepts a target-bundle path and expected SHA-256. It rejects a hash
mismatch, basin mismatch, duplicate basin-date keys, dates outside the allowed range, non-finite
targets, or missing expected dates. Candidate training code must not import or call the raw
discharge loader. Raw discharge access by candidate training must be zero.

The trusted preparation process may read protected rows internally but must not emit, print,
summarize, or expose any observation before 1999-10-01. Only its manifest is inspected.

## Fair model comparison

Both multiscale models use the same three encoders. Random dropout is applied separately to each
encoder state in both models. The fusion head and the expert heads plus gate receive those
dropped states; current forcing and static attributes remain undropped in both arms. Thus the
only intended difference remains one fused prediction head versus three interval-specific heads
combined by a dynamic gate.

The mainstream long short-term memory model retains its existing output-state dropout and
parameter budget. No interval, width, optimizer, epoch, basin, seed, or threshold changes are
allowed after v01 results.

## Analysis boundary

Before computing any score, the analyzer must require for each run:

- complete manifest identity and valid hashes;
- exactly 60 basins and 43,860 daily rows;
- dates from 2006-10-01 through 2008-09-30;
- unique basin-date keys;
- finite observed and simulated discharge;
- identical basin-date keys and observed values across all three variants for each seed.

Any violation raises an error or yields INCOMPLETE; it can never silently become GO or NO_GO.

## Experiment identity and evidence

- New family: historical_band_pilot_v02.
- New result root: results/26_historical_band_experts/pilot_v02.
- Variants: mainstream_lstm, multiscale_fusion, historical_band_experts.
- Seeds: 100, 200, 300.
- Old v01 outputs remain untouched and labeled protocol_invalid.
- The new registry row is separate from v01.
- The final result note records the target-bundle hash, source commit, nine manifests, all
  artifact hashes, access ledger, independent recomputation, and review verdict.

## Success and stopping rule

The six previously frozen numerical criteria remain unchanged. A v02 numerical verdict is
admissible only if the data-access ledger records zero raw observed-streamflow reads by candidate
training, all integrity checks pass, and independent review finds no Critical or Important
issue. Otherwise the status is protocol_invalid or incomplete, never GO.
