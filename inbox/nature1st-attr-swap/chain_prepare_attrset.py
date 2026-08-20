#!/usr/bin/env python
"""Build a static-attribute pair (stats json + station meta) for ANY attribute subset.

WHY GENERIC
-----------
The attribute-source campaign now runs one experiment per attribute block, and each
block needs the same two files: a stats json whose KEYS define the feature set, and
a station-meta table holding those columns (`QSequenceDataset._static_feats` walks
the stats keys and z-scores the matching meta column). Hand-writing a script per
block invites drift; this one takes the block as an argument.

NORMALISATION CONSTANTS ARE INHERITED, NEVER RECOMPUTED
-------------------------------------------------------
Every attribute's mean/std is copied from the arm that first used it:
  * the 12 US attributes  -> data/interim/stage_static_feature_stats.json (control)
  * the 13 HydroATLAS ones -> data/interim/stage_static_feature_stats_hydroatlas.json
Copying keeps each new arm on exactly the same scaling as the arm it is compared
against, so the attribute SET stays the single variable. Recomputing would smuggle
a second difference into the experiment. (The control's constants also encode
sentinel handling this repo cannot reproduce from the table alone -- e.g.
gageii_HydroMod_Dams_RAW_DIS_NEAREST_DAM carries -999 rows.)

Anti-leakage is inherited with them: both parent files were fitted on the TRAIN
split only, and the global one is re-verified against a train-only recompute here.

Usage
-----
  python scripts/chain_prepare_attrset.py --name armE \
      --attrs gageii_Topo_SLOPE_PCT,gageii_LC06_Basin_DEVNLCD06,gageii_Hydro_PERDUN,gageii_Topo_RRMEAN

Writes data/interim/stage_static_feature_stats_<name>.json, plus
data/processed/station_meta/trainable_mountain_stations_<name>.csv when the block
mixes sources (a pure-US block reuses the untouched US table).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]

US_STATS = ROOT / "data/interim/stage_static_feature_stats.json"
US_META = ROOT / "data/processed/station_meta/trainable_mountain_stations.csv"
GL_STATS = ROOT / "data/interim/stage_static_feature_stats_hydroatlas.json"
GL_META = ROOT / "data/processed/station_meta/trainable_mountain_stations_hydroatlas.csv"
SPLITS = ROOT / "data/interim/stage_station_splits.json"


def parse_args():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--name", required=True, help="short arm name, used in the output filenames")
    p.add_argument("--attrs", required=True, help="comma-separated attribute list, in feed order")
    p.add_argument("--out_dir_stats", default=str(ROOT / "data/interim"))
    p.add_argument("--out_dir_meta", default=str(ROOT / "data/processed/station_meta"))
    return p.parse_args()


def main():
    args = parse_args()
    attrs = [a.strip() for a in args.attrs.split(",") if a.strip()]
    if len(set(attrs)) != len(attrs):
        raise ValueError("duplicate attribute in --attrs")

    us_stats = json.loads(US_STATS.read_text())
    gl_stats = json.loads(GL_STATS.read_text())
    us_meta = pd.read_csv(US_META)
    gl_meta = pd.read_csv(GL_META)
    splits = json.loads(SPLITS.read_text())

    out_stats = Path(args.out_dir_stats) / f"stage_static_feature_stats_{args.name}.json"
    out_meta = Path(args.out_dir_meta) / f"trainable_mountain_stations_{args.name}.csv"
    for p in (out_stats, out_meta):
        if p.exists():
            raise FileExistsError(f"refusing to overwrite existing file: {p}")

    # ---------- resolve every attribute to a source ----------
    stats, source = {}, {}
    for a in attrs:
        in_us, in_gl = a in us_stats, a in gl_stats
        if in_us and in_gl:
            raise ValueError(f"{a} exists in both parent stats files -- ambiguous source")
        if in_us:
            stats[a], source[a] = dict(us_stats[a]), "US"
        elif in_gl:
            stats[a], source[a] = dict(gl_stats[a]), "global"
        else:
            raise KeyError(f"{a} is in neither parent stats file; no inherited mean/std exists")

    us_used = [a for a in attrs if source[a] == "US"]
    gl_used = [a for a in attrs if source[a] == "global"]

    # ---------- anti-leakage re-verification for the global constants ----------
    train_ids = {int(s) for s in splits["train"]}
    worst = 0.0
    if gl_used:
        tr = gl_meta[gl_meta["station_id"].astype(np.int64).isin(train_ids)]
        if len(tr) != len(train_ids):
            raise ValueError(f"train split {len(train_ids)} stations, global meta covers {len(tr)}")
        for a in gl_used:
            v = tr[a].astype(np.float64)
            worst = max(worst, abs(float(v.mean()) - stats[a]["mean"]),
                        abs(float(v.std(ddof=0)) - stats[a]["std"]))
        if worst > 1e-9:
            raise ValueError(f"global constants fail a TRAIN-ONLY recompute (max diff {worst})")

    # ---------- station meta ----------
    if not gl_used:
        missing = [a for a in attrs if a not in us_meta.columns]
        if missing:
            raise KeyError(f"US station meta lacks {missing}")
        meta_path, meta_note = US_META, "reused unchanged (pure US block)"
        n_rows, n_cols = len(us_meta), us_meta.shape[1]
    else:
        us_block = us_meta[["station_id"] + us_used].copy() if us_used else us_meta[["station_id"]].copy()
        us_block["station_id"] = us_block["station_id"].astype(np.int64)
        gl_meta["station_id"] = gl_meta["station_id"].astype(np.int64)
        merged = gl_meta.merge(us_block, on="station_id", how="left", validate="one_to_one")
        if len(merged) != len(gl_meta):
            raise ValueError(f"merge changed row count: {len(gl_meta)} -> {len(merged)}")
        missing = [a for a in attrs if a not in merged.columns]
        if missing:
            raise KeyError(f"merged meta lacks {missing}")
        if us_used and int(merged[us_used].isna().all(axis=1).sum()):
            raise ValueError("some stations matched no row in the US table")
        merged = merged[["station_id"] + attrs].sort_values("station_id").reset_index(drop=True)
        merged.to_csv(out_meta, index=False)
        meta_path, meta_note = out_meta, "newly built (mixed-source block)"
        n_rows, n_cols = len(merged), merged.shape[1]

    out_stats.write_text(json.dumps(stats, indent=2))

    print("=" * 78)
    print(f"ATTRIBUTE SET '{args.name}' -- {len(attrs)} attributes")
    print("=" * 78)
    print(f"stats -> {out_stats}")
    print(f"meta  -> {meta_path}   [{meta_note}]  rows={n_rows} cols={n_cols}")
    print(f"sources: {len(us_used)} US, {len(gl_used)} global")
    if gl_used:
        print(f"global constants reproduce a TRAIN-ONLY recompute (max diff {worst:.2e})")
    print("-" * 78)
    for a in attrs:
        s = stats[a]
        print(f"  {a:<44} [{source[a]:>6}]  mean={s['mean']:>12.4f}  std={s['std']:>11.4f}")
    print("-" * 78)
    print("mean/std inherited from the parent arms; val/test stations contributed nothing.")
    print("=" * 78)


if __name__ == "__main__":
    main()
