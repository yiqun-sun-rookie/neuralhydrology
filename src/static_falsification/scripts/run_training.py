"""Batch training for static falsification experiments.

Usage:
    # Train all 15 models sequentially (local):
    python -m static_falsification.scripts.run_training --gpu 0

    # Train a specific condition+fold:
    python -m static_falsification.scripts.run_training --condition e1 --fold 0 --gpu 0

    # E3 requires shuffle injection:
    python -m static_falsification.scripts.run_training --condition e3 --fold 2 --gpu 0
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

from neuralhydrology.nh_run import start_run
from neuralhydrology.datasetzoo import register_dataset
from neuralhydrology.datasetzoo.camelsus import CamelsUS
from static_falsification.shuffled_dataset import ModifiedCamelsUS


def run_single(condition: str, fold_idx: int, gpu: int = 0):
    """Train one model for a given condition and fold."""
    config_path = Path(f"src/static_falsification/configs/ealstm_{condition}_fold{fold_idx}.yml")
    if not config_path.exists():
        raise FileNotFoundError(f"Config not found: {config_path}. Run generate_configs.py first.")

    if condition in ("e3", "e4"):
        ModifiedCamelsUS._shuffle_map = None
        ModifiedCamelsUS._constant_mode = False

        if condition == "e3":
            shuffle_maps_path = Path("src/static_falsification/data/shuffle_maps.json")
            with open(shuffle_maps_path) as f:
                all_maps = json.load(f)
            ModifiedCamelsUS._shuffle_map = all_maps[str(fold_idx)]
            print(f"[E3] Shuffle mode for fold {fold_idx}")
        elif condition == "e4":
            ModifiedCamelsUS._constant_mode = True
            print(f"[E4] Constant (zero) mode for fold {fold_idx}")

        register_dataset("camels_us", ModifiedCamelsUS)

    print(f"Training {condition} fold {fold_idx} with config: {config_path}")
    start_run(config_file=config_path, gpu=gpu)

    if condition in ("e3", "e4"):
        ModifiedCamelsUS._shuffle_map = None
        ModifiedCamelsUS._constant_mode = False
        register_dataset("camels_us", CamelsUS)


def main():
    parser = argparse.ArgumentParser(description="Train static falsification models")
    parser.add_argument("--condition", type=str, choices=["e1", "e3", "e4", "all"], default="all")
    parser.add_argument("--fold", type=int, default=-1, help="Fold index (0-4), -1 for all")
    parser.add_argument("--gpu", type=int, default=0, help="GPU id (-1 for CPU)")
    args = parser.parse_args()

    conditions = ["e1", "e3", "e4"] if args.condition == "all" else [args.condition]
    folds = list(range(5)) if args.fold < 0 else [args.fold]

    for condition in conditions:
        for fold_idx in folds:
            run_single(condition, fold_idx, args.gpu)


if __name__ == "__main__":
    main()
