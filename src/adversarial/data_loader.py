"""Load basin data from neuralhydrology for adversarial evaluation."""
from __future__ import annotations

from pathlib import Path
from typing import List, Optional, Tuple

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
    data_dir: Optional[Path] = None,
) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    """Load all data for a single basin, stacked into tensors.

    Args:
        run_dir: Path to the neuralhydrology run directory.
        basin_id: USGS gauge ID (e.g. "01013500").
        period: "test", "validation", or "train".
        device: torch device string.
        data_dir: Override data_dir from config (useful when data moved).

    Returns:
        x_d: [N, T, F] dynamic features (normalized)
        x_s: [N, S] static attributes (normalized)
        y_obs: [N, T, 1] observed streamflow (normalized)
    """
    cfg = Config(run_dir / "config.yml")
    if data_dir is not None:
        cfg.update_config({"data_dir": str(data_dir)})
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

    x_s = batch.get("x_s", torch.zeros(x_d.shape[0], 0)).to(device)  # [N, S]
    y_obs = batch["y"].to(device)  # [N, T, 1]

    return x_d, x_s, y_obs


def get_test_basins(run_dir: Path) -> List[str]:
    """Read the test basin list from a run's config."""
    cfg = Config(run_dir / "config.yml")
    basin_file = cfg.test_basin_file
    if not basin_file.is_absolute():
        basin_file = run_dir / basin_file
    if not basin_file.exists():
        # Try relative to project root
        from pathlib import PurePosixPath
        for candidate in [
            run_dir.parents[1] / basin_file,  # results/<id>/../basin_file
            Path("G:/github/pycharm/projects/neuralhydrology") / basin_file,
        ]:
            if candidate.exists():
                basin_file = candidate
                break
    with open(basin_file) as f:
        return [line.strip() for line in f if line.strip()]
