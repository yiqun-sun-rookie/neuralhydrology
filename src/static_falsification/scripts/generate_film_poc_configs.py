"""Generate 24 POC configs for FiLM-LSTM 2x2 ablation.

Matrix: 2 models (ealstm, filmlstm) x 2 static conditions (real, shuffle)
x 2 folds (0, 1) x 3 seeds (0, 1, 2) = 24 configs.

Condition is encoded in experiment_name as `{model}_poc_{real|shuffle}_fold{F}_seed{S}`.
The runner script (run_film_poc.py) parses it and injects shuffle via
ModifiedCamelsUS class-level attributes before calling start_run.
"""
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[3]
BASE_EALSTM = REPO_ROOT / 'src/static_falsification/configs/base_ealstm.yml'
BASE_FILM = REPO_ROOT / 'src/static_falsification/configs/base_filmlstm.yml'
OUT_DIR = REPO_ROOT / 'src/static_falsification/configs/film_poc'


def build_config(model: str, fold: int, seed: int, shuffle: bool) -> dict:
    base_path = BASE_FILM if model == 'filmlstm' else BASE_EALSTM
    with open(base_path, 'r', encoding='utf-8') as f:
        cfg = yaml.safe_load(f)

    cfg['experiment_name'] = f"{model}_poc_{'shuffle' if shuffle else 'real'}_fold{fold}_seed{seed}"
    cfg['seed'] = seed
    cfg['train_basin_file'] = f'src/static_falsification/data/fold{fold}_train.txt'
    cfg['validation_basin_file'] = f'src/static_falsification/data/fold{fold}_validation.txt'
    cfg['test_basin_file'] = f'src/static_falsification/data/fold{fold}_test.txt'

    return cfg


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    models = ['ealstm', 'filmlstm']
    folds = [0, 1]
    seeds = [0, 1, 2]
    conditions = [False, True]  # False=real, True=shuffle

    n = 0
    for model in models:
        for fold in folds:
            for seed in seeds:
                for shuffle in conditions:
                    cfg = build_config(model, fold, seed, shuffle)
                    cond = 'shuffle' if shuffle else 'real'
                    out = OUT_DIR / f'{model}_poc_{cond}_fold{fold}_seed{seed}.yml'
                    with open(out, 'w', encoding='utf-8') as f:
                        yaml.safe_dump(cfg, f, default_flow_style=False, sort_keys=False)
                    n += 1
                    print(f'  wrote {out.relative_to(REPO_ROOT)}')

    print(f'\nGenerated {n} configs in {OUT_DIR.relative_to(REPO_ROOT)}')
    assert n == 24, f'Expected 24 configs, got {n}'


if __name__ == '__main__':
    main()
