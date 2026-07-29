"""Frozen scientific and execution protocol for the formal version 09 experiment."""
from __future__ import annotations

from collections.abc import Mapping
import hashlib
import json
from pathlib import Path

import numpy as np


_PROTOCOL_ID = "P09-FORMAL"
_SEEDS = list(range(100, 801, 100))
_EDGE_SHA256 = "55bbdaf654e7ea2b8959cc5dd62de98e4631c272ffe9d7f4efeae9cb7240927b"
_AUTHORIZATION = {
    "protocol_implementation": True,
    "synthetic_tests": True,
    "formal_target_bundle_generation": False,
    "training": False,
    "formal_prediction_generation": False,
    "official_scoring": False,
}
_MEMORY_SAFETY = {
    "long_job_start_available_gib_min": 12.0,
    "long_job_start_available_fraction": 0.4,
    "runtime_reserve_gib_min": 8.0,
    "runtime_reserve_fraction": 0.25,
    "process_rss_gib_max": 6.0,
    "process_rss_fraction_max": 0.2,
    "single_allocation_mib_max": 512.0,
    "single_allocation_fraction_max": 0.02,
    "maximum_batch_size": 256,
    "full_window_materialization_forbidden": True,
}
_LEGACY_REFERENCE_RUNS = [
    {
        "seed": 100,
        "run_id": "lstm_cudalstm_maurer_s100_2026_0616_1513_ep30",
        "config_sha256": "e873fea95ee215179f284f14ec900068c5151f41b4622a342e59255aa642e4f9",
        "checkpoint_epoch030_sha256": "f7a4242f233304a309f6e4b225e539ca5b4f76089dbe3b7a96c88ce5a18d5654",
    },
    {
        "seed": 200,
        "run_id": "lstm_cudalstm_maurer_s200_2026_0616_1831_ep30",
        "config_sha256": "e8e0ba4a1d6ffb585d5d72171710e7034ecd750b34387c7408796bf41f0c3531",
        "checkpoint_epoch030_sha256": "fcc4b7322173f156ee5f05b9377ac865ef7f16a96237097253d0f7f9936e5b61",
    },
    {
        "seed": 300,
        "run_id": "lstm_cudalstm_maurer_s300_2026_0616_2016_ep30",
        "config_sha256": "cddcfc92d748c9149b276eb8529d01335bf56b85405508b01444617e720267e6",
        "checkpoint_epoch030_sha256": "f2fc10468e1926507d2395f1f8f50bf8af5ecb04f5fc4c3cbff8d49482d579c9",
    },
    {
        "seed": 400,
        "run_id": "lstm_cudalstm_maurer_s400_2026_0616_2209_ep30",
        "config_sha256": "d51c397da039e63e3f1709ecc351890d598d221c657785e9aacab9b4b5df32fe",
        "checkpoint_epoch030_sha256": "536cb3f927983dfb261cbb0f83d2bfce3fb84900bf1967e0177a1d2ac9fa3fc5",
    },
    {
        "seed": 500,
        "run_id": "lstm_cudalstm_maurer_s500_2026_0616_2341_ep30",
        "config_sha256": "ead6fd313f1815175bcafeebc4702e1e4a06cd651dde3a878a9c9421b7baf7eb",
        "checkpoint_epoch030_sha256": "cd24cd14465d4e70b2a279026970ab65e6a22fb305414e6083164cae382a1966",
    },
    {
        "seed": 600,
        "run_id": "lstm_cudalstm_maurer_s600_2026_0617_0112_ep30",
        "config_sha256": "e20065d979f6a358675213b63e9a6b61ef01851bf2a8406b6025305e7c588f88",
        "checkpoint_epoch030_sha256": "daf3e05a264cb574736a1451ed7ecb53f8846975ad5bd359db6b021703c4e34b",
    },
    {
        "seed": 700,
        "run_id": "lstm_cudalstm_maurer_s700_2026_0617_0243_ep30",
        "config_sha256": "33fb6f17537181ed29412cd5b8c868976e5e4e248c034ff9200b36dea8101960",
        "checkpoint_epoch030_sha256": "aa922f3abe8aff6884d72f83e70ea2a1744bd38687c03ff095cc2846b0343424",
    },
    {
        "seed": 800,
        "run_id": "lstm_cudalstm_maurer_s800_2026_0617_0414_ep30",
        "config_sha256": "e90a565f7b33ae8f785a17107835677649349d504509ca77955f84c9a30e0da6",
        "checkpoint_epoch030_sha256": "80a30be47fe23a73d51e1d519a42c04d004cd7608959de1e004928a616cdf963",
    },
]
_EXPECTED_SCALARS = {
    "protocol_id": _PROTOCOL_ID,
    "protocol_family": "historical_multiscale_formal_v09",
    "strict_reproduction_id": "R09-NEST",
    "classic_control_id": "B09-CLASSIC",
    "capacity_control_id": "B09-CAPACITY",
    "candidate_id": "E09-CONTINUOUS",
    "sealed_scoring_id": "S09-SEALED",
    "track": "track0_forcing_only",
    "basin_file": "src/fair_benchmark/frozen/track0_forcing_only_basins.txt",
    "basin_file_sha256": "cd2d3d466aca736fcd32042d2b0bde3d0b58e42ba37fe552d97480bd914b9e85",
    "basin_count": 531,
    "forcing_product": "maurer",
    "dynamic_input_count": 5,
    "static_attribute_count": 27,
    "static_file": "src/fair_benchmark/frozen/bundle/track0_statics.csv",
    "static_file_sha256": "085e8b5e0e56b42bfe7e6d012ebb6f2f56681059b60c61c04b835b207864a1f2",
    "expected_forcing_dates": 10_501,
    "expected_forcing_rows": 5_576_031,
    "expected_training_dates_per_basin": 3_288,
    "expected_training_samples": 1_745_928,
    "expected_evaluation_dates_per_basin": 3_652,
    "expected_evaluation_predictions": 1_939_212,
    "normalization_scope": "training_target_dates_only",
    "causal_window_days": 3_562,
    "history_bins": 120,
    "history_edge_formula": "round(exp(linspace(log(270),log(3562),121)))",
    "history_edges_sha256": _EDGE_SHA256,
    "state_transfer": "zero_gated_history_to_recent_hidden_and_cell",
    "classic_hidden_size": 256,
    "capacity_control_hidden_size": 369,
    "history_hidden_size": 256,
    "classic_parameter_count": 297_217,
    "capacity_control_parameter_count": 595_198,
    "candidate_parameter_count": 596_737,
    "single_flow_output": True,
    "epochs": 30,
    "batch_size": 256,
    "optimizer_steps_per_epoch": 6_821,
    "optimizer_steps_total": 204_630,
    "optimizer": "Adam",
    "gradient_clip": 1.0,
    "initial_forget_bias": 5.0,
    "output_dropout": 0.4,
    "dropout_stream": "core_torch_rng_full_recent_sequence",
    "formal_evaluation_target_access": False,
}


def history_edges_v09() -> np.ndarray:
    """Return the frozen 121 edges spanning historical lags 270 through 3561."""
    edges = np.rint(np.exp(np.linspace(np.log(270.0), np.log(3562.0), 121))).astype(np.int64)
    edges[0] = 270
    edges[-1] = 3_562
    if edges.shape != (121,) or np.any(np.diff(edges) <= 0):
        raise RuntimeError("version 09 history edges are not strictly increasing")
    payload = json.dumps(edges.tolist(), separators=(",", ":")).encode("utf-8")
    if hashlib.sha256(payload).hexdigest() != _EDGE_SHA256:
        raise RuntimeError("version 09 history-edge hash drift")
    return edges


def learning_rate_for_epoch_v09(epoch: int) -> float:
    """Return the clean-classic learning rate for an epoch in the frozen 30-epoch run."""
    epoch = int(epoch)
    if not 1 <= epoch <= 30:
        raise ValueError("epoch must be from 1 through 30")
    if epoch <= 10:
        return 0.001
    if epoch <= 20:
        return 0.0005
    return 0.0001


def load_protocol_v09(path: str | Path) -> dict:
    """Load and validate one version 09 JSON protocol snapshot."""
    path = Path(path)
    config = json.loads(path.read_text(encoding="utf-8"))
    validate_protocol_v09(config)
    return config


def _require_equal(config: Mapping, key: str, expected) -> None:
    if config.get(key) != expected:
        raise ValueError(f"{key} must be frozen at {expected!r}, got {config.get(key)!r}")


def validate_protocol_v09(config: Mapping) -> None:
    """Reject scientific, authorization, or resource-policy drift."""
    for key, expected in _EXPECTED_SCALARS.items():
        _require_equal(config, key, expected)
    _require_equal(config, "train_period", ["1999-10-01", "2008-09-30"])
    _require_equal(config, "evaluation_period", ["1989-10-01", "1999-09-30"])
    _require_equal(config, "forcing_period", ["1980-01-01", "2008-09-30"])
    _require_equal(config, "dynamic_inputs", ["prcp", "tmin", "tmax", "srad", "vp"])
    _require_equal(
        config,
        "known_forcing_data_issue",
        {
            "evidence_scope": "prior_read_only_audit_of_required_1980_2008_raw_maurer_rows",
            "condition": "tmin_equals_tmax_elementwise",
            "named_dynamic_columns": 5,
            "independent_dynamic_value_columns": 4,
            "handling": "preserve_frozen_named_columns_and_report_without_posthoc_repair",
        },
    )
    _require_equal(
        config,
        "training_target_interface",
        {
            "period": ["1999-10-01", "2008-09-30"],
            "bundle_generated": False,
            "generation_authorized": False,
        },
    )
    _require_equal(
        config,
        "forbidden_inputs",
        [
            "formal_evaluation_observed_discharge",
            "usgs_streamflow",
            "camels_hydro",
            "observed_discharge_derived_hydrologic_signatures",
            "future_forcing",
            "other_forcing_products",
            "other_model_outputs",
            "test_period_or_full_dataset_statistics",
        ],
    )
    _require_equal(config, "recent_lags", [0, 269])
    _require_equal(config, "history_lags", [270, 3_561])
    _require_equal(config, "history_width_range_days", [6, 76])
    _require_equal(
        config,
        "history_features",
        ["maurer_mean_5", "log_duration_coordinate", "log_midpoint_lag_coordinate"],
    )
    _require_equal(config, "learning_rate_schedule", {"1": 0.001, "11": 0.0005, "21": 0.0001})
    _require_equal(config, "seeds", _SEEDS)
    _require_equal(
        config,
        "ensemble",
        {
            "operation": "arithmetic_mean",
            "accumulator_dtype": "float64",
            "seed_order": _SEEDS,
        },
    )
    _require_equal(
        config,
        "strict_nesting",
        {
            "same_environment_absolute_tolerance": 0.0,
            "same_environment_relative_tolerance": 0.0,
            "independent_environment_prediction_absolute_tolerance": 1e-6,
            "independent_environment_prediction_relative_tolerance": 0.0,
        },
    )
    _require_equal(
        config,
        "core_classic_compatibility",
        {
            "reference_model": "neuralhydrology.modelzoo.cudalstm.CudaLSTM",
            "reference_code_commit": "1f9804e359283f1963bcf0aa9ffab213538c16e8",
            "actual_run_recorded_commit_prefix": "1f9804e",
            "actual_run_id": "lstm_cudalstm_maurer_s100_2026_0616_1513_ep30",
            "actual_run_config_sha256": (
                "e873fea95ee215179f284f14ec900068c5151f41b4622a342e59255aa642e4f9"
            ),
            "tracked_reference_config": (
                "src/lstm_fair_531/configs/lstm_cudalstm_maurer_531_s100.yml"
            ),
            "tracked_reference_config_added_commit": (
                "49433803a6a598fde068f732834e6f918ee826f4"
            ),
            "tracked_reference_config_lf_sha256": (
                "83b3acd908d44397de671d01b172e3e9b92cc0c6efa7bd539c7017449d2c102f"
            ),
            "cudalstm_lf_sha256": (
                "27f2e17d3f388a9b7ef25a261ec33007c328985d8c2a879592794c3fb8dede01"
            ),
            "inputlayer_lf_sha256": (
                "b89b8eadbebaebe4f01b1bffaf64513c89d69f5726576f32e5a6bd83f4cbcbcb"
            ),
            "head_lf_sha256": (
                "93331b1bf913857bb6f34deba41dd608c720c862209b6c821dd940f3a7b1282b"
            ),
            "dropout_placement": "full_recent_sequence_before_regression_head",
            "same_process_tolerance": 0.0,
        },
    )
    _require_equal(
        config,
        "success_gates",
        {
            "full_coverage_required": True,
            "public_median_paired_delta_at_least": 0.01,
            "wilcoxon_p_below": 0.05,
            "bootstrap_ci_lower_above": 0.0,
            "secret_holdout_median_delta_at_least": 0.005,
            "secret_retained_public_fraction_at_least": 0.5,
        },
    )
    _require_equal(config, "memory_safety", _MEMORY_SAFETY)
    _require_equal(config, "authorization", _AUTHORIZATION)
    _require_equal(
        config,
        "legacy_reference",
        {
            "description": "frozen eight-seed classic LSTM ensemble; scoring reference only",
            "median_nse": 0.759225,
            "training_trajectory_reproduction_claimed": False,
            "recorded_code_commit_prefix": "1f9804e",
            "resolved_code_commit": "1f9804e359283f1963bcf0aa9ffab213538c16e8",
            "runs": _LEGACY_REFERENCE_RUNS,
        },
    )
    _require_equal(
        config,
        "legacy_frozen_manifest_issue",
        {
            "file": "src/fair_benchmark/frozen/track0_forcing_only.spec.yaml",
            "manifest_sha256": "1beb31af1e7d1131370ffe6c3f829b897869599cb75dbd42917265da0e1a9c00",
            "windows_bytes_sha256": "8fb707cb5e2ec0f8edbf3f191f9ce836d259e8a31286466da63e6e62791388fb",
            "lf_normalized_sha256": "0439eb55cd059300eca9c90c20aaed1901cd8be5e9b556bd4ae2e4609a2f5d5e",
            "must_be_resolved_before_scoring_authorization": True,
        },
    )

    edges = history_edges_v09()
    widths = np.diff(edges)
    if int(widths.sum()) != 3_292 or (int(widths.min()), int(widths.max())) != (6, 76):
        raise ValueError("history edge geometry drift")
    if config["expected_training_samples"] != config["basin_count"] * config["expected_training_dates_per_basin"]:
        raise ValueError("expected training sample count is inconsistent")
    if (
        config["expected_evaluation_predictions"]
        != config["basin_count"] * config["expected_evaluation_dates_per_basin"]
    ):
        raise ValueError("expected evaluation prediction count is inconsistent")
    if config["optimizer_steps_per_epoch"] != int(
        np.ceil(config["expected_training_samples"] / config["batch_size"])
    ):
        raise ValueError("optimizer steps per epoch are inconsistent")
    if config["optimizer_steps_total"] != config["epochs"] * config["optimizer_steps_per_epoch"]:
        raise ValueError("total optimizer step count is inconsistent")
    if config["capacity_control_parameter_count"] >= config["candidate_parameter_count"]:
        raise ValueError("capacity control must remain slightly smaller than the candidate")
    relative_difference = (
        config["candidate_parameter_count"] - config["capacity_control_parameter_count"]
    ) / config["candidate_parameter_count"]
    if abs(relative_difference - float(config.get("parameter_count_relative_difference", -1))) > 5e-7:
        raise ValueError("parameter_count_relative_difference is inconsistent")
