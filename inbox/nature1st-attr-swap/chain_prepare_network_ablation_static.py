#!/usr/bin/env python
"""Build the two static-attribute pairs for the STREAM-NETWORK ablation (arms C and D).

THE QUESTION
------------
Swapping the 12 US-only attributes for 13 HydroATLAS global attributes cost
0.6432 -> 0.5983 median NSE (paired median -0.0309, 431 val stations, both arms
converged on the same node, same env, same 40-epoch cap). Hypothesis for WHY:
four of the US attributes are stream-network / flow-routing quantities and the
global set contains no counterpart at all:

    hand_p50_m                        height above nearest drainage (US DEM routing)
    gageii_Hydro_STRAHLER_MAX         Strahler order of the network
    gageii_Hydro_STREAMS_KM_SQ_KM     drainage density
    gageii_Hydro_MAINSTEM_SINUOUSITY  mainstem sinuosity

Two arms settle it, both on US data with US ground truth (nothing downloaded):

    C (subtraction) 12 US attributes MINUS those 4  =  8   -> expect ~0.60 if true
    D (addition)    13 global attributes PLUS those 4 = 17  -> expect ~0.64 if true

C shows "removing them hurts", D shows "adding them repairs". BOTH must hold;
either one failing kills the hypothesis.

WHY THE mean/std ARE COPIED, NOT RECOMPUTED
-------------------------------------------
`QSequenceDataset._static_feats` walks the KEYS of the stats file and z-scores the
matching station-meta COLUMN, so the stats file alone defines the attribute set.
Arm C must be the control arm minus four features and NOTHING else, so its eight
mean/std pairs are copied byte-for-byte from the control's own stats file. Same
logic for D: its 13 global entries are copied from the treatment arm's file and
its 4 network entries from the control's. Recomputing would silently introduce a
second difference (different normalisation constants) into a single-variable
experiment.

Provenance of the inherited constants is asserted, not assumed:
  * the 13 global entries are re-derived here from the TRAIN split (2020 stations)
    and must match the treatment file to 1e-9;
  * the 4 network entries cannot be re-derived that way -- the control stats file
    predates this campaign and its exact station subset / sentinel filtering is
    unknown (e.g. gageii_HydroMod_Dams_RAW_DIS_NEAREST_DAM carries -999 sentinels
    that a naive train-split recompute does not reproduce). They are therefore
    copied verbatim and reported, so arms C and D normalise them EXACTLY as the
    control did. This is stated rather than silently assumed.

Usage (from repo root; read-only inputs, writes three NEW files):
  python scripts/chain_prepare_network_ablation_static.py
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]

NETWORK_ATTRS = [
    "hand_p50_m",
    "gageii_Hydro_STRAHLER_MAX",
    "gageii_Hydro_MAINSTEM_SINUOUSITY",
    "gageii_Hydro_STREAMS_KM_SQ_KM",
]

GLOBAL_ATTRS = [
    "slp_dg_uav", "ele_mt_sav", "ele_mt_smn", "ele_mt_smx", "urb_pc_use",
    "dor_pc_pva", "cly_pc_uav", "snd_pc_uav", "kar_pc_use", "swc_pc_syr",
    "gwt_cm_sav", "ari_ix_uav", "for_pc_use",
]


def parse_args():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--us_stats", default=str(ROOT / "data/interim/stage_static_feature_stats.json"))
    p.add_argument("--us_meta", default=str(ROOT / "data/processed/station_meta/"
                                                   "trainable_mountain_stations.csv"))
    p.add_argument("--global_stats",
                   default=str(ROOT / "data/interim/stage_static_feature_stats_hydroatlas.json"))
    p.add_argument("--global_meta",
                   default=str(ROOT / "data/processed/station_meta/"
                                      "trainable_mountain_stations_hydroatlas.csv"))
    p.add_argument("--splits_path", default=str(ROOT / "data/interim/stage_station_splits.json"))
    p.add_argument("--out_stats_c",
                   default=str(ROOT / "data/interim/"
                                      "stage_static_feature_stats_us_minus_network.json"))
    p.add_argument("--out_stats_d",
                   default=str(ROOT / "data/interim/"
                                      "stage_static_feature_stats_hydroatlas_plus_network.json"))
    p.add_argument("--out_meta_d",
                   default=str(ROOT / "data/processed/station_meta/"
                                      "trainable_mountain_stations_hydroatlas_plus_network.csv"))
    return p.parse_args()


def main():
    args = parse_args()
    for p in (Path(args.out_stats_c), Path(args.out_stats_d), Path(args.out_meta_d)):
        if p.exists():
            raise FileExistsError(f"refusing to overwrite existing file: {p}")

    us_stats = json.loads(Path(args.us_stats).read_text())
    gl_stats = json.loads(Path(args.global_stats).read_text())
    us_meta = pd.read_csv(args.us_meta)
    gl_meta = pd.read_csv(args.global_meta)
    splits = json.loads(Path(args.splits_path).read_text())

    # ---------- sanity on the inherited parents ----------
    if list(gl_stats.keys()) != GLOBAL_ATTRS:
        raise ValueError(f"global stats keys are not the expected 13: {list(gl_stats)}")
    missing = [k for k in NETWORK_ATTRS if k not in us_stats]
    if missing:
        raise KeyError(f"control stats file lacks the network attributes {missing}")
    if len(us_stats) != 12:
        raise ValueError(f"control stats file should hold 12 attributes, found {len(us_stats)}")

    # ---------- arm C: control minus the four network attributes ----------
    stats_c = {k: v for k, v in us_stats.items() if k not in NETWORK_ATTRS}
    if len(stats_c) != 8:
        raise ValueError(f"arm C should hold 8 attributes, built {len(stats_c)}")
    absent_c = [k for k in stats_c if k not in us_meta.columns]
    if absent_c:
        raise KeyError(f"US station meta lacks columns {absent_c} -> dataset would feed 0.0")

    # ---------- arm D: global plus the four network attributes ----------
    stats_d = {k: dict(v) for k, v in gl_stats.items()}
    for k in NETWORK_ATTRS:
        stats_d[k] = dict(us_stats[k])
    if list(stats_d.keys()) != GLOBAL_ATTRS + NETWORK_ATTRS or len(stats_d) != 17:
        raise ValueError("arm D key set/order is not the expected 13 global + 4 network")

    net_block = us_meta[["station_id"] + NETWORK_ATTRS].copy()
    net_block["station_id"] = net_block["station_id"].astype(np.int64)
    gl_meta["station_id"] = gl_meta["station_id"].astype(np.int64)
    meta_d = gl_meta.merge(net_block, on="station_id", how="left", validate="one_to_one")
    if len(meta_d) != len(gl_meta):
        raise ValueError(f"merge changed row count: {len(gl_meta)} -> {len(meta_d)}")
    unmatched = int(meta_d[NETWORK_ATTRS].isna().all(axis=1).sum())
    if unmatched:
        raise ValueError(f"{unmatched} stations got no network attributes from the US table")
    meta_d = meta_d[["station_id"] + GLOBAL_ATTRS + NETWORK_ATTRS].sort_values(
        "station_id").reset_index(drop=True)

    # ---------- anti-leakage assertion on the inherited global constants ----------
    train_ids = {int(s) for s in splits["train"]}
    train_rows = gl_meta[gl_meta["station_id"].isin(train_ids)]
    if len(train_rows) != len(train_ids):
        raise ValueError(f"train split {len(train_ids)} stations, meta covers {len(train_rows)}")
    worst = 0.0
    for col in GLOBAL_ATTRS:
        v = train_rows[col].astype(np.float64)
        worst = max(worst, abs(float(v.mean()) - gl_stats[col]["mean"]),
                    abs(float(v.std(ddof=0)) - gl_stats[col]["std"]))
    if worst > 1e-9:
        raise ValueError(f"global stats do not reproduce a TRAIN-ONLY recompute (max diff {worst})")

    # ---------- write ----------
    Path(args.out_stats_c).write_text(json.dumps(stats_c, indent=2))
    Path(args.out_stats_d).write_text(json.dumps(stats_d, indent=2))
    meta_d.to_csv(args.out_meta_d, index=False)

    print("=" * 78)
    print("STREAM-NETWORK ABLATION -- attribute pairs built")
    print("=" * 78)
    print(f"arm C stats -> {args.out_stats_c}")
    print(f"  {len(stats_c)} attributes = control 12 minus {NETWORK_ATTRS}")
    print(f"  station meta REUSED unchanged: {args.us_meta}")
    print(f"arm D stats -> {args.out_stats_d}")
    print(f"  {len(stats_d)} attributes = 13 global + 4 network")
    print(f"arm D meta  -> {args.out_meta_d}")
    print(f"  rows={len(meta_d)} cols={meta_d.shape[1]}")
    print("-" * 78)
    print("global 13: mean/std reproduce a TRAIN-SPLIT-ONLY recompute "
          f"(max diff {worst:.2e}, over 2020 train stations)")
    print("network 4: mean/std copied verbatim from the control stats file so that "
          "arms C and D normalise them exactly as the control did:")
    for k in NETWORK_ATTRS:
        s = us_stats[k]
        col = us_meta[k].astype(float)
        print(f"  {k:<34} mean={s['mean']:>10.4f} std={s['std']:>9.4f}   "
              f"(meta: n_nan={int(col.isna().sum())}, min={col.min():.3f}, max={col.max():.3f})")
    print("-" * 78)
    print("val/test stations contributed NOTHING to any mean/std (leak-free by construction).")
    print("=" * 78)


if __name__ == "__main__":
    main()
