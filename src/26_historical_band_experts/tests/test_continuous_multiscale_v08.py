import csv
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import pytest
import torch


IDEA_ROOT = Path(__file__).resolve().parents[1]
CONFIG_ROOT = IDEA_ROOT / "configs"
REPO_ROOT = IDEA_ROOT.parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def _load(name: str) -> dict:
    return json.loads((CONFIG_ROOT / name).read_text(encoding="utf-8"))


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _edge_hash(edges: np.ndarray) -> str:
    payload = json.dumps(edges.tolist(), separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def test_v08_configs_freeze_new_split_geometry_and_gates():
    pilot = _load("continuous_multiscale_c01_v08.json")
    smoke = _load("continuous_multiscale_c01_smoke_v08.json")

    for config in (pilot, smoke):
        assert config["experiment_id"] == "E08-C01"
        assert config["experiment_family"] == "continuous_multiscale_history_v08"
        assert config["basin_file_sha256"] == (
            "3160dad3b22200fdb596164c9f69e4fbe19cc156cfad768beb193efea7b26b65"
        )
        assert config["target_bundle_sha256"] == (
            "d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c"
        )
        assert config["train_period"] == ["1999-10-01", "2004-09-30"]
        assert config["confirmation_period"] == ["2004-10-01", "2006-09-30"]
        assert config["unused_previous_validation_period"] == [
            "2006-10-01",
            "2008-09-30",
        ]
        assert config["expected_training_samples"] == 109_620
        assert config["expected_confirmation_predictions"] == 43_800
        assert config["recent_lags"] == [0, 269]
        assert config["history_lags"] == [270, 3649]
        assert config["history_bins"] == 120
        assert config["history_edge_formula"] == (
            "round(exp(linspace(log(270),log(3650),121)))"
        )
        assert config["history_edges_sha256"] == (
            "bae1f744feca9160181365545a07b445eab269d6afa8817a2e7c99e19f200d73"
        )
        assert config["history_width_range_days"] == [6, 78]
        assert config["history_features"] == [
            "maurer_mean_5",
            "log_duration_coordinate",
            "log_midpoint_lag_coordinate",
        ]
        assert config["state_transfer"] == "zero_gated_history_to_recent_hidden_and_cell"
        assert config["recent_hidden_size"] == 256
        assert config["history_hidden_size"] == 256
        assert config["capacity_control_hidden_size"] == 369
        assert config["candidate_parameter_count"] == 596_737
        assert config["capacity_control_parameter_count"] == 595_198
        assert config["stage1_seed"] == 100
        assert config["conditional_seeds"] == [200, 300]
        assert config["bootstrap_resamples"] == 100_000
        assert config["bootstrap_seed"] == 20_260_728
        assert config["stage1_gates"] == {
            "median_delta_classic_at_least": 0.01,
            "median_delta_capacity_above": 0.0,
            "win_fraction_classic_at_least": 0.55,
            "bootstrap_ci_lower_above": 0.0,
        }
        assert config["formal_evaluation_target_access"] is False
        assert config["earliest_forcing_date"] == "1989-10-04"
        assert _sha256(REPO_ROOT / config["design_file"]) == config["design_file_sha256"]
        assert (
            _sha256(REPO_ROOT / config["prior_mask_summary"])
            == config["prior_mask_summary_sha256"]
        )
        assert (
            _sha256(REPO_ROOT / config["prior_strict_nesting_summary"])
            == config["prior_strict_nesting_summary_sha256"]
        )

    assert pilot["mode"] == "pilot"
    assert pilot["epochs"] == 30
    assert pilot["limit_batches"] == 0
    assert pilot["limit_confirmation_samples"] == 0
    assert pilot["results_root"].endswith("continuous_multiscale_history_v08")

    assert smoke["mode"] == "smoke"
    assert smoke["epochs"] == 2
    assert smoke["limit_batches"] == 2
    assert smoke["limit_confirmation_samples"] == 1024
    assert smoke["results_root"].endswith("continuous_multiscale_history_v08_smoke")


def test_v08_registry_has_unique_reproduction_and_candidate_rows():
    with (IDEA_ROOT / "registry.csv").open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    reproduction = [row for row in rows if row["exp_id"] == "R08-NEST"]
    candidate = [row for row in rows if row["exp_id"] == "E08-C01"]

    assert len(reproduction) == len(candidate) == 1
    assert reproduction[0]["status"] == "complete_exact"
    assert candidate[0]["status"] == "go_internal_multiseed"
    assert candidate[0]["base_config"] == "configs/continuous_multiscale_c01_v08.json"
    assert candidate[0]["run_dir"].endswith("continuous_multiscale_history_v08")
    assert reproduction[0]["best_checkpoint"].endswith(
        "continuous_multiscale_history_v08/strict_nesting_s100/checkpoint.pt"
    )
    assert candidate[0]["best_checkpoint"].endswith(
        "continuous_multiscale_history_v08/continuous_multiscale_history_s100/checkpoint.pt"
    )


def test_v08_edges_cover_every_historical_lag_once():
    from bands_continuous_v08 import continuous_history_edges_v08

    edges = continuous_history_edges_v08()
    widths = np.diff(edges)

    assert edges.shape == (121,)
    assert edges[0] == 270
    assert edges[-1] == 3650
    assert np.all(widths > 0)
    assert int(widths.sum()) == 3380
    assert (int(widths.min()), int(widths.max())) == (6, 78)
    assert _edge_hash(edges) == (
        "bae1f744feca9160181365545a07b445eab269d6afa8817a2e7c99e19f200d73"
    )
    covered = np.concatenate([
        np.arange(int(edges[index]), int(edges[index + 1]))
        for index in range(120)
    ])
    np.testing.assert_array_equal(covered, np.arange(270, 3650))


def test_v08_gather_is_causal_chronological_and_has_exact_coordinates():
    from bands_continuous_v08 import (
        continuous_history_edges_v08,
        forcing_prefix,
        gather_continuous_history_v08,
    )

    time = torch.arange(4000, dtype=torch.float64)
    forcing = torch.stack([time + 10_000 * feature for feature in range(5)], dim=-1)[
        None, :, :
    ]
    target = 3900
    result = gather_continuous_history_v08(
        forcing,
        forcing_prefix(forcing),
        torch.tensor([0]),
        torch.tensor([target]),
    )

    assert tuple(result) == ("recent", "history")
    assert result["recent"].shape == (1, 270, 5)
    assert result["history"].shape == (1, 120, 7)
    torch.testing.assert_close(
        result["recent"][0, :, 0],
        torch.arange(target - 269, target + 1, dtype=torch.float64),
        rtol=0,
        atol=0,
    )

    edges = continuous_history_edges_v08()
    for sequence_index, edge_index in enumerate(reversed(range(120))):
        low = int(edges[edge_index])
        high = int(edges[edge_index + 1])
        expected = forcing[0, target - high + 1:target - low + 1].mean(dim=0)
        torch.testing.assert_close(
            result["history"][0, sequence_index, :5],
            expected,
            rtol=0,
            atol=1e-4,
        )
        duration = (
            np.log(high - low) - np.log(6.0)
        ) / (np.log(78.0) - np.log(6.0))
        midpoint = 0.5 * (low + high - 1)
        age = (np.log(midpoint) - np.log(270.0)) / (
            np.log(3649.0) - np.log(270.0)
        )
        assert result["history"][0, sequence_index, 5].item() == pytest.approx(
            duration,
            abs=1e-7,
        )
        assert result["history"][0, sequence_index, 6].item() == pytest.approx(
            age,
            abs=1e-7,
        )


def test_v08_gather_rejects_missing_history_or_wrong_forcing_width():
    from bands_continuous_v08 import forcing_prefix, gather_continuous_history_v08

    forcing = torch.zeros(1, 4000, 5)
    prefix = forcing_prefix(forcing)
    with pytest.raises(ValueError, match="at least 3649"):
        gather_continuous_history_v08(
            forcing,
            prefix,
            torch.tensor([0]),
            torch.tensor([3648]),
        )
    with pytest.raises(ValueError, match="five Maurer"):
        wrong = torch.zeros(1, 4000, 4)
        gather_continuous_history_v08(
            wrong,
            forcing_prefix(wrong),
            torch.tensor([0]),
            torch.tensor([3900]),
        )


def _dynamic_inputs_v08(
    batch_size: int = 3,
) -> tuple[dict[str, torch.Tensor], torch.Tensor]:
    generator = torch.Generator().manual_seed(2808)
    dynamic = {
        "recent": torch.randn(batch_size, 270, 5, generator=generator),
        "history": torch.randn(batch_size, 120, 7, generator=generator),
    }
    statics = torch.randn(batch_size, 27, generator=generator)
    return dynamic, statics


def test_v08_candidate_structure_counts_and_zero_gate_identity():
    from models_continuous_v08 import (
        ContinuousMultiscaleHistoryLSTM,
        build_model_v08,
    )
    from models_v03 import count_trainable_parameters

    classic = build_model_v08("classic_lstm_256_keyed", seed=100)
    capacity = build_model_v08("classic_lstm_369_keyed", seed=100)
    candidate = build_model_v08("continuous_multiscale_history", seed=100)
    dynamic, statics = _dynamic_inputs_v08()

    assert isinstance(candidate, ContinuousMultiscaleHistoryLSTM)
    assert candidate.history_encoder.input_size == 34
    assert candidate.lstm.input_size == 32
    assert candidate.history_encoder.hidden_size == 256
    assert candidate.lstm.hidden_size == 256
    assert candidate.history_encoder.num_layers == candidate.lstm.num_layers == 1
    assert count_trainable_parameters(classic) == 297_217
    assert count_trainable_parameters(capacity) == 595_198
    assert count_trainable_parameters(candidate) == 596_737
    assert sum(isinstance(module, torch.nn.Linear) for module in candidate.modules()) == 1
    assert torch.count_nonzero(candidate.hidden_gate).item() == 0
    assert torch.count_nonzero(candidate.cell_gate).item() == 0
    assert tuple(candidate.consumed_dynamic_keys) == ("recent", "history")
    for key, value in candidate.lstm.state_dict().items():
        assert torch.equal(value, classic.lstm.state_dict()[key])
    for key, value in candidate.head.state_dict().items():
        assert torch.equal(value, classic.head.state_dict()[key])

    classic.train()
    candidate.train()
    context = (100, 1, 0)
    expected = classic(dynamic, statics, dropout_context=context).prediction
    actual = candidate(dynamic, statics, dropout_context=context).prediction
    assert torch.equal(actual, expected)
    assert actual.shape == (3,)


def test_v08_disabled_history_is_an_exact_active_parameter_nest():
    from models_continuous_v08 import build_model_v08
    from train_strict_v06 import active_named_parameters

    classic = build_model_v08("classic_lstm_256_keyed", seed=100)
    classic_rng = torch.get_rng_state().clone()
    nested = build_model_v08("nested_history_disabled", seed=100)
    nested_rng = torch.get_rng_state().clone()
    dynamic, statics = _dynamic_inputs_v08()
    recent_only = {"recent": dynamic["recent"]}

    classic_parameters = active_named_parameters(classic)
    nested_parameters = active_named_parameters(nested)
    assert [name for name, _ in classic_parameters] == [
        name for name, _ in nested_parameters
    ]
    for (_, expected), (_, actual) in zip(classic_parameters, nested_parameters):
        assert torch.equal(actual, expected)
    assert torch.equal(classic_rng, nested_rng)
    assert tuple(nested.consumed_dynamic_keys) == ("recent",)
    assert all(
        not parameter.requires_grad
        for name, parameter in nested.named_parameters()
        if name.startswith("history_encoder") or name.endswith("_gate")
    )
    classic.train()
    nested.train()
    context = (100, 1, 0)
    assert torch.equal(
        classic(recent_only, statics, dropout_context=context).prediction,
        nested(recent_only, statics, dropout_context=context).prediction,
    )


def test_v08_zero_gates_delay_history_encoder_gradient_until_gate_updates():
    from models_continuous_v08 import build_model_v08

    candidate = build_model_v08("continuous_multiscale_history", seed=100)
    dynamic, statics = _dynamic_inputs_v08(batch_size=4)
    target = torch.randn(4, generator=torch.Generator().manual_seed(81))
    optimizer = torch.optim.Adam(candidate.parameters(), lr=0.001)
    candidate.train()

    first = candidate(dynamic, statics, dropout_context=(100, 1, 0)).prediction
    first.square().add(target.square()).mean().backward()
    assert candidate.hidden_gate.grad is not None
    assert candidate.cell_gate.grad is not None
    assert float(candidate.hidden_gate.grad.norm()) > 0
    assert float(candidate.cell_gate.grad.norm()) > 0
    history_gradient = candidate.history_encoder.weight_ih_l0.grad
    assert history_gradient is not None
    assert torch.count_nonzero(history_gradient).item() == 0
    optimizer.step()
    optimizer.zero_grad(set_to_none=True)

    second = candidate(dynamic, statics, dropout_context=(100, 1, 1)).prediction
    second.square().add(target.square()).mean().backward()
    history_gradient = candidate.history_encoder.weight_ih_l0.grad
    assert history_gradient is not None
    assert float(history_gradient.norm()) > 0


def test_v08_candidate_rejects_unknown_history_mode():
    from models_continuous_v08 import build_model_v08

    candidate = build_model_v08("continuous_multiscale_history", seed=100)
    dynamic, statics = _dynamic_inputs_v08(batch_size=2)
    with pytest.raises(ValueError, match="history mode"):
        candidate(dynamic, statics, history_mode="wrong")


def _synthetic_pack_v08():
    from data import DataPack

    dates = pd.date_range("1989-10-04", "2006-09-30", freq="D")
    generator = np.random.default_rng(2808)
    forcing = generator.normal(size=(1, len(dates), 5)).astype(np.float32)
    time = np.arange(len(dates), dtype=np.float32)
    discharge = (
        2.0
        + 0.4 * np.sin(time / 23.0)
        + 0.1 * forcing[0, :, 0]
    )[None, :].astype(np.float32)
    discharge[:, dates < pd.Timestamp("1999-10-01")] = np.nan
    statics = generator.normal(size=(1, 27)).astype(np.float32)
    return DataPack(
        basins=("00000001",),
        dates=dates,
        forcing=forcing,
        discharge=discharge,
        statics=statics,
    )


def _training_config_v08() -> dict:
    config = _load("continuous_multiscale_c01_smoke_v08.json")
    config["batch_size"] = 4
    config["confirmation_batch_size"] = 4
    config["limit_batches"] = 2
    config["limit_confirmation_samples"] = 8
    return config


def test_v08_split_counts_and_scaler_exclude_confirmation_values():
    from train_continuous_v08 import (
        compute_scaler_v08,
        split_target_indices_v08,
    )

    dates = pd.date_range("1999-10-01", "2006-09-30", freq="D")
    forcing = np.ones((1, len(dates), 5), dtype=np.float32)
    discharge = np.full((1, len(dates)), 2.0, dtype=np.float32)
    statics = np.arange(27, dtype=np.float32)[None, :]
    confirmation = dates >= pd.Timestamp("2004-10-01")
    forcing[:, confirmation, :] = 1_000_000.0
    discharge[:, confirmation] = 1_000_000.0
    config = _training_config_v08()

    train_basins, train_times = split_target_indices_v08(
        dates,
        discharge,
        split="train",
        config=config,
        require_history=False,
    )
    confirm_basins, confirm_times = split_target_indices_v08(
        dates,
        discharge,
        split="confirmation",
        config=config,
        require_history=False,
    )
    scaler = compute_scaler_v08(forcing, discharge, statics, dates, config)

    assert len(train_basins) == len(train_times) == 1827
    assert len(confirm_basins) == len(confirm_times) == 730
    np.testing.assert_array_equal(dates[train_times].min(), pd.Timestamp("1999-10-01"))
    np.testing.assert_array_equal(dates[train_times].max(), pd.Timestamp("2004-09-30"))
    np.testing.assert_array_equal(dates[confirm_times].min(), pd.Timestamp("2004-10-01"))
    np.testing.assert_array_equal(dates[confirm_times].max(), pd.Timestamp("2006-09-30"))
    np.testing.assert_allclose(scaler["dynamic_center"], np.ones(5))
    assert scaler["q_center"] == 2.0
    np.testing.assert_allclose(scaler["per_basin_q_std"], np.zeros(1))


@pytest.mark.parametrize(
    ("key", "value"),
    [
        ("train_period", ["1999-10-01", "2005-09-30"]),
        ("confirmation_period", ["2005-10-01", "2006-09-30"]),
        ("history_bins", 119),
        ("history_edges_sha256", "0" * 64),
        ("state_transfer", "direct"),
        ("candidate_parameter_count", 596_738),
        ("formal_evaluation_target_access", True),
    ],
)
def test_v08_config_rejects_scientific_or_access_drift(key, value):
    from train_continuous_v08 import validate_config_v08

    config = _training_config_v08()
    config[key] = value
    with pytest.raises(ValueError, match=key):
        validate_config_v08(config)


@pytest.mark.parametrize(
    "variant",
    (
        "classic_lstm_256_keyed",
        "classic_lstm_369_keyed",
        "continuous_multiscale_history",
    ),
)
def test_v08_tiny_run_writes_recomputable_artifacts(tmp_path, variant):
    from metrics import per_basin_nse
    from train_continuous_v08 import run_experiment_v08

    output = tmp_path / variant
    manifest = run_experiment_v08(
        pack=_synthetic_pack_v08(),
        config=_training_config_v08(),
        variant=variant,
        seed=100,
        output_dir=output,
        device="cpu",
    )

    assert manifest["status"] == "complete"
    assert manifest["optimizer_steps_total"] == 4
    assert manifest["n_confirmation_predictions"] == 8
    assert manifest["confirmation_period"] == ["2004-10-01", "2006-09-30"]
    assert manifest["data_access"] == {
        "raw_observed_discharge_reads": 0,
        "target_bundle_interface": True,
        "formal_evaluation_target_access": False,
        "unused_previous_validation_target_uses": 0,
        "earliest_forcing_date": "1989-10-04",
    }
    assert {path.name for path in output.iterdir()} == {
        "config.json",
        "checkpoint.pt",
        "predictions.csv",
        "per_basin_metrics.csv",
        "training_diagnostics.json",
        "manifest.json",
    }
    predictions = pd.read_csv(output / "predictions.csv", dtype={"basin": str})
    metrics = pd.read_csv(output / "per_basin_metrics.csv", dtype={"basin": str})
    pd.testing.assert_frame_equal(metrics, per_basin_nse(predictions), check_exact=True)
    diagnostics = json.loads(
        (output / "training_diagnostics.json").read_text(encoding="utf-8")
    )
    if variant == "continuous_multiscale_history":
        assert diagnostics["history_first_nonzero_gradient_step"] in (2, 3)
        assert diagnostics["history_gradient_norm"] > 0
        assert diagnostics["hidden_gate_norm"] > 0
        assert diagnostics["cell_gate_norm"] > 0
    else:
        assert diagnostics["history_first_nonzero_gradient_step"] is None
    for name, expected in manifest["artifacts"].items():
        assert _sha256(output / name) == expected
    with pytest.raises(FileExistsError, match="not empty"):
        run_experiment_v08(
            pack=_synthetic_pack_v08(),
            config=_training_config_v08(),
            variant=variant,
            seed=100,
            output_dir=output,
            device="cpu",
        )


def test_v08_tiny_strict_reproduction_is_exact(tmp_path):
    from train_continuous_v08 import run_strict_reproduction_v08

    output = tmp_path / "strict"
    manifest = run_strict_reproduction_v08(
        pack=_synthetic_pack_v08(),
        config=_training_config_v08(),
        seed=100,
        output_dir=output,
        device="cpu",
    )

    assert manifest["status"] == "complete_exact"
    assert manifest["lockstep_exact"] is True
    assert manifest["optimizer_steps_total"] == 4
    assert manifest["n_confirmation_predictions"] == 8
    assert manifest["max_prediction_abs_difference"] == 0.0
    predictions = pd.read_csv(output / "predictions.csv", dtype={"basin": str})
    assert np.array_equal(
        predictions["qsim_classic"].to_numpy(),
        predictions["qsim_nested"].to_numpy(),
    )
    summary = json.loads((output / "summary.json").read_text(encoding="utf-8"))
    assert summary["status"] == "complete_exact"
    assert summary["max_prediction_abs_difference"] == 0.0
    for name, expected in manifest["artifacts"].items():
        assert _sha256(output / name) == expected


def test_v08_stage1_analysis_applies_all_four_frozen_gates():
    from analyze_continuous_v08 import evaluate_stage1_v08

    paired = pd.DataFrame({
        "basin": ["a", "b", "c", "d"],
        "nse_classic": [0.50, 0.60, 0.70, 0.80],
        "nse_capacity": [0.50, 0.60, 0.70, 0.80],
        "nse_candidate": [0.52, 0.62, 0.72, 0.82],
    })
    config = _training_config_v08()
    result = evaluate_stage1_v08(
        paired,
        config["stage1_gates"],
        bootstrap_resamples=1000,
        bootstrap_seed=2808,
    )

    assert result["passed"] is True
    assert result["criteria"] == {
        "median_delta_classic_at_least": True,
        "median_delta_capacity_above": True,
        "win_fraction_classic_at_least": True,
        "bootstrap_ci_lower_above": True,
    }
    assert result["median_delta_classic"] == pytest.approx(0.02)
    assert result["median_delta_capacity"] == pytest.approx(0.02)
    assert result["win_fraction_classic"] == 1.0
    assert result["bootstrap_median_delta_ci95"][0] > 0


def test_v08_stage1_rejects_effect_capacity_win_or_uncertainty_failure():
    from analyze_continuous_v08 import evaluate_stage1_v08

    paired = pd.DataFrame({
        "basin": [str(index) for index in range(60)],
        "nse_classic": np.full(60, 0.6),
        "nse_capacity": np.full(60, 0.62),
        "nse_candidate": np.r_[
            np.full(32, 0.612),
            np.full(28, 0.588),
        ],
    })
    config = _training_config_v08()
    result = evaluate_stage1_v08(
        paired,
        config["stage1_gates"],
        bootstrap_resamples=2000,
        bootstrap_seed=2808,
    )

    assert result["passed"] is False
    assert result["criteria"]["median_delta_classic_at_least"] is True
    assert result["criteria"]["median_delta_capacity_above"] is False
    assert result["criteria"]["win_fraction_classic_at_least"] is False
    assert result["criteria"]["bootstrap_ci_lower_above"] is False


def test_v08_analysis_rejects_prediction_key_or_observation_mismatch():
    from analyze_continuous_v08 import assert_same_targets_v08

    reference = pd.DataFrame({
        "basin": ["a", "a"],
        "date": ["2005-01-01", "2005-01-02"],
        "qobs": [1.0, 2.0],
        "qsim": [1.1, 1.9],
    })
    wrong_key = reference.copy()
    wrong_key.loc[1, "date"] = "2005-01-03"
    wrong_observation = reference.copy()
    wrong_observation.loc[1, "qobs"] = 2.5

    with pytest.raises(ValueError, match="keys"):
        assert_same_targets_v08(reference, wrong_key, "wrong_key")
    with pytest.raises(ValueError, match="observations"):
        assert_same_targets_v08(reference, wrong_observation, "wrong_observation")


def test_v08_tiny_diagnostic_and_analysis_are_recomputable(tmp_path):
    from analyze_continuous_v08 import (
        analyze_results_v08,
        run_history_gate_diagnostic_v08,
    )
    from metrics import per_basin_nse
    from train_continuous_v08 import run_experiment_v08

    config = _training_config_v08()
    root = tmp_path / "continuous_multiscale_history_v08_smoke"
    config["results_root"] = str(root)
    pack = _synthetic_pack_v08()
    for variant in config["variants"]:
        run_experiment_v08(
            pack=pack,
            config=config,
            variant=variant,
            seed=100,
            output_dir=root / f"{variant}_s100",
            device="cpu",
        )
    diagnostic = run_history_gate_diagnostic_v08(
        pack=pack,
        config=config,
        seed=100,
        candidate_run_dir=root / "continuous_multiscale_history_s100",
        output_dir=root / "history_gate_diagnostic_s100",
        device="cpu",
    )
    assert diagnostic["status"] == "complete"
    assert diagnostic["causal_attribution_allowed"] is False
    for mode in config["diagnostic_modes"]:
        predictions = pd.read_csv(
            root / "history_gate_diagnostic_s100" / f"{mode}_predictions.csv",
            dtype={"basin": str},
        )
        metrics = pd.read_csv(
            root / "history_gate_diagnostic_s100" / f"{mode}_per_basin_metrics.csv",
            dtype={"basin": str},
        )
        pd.testing.assert_frame_equal(metrics, per_basin_nse(predictions), check_exact=True)

    summary = analyze_results_v08(config)
    assert summary["status"] in (
        "complete_stage1_no_go",
        "complete_stage1_go_pending_multiseed",
    )
    assert summary["stage1"]["n_basins"] == 1
    paired = pd.read_csv(root / "paired_per_basin_s100.csv", dtype={"basin": str})
    assert len(paired) == 1
    analysis_manifest = json.loads(
        (root / "analysis_manifest.json").read_text(encoding="utf-8")
    )
    for name, expected in analysis_manifest["artifacts"].items():
        assert _sha256(root / name) == expected
