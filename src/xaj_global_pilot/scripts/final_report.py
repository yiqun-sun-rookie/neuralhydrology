"""Full-531 final report for the XAJ playbook run.

Loads a variant's 531 summary, computes the distribution, breaks it down by
climate regime, and lays it beside the published CAMELS-US conceptual-model
benchmarks + HBV-lite playbook results on the SAME 531 basins.

Usage::

    python -X utf8 -m src.xaj_global_pilot.scripts.final_report xaj_pdd_cma_FINAL_oudin_warmup
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

_ROOT = Path("results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01")


def _series(path: Path, col="nse", idx="basin_id") -> pd.Series:
    df = pd.read_csv(path, dtype={idx: str}, keep_default_na=False)
    df[idx] = df[idx].str.zfill(8)
    return pd.to_numeric(df.set_index(idx)[col], errors="coerce")


def _dist(s: pd.Series) -> dict:
    x = s.dropna()
    return dict(median=x.median(), mean=x.mean(),
               p5=x.quantile(.05), p25=x.quantile(.25),
               p75=x.quantile(.75), p95=x.quantile(.95),
               n=len(x), neg=(x < 0).sum(), neg1=(x < -1).sum())


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("subdir")
    args = p.parse_args(argv)

    xaj = _series(_ROOT / "summary" / f"{args.subdir}_local_full.csv")

    refs = {
        "XAJ-PDD playbook (THIS)": xaj,
        "XAJ-PDD orig (PET-bug)": _series(_ROOT / "summary" / "xaj_pdd_local_full.csv"),
        "HBV-lite v1 single": _series(_ROOT / "summary" / "hbv_lite_cma_local_full.csv"),
        "HBV-lite ens_cal_best": _series(_ROOT.parent / "camels_us_531_repro_v01_FINAL_MEGA" / "summary" / "mega_ensemble.csv", "ens_cal_best"),
        "HBV-lite ens+warmup": _series(_ROOT.parent / "camels_us_531_repro_v01_FINAL_MEGA_warmup" / "summary" / "mega_ensemble_warmup_R2fix.csv", "ens_cal_best"),
    }
    # published benchmarks from the cross-method diagnostic
    cm = pd.read_csv(_ROOT / "diagnostic" / "cross_method_per_basin_nse.csv", dtype={"basin_id": str})
    cm["basin_id"] = cm["basin_id"].str.zfill(8)
    for model in ["SAC-SMA + Snow-17", "VIC (basin-cal)", "mHM (basin-cal)", "HBV (upper)", "FUSE-902"]:
        sub = cm[cm["model"] == model].set_index("basin_id")["nse"]
        refs[f"lit: {model}"] = pd.to_numeric(sub, errors="coerce")
    regime = cm[cm["model"] == "XAJ-PDD (ours)"].drop_duplicates("basin_id").set_index("basin_id")["regime"]

    print("=" * 96)
    print(f"FULL-531 FINAL REPORT  —  {args.subdir}")
    print("=" * 96)
    print(f"{'series':<28}{'median':>9}{'mean':>9}{'p5':>8}{'p25':>8}{'p75':>8}{'p95':>8}{'n':>5}{'<0':>5}{'<-1':>5}")
    print("-" * 96)
    for name, s in refs.items():
        d = _dist(s)
        print(f"{name:<28}{d['median']:>9.4f}{d['mean']:>9.4f}{d['p5']:>8.2f}"
              f"{d['p25']:>8.3f}{d['p75']:>8.3f}{d['p95']:>8.3f}{d['n']:>5}{d['neg']:>5}{d['neg1']:>5}")

    print("-" * 96)
    print("XAJ-PDD playbook by regime (this run):")
    for rg in ["humid", "snow-dominated", "semi-humid", "semi-arid/arid"]:
        ids = [b for b in xaj.index if regime.get(b) == rg]
        x = xaj.reindex(ids).dropna()
        if len(x):
            print(f"  {rg:<16} median={x.median():.4f}  mean={x.mean():.4f}  n={len(x)}")

    # head-to-head vs HBV ens on common basins
    hbv = refs["HBV-lite ens_cal_best"]
    common = xaj.dropna().index.intersection(hbv.dropna().index)
    d = (xaj.reindex(common) - hbv.reindex(common)).dropna()
    print("-" * 96)
    print(f"XAJ playbook - HBV ens_cal_best (per-basin, n={len(d)}): "
          f"median delta={d.median():+.4f}, XAJ wins {(d>0).sum()}/{len(d)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
