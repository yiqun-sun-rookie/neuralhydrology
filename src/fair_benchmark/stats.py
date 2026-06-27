"""Paired challenger-vs-baseline statistics.

A "win" must be statistical, not a lucky single number: we pair per basin,
report the median paired delta, win-rate, Wilcoxon signed-rank p, and a
bootstrap CI on the median paired delta. Only basins present and finite on
BOTH sides are paired, so a challenger cannot inflate its score by dropping
hard basins (a separate coverage check guards that too).
"""
from typing import Mapping

import numpy as np
from scipy import stats as _sp

_CI_ALPHA = 0.05
_DEFAULT_BOOTSTRAP = 10000


def _paired(challenger: Mapping[str, float], baseline: Mapping[str, float]):
    basins, diffs, ch, bl = [], [], [], []
    for basin, c in challenger.items():
        b = baseline.get(basin)
        if b is None:
            continue
        if c is None or b is None or np.isnan(c) or np.isnan(b):
            continue
        basins.append(basin)
        ch.append(float(c))
        bl.append(float(b))
        diffs.append(float(c) - float(b))
    return basins, np.asarray(ch), np.asarray(bl), np.asarray(diffs)


def paired_comparison(
    challenger: Mapping[str, float],
    baseline: Mapping[str, float],
    n_bootstrap: int = _DEFAULT_BOOTSTRAP,
    seed: int = 0,
) -> dict:
    basins, ch, bl, diffs = _paired(challenger, baseline)
    n = len(basins)
    if n == 0:
        return {
            "n": 0, "challenger_median": float("nan"), "baseline_median": float("nan"),
            "median_paired_delta": float("nan"), "win_rate": float("nan"),
            "wilcoxon_p": float("nan"), "ci_low": float("nan"), "ci_high": float("nan"),
        }

    median_delta = float(np.median(diffs))
    win_rate = float(np.mean(diffs > 0.0))

    if np.allclose(diffs, 0.0):
        wilcoxon_p = float("nan")
    else:
        wilcoxon_p = float(_sp.wilcoxon(diffs).pvalue)

    rng = np.random.default_rng(seed)
    boot = np.array([
        np.median(diffs[rng.integers(0, n, n)]) for _ in range(n_bootstrap)
    ])
    ci_low = float(np.percentile(boot, 100 * _CI_ALPHA / 2))
    ci_high = float(np.percentile(boot, 100 * (1 - _CI_ALPHA / 2)))

    return {
        "n": n,
        "challenger_median": float(np.median(ch)),
        "baseline_median": float(np.median(bl)),
        "median_paired_delta": median_delta,
        "win_rate": win_rate,
        "wilcoxon_p": wilcoxon_p,
        "ci_low": ci_low,
        "ci_high": ci_high,
    }
