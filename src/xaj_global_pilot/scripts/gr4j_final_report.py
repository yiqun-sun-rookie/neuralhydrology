"""Full-531 final report for the GR4J playbook run.

GR4J(+PDD) 分布 + 气候 regime 分解 + 与 XAJ-PDD / HBV-lite / 文献基准在 *同 531
basin* 上并排对比 + 逐 basin head-to-head。所有对比对象用同一 repro_v01 协议。

Usage::

    python -X utf8 -m src.xaj_global_pilot.scripts.gr4j_final_report gr4j_pdd_cma_FINAL_pt_v1
"""
from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd

_ROOT = Path("results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01")


def _series(path: Path, col="nse", idx="basin_id"):
    if not path.exists():
        return None
    df = pd.read_csv(path, dtype={idx: str}, keep_default_na=False)
    df[idx] = df[idx].str.zfill(8)
    return pd.to_numeric(df.set_index(idx)[col], errors="coerce")


def _dist(s):
    x = s.dropna()
    return dict(median=x.median(), mean=x.mean(), p5=x.quantile(.05),
               p25=x.quantile(.25), p75=x.quantile(.75), p95=x.quantile(.95),
               n=len(x), neg=int((x < 0).sum()), neg1=int((x < -1).sum()))


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("subdir")
    args = p.parse_args(argv)

    gr4j = _series(_ROOT / "summary" / f"{args.subdir}_local_full.csv")
    if gr4j is None:
        raise SystemExit(f"GR4J summary not found for {args.subdir!r}")

    # SAME-PET single-variant comparison is the clean headline. HBV-PT v7 uses
    # PT + tight bounds + init=0.5 (identical knobs to GR4J) — the fair HBV peer.
    # Oudin variants and the 9-way mixed-PET ensemble are kept only as references.
    candidates = {
        "GR4J+PDD playbook (THIS)": (_ROOT / "summary" / f"{args.subdir}_local_full.csv", "nse"),
        "XAJ-PDD (PT, same-PET single)": (_ROOT / "summary" / "xaj_pdd_cma_PT_v1_warmup_local_full.csv", "nse"),
        "HBV-PT (v7, same-PET+init single)": (_ROOT.parent / "camels_us_531_repro_v01_v7_PT_tight" / "summary" / "hbv_lite_cma_local_full.csv", "nse"),
        "XAJ-PDD (Oudin, non-std ref)": (_ROOT / "summary" / "xaj_pdd_cma_FINAL_oudin_warmup_local_full.csv", "nse"),
        "HBV-lite v1 (Oudin ref)": (_ROOT / "summary" / "hbv_lite_cma_local_full.csv", "nse"),
        "HBV 9-way ens (mixed-PET 9x ref)": (_ROOT.parent / "camels_us_531_repro_v01_FINAL_MEGA" / "summary" / "mega_ensemble.csv", "ens_cal_best"),
    }
    refs = {}
    for name, (path, col) in candidates.items():
        s = _series(path, col)
        if s is not None:
            refs[name] = s

    # 文献基准 + regime
    regime = None
    cm_path = _ROOT / "diagnostic" / "cross_method_per_basin_nse.csv"
    if cm_path.exists():
        cm = pd.read_csv(cm_path, dtype={"basin_id": str})
        cm["basin_id"] = cm["basin_id"].str.zfill(8)
        for model in ["SAC-SMA + Snow-17", "VIC (basin-cal)", "mHM (basin-cal)", "HBV (upper)", "FUSE-902"]:
            sub = cm[cm["model"] == model].set_index("basin_id")["nse"]
            if len(sub):
                refs[f"lit: {model}"] = pd.to_numeric(sub, errors="coerce")
        rsub = cm[cm["model"] == "XAJ-PDD (ours)"].drop_duplicates("basin_id")
        if len(rsub):
            regime = rsub.set_index("basin_id")["regime"]

    print("=" * 100)
    print(f"FULL-531 FINAL REPORT  —  GR4J  {args.subdir}")
    print("=" * 100)
    print(f"{'series':<30}{'median':>9}{'mean':>9}{'p5':>8}{'p25':>8}{'p75':>8}{'p95':>8}{'n':>5}{'<0':>5}{'<-1':>5}")
    print("-" * 100)
    for name, s in refs.items():
        d = _dist(s)
        print(f"{name:<30}{d['median']:>9.4f}{d['mean']:>9.4f}{d['p5']:>8.2f}"
              f"{d['p25']:>8.3f}{d['p75']:>8.3f}{d['p95']:>8.3f}{d['n']:>5}{d['neg']:>5}{d['neg1']:>5}")

    if regime is not None:
        print("-" * 100)
        print("GR4J by climate regime (this run):")
        for rg in ["humid", "snow-dominated", "semi-humid", "semi-arid/arid"]:
            ids = [b for b in gr4j.index if regime.get(b) == rg]
            x = gr4j.reindex(ids).dropna()
            if len(x):
                print(f"  {rg:<16} median={x.median():.4f}  mean={x.mean():.4f}  n={len(x)}")

    # head-to-head
    print("-" * 100)
    for opp_name in ["XAJ-PDD (PT, same-PET single)", "HBV-PT (v7, same-PET+init single)",
                     "HBV 9-way ens (mixed-PET 9x ref)"]:
        if opp_name in refs:
            opp = refs[opp_name]
            common = gr4j.dropna().index.intersection(opp.dropna().index)
            d = (gr4j.reindex(common) - opp.reindex(common)).dropna()
            if len(d):
                print(f"GR4J - {opp_name:<26} (n={len(d)}): median Δ={d.median():+.4f}, "
                      f"GR4J wins {(d>0).sum()}/{len(d)} ({100*(d>0).mean():.0f}%)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
