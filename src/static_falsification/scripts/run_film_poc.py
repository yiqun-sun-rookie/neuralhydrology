"""Runner for FiLM-LSTM POC: reads config's static_condition and injects shuffle if needed.

Usage:
    python src/static_falsification/scripts/run_film_poc.py \
        --config-file src/static_falsification/configs/film_poc/filmlstm_poc_shuffle_fold0_seed0.yml \
        --gpu 0
"""
import argparse
import json
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

from neuralhydrology.nh_run import start_run
from neuralhydrology.datasetzoo import register_dataset
from neuralhydrology.datasetzoo.camelsus import CamelsUS
from static_falsification.shuffled_dataset import ModifiedCamelsUS

REPO_ROOT = Path(__file__).resolve().parents[3]
SHUFFLE_MAPS_PATH = REPO_ROOT / 'src/static_falsification/data/shuffle_maps.json'


def _parse_experiment_name(experiment_name: str) -> tuple[str, int]:
    # experiment_name format: {model}_poc_{condition}_fold{F}_seed{S}
    parts = experiment_name.split('_')
    condition, fold_idx = None, None
    for part in parts:
        if part in ('real', 'shuffle'):
            condition = part
        elif part.startswith('fold'):
            fold_idx = int(part[len('fold'):])
    if condition is None or fold_idx is None:
        raise ValueError(f"Cannot parse condition/fold from experiment_name: {experiment_name}")
    return condition, fold_idx


def run(config_file: Path, gpu: int):
    with open(config_file, 'r', encoding='utf-8') as f:
        cfg_dict = yaml.safe_load(f)

    experiment_name = cfg_dict.get('experiment_name', '')
    static_condition, fold_idx = _parse_experiment_name(experiment_name)

    # Reset class state before setup
    ModifiedCamelsUS._shuffle_map = None
    ModifiedCamelsUS._constant_mode = False

    try:
        if static_condition == 'shuffle':
            with open(SHUFFLE_MAPS_PATH, 'r') as f:
                all_maps = json.load(f)
            ModifiedCamelsUS._shuffle_map = all_maps[str(fold_idx)]
            register_dataset('camels_us', ModifiedCamelsUS)
            print(f"[POC] Shuffle mode, fold {fold_idx}, experiment={experiment_name}")
        elif static_condition == 'real':
            register_dataset('camels_us', CamelsUS)
            print(f"[POC] Real mode, fold {fold_idx}, experiment={experiment_name}")
        else:
            raise ValueError(f"Unknown static_condition: {static_condition}")

        start_run(config_file=config_file, gpu=gpu)
    finally:
        # Always reset
        ModifiedCamelsUS._shuffle_map = None
        ModifiedCamelsUS._constant_mode = False
        register_dataset('camels_us', CamelsUS)


def main():
    parser = argparse.ArgumentParser(description='Run a FiLM POC training')
    parser.add_argument('--config-file', type=Path, required=True)
    parser.add_argument('--gpu', type=int, default=0, help='GPU id (-1 for CPU)')
    args = parser.parse_args()
    run(args.config_file, args.gpu)


if __name__ == '__main__':
    main()
