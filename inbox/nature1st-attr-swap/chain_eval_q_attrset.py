#!/usr/bin/env python
"""Per-station evaluation for any attribute-set arm (INFERENCE ONLY).

chain_eval_q.py builds QDatasetConfig from the dataclass defaults, i.e. the 12
US-only attribute files. Feeding those to a model trained on a different set would
be a shape crash (or, if a count happened to match, a silent nonsense score), so
this wrapper redirects both attribute paths and then runs the formal evaluator
verbatim. Its own two flags are stripped before the evaluator parses argv; every
remaining flag is passed through untouched.

  python scripts/chain_eval_q_attrset.py \
      --static data/interim/stage_static_feature_stats_armE.json \
      --meta   data/processed/station_meta/trainable_mountain_stations.csv \
      --model_dir models/q_lstm_armE_hpc_s42 --subset val --max_hours 43800
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
for p in (str(ROOT), str(ROOT / "scripts")):
    if p not in sys.path:
        sys.path.insert(0, p)

import chain_eval_q as ev
from src.q_dataset_v1 import QDatasetConfig

_p = argparse.ArgumentParser(add_help=False)
_p.add_argument("--static", required=True)
_p.add_argument("--meta", required=True)
_own, _rest = _p.parse_known_args()

STATIC_PATH = Path(_own.static)
META_PATH = Path(_own.meta)
for _f in (STATIC_PATH, META_PATH):
    if not _f.exists():
        raise FileNotFoundError(f"{_f} missing")


def _config_with_attrset(**kwargs):
    kwargs["static_path"] = STATIC_PATH
    kwargs["station_meta_path"] = META_PATH
    return QDatasetConfig(**kwargs)


ev.QDatasetConfig = _config_with_attrset
sys.argv = [sys.argv[0], *_rest]

if __name__ == "__main__":
    print(f"[eval] attribute files: {STATIC_PATH.name} / {META_PATH.name}")
    ev.main()
