import torch
import torch.nn as nn


class StateContinuityLoss(nn.Module):
    """L2 penalty on hidden state differences at temporal overlap points.

    Computes mean squared difference between hidden states from two overlapping segments
    at corresponding timesteps, weighted by scl_weight.
    """

    def __init__(self, scl_weight: float = 0.1):
        super().__init__()
        self.scl_weight = scl_weight

    def forward(self, h_k_overlap: torch.Tensor, h_k1_overlap: torch.Tensor) -> torch.Tensor:
        """Compute state continuity loss.

        Args:
            h_k_overlap: [batch, overlap_len, hidden] — seg_k hidden states at overlap.
            h_k1_overlap: [batch, overlap_len, hidden] — seg_k+1 hidden states at overlap.

        Returns:
            Scalar loss: scl_weight * mean((h_k - h_k1)^2).
        """
        return self.scl_weight * torch.mean((h_k_overlap - h_k1_overlap) ** 2)
