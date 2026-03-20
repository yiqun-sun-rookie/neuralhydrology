"""SCLTrainer: training loop for SCL-LSTM with overlapping segment pairs.

Combines SCLCudaLSTM, SCLDataset, and StateContinuityLoss into a single
training step that handles paired forward passes and state continuity loss.
"""
from typing import Dict, Optional

import torch
import torch.nn as nn
from torch.utils.data import DataLoader

from scl_hydro.model import SCLCudaLSTM
from scl_hydro.dataset import SCLDataset
from scl_hydro.loss import StateContinuityLoss


class SCLTrainer:
    """Trainer for SCL-LSTM with overlapping segment pairs.

    Handles: paired forward pass, prediction loss, state continuity loss,
    gradient computation, and optimizer step.

    Parameters
    ----------
    model : SCLCudaLSTM
        The SCL-LSTM model to train.
    dataset : SCLDataset
        Dataset that yields overlapping segment pairs.
    scl_weight : float
        Weight multiplier for the state continuity loss term.
    overlap_start : int
        Index into predict_k's time axis where the overlap region starts.
        Must satisfy: overlap_start + overlap_length == seg_length.
    overlap_length : int
        Number of timesteps shared between predict_k tail and predict_k+1 head.
    lr : float, optional
        Learning rate for Adam optimizer. Default 0.001.
    batch_size : int, optional
        Mini-batch size. Default 128.
    device : str, optional
        Torch device string ('cpu' or 'cuda'). Default 'cpu'.
    clip_grad_norm : float or None, optional
        Max gradient norm for clipping. None disables clipping. Default 1.0.
    """

    def __init__(self, model: SCLCudaLSTM, dataset: SCLDataset, scl_weight: float,
                 overlap_start: int, overlap_length: int, lr: float = 0.001,
                 batch_size: int = 128, device: str = "cpu",
                 clip_grad_norm: Optional[float] = 1.0):
        self.model = model.to(device)
        self.device = device
        self.overlap_start = overlap_start
        self.overlap_length = overlap_length

        self.loader = DataLoader(dataset, batch_size=batch_size, shuffle=True, drop_last=True)
        self._loader_iter = iter(self.loader)

        self.optimizer = torch.optim.Adam(model.parameters(), lr=lr)
        self.pred_loss_fn = nn.MSELoss()
        self.scl_loss_fn = StateContinuityLoss(scl_weight=scl_weight)
        self.clip_grad_norm = clip_grad_norm

    def _get_batch(self) -> Dict[str, torch.Tensor]:
        """Fetch next batch, resetting the iterator at epoch boundaries."""
        try:
            batch = next(self._loader_iter)
        except StopIteration:
            self._loader_iter = iter(self.loader)
            batch = next(self._loader_iter)
        return {k: v.to(self.device) for k, v in batch.items()}

    def train_step(self) -> Dict[str, float]:
        """Execute one training step on a batch of segment pairs.

        Concatenates both segments into a 2B batch for a single efficient
        forward pass, then splits outputs to compute prediction loss on both
        segments and state continuity loss on the overlap region.

        Returns
        -------
        dict with keys:
            'pred_loss' : float — sum of MSE on seg_k and seg_k+1 predictions.
            'scl_loss'  : float — weighted L2 loss on overlapping hidden states.
            'total_loss': float — pred_loss + scl_loss.
        """
        self.model.train()
        batch = self._get_batch()

        # Concatenate both segments for a single batched forward pass (2B samples)
        predict_2b = torch.cat([batch["predict_k"], batch["predict_k1"]], dim=0)
        context_2b = torch.cat([batch["context_k"], batch["context_k1"]], dim=0)

        output = self.model(predict_2b, context_2b)
        y_hat_k, y_hat_k1 = output["y_hat"].chunk(2, dim=0)
        lstm_out_k, lstm_out_k1 = output["lstm_output"].chunk(2, dim=0)

        # Prediction loss on both segments
        pred_loss = (self.pred_loss_fn(y_hat_k, batch["y_k"])
                     + self.pred_loss_fn(y_hat_k1, batch["y_k1"]))

        # State continuity loss: compare hidden states at the overlap region
        # overlap region of seg_k: timesteps [overlap_start : overlap_start + overlap_length]
        # overlap region of seg_k+1: timesteps [0 : overlap_length]
        h_k_ov = lstm_out_k[:, self.overlap_start:self.overlap_start + self.overlap_length, :]
        h_k1_ov = lstm_out_k1[:, :self.overlap_length, :]
        scl_loss = self.scl_loss_fn(h_k_ov, h_k1_ov)

        total_loss = pred_loss + scl_loss

        # Backward pass + gradient clip + optimizer step
        self.optimizer.zero_grad()
        total_loss.backward()
        if self.clip_grad_norm is not None:
            nn.utils.clip_grad_norm_(self.model.parameters(), self.clip_grad_norm)
        self.optimizer.step()

        return {
            "pred_loss": pred_loss.item(),
            "scl_loss": scl_loss.item(),
            "total_loss": total_loss.item(),
        }
