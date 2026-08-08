"""Pre-registered history-state diagnostics (stage S5).

Every constant checked here was written down in
docs/technical/historical_multiscale_formal_v09_state_diagnostics_preregistration.md before
any result was seen. The tests exist so that none of it can drift afterwards.
"""
from pathlib import Path
import sys

import numpy as np
import pytest
import torch

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))

# The twelve date indices transcribed from the pre-registration table, not computed here.
_PREREGISTERED_DATES = (0, 298, 597, 896, 1195, 1494, 1792, 2091, 2390, 2689, 2988, 3287)


def test_panel_dates_match_the_preregistered_table():
    from state_diagnostics_formal_v09 import panel_date_indices_v09

    assert tuple(panel_date_indices_v09().tolist()) == _PREREGISTERED_DATES


def test_panel_is_basin_major_and_has_531_times_12_rows():
    from state_diagnostics_formal_v09 import panel_keys_v09

    keys = panel_keys_v09(531)
    assert keys.shape == (6_372, 2)
    assert keys.dtype.str == "<i4" and keys.flags.c_contiguous
    assert keys[0].tolist() == [0, 0]
    assert keys[11].tolist() == [0, 3287]
    assert keys[12].tolist() == [1, 0]
    assert np.array_equal(keys[:12, 1], np.array(_PREREGISTERED_DATES, dtype=np.int32))


def test_all_training_keys_cover_every_basin_and_date_in_frozen_order():
    from state_diagnostics_formal_v09 import all_training_keys_v09

    keys = all_training_keys_v09(531)
    assert keys.shape == (1_745_928, 2)
    assert keys.dtype.str == "<i4"
    assert keys[0].tolist() == [0, 0]
    assert keys[3287].tolist() == [0, 3287]
    assert keys[3288].tolist() == [1, 0]


def test_the_five_columns_are_in_the_preregistered_order():
    from state_diagnostics_formal_v09 import state_norms_from_states_v09

    raw_hidden = torch.tensor([[3.0, 4.0]])
    raw_cell = torch.tensor([[-6.0, 8.0]])
    gated_hidden = torch.tensor([[1.0, 0.0]])
    gated_cell = torch.tensor([[0.0, 2.0]])
    columns = state_norms_from_states_v09(raw_hidden, raw_cell, gated_hidden, gated_cell)
    assert columns.dtype.str == "<f4" and columns.flags.c_contiguous
    assert columns[0].tolist() == pytest.approx([5.0, 10.0, 1.0, 2.0, 8.0])


def test_diagnostics_run_only_the_history_encoder():
    """No recent path, no flow head: the returned states must come from the encoder alone."""
    from models_formal_v09 import build_model_v09
    from models_v03 import _append_statics
    from state_diagnostics_formal_v09 import history_states_v09

    model = build_model_v09("continuous_multiscale_history", 100).eval()
    history = torch.randn(3, 120, 7, generator=torch.Generator().manual_seed(7))
    statics = torch.randn(3, 27, generator=torch.Generator().manual_seed(8))
    states = history_states_v09(model, history, statics)
    with torch.no_grad():
        _, (hidden, cell) = model.history_encoder(_append_statics(history, statics))
    assert torch.equal(states["raw_hidden"], hidden.squeeze(0))
    assert torch.equal(states["raw_cell"], cell.squeeze(0))
    # freshly built gates are exactly zero, so the gated states must be exactly zero too
    assert torch.count_nonzero(states["gated_hidden"]) == 0
    assert torch.count_nonzero(states["gated_cell"]) == 0


def test_gate_summary_reports_norm_extreme_and_saturation():
    from models_formal_v09 import build_model_v09
    from state_diagnostics_formal_v09 import gate_summary_v09

    model = build_model_v09("continuous_multiscale_history", 100)
    summary = gate_summary_v09(model)
    assert set(summary) == {"hidden_gate", "cell_gate"}
    for entry in summary.values():
        assert entry["euclidean_norm"] == 0.0
        assert entry["maximum_absolute"] == 0.0
        assert entry["saturated_fraction"] == 0.0
    with torch.no_grad():
        model.hidden_gate.fill_(5.0)
    assert gate_summary_v09(model)["hidden_gate"]["saturated_fraction"] == 1.0


def test_column_summary_uses_float64_and_linear_interpolation():
    from state_diagnostics_formal_v09 import column_summary_v09

    states = np.ascontiguousarray(np.arange(50, dtype="<f4").reshape(10, 5))
    summary = column_summary_v09(states)
    assert summary["sample_count"] == 10
    assert summary["finite_values"] == 50
    first = summary["columns"]["raw_hidden_norm"]
    expected = np.percentile(states[:, 0].astype(np.float64), 95, method="linear")
    assert first["percentile_95"] == pytest.approx(expected)
    assert first["minimum"] == 0.0 and first["maximum"] == 45.0


def test_nonfinite_values_are_counted_and_located():
    from state_diagnostics_formal_v09 import column_summary_v09

    states = np.ascontiguousarray(np.zeros((3, 5), dtype="<f4"))
    states[1, 2] = np.inf
    summary = column_summary_v09(states)
    assert summary["finite_values"] == 14
    assert [1, 2] in summary["nonfinite_positions"]


def _payload(samples=6, all_samples=9):
    generator = np.random.default_rng(11)
    panel_keys = np.ascontiguousarray(
        np.stack((np.repeat(np.arange(samples // 2), 2), np.tile([0, 1], samples // 2)), axis=1).astype("<i4"))
    panel_states = np.ascontiguousarray(generator.normal(size=(samples, 5)).astype("<f4"))
    all_keys = np.ascontiguousarray(
        np.stack((np.repeat(np.arange(all_samples // 3), 3), np.tile([0, 1, 2], all_samples // 3)),
                 axis=1).astype("<i4"))
    all_states = np.ascontiguousarray(generator.normal(size=(all_samples, 5)).astype("<f4"))
    gates = {"hidden_gate": {"euclidean_norm": 0.0, "maximum_absolute": 0.0, "saturated_fraction": 0.0}}
    return {
        10: {"panel_keys": panel_keys, "panel_states": panel_states, "gates": gates},
        20: {"panel_keys": panel_keys, "panel_states": panel_states, "gates": gates},
        30: {"panel_keys": panel_keys, "panel_states": panel_states, "gates": gates,
             "all_keys": all_keys, "all_states": all_states},
    }


def test_seed_directory_holds_every_preregistered_file(tmp_path):
    from state_diagnostics_formal_v09 import write_seed_diagnostics_v09

    manifest = write_seed_diagnostics_v09(tmp_path / "E09-CONTINUOUS_s100", seed=100, checkpoints=_payload())
    written = {p.name for p in (tmp_path / "E09-CONTINUOUS_s100").iterdir()}
    assert written == {
        "epoch010_panel_keys.int32.npy", "epoch010_panel_state_norms.float32.npy",
        "epoch020_panel_keys.int32.npy", "epoch020_panel_state_norms.float32.npy",
        "epoch030_panel_keys.int32.npy", "epoch030_panel_state_norms.float32.npy",
        "epoch030_all_training_keys.int32.npy", "epoch030_all_training_state_norms.float32.npy",
        "summary.json", "manifest.json",
    }
    assert manifest["state_columns"] == [
        "raw_hidden_norm", "raw_cell_norm", "gated_hidden_norm", "gated_cell_norm", "raw_cell_max_abs"]
    assert manifest["training_target_reads"] == 0
    assert manifest["recent_path_executed"] is False and manifest["flow_head_executed"] is False


def test_a_missing_checkpoint_is_refused(tmp_path):
    from state_diagnostics_formal_v09 import StateDiagnosticsError, write_seed_diagnostics_v09

    payload = _payload()
    del payload[20]
    with pytest.raises(StateDiagnosticsError, match="missing checkpoint 20"):
        write_seed_diagnostics_v09(tmp_path / "s100", seed=100, checkpoints=payload)


def test_a_nonempty_directory_is_never_overwritten(tmp_path):
    from state_diagnostics_formal_v09 import write_seed_diagnostics_v09

    target = tmp_path / "s100"
    target.mkdir()
    (target / "stale.npy").write_bytes(b"x")
    with pytest.raises(FileExistsError, match="not empty"):
        write_seed_diagnostics_v09(target, seed=100, checkpoints=_payload())


def test_replay_comparison_accepts_identical_and_rejects_drift(tmp_path):
    from state_diagnostics_formal_v09 import (
        StateDiagnosticsError,
        compare_diagnostic_manifests_v09,
        write_seed_diagnostics_v09,
    )

    payload = _payload()
    first = write_seed_diagnostics_v09(tmp_path / "a", seed=100, checkpoints=payload)
    second = write_seed_diagnostics_v09(tmp_path / "b", seed=100, checkpoints=payload)
    assert compare_diagnostic_manifests_v09(first, second)["arrays_identical"] is True

    drifted = write_seed_diagnostics_v09(tmp_path / "c", seed=100, checkpoints=payload)
    drifted["arrays"]["epoch010_panel_state_norms"]["raw_bytes_sha256"] = "0" * 64
    with pytest.raises(StateDiagnosticsError, match="epoch010_panel_state_norms"):
        compare_diagnostic_manifests_v09(first, drifted)
