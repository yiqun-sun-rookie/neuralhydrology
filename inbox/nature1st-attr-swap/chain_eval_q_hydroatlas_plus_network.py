#!/usr/bin/env python
"""Per-station evaluation for ARM D (13 global attributes plus the 4 network ones).

chain_eval_q.py builds QDatasetConfig from the dataclass defaults, i.e. the 12
US-only attribute files. Feeding those to a model trained on 17 attributes would
be a shape crash (or, if a count ever happened to match, a silent nonsense score),
so this wrapper redirects both attribute paths and then runs the formal evaluator
verbatim. No training, no gradient step, no file in the formal pipeline is
modified.

  python scripts/chain_eval_q_hydroatlas_plus_network.py \
      --model_dir models/q_lstm_globalplus4_hpc_s42 --subset val --max_hours 43800
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

STATIC_PATH = ROOT / "data/interim/stage_static_feature_stats_hydroatlas_plus_network.json"
META_PATH = (ROOT / "data/processed/station_meta/"
                    "trainable_mountain_stations_hydroatlas_plus_network.csv")


def _config_with_augmented_static(**kwargs):
    kwargs["static_path"] = STATIC_PATH
    kwargs["station_meta_path"] = META_PATH
    return QDatasetConfig(**kwargs)


ev.QDatasetConfig = _config_with_augmented_static

if __name__ == "__main__":
    ev.main()
