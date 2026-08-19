"""Stage-4 step 1: re-currency the Q-layer vote from likelihood to forecast skill.

Preregistration: docs/plans/2026-08-18-online-noise-stage4-s1-skill-weighting-prereg-v01.md

Offline only -- ZERO new filter runs.  Inputs are the amendment-01b single-member
control npz of stage 3 (52 basins x 15 cells, per-day one-step forecasts and
observations).  The single changed variable is the cross-cell weighting rule:
discounted-likelihood BMA (A2f99) -> discounted inverse squared forecast error.
lambda = 0.99 is inherited verbatim, the rule has no fitted parameter, and the
weights are strictly causal (day t uses errors through day t-1 only).

Gates (frozen before computing): G1 non-inferiority to the fixed m1_c0 cell
(median paired NSE diff >= -0.01); G2 repair (beats the likelihood mixture AND
the open loop, median paired diff > 0 for both).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

_SRC = Path(__file__).resolve().parents[1]
if str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))

from camels_switch_confirmation.run_online_noise_pilot import (  # noqa: E402
    BMA_FORGET,
    cell_tag,
    grid_cells,
)
from camels_switch_confirmation.run_online_noise_real_obs import (  # noqa: E402
    OUTPUT_ROOT as STAGE3_ROOT,
    PERMUTATION_SEED,
    _load_cell_npz,
    _sign_flip_p,
    admitted_frame,
    boundary_cell_indices,
    kge,
    mixture_forecast,
    nse,
)

PREREGISTRATION = (
    "docs/plans/2026-08-18-online-noise-stage4-s1-skill-weighting-prereg-v01.md"
)
EXPERIMENT_ID = "CAMELS_ONLINE_NOISE_STAGE4_S1_SKILL_WEIGHTING"
OUTPUT_ROOT = STAGE3_ROOT.parent / "online_noise_stage4_s1_20260818_local"
G1_TOLERANCE = -0.01
REFERENCE_CELL = "m1_c0"


def discounted_squared_errors(forecasts: np.ndarray, observations: np.ndarray,
                              forget: float = BMA_FORGET) -> np.ndarray:
    """S[g, t] = forget * S[g, t-1] + e[g, t-1]^2 with S[g, 0] = 0 (causal)."""
    forecasts = np.asarray(forecasts, dtype=np.float64)
    observations = np.asarray(observations, dtype=np.float64)
    errors_sq = (forecasts - observations[None, :]) ** 2
    scores = np.zeros_like(errors_sq)
    for day in range(1, errors_sq.shape[1]):
        scores[:, day] = forget * scores[:, day - 1] + errors_sq[:, day - 1]
    return scores


def inverse_error_weights(scores: np.ndarray) -> np.ndarray:
    """w[g, t] proportional to 1/S[g, t]; uniform where all-zero; zero-score
    cells (if any) split the whole weight equally among themselves."""
    scores = np.asarray(scores, dtype=np.float64)
    n_cells, n_days = scores.shape
    weights = np.empty_like(scores)
    for day in range(n_days):
        column = scores[:, day]
        zero = column <= 0.0
        if zero.all():
            weights[:, day] = 1.0 / n_cells
        elif zero.any():
            weights[:, day] = np.where(zero, 1.0 / zero.sum(), 0.0)
        else:
            inverse = 1.0 / column
            weights[:, day] = inverse / inverse.sum()
    return weights


def skill_mixture(forecasts: np.ndarray, observations: np.ndarray,
                  forget: float = BMA_FORGET) -> tuple:
    """Return (mixture forecast, weights) under the frozen inverse-error rule."""
    scores = discounted_squared_errors(forecasts, observations, forget)
    weights = inverse_error_weights(scores)
    return np.sum(weights * forecasts, axis=0), weights


def argmin_mixture(forecasts: np.ndarray, observations: np.ndarray,
                   forget: float = BMA_FORGET) -> np.ndarray:
    """Descriptive winner-take-all variant: follow the lowest-score cell."""
    scores = discounted_squared_errors(forecasts, observations, forget)
    choice = scores.argmin(axis=0)
    return forecasts[choice, np.arange(forecasts.shape[1])]


def _paired(diffs: np.ndarray) -> dict:
    from scipy.stats import wilcoxon

    diffs = np.asarray(diffs, dtype=np.float64)
    nonzero = diffs[diffs != 0.0]
    return {
        "n": int(len(diffs)),
        "improved": int((diffs > 0).sum()),
        "worse": int((diffs < 0).sum()),
        "median_diff": float(np.median(diffs)),
        "mean_diff": float(diffs.mean()),
        "wilcoxon_p": float(wilcoxon(nonzero).pvalue) if len(nonzero) >= 5 else float("nan"),
        "sign_flip_permutation_p": _sign_flip_p(diffs),
    }


def main() -> None:
    admitted = admitted_frame().set_index("basin_id")
    basins = sorted(admitted.index)
    cells = grid_cells()
    boundary = boundary_cell_indices(cells)
    column_of = {tag: index for index, (m, c) in enumerate(cells)
                 for tag in [cell_tag(m, c)]}
    rows = []
    weight_column_sums = np.zeros(len(cells))
    for basin in basins:
        forecasts, observations = [], None
        for (m, c) in cells:
            data = _load_cell_npz(
                STAGE3_ROOT / "grid" / "CTRL" / cell_tag(m, c) / "probs" / f"{basin}.npz"
            )
            forecasts.append(data["one_step_forecast"])
            observations = data["observations"]
        forecasts = np.asarray(forecasts)
        loglik = np.asarray([
            _load_cell_npz(
                STAGE3_ROOT / "grid" / "CTRL" / cell_tag(m, c) / "probs" / f"{basin}.npz"
            )["marginal_log_likelihood"]
            for (m, c) in cells
        ])
        skill_forecast, weights = skill_mixture(forecasts, observations)
        rows.append({
            "basin_id": basin,
            "stratum": admitted.loc[basin, "stratum"],
            "nse_skill_mix": nse(skill_forecast, observations),
            "nse_argmin_mix": nse(argmin_mixture(forecasts, observations), observations),
            "nse_likelihood_mix": nse(
                mixture_forecast(loglik, forecasts, BMA_FORGET), observations
            ),
            "nse_fixed_m1c0": nse(forecasts[column_of[REFERENCE_CELL]], observations),
            "nse_open_loop": float(admitted.loc[basin, "nse_m1"]),
            "kge_skill_mix": kge(skill_forecast, observations),
            "kge_fixed_m1c0": kge(forecasts[column_of[REFERENCE_CELL]], observations),
            "boundary_weight_timeavg": float(weights.mean(axis=1)[boundary].sum()),
        })
        weight_column_sums += weights.mean(axis=1)
    metrics = pd.DataFrame(rows)
    d_g1 = metrics["nse_skill_mix"] - metrics["nse_fixed_m1c0"]
    d_lik = metrics["nse_skill_mix"] - metrics["nse_likelihood_mix"]
    d_open = metrics["nse_skill_mix"] - metrics["nse_open_loop"]
    gates = {
        "G1_noninferiority_vs_m1c0": {
            **_paired(d_g1.to_numpy()),
            "tolerance": G1_TOLERANCE,
            "passed": bool(np.median(d_g1) >= G1_TOLERANCE),
        },
        "G2_repair": {
            "vs_likelihood_mix": _paired(d_lik.to_numpy()),
            "vs_open_loop": _paired(d_open.to_numpy()),
            "passed": bool(np.median(d_lik) > 0 and np.median(d_open) > 0),
        },
    }
    gates["step1_passed"] = bool(
        gates["G1_noninferiority_vs_m1c0"]["passed"] and gates["G2_repair"]["passed"]
    )
    mean_weights = weight_column_sums / len(basins)
    cell_weight_table = {
        cell_tag(m, c): round(float(w), 4)
        for (m, c), w in zip(cells, mean_weights)
    }
    summary = {
        "experiment_id": EXPERIMENT_ID,
        "preregistration": PREREGISTRATION,
        "n_basins": len(basins),
        "rule": "discounted inverse squared forecast error, lambda inherited 0.99",
        "permutation_seed_note": f"sign-flip permutation seed {PERMUTATION_SEED}",
        "gates": gates,
        "medians": {
            "skill_mix": float(metrics["nse_skill_mix"].median()),
            "argmin_mix": float(metrics["nse_argmin_mix"].median()),
            "likelihood_mix": float(metrics["nse_likelihood_mix"].median()),
            "fixed_m1c0": float(metrics["nse_fixed_m1c0"].median()),
            "open_loop": float(metrics["nse_open_loop"].median()),
            "kge_skill_mix": float(metrics["kge_skill_mix"].median()),
            "kge_fixed_m1c0": float(metrics["kge_fixed_m1c0"].median()),
        },
        "by_stratum_median_skill_minus_m1c0": {
            stratum: float(group.median())
            for stratum, group in d_g1.groupby(metrics["stratum"])
        },
        "boundary_weight_timeavg_median": float(
            metrics["boundary_weight_timeavg"].median()
        ),
        "mean_cell_weights": cell_weight_table,
    }
    out_dir = OUTPUT_ROOT / "verification"
    out_dir.mkdir(parents=True, exist_ok=True)
    metrics.to_csv(out_dir / "task_metrics.csv", index=False)
    (out_dir / "verification_summary.json").write_text(
        json.dumps(summary, indent=1), encoding="utf-8"
    )
    print(json.dumps({"gates": gates, "medians": summary["medians"]}, indent=1))


if __name__ == "__main__":
    main()
