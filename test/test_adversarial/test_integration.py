"""End-to-end integration test: load real model, run all attacks."""
import pytest
import torch
from pathlib import Path


RUN_DIR = Path(r"G:\github\pycharm\projects\neuralhydrology\runs\05_full_531_basins_smoke_v2_2026_0217_1632_ep1")
SKIP = not RUN_DIR.exists()


@pytest.fixture(scope="module")
def model_and_data():
    if SKIP:
        pytest.skip("neuralhydrology run_dir not found")

    from src.adversarial.model_wrapper import CudaLSTMWrapper
    from src.adversarial.data_loader import load_basin_data

    wrapper = CudaLSTMWrapper(run_dir=RUN_DIR, device="cpu")
    x_d, x_s, y_obs = load_basin_data(
        run_dir=RUN_DIR, basin_id="01013500", period="test", device="cpu",
    )
    # Use first sample only for speed
    x_d = x_d[:1]
    x_s = x_s[:1]
    y_obs = y_obs[:1]

    with torch.no_grad():
        y_clean = wrapper.forward(x_d, x_s)

    return wrapper, x_d, x_s, y_obs, y_clean


@pytest.mark.parametrize("attack_name", [
    "auto_pgd", "cw_regression", "sparse_temporal", "spectral",
])
def test_attack_runs(model_and_data, attack_name):
    from src.adversarial.attacks import ATTACK_REGISTRY
    from src.adversarial.constraints.lp_norm import LpConstraint

    wrapper, x_d, x_s, y_obs, y_clean = model_and_data
    constraint = LpConstraint(epsilon=0.2, norm="linf")

    attack_cls = ATTACK_REGISTRY[attack_name]
    kwargs = {"model": wrapper, "constraint": constraint,
              "target": "untargeted", "epsilon": 0.2, "n_iter": 10}
    if attack_name == "sparse_temporal":
        kwargs["max_steps"] = 18
    if attack_name == "cw_regression":
        kwargs["binary_search_steps"] = 2

    attack = attack_cls(**kwargs)
    x_adv = attack.attack(x_d, x_s, y_obs)

    assert x_adv.shape == x_d.shape
    assert (x_adv - x_d).abs().max() <= 0.2 + 1e-4


def test_causal_trigger(model_and_data):
    from src.adversarial.attacks.causal_trigger import CausalTriggerAttack
    from src.adversarial.constraints.lp_norm import LpConstraint

    wrapper, x_d, x_s, y_obs, _ = model_and_data
    constraint = LpConstraint(epsilon=0.3, norm="linf")
    attack = CausalTriggerAttack(
        model=wrapper, constraint=constraint,
        pre_window=7, n_iter=10,
    )
    x_adv = attack.attack(x_d, x_s, y_obs, peak_indices=[180])
    assert x_adv.shape == x_d.shape
    # Only perturbation in [173, 180)
    assert (x_adv[:, 187:, :] - x_d[:, 187:, :]).abs().max() < 1e-5


def test_uap(model_and_data):
    from src.adversarial.attacks.uap import UAP
    from src.adversarial.constraints.lp_norm import LpConstraint

    wrapper, x_d, x_s, y_obs, _ = model_and_data
    constraint = LpConstraint(epsilon=0.2, norm="linf")
    attack = UAP(model=wrapper, constraint=constraint, n_iter=5)

    dataset = [(x_d, x_s, y_obs)]
    uap = attack.craft_universal(dataset)
    assert uap.shape == (1, x_d.shape[1], x_d.shape[2])

    x_adv = attack.attack(x_d, x_s, y_obs)
    assert x_adv.shape == x_d.shape
