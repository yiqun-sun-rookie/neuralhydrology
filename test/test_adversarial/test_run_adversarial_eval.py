import json
import sys

import torch


def test_main_passes_configured_epoch_to_wrapper(monkeypatch, tmp_path):
    from src.adversarial.scripts import run_adversarial_eval as runner

    captured = {}
    output_dir = tmp_path / "out"

    class DummyWrapper:

        def __init__(self, run_dir, device, epoch=None):
            captured["run_dir"] = run_dir
            captured["device"] = device
            captured["epoch"] = epoch
            self.n_dynamic = 1
            self.dynamic_features = ["prcp(mm/day)"]

        def forward(self, x_d, x_s):
            return torch.zeros(x_d.shape[0], x_d.shape[1], 1)

        def get_scaler(self):
            return {}

    class DummyAttack:

        def __init__(self, **kwargs):
            pass

        def attack(self, x_d, x_s, y_obs):
            return x_d

    monkeypatch.setattr(runner, "CudaLSTMWrapper", DummyWrapper)
    monkeypatch.setitem(runner.ATTACK_REGISTRY, "fgsm", DummyAttack)
    monkeypatch.setattr(
        runner,
        "load_config",
        lambda _: {
            "output_dir": str(output_dir),
            "model": {
                "run_dir": "results/05_adversarial_robustness/runs/reproduce_531_nse074_2025_1129_2145_ep30",
                "device": "cpu",
                "epoch": 20,
            },
            "data": {"data_dir": None, "basins": ["01013500"]},
            "attacks": {"fgsm": {}},
            "epsilons": [0.1],
            "constraint_levels": ["lp"],
            "targets": ["untargeted"],
        },
    )
    monkeypatch.setattr(
        runner,
        "load_basin_data",
        lambda **kwargs: (
            torch.zeros(1, 365, 1),
            torch.zeros(1, 0),
            torch.zeros(1, 365, 1),
        ),
    )
    monkeypatch.setattr(
        runner,
        "run_single_experiment",
        lambda *args, **kwargs: {
            "nse_clean": 0.7,
            "nse_adv": 0.6,
            "delta_nse": -0.1,
            "kge_clean": 0.7,
            "kge_adv": 0.6,
            "peak_error": 0.0,
            "detectability_ks": 1.0,
            "l_inf": 0.0,
            "l2": 0.0,
        },
    )
    monkeypatch.setattr(sys, "argv", ["run_adversarial_eval.py", "--config", "dummy"])

    runner.main()

    assert captured["epoch"] == 20
    result_file = output_dir / "results.json"
    assert result_file.exists()
    records = json.loads(result_file.read_text(encoding="utf-8"))
    assert len(records) == 1
