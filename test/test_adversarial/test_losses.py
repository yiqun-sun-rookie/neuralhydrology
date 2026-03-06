import pytest
import torch


class TestAttackLosses:

    def test_untargeted_loss_gradient(self):
        """Untargeted loss should produce non-zero gradient w.r.t. input."""
        from src.adversarial.attacks.losses import untargeted_nse_loss
        y_pred = torch.tensor([1.0, 2.0, 3.0], requires_grad=True)
        y_obs = torch.tensor([1.0, 2.0, 3.0])
        loss = untargeted_nse_loss(y_pred, y_obs)
        loss.backward()
        assert y_pred.grad is not None

    def test_targeted_flood_loss(self):
        """Targeted flood loss only considers high-flow timesteps."""
        from src.adversarial.attacks.losses import targeted_flood_loss
        y_pred = torch.tensor([0.5, 10.0, 0.3, 8.0, 0.2], requires_grad=True)
        y_obs = torch.tensor([0.5, 10.0, 0.3, 8.0, 0.2])
        loss = targeted_flood_loss(y_pred, y_obs, quantile=0.5)
        loss.backward()
        assert y_pred.grad is not None

    def test_targeted_lowflow_loss(self):
        from src.adversarial.attacks.losses import targeted_lowflow_loss
        y_pred = torch.tensor([0.5, 10.0, 0.3, 8.0, 0.2], requires_grad=True)
        y_obs = torch.tensor([0.5, 10.0, 0.3, 8.0, 0.2])
        loss = targeted_lowflow_loss(y_pred, y_obs, quantile=0.2)
        loss.backward()
        assert y_pred.grad is not None
