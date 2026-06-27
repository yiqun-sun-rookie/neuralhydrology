"""Tests for paired challenger-vs-baseline statistics."""
import numpy as np

from fair_benchmark.stats import paired_comparison


def _vec(start, n, step=0.0):
    return {f"{i:08d}": start + i * step for i in range(n)}


def test_pairs_only_common_non_nan_basins():
    challenger = {"a": 0.7, "b": 0.8, "c": float("nan")}
    baseline = {"a": 0.6, "b": 0.75, "d": 0.9}
    r = paired_comparison(challenger, baseline)
    # c dropped (nan), d dropped (not in challenger) -> n = 2 (a, b)
    assert r["n"] == 2


def test_identical_vectors_zero_delta_no_wins():
    v = {f"{i:08d}": 0.5 + 0.001 * i for i in range(50)}
    r = paired_comparison(v, dict(v))
    assert abs(r["median_paired_delta"]) < 1e-12
    assert r["win_rate"] == 0.0          # ties are not wins
    assert r["ci_low"] <= 0.0 <= r["ci_high"]


def test_uniform_improvement_is_detected():
    baseline = {f"{i:08d}": 0.50 + 0.002 * i for i in range(60)}
    challenger = {k: v + 0.05 for k, v in baseline.items()}
    r = paired_comparison(challenger, baseline, seed=1)
    assert abs(r["median_paired_delta"] - 0.05) < 1e-9
    assert r["win_rate"] == 1.0
    assert r["wilcoxon_p"] < 0.01
    assert r["ci_low"] > 0.0             # whole CI above zero


def test_reports_both_medians():
    baseline = {"a": 0.60, "b": 0.62, "c": 0.64}
    challenger = {"a": 0.70, "b": 0.72, "c": 0.74}
    r = paired_comparison(challenger, baseline)
    assert abs(r["baseline_median"] - 0.62) < 1e-12
    assert abs(r["challenger_median"] - 0.72) < 1e-12


def test_bootstrap_ci_is_deterministic_with_seed():
    baseline = {f"{i:08d}": 0.5 for i in range(40)}
    challenger = {k: 0.5 + (0.03 if int(k) % 2 else -0.01) for k in baseline}
    r1 = paired_comparison(challenger, baseline, seed=42)
    r2 = paired_comparison(challenger, baseline, seed=42)
    assert r1["ci_low"] == r2["ci_low"]
    assert r1["ci_high"] == r2["ci_high"]


def test_all_zero_diff_wilcoxon_is_nan_not_crash():
    v = {f"{i:08d}": 0.5 + 0.001 * i for i in range(30)}
    r = paired_comparison(dict(v), dict(v))
    assert np.isnan(r["wilcoxon_p"])
