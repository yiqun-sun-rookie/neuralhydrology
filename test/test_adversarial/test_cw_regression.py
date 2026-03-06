import pytest
import torch
import torch.nn as nn


class FakeModel(nn.Module):
    def forward(self, x_d, x_s):
        return x_d.sum(dim=-1, keepdim=True)


@pytest.fixture
def setup():
    from src.adversarial.attacks.cw_regression import CWRegression
    from src.adversarial.constraints.lp_norm import LpConstraint
    model = FakeModel()
    constraint = LpConstraint(epsilon=1.0, norm="l2")
    attack = CWRegression(model=model, constraint=constraint,
                          n_iter=50, target_nse=0.0, lr=0.01)
    return attack, model


class TestCWRegression:

    def test_output_shape(self, setup):
        attack, _ = setup
        x_d = torch.randn(2, 50, 5)
        x_s = torch.randn(2, 13)
        y_obs = torch.randn(2, 50, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        assert x_adv.shape == x_d.shape

    def test_minimizes_perturbation_norm(self, setup):
        """C&W should find smaller perturbation than max epsilon."""
        attack, model = setup
        x_d = torch.randn(1, 50, 5)
        x_s = torch.randn(1, 13)
        y_obs = model(x_d, x_s).detach()
        x_adv = attack.attack(x_d, x_s, y_obs)
        l2 = (x_adv - x_d).reshape(1, -1).norm(dim=1)
        assert l2.item() < 1.0  # should be less than max epsilon
