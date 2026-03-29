"""Smoke test for static falsification EALSTM training."""
import sys
from pathlib import Path

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))


@pytest.mark.skipif(
    not Path("data/CAMELS_US").exists(),
    reason="CAMELS_US data not available"
)
def test_smoke_e1_single_basin(tmp_path):
    """Smoke test: train EALSTM on 1 basin for 1 epoch with correct static."""
    base_yml = Path("src/static_falsification/configs/base_ealstm.yml")
    if not base_yml.exists():
        pytest.skip("Base config not found")

    with open(base_yml, encoding="utf-8") as f:
        cfg = yaml.safe_load(f)

    # Override for smoke test
    cfg["experiment_name"] = "smoke_e1"
    cfg["epochs"] = 1
    cfg["batch_size"] = 16
    cfg["validate_every"] = 1
    cfg["validate_n_random_basins"] = 1
    cfg["run_dir"] = str(tmp_path / "runs")
    cfg["seq_length"] = 30
    # Use only robust attributes (some have zero std with few basins)
    cfg["static_attributes"] = [
        "elev_mean", "slope_mean", "area_gages2", "p_mean", "aridity", "frac_snow"
    ]
    cfg["save_weights_every"] = 1

    # Use 3 basins (single basin causes NaN std in static attribute normalization)
    basin_file = tmp_path / "basins.txt"
    basin_file.write_text("01013500\n01022500\n01030500\n")
    cfg["train_basin_file"] = str(basin_file)
    cfg["validation_basin_file"] = str(basin_file)
    cfg["test_basin_file"] = str(basin_file)

    smoke_cfg = tmp_path / "smoke.yml"
    with open(smoke_cfg, "w") as f:
        yaml.dump(cfg, f)

    from neuralhydrology.nh_run import start_run
    start_run(config_file=smoke_cfg, gpu=-1)

    # Check that a model checkpoint was saved
    run_dirs = list((tmp_path / "runs").iterdir())
    assert len(run_dirs) == 1
    assert any((run_dirs[0]).glob("model_epoch*.pt"))
