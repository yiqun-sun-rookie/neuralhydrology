#!/usr/bin/env python
"""Train the formal Q model on ANY static-attribute set (generic arm runner).

The attribute-source campaign runs one arm per attribute block; every arm is the
formal pipeline with a different pair of attribute files. `chain_train_q_v1.
build_loader` builds `QDatasetConfig` from its module globals and never exposes
static_path / station_meta_path as flags, so the swap is done by rebinding that
name in the imported module. Everything else -- data loading, model construction,
loss, evaluation, checkpoint selection, seeding -- is the formal pipeline executed
verbatim via `base.main()`.

TWO SILENT FAILURE MODES THIS SCRIPT REFUSES TO TOLERATE
--------------------------------------------------------
Both live in src/q_dataset_v1.py and neither raises on its own:
  * a missing static_path silently yields static_norm={} -> aux_dim 0, i.e. a model
    trained with NO attributes at all, which would look like a catastrophic arm
    result while actually testing nothing (line 336);
  * a stats key with no matching station-meta column is silently fed as 0.0
    (line 663) -- one typo becomes a constant channel.
`_guarded_build_loader` fails closed on both before a single gradient step.

THE FROZEN CONTRACT
-------------------
Hyper-parameters are hard-coded to the campaign contract (identical to the control
arm models/q_lstm_control_hpc_s42 and every arm since). Only --seed, --epochs,
--num_workers, --device and the two attribute paths are settable. Changing the
contract makes an arm incomparable to the rest, so it is deliberately not exposed.

Usage:
  python scripts/chain_train_q_attrset.py \
      --static data/interim/stage_static_feature_stats_armE.json \
      --meta   data/processed/station_meta/trainable_mountain_stations.csv \
      --output_dir models/q_lstm_armE_hpc_s42 --seed 42 --epochs 40
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

# Frozen method contract -- identical to every arm of this campaign.
FROZEN_ARGV = [
    "--window", "168", "--horizon", "1", "--stride", "24",
    "--daily_days", "365", "--max_hours", "43800",
    "--patience", "5", "--batch_size", "256", "--lr", "5e-4",
    "--lstm_hidden", "256", "--lstm_layers", "2",
    "--static_hidden", "64", "--mlp_hidden", "128", "--dropout", "0.2",
    "--initial_forget_bias", "5.0",
]

REFERENCE = {  # val median NSE of the finished arms, for the closing printout
    "control  (12 US)": 0.6432,
    "global   (13 HydroATLAS)": 0.5983,
    "armC     (8 US, no network)": 0.6466,
    "armD     (17 = 13 global + 4 network)": 0.6059,
}

_STATIC_PATH: Path
_META_PATH: Path
_EXPECTED: list[str]
_orig_build_loader = base.build_loader


def _config_with_attrset(**kwargs):
    kwargs["static_path"] = _STATIC_PATH
    kwargs["station_meta_path"] = _META_PATH
    return QDatasetConfig(**kwargs)


def _guarded_build_loader(subset, args, **kwargs):
    loader, ds = _orig_build_loader(subset, args, **kwargs)

    keys = list(ds.static_norm.keys())
    if keys != _EXPECTED:
        raise RuntimeError(
            f"[{subset}] loaded attribute set does not match the stats file. got {keys}; "
            f"expected {_EXPECTED}. (An empty list means the stats file was not found: "
            f"{_STATIC_PATH})")
    if ds.station_meta is None:
        raise RuntimeError(f"[{subset}] station meta not loaded: {_META_PATH}")
    absent = [k for k in _EXPECTED if k not in ds.station_meta.columns]
    if absent:
        raise RuntimeError(f"[{subset}] station meta lacks columns {absent} -> the dataset "
                           "would silently feed 0.0 for them")

    aux_dim = int(ds[0]["aux"].shape[-1])
    if aux_dim != len(_EXPECTED):
        raise RuntimeError(f"[{subset}] aux_dim={aux_dim}, expected {len(_EXPECTED)}")
    print(f"  [guard] {subset}: {aux_dim} attributes, {len(ds.station_meta)} stations in meta "
          "-- attribute set verified")
    return loader, ds


base.QDatasetConfig = _config_with_attrset
base.build_loader = _guarded_build_loader


def parse_args():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--static", required=True, help="stats json; its KEYS define the feature set")
    p.add_argument("--meta", required=True, help="station meta csv holding those columns")
    p.add_argument("--output_dir", required=True)
    p.add_argument("--seed", type=int, default=42, help="42 matches every arm so far.")
    p.add_argument("--epochs", type=int, default=40,
                   help="MUST equal the other arms' cap (40) or the comparison is void.")
    p.add_argument("--num_workers", type=int, default=4)
    p.add_argument("--device", default=None)
    return p.parse_args()


def main():
    global _STATIC_PATH, _META_PATH, _EXPECTED
    args = parse_args()
    _STATIC_PATH, _META_PATH = Path(args.static), Path(args.meta)
    for p in (_STATIC_PATH, _META_PATH):
        if not p.exists():
            raise FileNotFoundError(f"{p} missing -- run scripts/chain_prepare_attrset.py first")
    _EXPECTED = list(json.loads(_STATIC_PATH.read_text()).keys())
    if not _EXPECTED:
        raise ValueError(f"{_STATIC_PATH} defines no attributes")

    out_dir = Path(args.output_dir)
    print("=" * 78)
    print(f"ATTRIBUTE-SET ARM -- {len(_EXPECTED)} attributes, seed {args.seed}, epochs {args.epochs}")
    print(f"  stats : {_STATIC_PATH.name}")
    print(f"  meta  : {_META_PATH.name}")
    print(f"  attrs : {_EXPECTED}")
    print("  finished arms for reference:")
    for k, v in REFERENCE.items():
        print(f"    {k:<40} {v:.4f}")
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
    print(f"this arm median NSE = {best:.4f}")
    for k, v in REFERENCE.items():
        print(f"  vs {k:<40} {best - v:+.4f}")
    print("The verdict comes from the PAIRED per-station comparison, not this median.")
    print("=" * 78)


if __name__ == "__main__":
    main()
