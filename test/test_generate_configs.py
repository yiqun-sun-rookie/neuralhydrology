"""Tests for config generator."""
import sys
from pathlib import Path

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))


def test_generate_configs_creates_15_files(tmp_path):
    """generate_configs produces 15 YAML files (3 conditions x 5 folds)."""
    from static_falsification.scripts.generate_configs import generate_all_configs

    base_config = {
        "experiment_name": "sf_{condition}_fold{fold_idx}",
        "train_basin_file": "PLACEHOLDER",
        "validation_basin_file": "PLACEHOLDER",
        "test_basin_file": "PLACEHOLDER",
        "static_attributes": ["elev_mean", "slope_mean"],
    }
    base_yml = tmp_path / "base.yml"
    with open(base_yml, "w") as f:
        yaml.dump(base_config, f)

    data_dir = tmp_path / "data"
    data_dir.mkdir()
    for fold_idx in range(5):
        for split in ["train", "validation", "test"]:
            (data_dir / f"fold{fold_idx}_{split}.txt").write_text("01234567\n")

    out_dir = tmp_path / "configs"
    generate_all_configs(base_yml, data_dir, out_dir)

    configs = list(out_dir.glob("*.yml"))
    assert len(configs) == 15

    # E4 configs keep static_attributes (EALSTM requires x_s);
    # zeroing happens at dataset level, not config level.
    e4_configs = [c for c in configs if "e4" in c.name]
    assert len(e4_configs) == 5
    for cfg_path in e4_configs:
        with open(cfg_path) as f:
            cfg = yaml.safe_load(f)
        assert len(cfg.get("static_attributes", [])) > 0, "E4 must keep static_attributes for EALSTM"
