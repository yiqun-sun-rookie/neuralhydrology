"""Analyze where statistical-constraint perturbations still change forcing structure.

Inputs are records written by run_statistical_structure_probe.py. The script audits:
  1. whether whole-period mean/std are actually preserved after projection,
  2. how much 270-day input-window means/stds still change,
  3. how much whole-period and 270-day cross-variable correlations still change,
  4. whether recorded damage matches exp2_constraint_ablation.json.

Run:
    python src/adversarial/scripts/analyze_statistical_structure.py --eps 0.1
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

REPO = Path(__file__).resolve().parents[3]
RES = REPO / "results" / "05_adversarial_robustness" / "id18_s100"
WINDOW = 270


def window_sum(a: np.ndarray, win: int) -> np.ndarray:
    cs = np.concatenate([np.zeros((1, a.shape[1])), np.cumsum(a, axis=0)], axis=0)
    return cs[win:] - cs[:-win]


def rolling_mean_std(a: np.ndarray, win: int) -> tuple[np.ndarray, np.ndarray]:
    sums = window_sum(a, win)
    sums2 = window_sum(a * a, win)
    mean = sums / win
    var = np.maximum(sums2 / win - mean * mean, 0.0)
    return mean, np.sqrt(var)


def corr_matrix(a: np.ndarray) -> np.ndarray:
    return np.corrcoef(a, rowvar=False)


def rolling_pair_corr(a: np.ndarray, win: int, pairs: list[tuple[int, int]]) -> np.ndarray:
    means, stds = rolling_mean_std(a, win)
    out = []
    for i, j in pairs:
        xy_sum = window_sum((a[:, i] * a[:, j])[:, None], win)[:, 0]
        cov = xy_sum / win - means[:, i] * means[:, j]
        denom = np.maximum(stds[:, i] * stds[:, j], 1e-12)
        out.append(cov / denom)
    return np.stack(out, axis=1)


def q(values, prob):
    arr = np.asarray(values, dtype=float)
    arr = arr[np.isfinite(arr)]
    return float(np.quantile(arr, prob)) if arr.size else float("nan")


def summarize_vector(prefix: str, values) -> dict:
    arr = np.asarray(values, dtype=float)
    arr = arr[np.isfinite(arr)]
    if not arr.size:
        return {f"{prefix}_p50": np.nan, f"{prefix}_p90": np.nan, f"{prefix}_p99": np.nan, f"{prefix}_max": np.nan}
    return {
        f"{prefix}_p50": float(np.quantile(arr, 0.50)),
        f"{prefix}_p90": float(np.quantile(arr, 0.90)),
        f"{prefix}_p99": float(np.quantile(arr, 0.99)),
        f"{prefix}_max": float(np.max(arr)),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--eps", type=float, default=0.1)
    ap.add_argument("--level", default="statistical")
    args = ap.parse_args()

    rec_dir = RES / f"{args.level}_constraint_records_eps{args.eps:g}"
    exp2_path = RES / "exp2_constraint_ablation.json"
    exp2 = {}
    if exp2_path.exists():
        key = f"D_{args.level}_{args.eps:g}"
        exp2 = {r["basin"]: float(r[key]) for r in json.load(open(exp2_path)) if key in r}

    rows = []
    for path in sorted(rec_dir.glob("*.npz")):
        z = np.load(path, allow_pickle=True)
        basin = path.stem
        clean = z["clean_cal"].astype(float)
        delta = z["delta"].astype(float)
        adv = clean + delta
        feat = [str(x) for x in z["feat"]]
        pairs = [(i, j) for i in range(clean.shape[1]) for j in range(i + 1, clean.shape[1])]

        clean_mean, adv_mean = clean.mean(axis=0), adv.mean(axis=0)
        clean_std, adv_std = clean.std(axis=0), adv.std(axis=0)
        whole_mean_abs = np.abs(adv_mean - clean_mean)
        whole_std_rel = np.abs((adv_std - clean_std) / np.maximum(clean_std, 1e-12))

        cm, cs = rolling_mean_std(clean, WINDOW)
        am, astd = rolling_mean_std(adv, WINDOW)
        rolling_mean_abs = np.abs(am - cm).ravel()
        rolling_std_rel = np.abs((astd - cs) / np.maximum(cs, 1e-12)).ravel()

        whole_corr_delta = np.abs(corr_matrix(adv) - corr_matrix(clean))
        whole_pair_delta = np.array([whole_corr_delta[i, j] for i, j in pairs])
        rc = rolling_pair_corr(clean, WINDOW, pairs)
        ra = rolling_pair_corr(adv, WINDOW, pairs)
        rolling_corr_abs = np.abs(ra - rc).ravel()

        row = {
            "basin": basin,
            "D_record": float(z["D_nse"]),
            "D_exp2": exp2.get(basin, np.nan),
            "D_abs_diff_vs_exp2": abs(float(z["D_nse"]) - exp2[basin]) if basin in exp2 else np.nan,
            "whole_mean_abs_max": float(whole_mean_abs.max()),
            "whole_std_rel_max": float(whole_std_rel.max()),
            "whole_corr_abs_max": float(whole_pair_delta.max()),
            "whole_corr_abs_median": float(np.median(whole_pair_delta)),
            "delta_abs_p50": q(np.abs(delta).ravel(), 0.50),
            "delta_abs_p90": q(np.abs(delta).ravel(), 0.90),
            "delta_abs_p99": q(np.abs(delta).ravel(), 0.99),
        }
        row.update(summarize_vector("rolling_mean_abs", rolling_mean_abs))
        row.update(summarize_vector("rolling_std_rel", rolling_std_rel))
        row.update(summarize_vector("rolling_corr_abs", rolling_corr_abs))
        rows.append(row)

    df = pd.DataFrame(rows)
    out_csv = RES / f"{args.level}_structure_summary_eps{args.eps:g}.csv"
    df.to_csv(out_csv, index=False)

    print(f"records: {len(df)} -> {out_csv}")
    if len(df):
        print("\n--- damage reproducibility against exp2 ---")
        print(f"median D_record={df.D_record.median():.4f}")
        print(f"median D_exp2={df.D_exp2.median():.4f}")
        print(f"max |D_record-D_exp2|={df.D_abs_diff_vs_exp2.max():.3e}")

        print("\n--- whole-period moment audit ---")
        print(f"median basin max |mean shift|={df.whole_mean_abs_max.median():.3e}")
        print(f"max basin max |mean shift|={df.whole_mean_abs_max.max():.3e}")
        print(f"median basin max relative std shift={df.whole_std_rel_max.median():.3e}")
        print(f"max basin max relative std shift={df.whole_std_rel_max.max():.3e}")

        print("\n--- 270-day input-window structure ---")
        for col in [
                "rolling_mean_abs_p90",
                "rolling_mean_abs_p99",
                "rolling_mean_abs_max",
                "rolling_std_rel_p90",
                "rolling_std_rel_p99",
                "rolling_std_rel_max",
                "rolling_corr_abs_p90",
                "rolling_corr_abs_p99",
                "rolling_corr_abs_max",
        ]:
            print(f"{col}: median={df[col].median():.4f}  p90={df[col].quantile(0.90):.4f}")

        print("\n--- whole-period cross-variable structure ---")
        print(f"median basin max |corr change|={df.whole_corr_abs_max.median():.4f}")
        print(f"p90 basin max |corr change|={df.whole_corr_abs_max.quantile(0.90):.4f}")


if __name__ == "__main__":
    main()
