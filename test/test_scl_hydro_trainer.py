import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

import pytest
import numpy as np
import pandas as pd
import torch
from scl_hydro.trainer import SCLTrainer
from scl_hydro.model import SCLCudaLSTM
from scl_hydro.dataset import SCLDataset
from scl_hydro.loss import StateContinuityLoss


@pytest.fixture
def synthetic_data():
    n_days = 500
    dates = pd.date_range("2000-01-01", periods=n_days, freq="D")
    df = pd.DataFrame({
        "prcp": np.random.rand(n_days).astype(np.float32),
        "tmax": np.random.rand(n_days).astype(np.float32) * 30,
        "QObs": (np.abs(np.random.randn(n_days)) + 0.1).astype(np.float32),
    }, index=dates)
    return {"basin_01": df}


def test_scl_trainer_one_step(synthetic_data):
    """SCLTrainer should complete one training step without error."""
    model = SCLCudaLSTM(
        n_main_features=2, n_enc_features=3,
        hidden_size=32, enc_hidden_size=16, n_targets=1,
    )
    dataset = SCLDataset(
        data=synthetic_data, seg_length=30, context_length=10, overlap_length=10,
        main_features=["prcp", "tmax"], enc_features=["prcp", "tmax", "QObs"],
        target="QObs",
    )
    trainer = SCLTrainer(
        model=model, dataset=dataset,
        scl_weight=0.1, overlap_start=20, overlap_length=10,
        lr=0.001, batch_size=4,
    )
    loss_before = trainer.train_step()
    assert isinstance(loss_before, dict)
    assert "pred_loss" in loss_before
    assert "scl_loss" in loss_before
    assert "total_loss" in loss_before


def test_scl_trainer_loss_decreases(synthetic_data):
    """Loss should decrease after multiple training steps."""
    torch.manual_seed(42)
    model = SCLCudaLSTM(
        n_main_features=2, n_enc_features=3,
        hidden_size=32, enc_hidden_size=16, n_targets=1,
    )
    dataset = SCLDataset(
        data=synthetic_data, seg_length=30, context_length=10, overlap_length=10,
        main_features=["prcp", "tmax"], enc_features=["prcp", "tmax", "QObs"],
        target="QObs",
    )
    trainer = SCLTrainer(
        model=model, dataset=dataset,
        scl_weight=0.1, overlap_start=20, overlap_length=10,
        lr=0.001, batch_size=8,
    )
    losses = [trainer.train_step()["total_loss"] for _ in range(20)]
    # Loss should generally decrease (compare first 5 avg vs last 5 avg)
    assert np.mean(losses[-5:]) < np.mean(losses[:5])
