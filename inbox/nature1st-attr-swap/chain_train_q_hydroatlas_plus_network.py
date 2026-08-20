#!/usr/bin/env python
"""ARM D (addition, decisive): the 13 global attributes PLUS the 4 stream-network ones.

THE QUESTION
------------
Replacing the 12 US-only attributes with 13 HydroATLAS global attributes cost
0.6432 -> 0.5983 median NSE (paired median -0.0309 over 431 val stations; both
arms on node ngu008, same env, 40-epoch cap, both early-stopped on their own).
The leading hypothesis is that the loss comes from four stream-network /
flow-routing attributes that the global set has no counterpart for.

This arm hands those four BACK to the global set. If the hypothesis holds the
score should climb back to roughly the control level (~0.64). If it stays near
0.5983, the four do not repair the gap and the hypothesis is dead regardless of
what arm C shows -- which is why this arm is the decisive one.

  control  models/q_lstm_control_hpc_s42        12 US attributes      0.6432
  global   models/q_lstm_hydroatlas_hpc_s42     13 global             0.5983
  THIS     models/q_lstm_globalplus4_hpc_s42    13 global + 4 network   ?

PRE-REGISTERED READING (fix before seeing the number)
-----------------------------------------------------
Judged on the paired 431-station comparison against the GLOBAL arm:
  paired median >= +0.020  -> the four network attributes repair the gap
  paired median <= +0.010  -> they do not; the hypothesis is dead
  in between               -> undecided, do NOT rescue it with extra seeds without
                              fresh authorisation
Note this arm carries 17 attributes against the control's 12, so a win here is not
by itself evidence about attribute COUNT; the count confound is what arm C
(subtraction, same source) is there to break.

CAVEAT WORTH STATING
--------------------
The four network attributes are US products (GAGES-II network statistics and a US
DEM HAND layer). A win here diagnoses WHAT information is missing from the global
set; it does not by itself supply that information for China. Producing global
equivalents (e.g. from HydroSHEDS / MERIT Hydro) would be the follow-up, and is
NOT part of this run.

HOW THE SWAP IS DONE (no edits to the formal pipeline)
-----------------------------------------------------
`chain_train_q_v1.build_loader` builds `QDatasetConfig` from its module globals and
never exposes static_path / station_meta_path as flags, so both files are
redirected by rebinding that name in the imported module. Everything else is the
formal pipeline run verbatim through `base.main()`.

Usage (from repo root):
  python scripts/chain_train_q_hydroatlas_plus_network.py \
      --output_dir models/q_lstm_globalplus4_hpc_s42 --seed 42 --epochs 40
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import chain_train_q_v1 as base  # noqa: E402  (formal pipeline, imported verbatim)
from src.q_dataset_v1 import QDatasetConfig  # noqa: E402

STATIC_PATH = ROOT / "data/interim/stage_static_feature_stats_hydroatlas_plus_network.json"
META_PATH = (ROOT / "data/processed/station_meta/"
                    "trainable_mountain_stations_hydroatlas_plus_network.csv")

GLOBAL_ATTRS = [
    "slp_dg_uav", "ele_mt_sav", "ele_mt_smn", "ele_mt_smx", "urb_pc_use",
    "dor_pc_pva", "cly_pc_uav", "snd_pc_uav", "kar_pc_use", "swc_pc_syr",
    "gwt_cm_sav", "ari_ix_uav", "for_pc_use",
]

NETWORK_ATTRS = [
    "hand_p50_m",
    "gageii_Hydro_STRAHLER_MAX",
    "gageii_Hydro_MAINSTEM_SINUOUSITY",
    "gageii_Hydro_STREAMS_KM_SQ_KM",
]

EXPECTED_ATTRS = GLOBAL_ATTRS + NETWORK_ATTRS

CONTROL_MEDIAN_NSE = 0.6432   # models/q_lstm_control_hpc_s42, HPC re-run, seed 42
GLOBAL_MEDIAN_NSE = 0.5983    # models/q_lstm_hydroatlas_hpc_s42, same node/env

# Frozen method contract -- identical to both existing arms. Any change here makes
# this run incomparable to them.
FROZEN_ARGV = [
    "--window", "168", "--horizon", "1", "--stride", "24",
    "--daily_days", "365", "--max_hours", "43800",
    "--patience", "5", "--batch_size", "256", "--lr", "5e-4",
    "--lstm_hidden", "256", "--lstm_layers", "2",
    "--static_hidden", "64", "--mlp_hidden", "128", "--dropout", "0.2",
    "--initial_forget_bias", "5.0",
]

_orig_build_loader = base.build_loader


def _config_with_augmented_static(**kwargs):
    """QDatasetConfig with both attribute paths redirected. The only variable."""
    kwargs["static_path"] = STATIC_PATH
    kwargs["station_meta_path"] = META_PATH
    return QDatasetConfig(**kwargs)


def _guarded_build_loader(subset, args, **kwargs):
    """Fail closed on the two silent failure modes in src/q_dataset_v1.py.

    A missing stats file yields static_norm={} -> aux_dim 0 (a no-attribute model
    masquerading as this experiment); a stats key with no matching meta column is
    silently fed as 0.0 (a typo becomes a constant channel). Neither raises.
    """
    loader, ds = _orig_build_loader(subset, args, **kwargs)

    keys = list(ds.static_norm.keys())
    if keys != EXPECTED_ATTRS:
        raise RuntimeError(
            f"[{subset}] static attributes are not the augmented global set. got {keys}; "
            f"expected {EXPECTED_ATTRS}. (Empty list == stats file not found: {STATIC_PATH})")
    if ds.station_meta is None:
        raise RuntimeError(f"[{subset}] station meta not loaded: {META_PATH}")
    absent = [k for k in EXPECTED_ATTRS if k not in ds.station_meta.columns]
    if absent:
        raise RuntimeError(f"[{subset}] station meta lacks columns {absent} -> the dataset "
                           "would silently feed 0.0 for them")
    stray = [c for c in ds.station_meta.columns
             if (c.startswith("gageii_") or c == "hand_p50_m") and c not in NETWORK_ATTRS]
    if stray:
        raise RuntimeError(f"[{subset}] unexpected US columns in the meta table: {stray} -- "
                           "this arm adds the 4 network attributes and nothing else")

    aux_dim = int(ds[0]["aux"].shape[-1])
    if aux_dim != len(EXPECTED_ATTRS):
        raise RuntimeError(f"[{subset}] aux_dim={aux_dim}, expected {len(EXPECTED_ATTRS)}")
    print(f"  [guard] {subset}: {aux_dim} attributes (13 global + 4 network), "
          f"{len(ds.station_meta)} stations in meta -- augmentation verified")
    return loader, ds


base.QDatasetConfig = _config_with_augmented_static
base.build_loader = _guarded_build_loader


def parse_args():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--output_dir", default=str(ROOT / "models/q_lstm_globalplus4_hpc_s42"))
    p.add_argument("--seed", type=int, default=42, help="42 matches both existing arms.")
    p.add_argument("--epochs", type=int, default=40,
                   help="MUST equal the other arms' cap (40) or the comparison is void.")
    p.add_argument("--num_workers", type=int, default=4)
    p.add_argument("--device", default=None)
    return p.parse_args()


def main():
    args = parse_args()
    for p in (STATIC_PATH, META_PATH):
        if not p.exists():
            raise FileNotFoundError(
                f"{p} missing -- run scripts/chain_prepare_network_ablation_static.py first")

    out_dir = Path(args.output_dir)
    print("=" * 78)
    print("ARM D -- STREAM-NETWORK ADDITION (single variable: 4 attributes added back)")
    print(f"  control (12 US attrs)   median NSE {CONTROL_MEDIAN_NSE}")
    print(f"  global  (13 HydroATLAS) median NSE {GLOBAL_MEDIAN_NSE}")
    print(f"  this arm: {len(EXPECTED_ATTRS)} attributes, seed {args.seed}, epochs {args.epochs}")
    print(f"  added   : {NETWORK_ATTRS}")
    print(f"  stats   : {STATIC_PATH.name}")
    print(f"  meta    : {META_PATH.name}")
    print("=" * 78)

    argv = ["chain_train_q_v1.py", *FROZEN_ARGV,
            "--epochs", str(args.epochs),
            "--seed", str(args.seed),
            "--num_workers", str(args.num_workers),
            "--output_dir", str(out_dir),
            "--require_empty_output_dir"]
    if args.device:
        argv += ["--device", args.device]
    sys.argv = argv
    base.main()

    best_path = out_dir / "best_metrics.json"
    if not best_path.exists():
        print("!! no best_metrics.json -- training produced no scored epoch")
        return
    best = json.loads(best_path.read_text())["median_nse"]
    print("=" * 78)
    print(f"arm D median NSE = {best:.4f}   "
          f"global = {GLOBAL_MEDIAN_NSE:.4f} (delta {best - GLOBAL_MEDIAN_NSE:+.4f})   "
          f"control = {CONTROL_MEDIAN_NSE:.4f} (delta {best - CONTROL_MEDIAN_NSE:+.4f})")
    print("Read the verdict from the PAIRED per-station comparison against the global arm, "
          "not from this median alone.")
    print("=" * 78)


if __name__ == "__main__":
    main()
