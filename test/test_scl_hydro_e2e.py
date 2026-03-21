"""End-to-end smoke test: synthetic data → SCLDataset → SCLCudaLSTM → SCLTrainer → loss decreases."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

import numpy as np
import pandas as pd
import torch
from scl_hydro.model import SCLCudaLSTM
from scl_hydro.dataset import SCLDataset
from scl_hydro.trainer import SCLTrainer


def test_e2e_scl_training():
    """Full pipeline: data → dataset → model → trainer → loss decreases."""
    torch.manual_seed(42)
    np.random.seed(42)

    # Synthetic data: 2 basins, 3 years daily
    n_days = 1095
    data = {}
    for basin in ["basin_01", "basin_02"]:
        dates = pd.date_range("2000-01-01", periods=n_days, freq="D")
        data[basin] = pd.DataFrame({
            "prcp": np.random.rand(n_days).astype(np.float32),
            "tmax": (np.random.rand(n_days) * 30).astype(np.float32),
            "QObs": (np.abs(np.random.randn(n_days)) + 0.1).astype(np.float32),
        }, index=dates)

    seg_len = 60
    ctx_len = 15
    overlap = 15

    dataset = SCLDataset(
        data=data, seg_length=seg_len, context_length=ctx_len,
        overlap_length=overlap,
        main_features=["prcp", "tmax"],
        enc_features=["prcp", "tmax", "QObs"],
        target="QObs",
    )
    assert len(dataset) > 0, "Dataset should have samples"

    model = SCLCudaLSTM(
        n_main_features=2, n_enc_features=3,
        hidden_size=32, enc_hidden_size=16, n_targets=1,
    )

    trainer = SCLTrainer(
        model=model, dataset=dataset,
        scl_weight=0.1,
        overlap_start=seg_len - overlap,
        overlap_length=overlap,
        lr=0.001, batch_size=8,
    )

    # Train for 30 steps
    losses = []
    for _ in range(30):
        step_loss = trainer.train_step()
        losses.append(step_loss["total_loss"])

    # Verify loss decreases (first 10 avg > last 10 avg)
    first_avg = np.mean(losses[:10])
    last_avg = np.mean(losses[-10:])
    assert last_avg < first_avg, f"Loss should decrease: {first_avg:.4f} -> {last_avg:.4f}"

    # Verify SCL loss is non-trivial (not zero)
    scl_losses = [trainer.train_step()["scl_loss"] for _ in range(5)]
    assert any(l > 0 for l in scl_losses), "SCL loss should be non-zero"
