import pytest
import torch
import torch.nn as nn


class FakeModel(nn.Module):
    def forward(self, x_d, x_s):
        return x_d.cumsum(dim=1).sum(dim=-1, keepdim=True)


@pytest.fixture
def setup():
    from src.adversarial.attacks.causal_trigger import CausalTriggerAttack
    from src.adversarial.constraints.lp_norm import LpConstraint
    model = FakeModel()
    constraint = LpConstraint(epsilon=0.3, norm="linf")
    attack = CausalTriggerAttack(model=model, constraint=constraint,
                                  pre_window=7, n_iter=30)
    return attack, model


class TestCausalTrigger:

    def test_output_shape(self, setup):
        attack, _ = setup
        x_d = torch.randn(1, 100, 5)
        x_s = torch.randn(1, 13)
        y_obs = torch.randn(1, 100, 1)
        peak_indices = [50]
        x_adv = attack.attack(x_d, x_s, y_obs, peak_indices=peak_indices)
        assert x_adv.shape == x_d.shape

    def test_perturbation_only_before_peak(self, setup):
        """Perturbation should only exist in [peak-w, peak) window."""
        attack, _ = setup
        x_d = torch.randn(1, 100, 5)
        x_s = torch.randn(1, 13)
        y_obs = torch.randn(1, 100, 1)
        peak_indices = [50]
        x_adv = attack.attack(x_d, x_s, y_obs, peak_indices=peak_indices)
        delta = (x_adv - x_d).abs()

        # Before window: no perturbation
        assert delta[0, :43, :].max() < 1e-6
        # After peak: no perturbation
        assert delta[0, 50:, :].max() < 1e-6
        # In window [43, 50): may have perturbation
        assert delta[0, 43:50, :].max() > 1e-6
