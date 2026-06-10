"""Measurement instrument for the XAJ playbook iteration loop.

Given one or more per-basin result subdirs under the repro_v01 results root,
report (a) each variant's median eval NSE on the iteration subset, (b) the
``ens_cal_best`` ensemble median if multiple variants are given (per-basin pick
the variant with the highest ``_cal_nse``, report its eval ``nse`` — the SAME
rule HBV's mega-ensemble uses), and (c) a fixed comparison against the HBV and
XAJ baselines on the identical subset.

Usage::

    python -X utf8 -m src.xaj_global_pilot.scripts.playbook_eval \\
        iter1_pt_calfinal iter2_pt_warmup [...] \\
        --subset src/xaj_global_pilot/configs/xaj_playbook_iter_subset_40.txt
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

_ROOT = Path("results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01")


def _per_basin(path: Path, col: str = "nse", idx: str = "basin_id") -> pd.Series:
    df = pd.read_csv(path, dtype={idx: str}, keep_default_na=False)
    df[idx] = df[idx].str.zfill(8)
    return pd.to_numeric(df.set_index(idx)[col], errors="coerce")


def _load_variant(subdir: str, subset: list[str]) -> pd.DataFrame:
    """Load per-basin nse + _cal_nse for a variant, restricted to subset."""
    vdir = _ROOT / subdir
    rows = []
    for b in subset:
        f = vdir / f"{b}.csv"
        if not f.exists():
            continue
        r = pd.read_csv(f, dtype={"basin_id": str}, keep_default_na=False).iloc[0]
        rows.append({
            "basin_id": str(r["basin_id"]).zfill(8),
            "nse": pd.to_numeric(r.get("nse"), errors="coerce"),
            "cal_nse": pd.to_numeric(r.get("_cal_nse"), errors="coerce"),
        })
    return pd.DataFrame(rows).set_index("basin_id")


def _baselines(subset: list[str]) -> dict[str, pd.Series]:
    cm = pd.read_csv(_ROOT / "diagnostic" / "cross_method_per_basin_nse.csv", dtype={"basin_id": str})
    cm["basin_id"] = cm["basin_id"].str.zfill(8)
    out = {
        "XAJ-PDD orig (0.4458)": _per_basin(_ROOT / "summary" / "xaj_pdd_local_full.csv"),
        "HBV v1 single (0.5564)": _per_basin(_ROOT / "summary" / "hbv_lite_cma_local_full.csv"),
        "HBV ens_cal_best (0.6227)": _per_basin(
            _ROOT.parent / "camels_us_531_repro_v01_FINAL_MEGA" / "summary" / "mega_ensemble.csv", "ens_cal_best"),
        "HBV ens+warmup (0.6276)": _per_basin(
            _ROOT.parent / "camels_us_531_repro_v01_FINAL_MEGA_warmup" / "summary" / "mega_ensemble_warmup_R2fix.csv",
            "ens_cal_best"),
    }
    return {k: v.reindex(subset) for k, v in out.items()}


def _fmt(s: pd.Series) -> str:
    x = s.dropna()
    if x.empty:
        return "n=0"
    return (f"med={x.median():.4f} mean={x.mean():.4f} "
            f"p25={x.quantile(.25):.3f} p75={x.quantile(.75):.3f} "
            f"<0:{(x<0).sum()} <-1:{(x<-1).sum()} n={len(x)}")


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("subdirs", nargs="+", help="variant output subdirs under repro_v01 root")
    p.add_argument("--subset", default="src/xaj_global_pilot/configs/xaj_playbook_iter_subset_40.txt")
    p.add_argument("--regime", action="store_true", help="break down by climate regime")
    args = p.parse_args(argv)

    subset = [l.strip().zfill(8) for l in Path(args.subset).read_text().splitlines() if l.strip()]

    print("=" * 78)
    print(f"SUBSET: {len(subset)} basins  ({args.subset})")
    print("=" * 78)
    print("BASELINES (same subset):")
    for name, s in _baselines(subset).items():
        print(f"  {name:<28} {_fmt(s)}")

    print("-" * 78)
    print("VARIANTS:")
    variants = {}
    for sd in args.subdirs:
        v = _load_variant(sd, subset)
        variants[sd] = v
        if v.empty:
            print(f"  {sd:<28} (no per-basin csvs found)")
            continue
        print(f"  {sd:<28} {_fmt(v['nse'])}")

    # ens_cal_best across the given variants
    valid = {k: v for k, v in variants.items() if not v.empty}
    if len(valid) >= 2:
        # build basin x variant matrices for eval nse and cal nse
        names = list(valid)
        eval_m = pd.DataFrame({k: valid[k]["nse"] for k in names})
        cal_m = pd.DataFrame({k: valid[k]["cal_nse"] for k in names})
        common = eval_m.dropna(how="all").index
        eval_m, cal_m = eval_m.loc[common], cal_m.loc[common]
        best_cal = cal_m.idxmax(axis=1)
        ens = pd.Series({b: eval_m.loc[b, best_cal[b]] for b in common if pd.notna(best_cal[b])})
        print("-" * 78)
        print(f"ENS_CAL_BEST ({len(names)} variants): {_fmt(ens)}")

    if args.regime:
        cm = pd.read_csv(_ROOT / "diagnostic" / "cross_method_per_basin_nse.csv", dtype={"basin_id": str})
        cm["basin_id"] = cm["basin_id"].str.zfill(8)
        reg = cm[cm["model"] == "XAJ-PDD (ours)"].drop_duplicates("basin_id").set_index("basin_id")["regime"]
        print("-" * 78)
        print("BY REGIME (last variant):")
        last = variants[args.subdirs[-1]]
        for rg in ["humid", "snow-dominated", "semi-humid", "semi-arid/arid"]:
            ids = [b for b in last.index if reg.get(b) == rg]
            if ids:
                print(f"  {rg:<16} {_fmt(last.loc[ids, 'nse'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
