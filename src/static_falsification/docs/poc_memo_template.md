# FiLM-LSTM POC — Result Memo

**Date:** YYYY-MM-DD
**Runs:** 24 (2 models × 2 static conditions × 2 folds × 3 seeds)
**Reference spec:** `docs/superpowers/specs/2026-04-15-film-lstm-poc-design.md`
**Reference plan:** `docs/superpowers/plans/2026-04-15-film-lstm-poc-plan.md`

## Per-run median test NSE (averaged over seeds per fold)

|  | EA-LSTM real | EA-LSTM shuffle | FiLM-LSTM real | FiLM-LSTM shuffle |
|---|---|---|---|---|
| Fold 0 | _fill_ | _fill_ | _fill_ | _fill_ |
| Fold 1 | _fill_ | _fill_ | _fill_ | _fill_ |
| Fold-avg | _fill_ | _fill_ | _fill_ | _fill_ |

## Deltas

- ΔArch         = NSE(FiLM, real) − NSE(EA, real)   = _fill_
- ΔPhys_FiLM    = NSE(FiLM, real) − NSE(FiLM, shuf) = _fill_
- ΔPhys_EA      = NSE(EA, real)   − NSE(EA, shuf)   = _fill_

## Threshold B check

- [ ] ΔArch ≥ +0.02 — _pass/fail_
- [ ] ΔPhys_FiLM > ΔPhys_EA — _pass/fail_
- [ ] No fold sign conflict — _pass/fail_

## Verdict

_GO: upgrade to full 5-fold × 5 seeds on HPC._
_or_
_NO-GO: pivot per decision branch X in spec §10._

## Next action

_(Link to next plan / commit next piece of work here.)_
