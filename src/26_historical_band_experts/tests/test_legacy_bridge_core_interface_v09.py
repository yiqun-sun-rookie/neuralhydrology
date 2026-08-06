"""Cover the real core-model interface the legacy checkpoint bridge depends on.

Every other bridge test asserts that a guard fires before a model is ever built, so the
production path that addresses a frozen ``CudaLSTM`` had no coverage at all. These tests
pin the one fact that broke it: the dynamic-input keys belong to the bound legacy config,
never to the formal protocol.
"""
from pathlib import Path
import sys

import pytest
import torch

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))

_LEGACY_DYNAMIC_NAMES = ("PRCP(mm/day)", "Tmin(C)", "Tmax(C)", "SRAD(W/m2)", "Vp(Pa)")
_PROTOCOL_DYNAMIC_NAMES = ("prcp", "tmin", "tmax", "srad", "vp")
_STATIC_ATTRIBUTES = (
    "p_mean",
    "pet_mean",
    "aridity",
    "p_seasonality",
    "frac_snow",
    "high_prec_freq",
    "high_prec_dur",
    "low_prec_freq",
    "low_prec_dur",
    "elev_mean",
    "slope_mean",
    "area_gages2",
    "frac_forest",
    "lai_max",
    "lai_diff",
    "gvf_max",
    "gvf_diff",
    "soil_depth_pelletier",
    "soil_depth_statsgo",
    "soil_porosity",
    "soil_conductivity",
    "max_water_content",
    "sand_frac",
    "silt_frac",
    "clay_frac",
    "carbonate_rocks_frac",
    "geol_permeability",
)


class _StubLegacyConfig:
    """Carry only the attribute the name deriver is contractually allowed to read."""

    def __init__(self, dynamic_inputs) -> None:
        self.dynamic_inputs = dynamic_inputs


def _legacy_style_config(dynamic_inputs=_LEGACY_DYNAMIC_NAMES):
    """Mirror the model-relevant keys of the eight frozen seed configs."""
    from neuralhydrology.utils.config import Config

    return Config({
        "model": "cudalstm",
        "head": "regression",
        "output_activation": "linear",
        "output_dropout": 0.4,
        "hidden_size": 256,
        "initial_forget_bias": 5,
        "seq_length": 270,
        "predict_last_n": 1,
        "dynamic_inputs": list(dynamic_inputs),
        "static_attributes": list(_STATIC_ATTRIBUTES),
        "target_variables": ["QObs(mm/d)"],
        "number_of_basins": 531,
    })


def test_bridge_keys_come_from_the_legacy_config_not_the_protocol():
    from audit_legacy_checkpoint_bridge_v09 import _legacy_dynamic_input_names_v09

    names = _legacy_dynamic_input_names_v09(_legacy_style_config(), expected_count=5)
    assert names == _LEGACY_DYNAMIC_NAMES
    assert names != _PROTOCOL_DYNAMIC_NAMES


def test_real_core_model_rejects_protocol_short_names_as_dynamic_keys():
    from neuralhydrology.modelzoo.cudalstm import CudaLSTM

    core = CudaLSTM(_legacy_style_config())
    core.eval()
    recent = torch.zeros(2, 270, 5)
    statics = torch.zeros(2, 27)
    protocol_keyed = {
        "x_d": {name: recent[:, :, index:index + 1] for index, name in enumerate(_PROTOCOL_DYNAMIC_NAMES)},
        "x_s": statics,
    }
    with pytest.raises(KeyError):
        with torch.no_grad():
            core(protocol_keyed)


def test_core_and_formal_models_agree_exactly_when_addressed_by_config_names():
    from audit_legacy_checkpoint_bridge_v09 import _legacy_dynamic_input_names_v09
    from models_formal_v09 import build_model_v09
    from neuralhydrology.modelzoo.cudalstm import CudaLSTM

    config = _legacy_style_config()
    classic = build_model_v09("classic_lstm_256_clean", 100)
    state = classic.state_dict()
    core = CudaLSTM(config)
    _, unexpected = core.load_state_dict(state, strict=False)
    assert not unexpected
    core.eval()
    classic.eval()

    generator = torch.Generator().manual_seed(29_090)
    recent = torch.randn(2, 270, 5, generator=generator)
    statics = torch.randn(2, 27, generator=generator)
    names = _legacy_dynamic_input_names_v09(config, expected_count=5)
    core_data = {
        "x_d": {name: recent[:, :, index:index + 1] for index, name in enumerate(names)},
        "x_s": statics,
    }
    with torch.no_grad():
        reference = core(core_data)["y_hat"][:, -1, 0]
        candidate = classic({"recent": recent}, statics).prediction
    assert torch.equal(reference, candidate)


def test_legacy_names_equal_the_sealed_forcing_column_contract():
    """This equality is what makes the positional x_d assignment verifiable, not assumed."""
    from audit_legacy_checkpoint_bridge_v09 import _legacy_dynamic_input_names_v09
    from formal_input_contract_v09 import DYNAMIC_COLUMNS_V09

    assert DYNAMIC_COLUMNS_V09 == _LEGACY_DYNAMIC_NAMES
    assert _legacy_dynamic_input_names_v09(_legacy_style_config(), expected_count=5) == DYNAMIC_COLUMNS_V09


def test_strict_launch_rejects_report_names_outside_the_sealed_contract():
    from formal_v09_protocol import load_protocol_v09
    from run_formal_strict_stage_v09 import _validate_legacy_bridge_report_v09
    from test_run_formal_strict_stage_v09 import _valid_legacy_report

    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    report = _valid_legacy_report(protocol)
    bindings = report["input_bindings"]
    _validate_legacy_bridge_report_v09(report, protocol, device="cuda:0", input_bindings=bindings)

    report["legacy_dynamic_input_names"] = list(_PROTOCOL_DYNAMIC_NAMES)
    with pytest.raises(ValueError, match="legacy_dynamic_input_names"):
        _validate_legacy_bridge_report_v09(report, protocol, device="cuda:0", input_bindings=bindings)


@pytest.mark.parametrize(
    "dynamic_inputs, expected_count, match",
    [
        ({"1D": list(_LEGACY_DYNAMIC_NAMES)}, 5, "single-frequency"),
        ([list(_LEGACY_DYNAMIC_NAMES)], 5, "flat"),
        (["PRCP(mm/day)", "PRCP(mm/day)", "Tmin(C)", "Tmax(C)", "SRAD(W/m2)"], 5, "unique"),
        (list(_LEGACY_DYNAMIC_NAMES)[:4], 5, "count"),
        ([], 5, "invalid"),
    ],
)
def test_name_deriver_rejects_unsupported_legacy_configs(dynamic_inputs, expected_count, match):
    from audit_legacy_checkpoint_bridge_v09 import _legacy_dynamic_input_names_v09

    with pytest.raises(ValueError, match=match):
        _legacy_dynamic_input_names_v09(_StubLegacyConfig(dynamic_inputs), expected_count=expected_count)
