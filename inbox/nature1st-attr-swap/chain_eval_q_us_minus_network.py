#!/usr/bin/env python
"""Per-station evaluation for ARM C (12 US attributes minus the 4 network ones).

chain_eval_q.py builds QDatasetConfig from the dataclass defaults, i.e. the full
12-attribute US stats file. Feeding that to a model trained on 8 attributes would
be a shape crash (or, if a count ever happened to match, a silent nonsense score),
so this wrapper redirects the stats path and then runs the formal evaluator
verbatim. The station-meta table is the unchanged US file. No training, no
gradient step, no file in the formal pipeline is modified.

  python scripts/chain_eval_q_us_minus_network.py \
      --model_dir models/q_lstm_usminus4_hpc_s42 --subset val --max_hours 43800
"""
from __future__ import annotations
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
for p in (str(ROOT), str(ROOT / "scripts")):
    if p not in sys.path:
        sys.path.insert(0, p)

import chain_eval_q as ev
from src.q_dataset_v1 import QDatasetConfig

STATIC_PATH = ROOT / "data/interim/stage_static_feature_stats_us_minus_network.json"
META_PATH = ROOT / "data/processed/station_meta/trainable_mountain_stations.csv"


def _config_with_reduced_static(**kwargs):
    kwargs["static_path"] = STATIC_PATH
    kwargs["station_meta_path"] = META_PATH
    return QDatasetConfig(**kwargs)


ev.QDatasetConfig = _config_with_reduced_static

if __name__ == "__main__":
    ev.main()
