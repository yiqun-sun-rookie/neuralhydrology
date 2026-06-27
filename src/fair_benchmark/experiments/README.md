# experiments/ — challenger workspace

One directory per attempt: `NNN_short_name/` (e.g. `001_tft_forcing`). Copy
`TEMPLATE/` to start. Each experiment is self-contained: the code that produced
the predictions, a `submission.yaml` declaration, and the `predictions.csv` it
emits. The scoring service reads the predictions and (Level-1) scans this
directory for forbidden data access — so keep only allowed-input code here.

## The contract (Track-0)
1. **Read only the allowed bundle** — `../frozen/bundle/track0_forcing.parquet`
   (5 Maurer forcings) + `../frozen/bundle/track0_statics.csv` (27 attributes).
   Never read observed discharge, obs-derived hydro signatures, future windows,
   or extra data products. The held answer key is NOT on your side of the wall.
2. **Emit a hydrograph** — `predictions.csv` with columns `basin,date,qsim`
   (mm/day), covering the eval window (1989-10-01 … 1999-09-30) for all 531
   basins. Missing days fail the ≥99% coverage check → REJECT.
3. **Score it** — the service recomputes NSE from held obs, compares against the
   LSTM 8-seed ensemble (median NSE ≈ 0.759) with paired stats + a secret
   holdout, and appends the attempt to the portfolio ledger.

## Two modes
- **explore** — cheap, no ceremony. Iterate freely. If the Track-0 spec is not
  yet human-confirmed, score with `--allow-unconfirmed`. Honest non-wins log as
  HOLD; that is expected and fine.
- **claim** — only once a submission actually clears the gate (PASS). Requires a
  confirmed spec and triggers the independent audit (a clean, adversarial
  context — Codex or a fresh CC — re-checks the win from the frozen inputs).

## Run
```bash
# from repo root, src on path (see tests/conftest.py for the bootstrap)
EXP=src/fair_benchmark/experiments/001_x
python $EXP/predict.py --out $EXP/predictions.csv
python -m fair_benchmark.score \
    --predictions $EXP/predictions.csv \
    --experiment  001_x --track track0_forcing_only \
    --experiment-dir $EXP   # scanned for forbidden reads
```
