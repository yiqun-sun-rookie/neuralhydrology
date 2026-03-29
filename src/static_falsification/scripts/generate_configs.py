"""Batch-generate 15 YAML configs (3 conditions x 5 folds) from base template."""
import copy
from pathlib import Path

import yaml


def generate_all_configs(base_yml: Path, data_dir: Path, out_dir: Path, n_folds: int = 5):
    """Generate E1, E3, E4 configs for each fold.

    E1: correct static attributes (baseline)
    E3: shuffled static (shuffle injection happens at dataset level, not config)
    E4: no static attributes (constant zero = remove from config)
    """
    with open(base_yml, encoding="utf-8") as f:
        base = yaml.safe_load(f)

    out_dir.mkdir(parents=True, exist_ok=True)

    for fold_idx in range(n_folds):
        for condition in ["e1", "e3", "e4"]:
            cfg = copy.deepcopy(base)

            # Set experiment name
            cfg["experiment_name"] = f"sf_{condition}_fold{fold_idx}"

            # Set basin files
            cfg["train_basin_file"] = str(data_dir / f"fold{fold_idx}_train.txt")
            cfg["validation_basin_file"] = str(data_dir / f"fold{fold_idx}_validation.txt")
            cfg["test_basin_file"] = str(data_dir / f"fold{fold_idx}_test.txt")

            # E3 and E4: configs are identical to E1. The shuffle (E3) and
            # constant-zero (E4) transformations are applied at dataset level
            # by run_training.py, NOT in the config.
            # EALSTM requires x_s in forward pass, so static_attributes must stay.

            fname = out_dir / f"ealstm_{condition}_fold{fold_idx}.yml"
            with open(fname, "w") as f:
                yaml.dump(cfg, f, default_flow_style=False, sort_keys=False)


def main():
    base_yml = Path("src/static_falsification/configs/base_ealstm.yml")
    data_dir = Path("src/static_falsification/data")
    out_dir = Path("src/static_falsification/configs")
    generate_all_configs(base_yml, data_dir, out_dir)
    print(f"Generated 15 configs in {out_dir}")


if __name__ == "__main__":
    main()
