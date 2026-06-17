"""Compare a trained LSTM (nh test_metrics.csv) against the frozen three-school
conceptual models (GR4J/XAJ/HBV) on CAMELS-US 531, plus 447-subset literature
positioning vs Kratzert 2019 and the published benchmarks.

Usage:
  python -X utf8 -m src.lstm_fair_531.scripts.compare_lstm_vs_conceptual \
    --lstm-metrics results/18_lstm_fair_531/<run>/test/model_epoch030/test_metrics.csv \
    --label cudalstm_s100

Fairness note (audited): NSE is per-basin scale-invariant and every model is scored
against the same USGS cfs series, so native NSEs are directly comparable — no obs unification.
"""
import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

REPRO = Path("results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01")
DIAG = REPRO / "diagnostic" / "cross_method_per_basin_nse.csv"
COMMON_447 = REPRO / "diagnostic" / "common_447_basins.txt"

# Kratzert 2019 HESS Table 3 (447-basin medians)
KRATZERT = {"EA-LSTM ens": 0.742, "LSTM+static ens": 0.758,
            "SAC-SMA + Snow-17": 0.603, "mHM (basin-cal)": 0.666, "HBV (upper)": 0.676}

CONCEPTUAL = {
    "GR4J": "summary/gr4j_pdd_cma_FINAL_pt_v1_local_full.csv",
    "XAJ": "summary/xaj_pdd_cma_FINAL_pt_v1_5k3_local_full.csv",
    "HBV": "summary/hbv_lite_cma_FINAL_pt_v1_warmup_local_full.csv",
}


def _bid(s):
    return s.astype(str).str.replace(r"\.0$", "", regex=True).str.zfill(8)


def load_conceptual():
    out = {}
    for name, rel in CONCEPTUAL.items():
        p = REPRO / rel
        if not p.exists():
            cands = list((REPRO / "summary").glob(f"*{rel.split('/')[-1].split('_FINAL')[0].split('summary/')[-1]}*"))
            raise FileNotFoundError(f"{name}: {p} not found (candidates: {cands})")
        df = pd.read_csv(p, dtype={"basin_id": str})
        if "period" in df.columns:
            df = df[df.period == "evaluation"]
        df["basin_id"] = _bid(df["basin_id"])
        out[name] = df.set_index("basin_id")["nse"]
    return out


def load_lstm(path):
    df = pd.read_csv(path)
    bcol = "basin" if "basin" in df.columns else df.columns[0]
    df["basin_id"] = _bid(df[bcol])
    ncol = [c for c in df.columns if c.upper() == "NSE"][0]
    return df.set_index("basin_id")[ncol].astype(float)


def boot_median_diff(a, b, n=10000, seed=0):
    rng = np.random.default_rng(seed)
    d = (a - b).values
    idx = rng.integers(0, len(d), size=(n, len(d)))
    meds = np.median(d[idx], axis=1)
    return float(np.percentile(meds, 2.5)), float(np.percentile(meds, 97.5))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lstm-metrics", required=True)
    ap.add_argument("--label", default="lstm")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    try:
        from scipy.stats import wilcoxon
    except Exception:
        wilcoxon = None

    lstm = load_lstm(args.lstm_metrics)
    concept = load_conceptual()
    diag = pd.read_csv(DIAG, dtype={"basin_id": str})
    diag["basin_id"] = _bid(diag["basin_id"])
    regime = diag.drop_duplicates("basin_id").set_index("basin_id")["regime"]
    common447 = set(COMMON_447.read_text().split())

    report = {"label": args.label, "lstm_metrics": args.lstm_metrics, "n_lstm_basins": int(lstm.notna().sum())}

    # ---- full-531 head-to-head ----
    full = {"lstm_median": float(np.nanmedian(lstm)), "lstm_mean": float(np.nanmean(lstm)),
            "lstm_n": int(lstm.notna().sum()), "vs": {}}
    for name, c in concept.items():
        common = lstm.dropna().index.intersection(c.dropna().index)
        a, b = lstm.loc[common], c.loc[common]
        d = a - b
        row = {"n_common": len(common), "concept_median": float(np.median(b)),
               "lstm_median": float(np.median(a)), "median_diff": float(np.median(d)),
               "lstm_win_rate": float((d > 0).mean())}
        if wilcoxon is not None and len(common) > 10:
            try:
                row["wilcoxon_p"] = float(wilcoxon(a, b).pvalue)
            except Exception as e:
                row["wilcoxon_p"] = f"err:{e}"
        lo, hi = boot_median_diff(a, b)
        row["median_diff_CI95"] = [lo, hi]
        full["vs"][name] = row
    report["full_531"] = full

    # ---- per-regime (LSTM vs GR4J) ----
    reg = {}
    gr4j = concept["GR4J"]
    common = lstm.dropna().index.intersection(gr4j.dropna().index)
    rr = pd.DataFrame({"lstm": lstm.loc[common], "gr4j": gr4j.loc[common],
                       "regime": regime.reindex(common)})
    for rname, g in rr.groupby("regime"):
        reg[rname] = {"n": len(g), "lstm_median": float(g.lstm.median()),
                      "gr4j_median": float(g.gr4j.median())}
    report["per_regime_lstm_vs_gr4j"] = reg

    # ---- 447 literature positioning + reproduction gate ----
    s447 = sorted(common447)
    lstm447 = lstm.reindex(s447).dropna()
    sub = {"n": len(lstm447), "lstm_median": float(lstm447.median()), "lstm_mean": float(lstm447.mean()),
           "ours_conceptual": {}, "published_targets": KRATZERT}
    for name, c in concept.items():
        v = c.reindex(s447).dropna()
        sub["ours_conceptual"][name] = {"median": float(v.median()), "n": len(v)}
    # gate vs single-seed Kratzert ~0.731 (cudalstm+static single) / ~0.714 (ealstm single)
    sub["repro_gate_note"] = ("single-seed cudalstm+static target ~0.731, ensemble ~0.758; "
                              "ealstm single ~0.714, ensemble ~0.742 (Kratzert 2019 Table 3, 447)")
    report["subset_447"] = sub

    out = args.out or f"results/18_lstm_fair_531/_reports/compare_{args.label}.json"
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    Path(out).write_text(json.dumps(report, indent=2))

    # pretty print
    print(f"\n=== {args.label} :: full-531 ===")
    print(f"LSTM median={full['lstm_median']:.4f} mean={full['lstm_mean']:.4f} (n={full['lstm_n']})")
    for name, r in full["vs"].items():
        p = r.get("wilcoxon_p", "NA")
        ps = f"{p:.2e}" if isinstance(p, float) else p
        print(f"  vs {name:5s}: concept_med={r['concept_median']:.4f}  Δmed={r['median_diff']:+.4f} "
              f"CI95={r['median_diff_CI95'][0]:+.4f}/{r['median_diff_CI95'][1]:+.4f}  "
              f"LSTM win={r['lstm_win_rate']*100:.1f}%  p={ps}  (n={r['n_common']})")
    print(f"\n=== 447 subset (n={sub['n']}) ===")
    print(f"LSTM median={sub['lstm_median']:.4f} mean={sub['lstm_mean']:.4f}")
    print(f"  Kratzert targets: EA-LSTM ens 0.742 / LSTM+static ens 0.758 / single ~0.714-0.731")
    print(f"  ours conceptual @447: " + ", ".join(f"{k}={v['median']:.4f}" for k, v in sub["ours_conceptual"].items()))
    print(f"\n=== per-regime (LSTM vs GR4J) ===")
    for rn, g in reg.items():
        print(f"  {rn:16s} n={g['n']:3d}  LSTM={g['lstm_median']:.3f}  GR4J={g['gr4j_median']:.3f}")
    print(f"\nwrote {out}")


if __name__ == "__main__":
    main()
