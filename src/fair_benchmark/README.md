# fair_benchmark — same-information research-competition scoring service

**Lock the rules, open the methods.** A challenger may use any ML/AI method in
any framework. It must (a) use only the information its track allows and (b)
submit a per-basin daily hydrograph. The scoring service holds the only copy of
the evaluation observations, recomputes the metric itself, compares against a
frozen baseline with paired statistics + a secret holdout, and logs every
attempt. The target to beat is the LSTM 8-seed ensemble (median NSE ≈ 0.759).

## Why it is hard to cheat
- **Predictions in, score out.** The challenger submits a hydrograph, never a
  self-reported NSE. The service recomputes NSE from held obs (`score.py`).
- **Coverage check.** Hard days cannot be NaN'd away — predicted finite-day
  count must cover ≥99% of obs days per basin, or REJECT.
- **Secret holdout.** A public win that collapses on a held-back basin set →
  HOLD (overfit/selection suspicion), not PASS.
- **Portfolio ledger.** Every attempt (PASS/HOLD/REJECT) is appended to
  `registry/portfolio_ledger.csv` — the multiple-testing denominator.
- **One authoritative NSE** — verified numerically identical to
  `neuralhydrology/evaluation/metrics.py::nse` (see test_metrics).
- **Level-1 data-tap teeth (`leakage.py`).** The challenger reads only the
  allowed inputs (forcing + statics); the scoring service scans the experiment
  dir for forbidden reads (observed streamflow files, hydro-signature columns
  like runoff_ratio/baseflow_index, the held answer key). A hit forces HOLD for
  audit — never a silent PASS. Heuristic by design (renaming defeats it); its
  job is to surface lazy/accidental obs reads to the independent auditor, not to
  be airtight. Track-aware: Track 1 (past-Q allowed) drops the obs patterns.

## Verdicts
- **PASS** — significant win (median paired Δ ≥ min_effect, Wilcoxon p<0.05,
  bootstrap CI above 0) AND the holdout retains the win.
- **HOLD** — valid but not a clear claimable win (below min effect, not
  significant, CI touches 0, or holdout collapses). Includes honest non-wins.
- **REJECT** — invalid/unfair: no predictions, contract violation, coverage
  mismatch, or no paired basins.

## Tracks (separated, each independently rigorous)
- `track0_forcing_only` — inputs = forcing + static attributes, **no observed
  discharge**. Built now.
- `track1_past_q` — (future) may use observed discharge up to issue time t0;
  rolling-origin lead-time eval; reuses `src/ylx_dl_da` leakage guards +
  eval protocol. **Cross-track comparison is forbidden** (leaderboard keyed by track).

## Usage
```bash
# one-time: build the held obs answer key + secret holdout from the baseline run
python -m fair_benchmark.build_frozen_obs           # run from repo root, src on path

# score a challenger submission (per-basin long CSV/parquet: basin,date,qsim)
python -m fair_benchmark.score \
    --predictions experiments/001_my_idea/predictions.csv \
    --experiment  001_my_idea \
    --track       track0_forcing_only
# -> GATE: PASS|HOLD|REJECT ... ; appends a row to registry/portfolio_ledger.csv
```
Run tests: `pytest src/fair_benchmark/tests -v` (not auto-collected by bare `pytest`).

## Status (2026-06-25)
Built + tested (41 tests): metrics, paired stats, gate, ledger, scoring
orchestration, Track-0 frozen baseline + obs answer key, **Level-1 leakage
scan**. **Deferred (named):** Level-2 OS sandbox that re-executes arbitrary
challenger code with obs unreadable — the only way to *prove* (not heuristically
surface) "no observed Q" for untrusted/black-box code; for self-written,
auditor-readable code the Level-1 scan + independent audit suffice and a full
sandbox is over-engineered for this internal threat model. Also deferred:
pretraining-provenance probe for foundation models; claim-mode workflows; Track 1.
