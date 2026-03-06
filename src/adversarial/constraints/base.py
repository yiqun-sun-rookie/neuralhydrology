from __future__ import annotations

from abc import ABC, abstractmethod

import torch


class BaseConstraint(ABC):
    """Abstract base for perturbation constraints."""

    def __init__(self, epsilon: float):
        self.epsilon = epsilon

    @abstractmethod
    def project(self, x_clean: torch.Tensor, x_adv: torch.Tensor) -> torch.Tensor:
        """Project x_adv to satisfy constraints.

        Args:
            x_clean: [B, T, F] original clean input.
            x_adv: [B, T, F] perturbed input.

        Returns:
            x_proj: [B, T, F] projected input satisfying constraints.
        """
        ...
