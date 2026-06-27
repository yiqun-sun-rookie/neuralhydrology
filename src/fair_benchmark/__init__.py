"""Fair-benchmark: a same-information research-competition scoring service.

Lock the rules, open the methods. A challenger submits per-basin daily
streamflow predictions; the scoring service holds the only copy of the
evaluation observations, recomputes the metric itself, compares against a
frozen baseline with proper paired statistics, checks a secret holdout, and
logs every attempt to an append-only portfolio ledger.

Tracks (separated, each rigorous):
  - track0_forcing_only: inputs = meteorological forcing + static attributes,
    NO observed discharge. Baseline = LSTM 8-seed ensemble (median NSE 0.759).
  - track1_past_q (future): may use observed discharge up to issue time t0.
    Seam left; reuses src/ylx_dl_da leakage guards + rolling-origin protocol.
"""
