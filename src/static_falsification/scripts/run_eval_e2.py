"""E2 evaluation: load E1 models and evaluate with shuffled static attributes.

Usage:
    python -m static_falsification.scripts.run_eval_e2 --results-dir results/11_static_falsification --gpu 0
    python -m static_falsification.scripts.run_eval_e2 --results-dir results/11_static_falsification --fold 0 --gpu 0
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

from neuralhydrology.datasetzoo import register_dataset
from neuralhydrology.datasetzoo.camelsus import CamelsUS
from neuralhydrology.evaluation.evaluate import start_evaluation
from neuralhydrology.utils.config import Config
from static_falsification.shuffled_dataset import ModifiedCamelsUS


def eval_e2_single(results_dir: Path, fold_idx: int, gpu: int = 0):
    """Evaluate E1 model from a fold with shuffled static attributes."""
    # Find the E1 run directory
    e1_pattern = f"sf_e1_fold{fold_idx}_*"
    e1_dirs = sorted(results_dir.glob(e1_pattern))
    if not e1_dirs:
        raise FileNotFoundError(f"No E1 run directory found matching {e1_pattern} in {results_dir}")
    run_dir = e1_dirs[-1]  # Use the latest if multiple exist

    # Load shuffle map and register modified dataset
    shuffle_maps_path = Path("src/static_falsification/data/shuffle_maps.json")
    with open(shuffle_maps_path) as f:
        all_maps = json.load(f)
    ModifiedCamelsUS._shuffle_map = all_maps[str(fold_idx)]
    ModifiedCamelsUS._constant_mode = False
    register_dataset("camels_us", ModifiedCamelsUS)

    print(f"[E2] Evaluating E1 model from {run_dir} with shuffled static (fold {fold_idx})")

    config = Config(run_dir / "config.yml")
    if gpu >= 0:
        config.device = f"cuda:{gpu}"
    else:
        config.device = "cpu"

    # Override experiment name so results are saved separately
    # (experiment_name is a read-only property, modify via _cfg dict)
    config._cfg["experiment_name"] = f"sf_e2_fold{fold_idx}"

    start_evaluation(cfg=config, run_dir=run_dir, period="test")

    # Restore
    ModifiedCamelsUS._shuffle_map = None
    ModifiedCamelsUS._constant_mode = False
    register_dataset("camels_us", CamelsUS)


def main():
    parser = argparse.ArgumentParser(description="E2: evaluate E1 models with shuffled static")
    parser.add_argument("--results-dir", type=str, required=True)
    parser.add_argument("--fold", type=int, default=-1, help="Fold index (0-4), -1 for all")
    parser.add_argument("--gpu", type=int, default=0)
    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    folds = list(range(5)) if args.fold < 0 else [args.fold]

    for fold_idx in folds:
        eval_e2_single(results_dir, fold_idx, args.gpu)


if __name__ == "__main__":
    main()
