import pytest
import torch
import torch.nn as nn


class FakeModel(nn.Module):
    """Simple differentiable model for testing attacks."""
    def forward(self, x_d, x_s):
        return x_d.sum(dim=-1, keepdim=True)  # [B, T, 1]


@pytest.fixture
def setup():
    from src.adversarial.attacks.auto_pgd import AutoPGD
    from src.adversarial.constraints.lp_norm import LpConstraint
    model = FakeModel()
    constraint = LpConstraint(epsilon=0.1, norm="linf")
    attack = AutoPGD(model=model, constraint=constraint, n_iter=10, target="untargeted")
    return attack, model


class TestAutoPGD:

    def test_output_shape(self, setup):
        attack, _ = setup
        x_d = torch.randn(2, 50, 5)
        x_s = torch.randn(2, 13)
        y_obs = torch.randn(2, 50, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        assert x_adv.shape == x_d.shape

    def test_perturbation_within_bounds(self, setup):
        attack, _ = setup
        x_d = torch.randn(2, 50, 5)
        x_s = torch.randn(2, 13)
        y_obs = torch.randn(2, 50, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        delta = (x_adv - x_d).abs()
        assert delta.max() <= 0.1 + 1e-5

    def test_perturbation_is_nonzero(self, setup):
        attack, _ = setup
        x_d = torch.randn(2, 50, 5)
        x_s = torch.randn(2, 13)
        y_obs = x_d.sum(dim=-1, keepdim=True)  # match model output
        x_adv = attack.attack(x_d, x_s, y_obs)
        assert (x_adv - x_d).abs().max() > 1e-6

    def test_loss_decreases(self, setup):
        """Attack should decrease NSE (make predictions worse)."""
        attack, model = setup
        x_d = torch.randn(2, 50, 5)
        x_s = torch.randn(2, 13)
        y_obs = model(x_d, x_s).detach()

        y_clean = model(x_d, x_s)
        loss_clean = attack.compute_loss(y_clean, y_obs)

        x_adv = attack.attack(x_d, x_s, y_obs)
        y_adv = model(x_adv, x_s)
        loss_adv = attack.compute_loss(y_adv, y_obs)

        assert loss_adv < loss_clean  # NSE should decrease
