"""Tests for the PASS/HOLD/REJECT decision logic."""
from fair_benchmark.gate import GateConfig, decide

CFG = GateConfig()


def _stats(delta, p=0.001, ci_low=None, n=400):
    """A stats dict like stats.paired_comparison returns."""
    if ci_low is None:
        ci_low = delta - 0.005
    return {
        "n": n, "challenger_median": 0.80, "baseline_median": 0.80 - delta,
        "median_paired_delta": delta, "win_rate": 0.7,
        "wilcoxon_p": p, "ci_low": ci_low, "ci_high": delta + 0.005,
    }


def _ok(**over):
    base = dict(has_predictions=True, contract_ok=True, coverage_ok=True,
               public=_stats(0.04), holdout=_stats(0.04, n=100), cfg=CFG)
    base.update(over)
    return base


def test_missing_predictions_rejected():
    assert decide(**_ok(has_predictions=False))["verdict"] == "REJECT"


def test_contract_violation_rejected():
    assert decide(**_ok(contract_ok=False))["verdict"] == "REJECT"


def test_coverage_mismatch_rejected():
    out = decide(**_ok(coverage_ok=False))
    assert out["verdict"] == "REJECT"
    assert "coverage" in " ".join(out["reasons"]).lower()


def test_no_paired_basins_rejected():
    assert decide(**_ok(public=_stats(0.04, n=0)))["verdict"] == "REJECT"


def test_significant_win_with_consistent_holdout_passes():
    out = decide(**_ok(public=_stats(0.04), holdout=_stats(0.038, n=100)))
    assert out["verdict"] == "PASS"


def test_significant_public_but_holdout_collapses_is_hold():
    # public looks great, holdout near zero -> overfit/selection suspicion
    out = decide(**_ok(public=_stats(0.05), holdout=_stats(0.001, n=100)))
    assert out["verdict"] == "HOLD"
    assert "holdout" in " ".join(out["reasons"]).lower()


def test_large_uniform_win_passes_despite_absolute_gap():
    # both public and holdout win big; a small absolute gap between the two
    # subset medians is sampling noise, NOT overfit -> must PASS.
    out = decide(**_ok(public=_stats(0.247, ci_low=0.231), holdout=_stats(0.232, n=107)))
    assert out["verdict"] == "PASS"


def test_forbidden_data_access_holds_even_with_strong_win():
    # a leakage-scan hit must force HOLD-for-audit, never a silent PASS
    out = decide(**_ok(leakage_ok=False, public=_stats(0.247, ci_low=0.231),
                       holdout=_stats(0.232, n=107)))
    assert out["verdict"] == "HOLD"
    assert "access" in " ".join(out["reasons"]).lower()


def test_improvement_below_min_effect_is_hold_not_pass():
    out = decide(**_ok(public=_stats(0.003), holdout=_stats(0.003, n=100)))
    assert out["verdict"] == "HOLD"


def test_not_significant_pvalue_is_hold():
    out = decide(**_ok(public=_stats(0.04, p=0.20)))
    assert out["verdict"] == "HOLD"


def test_ci_touching_zero_is_hold():
    out = decide(**_ok(public=_stats(0.04, ci_low=-0.001)))
    assert out["verdict"] == "HOLD"
