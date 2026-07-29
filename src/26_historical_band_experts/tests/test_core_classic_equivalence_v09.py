from pathlib import Path
import hashlib
import sys

import torch


IDEA_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = IDEA_ROOT.parents[1]
BASELINE_CONFIG = REPO_ROOT / "src/lstm_fair_531/configs/lstm_cudalstm_maurer_531_s100.yml"
sys.path.insert(0, str(IDEA_ROOT))

_FROZEN_LF_HASHES = {
    "src/lstm_fair_531/configs/lstm_cudalstm_maurer_531_s100.yml": (
        "83b3acd908d44397de671d01b172e3e9b92cc0c6efa7bd539c7017449d2c102f"
    ),
    "neuralhydrology/modelzoo/cudalstm.py": (
        "27f2e17d3f388a9b7ef25a261ec33007c328985d8c2a879592794c3fb8dede01"
    ),
    "neuralhydrology/modelzoo/inputlayer.py": (
        "b89b8eadbebaebe4f01b1bffaf64513c89d69f5726576f32e5a6bd83f4cbcbcb"
    ),
    "neuralhydrology/modelzoo/head.py": (
        "93331b1bf913857bb6f34deba41dd608c720c862209b6c821dd940f3a7b1282b"
    ),
}


def test_v09_core_classic_reference_files_match_frozen_lf_hashes():
    for relative_path, expected in _FROZEN_LF_HASHES.items():
        content = (REPO_ROOT / relative_path).read_bytes().replace(b"\r\n", b"\n")
        assert hashlib.sha256(content).hexdigest() == expected


def _build_pair():
    from models_formal_v09 import build_model_v09
    from neuralhydrology.modelzoo.cudalstm import CudaLSTM
    from neuralhydrology.utils.config import Config

    config = Config(BASELINE_CONFIG)
    torch.manual_seed(100)
    core = CudaLSTM(config)
    core_rng = torch.get_rng_state().clone()
    formal = build_model_v09("classic_lstm_256_clean", seed=100)
    formal_rng = torch.get_rng_state().clone()
    return config, core, formal, core_rng, formal_rng


def _synthetic_inputs(config, batch_size: int = 2):
    generator = torch.Generator().manual_seed(29_090)
    dynamic = {
        name: torch.randn(batch_size, 270, 1, generator=generator)
        for name in config.dynamic_inputs
    }
    recent = torch.cat([dynamic[name] for name in config.dynamic_inputs], dim=-1)
    statics = torch.randn(batch_size, 27, generator=generator)
    target_sequence = torch.randn(batch_size, 270, 1, generator=generator)
    raw_target_stds = torch.rand(batch_size, 1, 1, generator=generator)
    return (
        {"x_d": dynamic, "x_s": statics},
        {"recent": recent},
        statics,
        target_sequence,
        raw_target_stds,
    )


def test_v09_clean_classic_initialization_and_input_order_match_core_exactly():
    from models_v03 import _append_statics

    config, core, formal, core_rng, formal_rng = _build_pair()
    core_data, formal_dynamic, statics, _, _ = _synthetic_inputs(config)

    assert torch.equal(core_rng, formal_rng)
    assert [name for name, _ in core.named_parameters()] == [
        name for name, _ in formal.named_parameters()
    ]
    for (_, core_parameter), (_, formal_parameter) in zip(
        core.named_parameters(),
        formal.named_parameters(),
    ):
        assert torch.equal(core_parameter, formal_parameter)
    embedded = core.embedding_net(core_data)
    expected = _append_statics(formal_dynamic["recent"], statics).transpose(0, 1)
    assert torch.equal(embedded, expected)


def test_v09_clean_classic_training_forward_and_rng_match_core_exactly():
    config, core, formal, _, _ = _build_pair()
    core_data, formal_dynamic, statics, _, _ = _synthetic_inputs(config)
    core.train()
    formal.train()

    torch.manual_seed(8_123)
    before = torch.get_rng_state().clone()
    core_prediction = core(core_data)["y_hat"][:, -1, 0]
    core_after = torch.get_rng_state().clone()
    torch.set_rng_state(before)
    formal_prediction = formal(
        formal_dynamic,
        statics,
        dropout_context=(100, 1, 0),
    ).prediction
    formal_after = torch.get_rng_state().clone()

    assert torch.equal(core_prediction, formal_prediction)
    assert torch.equal(core_after, formal_after)


def test_v09_clean_classic_gradients_adam_and_updated_parameters_match_core_exactly():
    from train_strict_v06 import (
        _assert_gradients_equal,
        _assert_optimizer_states_equal,
        active_named_parameters,
        assert_exact_tensor,
        assert_parameter_sequence_equal,
    )

    config, core, formal, _, _ = _build_pair()
    from neuralhydrology.training.loss import MaskedNSELoss

    core_data, formal_dynamic, statics, target_sequence, raw_target_stds = _synthetic_inputs(config)
    core_parameters = active_named_parameters(core)
    formal_parameters = active_named_parameters(formal)
    assert_parameter_sequence_equal(core_parameters, formal_parameters)
    core_optimizer = torch.optim.Adam(
        [parameter for _, parameter in core_parameters],
        lr=0.001,
    )
    formal_optimizer = torch.optim.Adam(
        [parameter for _, parameter in formal_parameters],
        lr=0.001,
    )
    core.train()
    formal.train()

    torch.manual_seed(8_123)
    before = torch.get_rng_state().clone()
    core_output = core(core_data)
    core_prediction = core_output["y_hat"][:, -1, 0]
    torch.set_rng_state(before)
    formal_prediction = formal(
        formal_dynamic,
        statics,
        dropout_context=(100, 1, 0),
    ).prediction
    core_loss, _ = MaskedNSELoss(config)(
        core_output,
        {
            "y": target_sequence,
            "per_basin_target_stds": raw_target_stds,
        },
    )
    formal_weights = 1.0 / torch.square(raw_target_stds[:, 0, 0] + 0.1)
    formal_loss = (
        formal_weights
        * torch.square(formal_prediction - target_sequence[:, -1, 0])
    ).mean()
    assert_exact_tensor("core compatibility prediction", core_prediction, formal_prediction)
    assert_exact_tensor("core compatibility loss", core_loss, formal_loss)

    core_loss.backward()
    formal_loss.backward()
    _assert_gradients_equal(core_parameters, formal_parameters, "core compatibility unclipped")
    core_norm = torch.nn.utils.clip_grad_norm_(
        [parameter for _, parameter in core_parameters],
        1.0,
    )
    formal_norm = torch.nn.utils.clip_grad_norm_(
        [parameter for _, parameter in formal_parameters],
        1.0,
    )
    assert_exact_tensor("core compatibility gradient norm", core_norm, formal_norm)
    _assert_gradients_equal(core_parameters, formal_parameters, "core compatibility clipped")

    core_optimizer.step()
    formal_optimizer.step()
    assert_parameter_sequence_equal(core_parameters, formal_parameters)
    _assert_optimizer_states_equal(
        core_optimizer,
        formal_optimizer,
        core_parameters,
        formal_parameters,
    )
