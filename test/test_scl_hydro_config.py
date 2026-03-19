"""Tests for SCLConfig — wraps NH Config with SCL-specific parameters."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

import pytest

from scl_hydro.config import SCLConfig

# Minimal dict that NH Config accepts (dev_mode=True allows unknown keys,
# but we still need at least the keys that NH Config references during init).
_MINIMAL_NH = {
    "experiment_name": "scl_test",
    "run_dir": ".",
    "train_basin_file": "./test/test_data/4_basins_test_set.txt",
    "validation_basin_file": "./test/test_data/4_basins_test_set.txt",
    "test_basin_file": "./test/test_data/4_basins_test_set.txt",
    "train_start_date": "01/01/2000",
    "train_end_date": "31/12/2001",
    "validation_start_date": "01/01/2001",
    "validation_end_date": "31/12/2002",
    "test_start_date": "01/01/2001",
    "test_end_date": "31/12/2002",
    "seed": 111,
    "device": "cpu",
    "model": "cudalstm",
    "head": "regression",
    "hidden_size": 16,
    "output_activation": "linear",
    "initial_forget_bias": 3,
    "output_dropout": 0.4,
    "optimizer": "Adam",
    "loss": "MSE",
    "learning_rate": {0: 1e-3},
    "batch_size": 256,
    "epochs": 1,
    "predict_last_n": 1,
    "seq_length": 30,
    "num_workers": 0,
    "log_interval": 5,
    "log_tensorboard": False,
    "log_n_figures": 0,
    "save_weights_every": 1,
    "dataset": "camels_us",
    "data_dir": "./test/test_data",
    "dynamic_inputs": ["prcp(mm/day)"],
    "target_variables": ["QObs(mm/d)"],
    "static_attributes": ["elev_mean"],
    "validate_every": 1,
    "validate_n_random_basins": 1,
    "metrics": ["NSE"],
}


def test_scl_config_defaults():
    """Create SCLConfig with minimal dict — all SCL defaults should apply."""
    cfg = SCLConfig(_MINIMAL_NH.copy())

    assert cfg.seg_length == 180
    assert cfg.context_length == 30
    assert cfg.overlap_length == 30
    assert cfg.scl_weight == pytest.approx(0.1)
    assert cfg.enc_hidden_size == 64
    assert cfg.encoder_inputs == []
    # derived property
    assert cfg.overlap_start == 180 - 30  # seg_length - overlap_length

    # Delegation to NH Config: should still see hidden_size
    assert cfg.hidden_size == 16


def test_scl_config_custom():
    """Create SCLConfig with custom SCL params — they should override defaults."""
    d = _MINIMAL_NH.copy()
    d.update({
        "seg_length": 365,
        "context_length": 60,
        "overlap_length": 45,
        "scl_weight": 0.05,
        "enc_hidden_size": 128,
        "encoder_inputs": ["temperature"],
    })
    cfg = SCLConfig(d)

    assert cfg.seg_length == 365
    assert cfg.context_length == 60
    assert cfg.overlap_length == 45
    assert cfg.scl_weight == pytest.approx(0.05)
    assert cfg.enc_hidden_size == 128
    assert cfg.encoder_inputs == ["temperature"]
    assert cfg.overlap_start == 365 - 45

    # NH keys still work
    assert cfg.hidden_size == 16


def test_scl_config_validation_overlap_gt_seg():
    """overlap_length >= seg_length should raise ValueError."""
    d = _MINIMAL_NH.copy()
    # overlap_length == seg_length → invalid
    d.update({"seg_length": 100, "overlap_length": 100})
    with pytest.raises(ValueError, match="overlap_length"):
        SCLConfig(d)

    # overlap_length > seg_length → invalid
    d2 = _MINIMAL_NH.copy()
    d2.update({"seg_length": 100, "overlap_length": 150})
    with pytest.raises(ValueError, match="overlap_length"):
        SCLConfig(d2)
