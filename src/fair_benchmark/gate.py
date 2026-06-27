"""PASS / HOLD / REJECT decision logic.

Two layers, in order:
  1. INTEGRITY (any failure -> REJECT): the result is invalid/unfair and does
     not count. Covers missing predictions, contract violation, coverage
     mismatch (the "NaN your worst timesteps" exploit), no paired basins.
  2. WIN VALIDITY (valid results only):
       PASS  - statistically significant win AND the secret holdout agrees.
       HOLD  - valid but not a clear claimable win: improvement below the
               minimum meaningful effect, not significant, CI touches zero,
               OR public win that collapses on the holdout (overfit/selection
               suspicion). HOLD = "valid, look closer / iterate", not a win.

A clean negative ("tried, did not beat baseline") is HOLD, not REJECT:
REJECT is reserved for invalidity, never for an honest non-win.
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class GateConfig:
    min_effect: float = 0.01          # min meaningful median paired delta (~baseline seed sigma)
    max_wilcoxon_p: float = 0.05
    holdout_min_effect: float = 0.005  # holdout has smaller n -> more lenient floor
    holdout_retention: float = 0.5     # holdout must retain >= this fraction of the public win


def _is_significant_win(s: dict, cfg: GateConfig) -> bool:
    p = s["wilcoxon_p"]
    return (
        s["median_paired_delta"] >= cfg.min_effect
        and p == p  # not NaN
        and p < cfg.max_wilcoxon_p
        and s["ci_low"] > 0.0
    )


def decide(*, has_predictions: bool, contract_ok: bool, coverage_ok: bool,
           public: dict, holdout: dict, cfg: GateConfig, leakage_ok: bool = True) -> dict:
    # --- Layer 1: integrity (REJECT) ---
    if not has_predictions:
        return {"verdict": "REJECT", "reasons": ["no_predictions_file"]}
    if not contract_ok:
        return {"verdict": "REJECT", "reasons": ["contract_violation"]}
    if not coverage_ok:
        return {"verdict": "REJECT", "reasons": ["coverage_mismatch_vs_baseline"]}
    if public.get("n", 0) == 0:
        return {"verdict": "REJECT", "reasons": ["no_paired_basins"]}

    # --- Layer 1b: leakage scan (HOLD, not REJECT: heuristic may false-positive,
    #     so a hit forces audit rather than auto-invalidating an honest run) ---
    if not leakage_ok:
        return {"verdict": "HOLD", "reasons": ["forbidden_data_access_suspected_audit_required"]}

    # --- Layer 2: win validity (PASS / HOLD) ---
    if not _is_significant_win(public, cfg):
        return {"verdict": "HOLD", "reasons": ["no_significant_improvement_over_baseline"]}

    holdout_delta = holdout.get("median_paired_delta", float("nan"))
    public_delta = public["median_paired_delta"]
    # Consistent if the holdout independently clears the floor AND retains a
    # reasonable fraction of the public win. A retention ratio (not an absolute
    # gap) scales correctly: it does not punish a big uniform win for a little
    # subset-to-subset noise, but it does catch a public win that collapses.
    holdout_consistent = (
        holdout_delta == holdout_delta  # not NaN
        and holdout_delta >= cfg.holdout_min_effect
        and holdout_delta >= cfg.holdout_retention * public_delta
    )
    if not holdout_consistent:
        return {"verdict": "HOLD", "reasons": ["holdout_inconsistent_possible_overfit_or_selection"]}

    return {"verdict": "PASS", "reasons": ["significant_win_holdout_consistent"]}
