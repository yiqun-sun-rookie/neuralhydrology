"""Analyze the ID-17 FiLM-vs-EA-LSTM minimal GATE (real condition, PUB test basins).

Headline question (H3): on basins NOT seen in training, does FiLM-LSTM beat EA-LSTM?
We report BOTH:
  * unpaired   : median-over-basins NSE per model, then film - ea  (matches analyze_film_poc)
  * paired     : per-basin (film[b] - ea[b]) on the SAME held-out basins -> median, win rate,
                 and a sign / Wilcoxon test. Paired cancels common per-basin difficulty and is
                 the stronger test for a small, noisy effect.
Cross-fold sign consistency is the gate's real criterion: a real effect keeps its sign across folds.

FAIRNESS (apples-to-apples): EA-LSTM and FiLM-LSTM are ALWAYS scored at the SAME evaluated epoch
within a fold. The verdict epoch is 30 (converged); if a fold has no shared epoch-30 result the
fold is scored at the highest *shared* epoch and flagged NON-CONVERGED, and GREEN is withheld.
This prevents an EA@30-vs-FiLM@20 training-budget asymmetry (one model trained 50% longer).

H2 (physical signal, optional) is read from E2 results if present (inference-time static shuffle):
  ΔPhys = NSE(real) - NSE(E2-shuffle); a model that truly USES static info should drop more.

Usage:
    python src/static_falsification/scripts/analyze_gate.py
    # fixed FiLM variant (input-site, unbounded gamma) vs the SAME EA baselines:
    python src/static_falsification/scripts/analyze_gate.py --film-exp-prefix filmlstm_input_poc_real
"""
import argparse
import math
import pickle
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[3]
RUNS = REPO_ROOT / "runs"
MODELS = ["ealstm", "filmlstm"]
FOLDS = [0, 1]
VERDICT_EPOCH = 30  # converged epoch required for GREEN; both models are scored at the SAME epoch
FILM_EXP_PREFIX = "filmlstm_poc_real"  # overridable via --film-exp-prefix (e.g. input-site variant)


def latest_run_dir(experiment_name: str):
    dirs = sorted(RUNS.glob(f"{experiment_name}_*"))
    return dirs[-1] if dirs else None


def available_test_epochs(run_dir: Path):
    """Sorted list of epochs (ints) that have a test_results.p on disk for this run."""
    if run_dir is None:
        return []
    eps = []
    for p in run_dir.glob("test/model_epoch*/test_results.p"):
        try:
            eps.append(int(p.parent.name.replace("model_epoch", "")))
        except ValueError:
            continue
    return sorted(eps)


def load_nse_by_basin(run_dir: Path, epoch: int):
    """Return {basin_id: NSE} from test/model_epoch{epoch:03d}/test_results.p, or None.

    Reads the first frequency block (handles the '1D' key without hard-coding it)."""
    if run_dir is None:
        return None
    p = run_dir / "test" / f"model_epoch{epoch:03d}" / "test_results.p"
    if not p.is_file():
        return None
    with open(p, "rb") as f:
        res = pickle.load(f)
    out = {}
    for basin, freq_dict in res.items():
        for _freq, metrics in freq_dict.items():
            if isinstance(metrics, dict) and "NSE" in metrics:
                v = metrics["NSE"]
                if v is not None and np.isfinite(v):
                    out[basin] = float(v)
            break
    return out


def sign_test_p(diffs):
    """Two-sided sign test p-value for median(diffs) != 0 (binomial, ties dropped)."""
    pos = sum(1 for d in diffs if d > 0)
    neg = sum(1 for d in diffs if d < 0)
    n = pos + neg
    if n == 0:
        return 1.0
    k = min(pos, neg)
    # two-sided: 2 * P(X <= k) under Binom(n, 0.5)
    cdf = sum(math.comb(n, i) for i in range(k + 1)) / (2 ** n)
    return min(1.0, 2 * cdf)


def fold_report(fold: int):
    ea_dir = latest_run_dir(f"ealstm_poc_real_fold{fold}_seed0")
    film_dir = latest_run_dir(f"{FILM_EXP_PREFIX}_fold{fold}_seed0")
    ea_eps = available_test_epochs(ea_dir)
    film_eps = available_test_epochs(film_dir)
    shared = sorted(set(ea_eps) & set(film_eps))
    if not shared:
        print(f"\n=== fold {fold}: INCOMPLETE — no SHARED evaluated epoch "
              f"(ea={ea_eps or 'MISSING'}, film={film_eps or 'MISSING'}) ===")
        return None
    # Apples-to-apples: score BOTH models at the same epoch. Prefer the converged epoch 30;
    # otherwise the highest shared epoch, flagged NON-CONVERGED (no GREEN).
    eval_epoch = VERDICT_EPOCH if VERDICT_EPOCH in shared else shared[-1]
    converged = eval_epoch == VERDICT_EPOCH
    ea = load_nse_by_basin(ea_dir, eval_epoch)
    film = load_nse_by_basin(film_dir, eval_epoch)
    if not ea or not film:
        print(f"\n=== fold {fold}: INCOMPLETE — could not load epoch {eval_epoch} for both models ===")
        return None
    common = sorted(set(ea) & set(film))
    if not common:
        print(f"\n=== fold {fold}: INCOMPLETE — no common finite-NSE basins ===")
        return None
    ea_med = float(np.median([ea[b] for b in common]))
    film_med = float(np.median([film[b] for b in common]))
    diffs = [film[b] - ea[b] for b in common]
    median_paired = float(np.median(diffs))
    win = sum(1 for d in diffs if d > 0) / len(diffs)
    p = sign_test_p(diffs)
    try:
        from scipy.stats import wilcoxon
        p_w = float(wilcoxon(diffs).pvalue) if any(d != 0 for d in diffs) else 1.0
    except Exception:  # noqa: BLE001
        p_w = None

    tag = "" if converged else "  [NON-CONVERGED]"
    dropped = max(len(ea), len(film)) - len(common)
    print(f"\n=== fold {fold}: {len(common)} common PUB basins @ epoch {eval_epoch}{tag} ===")
    print(f"  scored {len(common)} basins (ea had {len(ea)}, film had {len(film)}; "
          f"{dropped} dropped as non-finite or one-sided)")
    print(f"  median NSE      ea={ea_med:.4f}  film={film_med:.4f}")
    print(f"  ΔArch (unpaired, median film - median ea) = {film_med - ea_med:+.4f}")
    print(f"  paired Δ (film-ea per basin): median={median_paired:+.4f}  "
          f"film_win_rate={win:.1%}  sign-test p={p:.3f}"
          + (f"  wilcoxon p={p_w:.3f}" if p_w is not None else ""))
    return {
        "fold": fold, "n": len(common), "eval_epoch": eval_epoch, "converged": converged,
        "ea_med": ea_med, "film_med": film_med,
        "delta_arch_unpaired": film_med - ea_med,
        "median_paired": median_paired, "win_rate": win,
        "p_sign": p, "p_wilcoxon": p_w,
    }


def main():
    global FILM_EXP_PREFIX
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--film-exp-prefix", default=FILM_EXP_PREFIX,
                        help="experiment-name prefix of the FiLM runs (default: %(default)s; "
                             "use filmlstm_input_poc_real for the input-site unbounded-gamma fix)")
    FILM_EXP_PREFIX = parser.parse_args().film_exp_prefix

    print("=" * 70)
    print(f"ID-17 FiLM-vs-EA-LSTM GATE  (PUB = held-out basins, film prefix: {FILM_EXP_PREFIX})")
    print("=" * 70)
    results = [fold_report(f) for f in FOLDS]
    results = [r for r in results if r is not None]

    if not results:
        print("\nNo completed folds yet.")
        return

    unp = [r["delta_arch_unpaired"] for r in results]
    paired = [r["median_paired"] for r in results]
    wins = [r["win_rate"] for r in results]
    epochs = [r["eval_epoch"] for r in results]
    all_converged = all(r["converged"] for r in results)
    print("\n" + "-" * 70)
    print("CROSS-FOLD SUMMARY")
    print(f"  folds scored at epochs   : {epochs}  (verdict requires all == {VERDICT_EPOCH})")
    print(f"  per-fold ΔArch (unpaired): {[f'{d:+.4f}' for d in unp]}  mean={np.mean(unp):+.4f}")
    print(f"  per-fold paired-median Δ : {[f'{d:+.4f}' for d in paired]}  mean={np.mean(paired):+.4f}")
    print(f"  per-fold film win-rate   : {[f'{w:.1%}' for w in wins]}")

    n_folds = len(results)
    same_sign = (all(d > 0 for d in paired) or all(d < 0 for d in paired)) if n_folds >= 2 else None
    mean_delta = float(np.mean(unp))

    # Gate verdict on H3. GREEN (per spec): unpaired mean ΔArch >= +0.02 AND cross-fold paired sign
    # consistent AND paired mean > 0 AND film win-rate > 50% on EVERY fold. RED: ΔArch < -0.02.
    # Otherwise AMBER. No verdict at all until every fold is converged at epoch 30.
    print("\n" + "-" * 70)
    print("H3 VERDICT (architecture advantage on ungauged basins)")
    if not all_converged:
        print(f"  NON-CONVERGED — not all folds reached epoch {VERDICT_EPOCH} (epochs={epochs}). "
              "Monitoring only; no GREEN/AMBER/RED until both models hit epoch 30 on every fold.")
        print(f"  (aligned-epoch preview: mean ΔArch={mean_delta:+.4f}, paired mean={np.mean(paired):+.4f} "
              "— noisy, NOT a verdict.)")
    elif n_folds < 2:
        print("  AMBER/incomplete — only 1 converged fold; cannot judge cross-fold sign consistency.")
        print(f"  fold ΔArch={mean_delta:+.4f}. Need fold1 (+ ideally more) before any GREEN call.")
    elif mean_delta < -0.02:
        print(f"  RED ✗ — mean ΔArch={mean_delta:+.4f} (< -0.02). FiLM cannot even match EA on PUB. "
              "Per spec, downgrade ID-17, pivot to ID-14.")
    elif mean_delta >= 0.02 and bool(same_sign) and np.mean(paired) > 0 and min(wins) > 0.5:
        print(f"  GREEN-leaning ✓ — mean ΔArch={mean_delta:+.4f} (>=+0.02), paired sign consistent, "
              f"film win-rate>50% every fold {[f'{w:.1%}' for w in wins]}. "
              "Consider full 5-fold x 3-seed on HPC.")
    else:
        why = []
        if mean_delta < 0.02:
            why.append(f"ΔArch={mean_delta:+.4f}<+0.02")
        if not same_sign:
            why.append("paired sign inconsistent across folds")
        if np.mean(paired) <= 0:
            why.append("paired mean<=0")
        if min(wins) <= 0.5:
            why.append(f"win-rate not >50% every fold {[f'{w:.1%}' for w in wins]}")
        print(f"  AMBER — not output-significant ({'; '.join(why)}), but ΔArch>=-0.02 (no real loss). "
              "Effect too small for a WRR-level claim; short paper / honest negative.")
    print("\n(Reminder: local gate, seeds=1/fold — treat small effects as noise. FiLM has ~2x params / "
          "~21x static-encoder capacity vs EA, so a FiLM WIN is capacity-confounded; a tie/loss is robust.)")


if __name__ == "__main__":
    main()
