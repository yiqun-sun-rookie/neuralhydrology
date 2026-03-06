"""Load basin data from neuralhydrology for adversarial evaluation."""
from __future__ import annotations

from pathlib import Path
from typing import Tuple

import torch
from torch.utils.data import DataLoader

from neuralhydrology.utils.config import Config
from neuralhydrology.datasetzoo import get_dataset
from neuralhydrology.datautils.utils import load_scaler


def load_basin_data(
    run_dir: Path,
    basin_id: str,
    period: str = "test",
    device: str = "cpu",
) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    """Load all data for a single basin, stacked into tensors.

    Returns:
        x_d: [N, T, F] dynamic features (normalized)
        x_s: [N, S] static attributes (normalized)
        y_obs: [N, T, 1] observed streamflow (normalized)
    """
    cfg = Config(run_dir / "config.yml")
    scaler = load_scaler(run_dir)

    ds = get_dataset(
        cfg=cfg,
        is_train=False,
        period=period,
        basin=basin_id,
        scaler=scaler,
        id_to_int={},
    )

    loader = DataLoader(ds, batch_size=len(ds), collate_fn=ds.collate_fn,
                        shuffle=False)
    batch = next(iter(loader))

    # Stack x_d dict into tensor
    feature_names = list(cfg.dynamic_inputs)
    x_d_list = [batch["x_d"][feat] for feat in feature_names]
    x_d = torch.cat(x_d_list, dim=-1).to(device)  # [N, T, F]

    x_s = batch["x_s"].to(device)  # [N, S]
    y_obs = batch["y"].to(device)  # [N, T, 1]

    return x_d, x_s, y_obs
