"""Verdict for the ID17 HPC gate matrix: 5 folds x 2 seeds, EA-LSTM vs input-site FiLM-LSTM.

Reads runs/gate_{ea,film}_fold{F}_seed{S}_*/test/model_epoch030/*_metrics.csv and reports, at the
pre-registered verdict epoch 30 on held-out (never-trained-on) basins:

  per cell (fold, seed) : median NSE per arm, unpaired dArch, paired per-basin median, win rate
  per fold              : dArch averaged over the 2 seeds  (training noise averaged down)
  across folds          : mean dArch, sign consistency, and a sign test over the 5 fold means

Pre-registered reading (set BEFORE the matrix ran, so it cannot be picked after the fact):
  GREEN  : mean dArch >= +0.02 AND all 5 fold means positive
  RED    : mean dArch <= -0.02 AND all 5 fold means negative
  AMBER  : anything else -> the architecture effect is inside the noise at this scale

Usage:  python src/static_falsification/hpc/analyze_gate_matrix.py
"""
import glob
import math
from pathlib import Path

import numpy as np
import pandas as pd

REPO = Path(__file__).resolve().parents[3]
RUNS = REPO / "runs"
FOLDS = [0, 1, 2, 3, 4]
SEEDS = [0, 1]
EPOCH = 30


def nse_by_basin(model: str, fold: int, seed: int):
    dirs = sorted(RUNS.glob(f"gate_{model}_fold{fold}_seed{seed}_*"))
    if not dirs:
        return None
    files = glob.glob(str(dirs[-1] / "test" / f"model_epoch{EPOCH:03d}" / "*_metrics.csv"))
    if not files:
        return None
    df = pd.read_csv(files[0])
    basin_col = "basin" if "basin" in df.columns else df.columns[0]
    out = {}
    for b, v in zip(df[basin_col], df["NSE"]):
        if pd.notna(v) and np.isfinite(v):
            out[str(b)] = float(v)
    return out or None


def sign_test_p(diffs):
    pos = sum(1 for d in diffs if d > 0)
    neg = sum(1 for d in diffs if d < 0)
    n = pos + neg
    if n == 0:
        return 1.0
    k = min(pos, neg)
    return min(1.0, 2 * sum(math.comb(n, i) for i in range(k + 1)) / (2 ** n))


def main():
    print("=" * 78)
    print(f"ID17 GATE MATRIX — EA-LSTM vs FiLM-LSTM (input-site, unbounded gamma) @ epoch {EPOCH}")
    print("=" * 78)

    fold_means, cells = {}, []
    for fold in FOLDS:
        per_seed = []
        for seed in SEEDS:
            ea, film = nse_by_basin("ea", fold, seed), nse_by_basin("film", fold, seed)
            if not ea or not film:
                print(f"  fold{fold} seed{seed}: INCOMPLETE (ea={'ok' if ea else 'MISSING'}, "
                      f"film={'ok' if film else 'MISSING'})")
                continue
            common = sorted(set(ea) & set(film))
            ea_med, film_med = float(np.median([ea[b] for b in common])), float(np.median([film[b] for b in common]))
            diffs = [film[b] - ea[b] for b in common]
            d_arch = film_med - ea_med
            win = sum(1 for d in diffs if d > 0) / len(diffs)
            per_seed.append(d_arch)
            cells.append(dict(fold=fold, seed=seed, n=len(common), ea=ea_med, film=film_med,
                              d_arch=d_arch, paired=float(np.median(diffs)), win=win,
                              p=sign_test_p(diffs)))
            print(f"  fold{fold} seed{seed}: n={len(common):3d}  ea={ea_med:.4f}  film={film_med:.4f}  "
                  f"dArch={d_arch:+.4f}  paired={np.median(diffs):+.4f}  win={win:.1%}  p={cells[-1]['p']:.3f}")
        if per_seed:
            fold_means[fold] = float(np.mean(per_seed))

    if not fold_means:
        print("\nNo complete cells yet.")
        return

    print("\n" + "-" * 78)
    print("PER-FOLD dArch (averaged over seeds)")
    for f, v in fold_means.items():
        print(f"  fold{f}: {v:+.4f}   ({len([c for c in cells if c['fold'] == f])} seed(s))")

    vals = list(fold_means.values())
    mean_d = float(np.mean(vals))
    all_pos, all_neg = all(v > 0 for v in vals), all(v < 0 for v in vals)
    paired_all = [c["paired"] for c in cells]
    wins = [c["win"] for c in cells]

    print("\n" + "-" * 78)
    print(f"  folds complete       : {len(fold_means)}/{len(FOLDS)}   cells: {len(cells)}/{len(FOLDS)*len(SEEDS)}")
    print(f"  mean dArch over folds: {mean_d:+.4f}   (sd {np.std(vals):.4f}, range {min(vals):+.4f}..{max(vals):+.4f})")
    print(f"  fold-mean signs      : {['+' if v > 0 else '-' for v in vals]}   sign-test p={sign_test_p(vals):.3f}")
    print(f"  paired median (cells): mean {np.mean(paired_all):+.4f}, {sum(1 for p in paired_all if p > 0)}/{len(paired_all)} positive")
    print(f"  FiLM win rate        : mean {np.mean(wins):.1%}, {sum(1 for w in wins if w > 0.5)}/{len(wins)} cells >50%")

    print("\n" + "-" * 78)
    print("H3 VERDICT (pre-registered)")
    if len(fold_means) < len(FOLDS):
        print(f"  INCOMPLETE — {len(fold_means)}/{len(FOLDS)} folds done; no verdict yet.")
    elif mean_d >= 0.02 and all_pos:
        print(f"  GREEN — mean dArch={mean_d:+.4f} >= +0.02 and all {len(vals)} fold means positive. "
              "Static-attribute conditioning DOES help on ungauged basins; ID17 has a real result.")
    elif mean_d <= -0.02 and all_neg:
        print(f"  RED — mean dArch={mean_d:+.4f} <= -0.02 and all fold means negative. FiLM loses; EA stands.")
    else:
        why = []
        if abs(mean_d) < 0.02:
            why.append(f"|mean dArch|={abs(mean_d):.4f} < 0.02")
        if not (all_pos or all_neg):
            why.append(f"fold-mean signs inconsistent {['+' if v > 0 else '-' for v in vals]}")
        print(f"  AMBER — {'; '.join(why)}. The architecture effect is inside the fold/seed noise "
              "at this scale: neither '反超' nor 'EA wins' is supported.")
    print("=" * 78)


if __name__ == "__main__":
    main()
