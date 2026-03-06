import pytest
import torch
import torch.nn as nn


class FakeModel(nn.Module):
    def forward(self, x_d, x_s):
        return x_d.sum(dim=-1, keepdim=True)


@pytest.fixture
def setup():
    from src.adversarial.attacks.uap import UAP
    from src.adversarial.constraints.lp_norm import LpConstraint
    model = FakeModel()
    constraint = LpConstraint(epsilon=0.2, norm="linf")
    attack = UAP(model=model, constraint=constraint, n_iter=20)
    return attack, model


class TestUAP:

    def test_universal_shape(self, setup):
        """UAP should produce a single perturbation pattern [1, T, F]."""
        attack, _ = setup
        dataset = [(torch.randn(1, 50, 5), torch.randn(1, 13),
                     torch.randn(1, 50, 1)) for _ in range(5)]
        uap = attack.craft_universal(dataset)
        assert uap.shape == (1, 50, 5)

    def test_apply_to_new_sample(self, setup):
        """UAP applies to unseen samples without per-sample optimization."""
        attack, _ = setup
        dataset = [(torch.randn(1, 50, 5), torch.randn(1, 13),
                     torch.randn(1, 50, 1)) for _ in range(5)]
        attack.craft_universal(dataset)

        x_new = torch.randn(3, 50, 5)
        x_adv = attack.attack(x_new, torch.randn(3, 13), torch.randn(3, 50, 1))
        assert x_adv.shape == x_new.shape

    def test_perturbation_bounded(self, setup):
        attack, _ = setup
        dataset = [(torch.randn(1, 50, 5), torch.randn(1, 13),
                     torch.randn(1, 50, 1)) for _ in range(5)]
        uap = attack.craft_universal(dataset)
        assert uap.abs().max() <= 0.2 + 1e-5
