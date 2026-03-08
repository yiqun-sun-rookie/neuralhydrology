"""Wrap neuralhydrology CudaLSTM for adversarial attack interface."""
from __future__ import annotations

from pathlib import Path
from typing import Optional

import torch
import torch.nn as nn

from neuralhydrology.modelzoo import get_model
from neuralhydrology.utils.config import Config
from neuralhydrology.datautils.utils import load_scaler


class CudaLSTMWrapper(nn.Module):
    """Tensor-interface wrapper around neuralhydrology CudaLSTM.

    Converts stacked tensor [B, T, F] <-> feature-dict expected by CudaLSTM.
    """

    def __init__(self, run_dir: Path, device: str = "cpu",
                 epoch: Optional[int] = None):
        super().__init__()
        self.run_dir = Path(run_dir)
        self.device = torch.device(device)

        # Load config
        cfg_path = self.run_dir / "config.yml"
        self.cfg = Config(cfg_path)

        # Load model
        self.model = get_model(self.cfg).to(self.device)

        # Find checkpoint
        if epoch is None:
            pts = sorted(self.run_dir.glob("model_epoch*.pt"))
            if not pts:
                raise FileNotFoundError(f"No checkpoint found in {self.run_dir}")
            weight_file = pts[-1]  # latest epoch
        else:
            weight_file = self.run_dir / f"model_epoch{epoch:03d}.pt"

        state = torch.load(weight_file, map_location=self.device, weights_only=True)
        self.model.load_state_dict(state)
        self.model.eval()

        # Feature metadata
        dynamic_inputs = self.cfg.dynamic_inputs
        if isinstance(dynamic_inputs, dict):
            # Multi-frequency: flatten to single list
            self.dynamic_features = []
            for feats in dynamic_inputs.values():
                self.dynamic_features.extend(feats)
        else:
            self.dynamic_features = list(dynamic_inputs)
        self.static_features = list(self.cfg.static_attributes) if self.cfg.static_attributes else []
        self.n_dynamic = len(self.dynamic_features)
        self.n_static = len(self.static_features)

        # Scaler
        self._scaler = load_scaler(self.run_dir)

    def forward(self, x_d: torch.Tensor, x_s: torch.Tensor) -> torch.Tensor:
        """Run forward pass.

        Args:
            x_d: [B, T, n_dynamic] dynamic features (normalized).
            x_s: [B, n_static] static attributes (normalized).

        Returns:
            y_hat: [B, T, 1] streamflow predictions (normalized).
        """
        # Convert stacked tensor to feature dict expected by InputLayer
        x_d_dict = {}
        for i, feat in enumerate(self.dynamic_features):
            x_d_dict[feat] = x_d[:, :, i:i + 1]  # [B, T, 1]

        data = {"x_d": x_d_dict}
        if self.n_static > 0:
            data["x_s"] = x_s

        # Disable cuDNN for forward pass when gradients are needed (adversarial attacks).
        # cuDNN RNN does not support backward in eval mode.
        needs_grad = x_d.requires_grad
        if needs_grad and torch.cuda.is_available():
            with torch.backends.cudnn.flags(enabled=False):
                predictions = self.model(data)
        else:
            predictions = self.model(data)
        return predictions["y_hat"]  # [B, T, 1]

    def get_scaler(self) -> dict:
        """Return normalization scaler."""
        return self._scaler
