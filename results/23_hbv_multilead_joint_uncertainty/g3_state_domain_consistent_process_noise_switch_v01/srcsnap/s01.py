"""Run the frozen clean process-noise switch assimilation experiment."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import platform
import shutil
import subprocess
import sys
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

import matplotlib
import matplotlib.image as matplotlib_image
import numpy as np
import scipy


matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SRC_ROOT = PROJECT_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from hbv_multilead_joint_uncertainty.state_domain_consistent_process_noise_switch import (  # noqa: E402
    build_lower_groundwater_process_covariances,
    build_probability_response_curves,
    run_state_domain_consistent_process_noise_switch,
    summarize_full_stage_accuracy,
    summarize_switch_response,
)
from hbv_multilead_joint_uncertainty.synthetic_truth import (  # noqa: E402
    PARAMETER_NAMES,
)


EXPERIMENT_ID = "g3_state_domain_consistent_process_noise_switch_v01"
DEFAULT_CONFIG = (
    PROJECT_ROOT
    / "src/hbv_multilead_joint_uncertainty/configs"
    / f"{EXPERIMENT_ID}.json"
)
DEFAULT_OUTPUT = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty"
    / EXPERIMENT_ID
)
DEFAULT_VERIFICATION = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty"
    / f"{EXPERIMENT_ID}_independent_verification_v01"
)
PROCESS_IDS = (
    "lower_groundwater_low",
    "lower_groundwater_medium",
    "lower_groundwater_high",
)
PROCESS_STANDARD_DEVIATIONS = (1.0, 4.0, 16.0)
PROCESS_VARIANCES = (1.0, 16.0, 256.0)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _read_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read JSON contract: {path}") from exc
    if not isinstance(value, dict):
        raise ValueError("frozen experiment contract must be a JSON object")
    return value


def _critical_contract(config: dict) -> dict:
    return {
        "experiment_id": config.get("experiment_id"),
        "status": config.get("status"),
        "fixed_parameter_id": config.get("fixed_parameter_id"),
        "state_contract": config.get("state_contract"),
        "process_noise_candidates": config.get("process_noise_candidates"),
        "forcing": config.get("forcing"),
        "population": config.get("population"),
        "truth_trial_stage_orders": config.get("truth_trial_stage_orders"),
        "seeds": config.get("seeds"),
        "filter": config.get("filter"),
        "truth_domain_gate": config.get("truth_domain_gate"),
        "response_rule": config.get("response_rule"),
        "forbidden_scope": config.get("forbidden_scope"),
        "result_relative_path": config.get("result_relative_path"),
        "verification_relative_path": config.get("verification_relative_path"),
    }


def _expected_critical_contract() -> dict:
    return {
        "experiment_id": EXPERIMENT_ID,
        "status": "frozen_before_run",
        "fixed_parameter_id": "trained_center",
        "state_contract": {
            "state_count": 15,
            "perturbed_state_index": 4,
            "perturbed_state_name": "SLZ",
            "perturbed_state_plain_name": "lower groundwater storage",
            "all_other_state_noise_variances": 0.0,
            "truth_state_continuous_across_switches": True,
            "state_reset_at_switch": False,
        },
        "process_noise_candidates": [
            {
                "process_id": identifier,
                "plain_name": plain_name,
                "standard_deviation_mm_day": standard_deviation,
                "variance_mm2_day2": variance,
            }
            for identifier, plain_name, standard_deviation, variance in zip(
                PROCESS_IDS,
                ("low process noise", "medium process noise", "high process noise"),
                PROCESS_STANDARD_DEVIATIONS,
                PROCESS_VARIANCES,
            )
        ],
        "forcing": {
            "warmup_days": 90,
            "assimilation_days": 540,
            "rain_floor_mm_day": 5.0,
            "rain_gamma_shape": 0.8,
            "rain_gamma_scale_mm_day": 4.0,
            "potential_evaporation_mm_day": 2.0,
            "temperature_celsius": 10.0,
        },
        "population": {
            "matched_block_count": 8,
            "truth_trial_count": 3,
            "stage_length_days": 180,
            "stage_count": 3,
            "switch_count_per_trial": 2,
            "event_count": 48,
            "events_per_directed_transition": 16,
        },
        "truth_trial_stage_orders": [
            [PROCESS_IDS[1], PROCESS_IDS[2], PROCESS_IDS[0]],
            [PROCESS_IDS[2], PROCESS_IDS[0], PROCESS_IDS[1]],
            [PROCESS_IDS[0], PROCESS_IDS[1], PROCESS_IDS[2]],
        ],
        "seeds": {
            "forcing": list(range(3501001, 3501009)),
            "process_noise": list(range(3502001, 3502009)),
            "observation_noise": list(range(3503001, 3503009)),
        },
        "filter": {
            "candidate_count": 3,
            "interaction_mode": "full",
            "factor_transition_stay_probability": 0.98,
            "initial_covariance_fraction": 0.001,
            "global_posterior_output": (
                "posterior-probability-weighted fifteen-state state and "
                "covariance after every update"
            ),
        },
        "truth_domain_gate": {
            "projection_event_count_required": 0,
            "maximum_absolute_projection_adjustment_required": 0.0,
            "failure_action": "stop_without_scientific_conclusion",
        },
        "response_rule": {
            "response_window_days": 30,
            "consecutive_top_ranked_days": 5,
            "minimum_successful_events_per_directed_transition": 13,
            "event_count_per_directed_transition": 16,
            "confidence_level": 0.95,
            "minimum_exact_interval_lower_bound_exclusive": 0.5,
            "success_definition": (
                "the new true process-noise candidate is top-ranked for five "
                "consecutive days with the run beginning within days zero "
                "through twenty-five after the switch"
            ),
        },
        "forbidden_scope": {
            "forecast_imported": False,
            "forecast_executed": False,
            "future_observations_used": False,
            "parameter_switching": False,
            "parameter_estimation": False,
            "real_basin_claim": False,
            "walrus_claim": False,
        },
        "result_relative_path": (
            "results/23_hbv_multilead_joint_uncertainty/"
            f"{EXPERIMENT_ID}"
        ),
        "verification_relative_path": (
            "results/23_hbv_multilead_joint_uncertainty/"
            f"{EXPERIMENT_ID}_independent_verification_v01"
        ),
    }


def load_and_validate_config(path: Path) -> dict:
    """Load only the exact frozen contract and reject scientific mutations."""
    candidate_path = Path(path).resolve()
    config = _read_json(candidate_path)
    canonical = _read_json(DEFAULT_CONFIG)
    if config != canonical or _critical_contract(config) != _expected_critical_contract():
        raise ValueError("frozen experiment contract does not match the registered design")
    required = set(config.get("required_result_files", ()))
    expected_required = {
        "checksums.json",
        "config_snapshot.json",
        "daily_probabilities.csv",
        "environment.json",
        "evidence.npz",
        "observation_noise_low.csv",
        "parameter_vectors.csv",
        "probability_response.png",
        "process_noise_covariances.csv",
        "registry_entry.json",
        "response_summary.png",
        "summary.json",
        "switch_response_events.csv",
        "switch_response_summary.csv",
    }
    if required != expected_required:
        raise ValueError("frozen experiment contract has an invalid result-file set")
    if float(config.get("numerical_tolerance", np.nan)) != 1e-12:
        raise ValueError("frozen experiment contract has an invalid tolerance")
    return config


def assert_output_paths_absent(result_path: Path, verification_path: Path) -> None:
    if Path(result_path).exists():
        raise FileExistsError(f"result path already exists: {result_path}")
    if Path(verification_path).exists():
        raise FileExistsError(
            f"verification path already exists: {verification_path}"
        )


def generate_forcing_blocks(config: dict) -> np.ndarray:
    """Generate the frozen warm-wet forcing independently for each block."""
    forcing = config["forcing"]
    total_days = int(forcing["warmup_days"]) + int(forcing["assimilation_days"])
    blocks = []
    for seed in config["seeds"]["forcing"]:
        generator = np.random.default_rng(int(seed))
        rain = float(forcing["rain_floor_mm_day"]) + generator.gamma(
            shape=float(forcing["rain_gamma_shape"]),
            scale=float(forcing["rain_gamma_scale_mm_day"]),
            size=total_days,
        )
        blocks.append(
            np.column_stack(
                (
                    rain,
                    np.full(
                        total_days,
                        float(forcing["potential_evaporation_mm_day"]),
                    ),
                    np.full(
                        total_days, float(forcing["temperature_celsius"])
                    ),
                )
            )
        )
    result = np.asarray(blocks, dtype=np.float64)
    expected_shape = (
        int(config["population"]["matched_block_count"]),
        total_days,
        3,
    )
    if result.shape != expected_shape or not np.all(np.isfinite(result)):
        raise FloatingPointError("frozen forcing generation failed")
    return result


def _verify_source(config: dict, key: str) -> Path:
    contract = config[key]
    path = (PROJECT_ROOT / contract["path"]).resolve()
    if not path.is_file():
        raise FileNotFoundError(f"sealed source does not exist: {path}")
    actual = _sha256(path)
    if actual != str(contract["sha256"]).lower():
        raise ValueError(f"sealed source hash mismatch: {path}")
    return path


def _load_parameter_vectors(path: Path) -> dict[str, dict[str, float]]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 3:
        raise ValueError("parameter source must contain exactly three rows")
    vectors = {}
    for row in rows:
        identifier = row["parameter_id"]
        if identifier in vectors:
            raise ValueError("parameter source contains duplicate identifiers")
        vectors[identifier] = {
            name: float(row[name]) for name in PARAMETER_NAMES
        }
    if set(vectors) != {
        "equifinal_diverse_1",
        "trained_center",
        "equifinal_diverse_2",
    }:
        raise ValueError("parameter source identifiers do not match the frozen bank")
    return vectors


def _load_observation_standard_deviation(path: Path) -> float:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 1:
        raise ValueError("observation-noise source must contain exactly one row")
    standard_deviation = float(rows[0]["standard_deviation_mm_day"])
    variance = float(rows[0]["variance_mm2_day2"])
    if (
        not np.isfinite(standard_deviation)
        or standard_deviation <= 0.0
        or abs(variance - standard_deviation**2) > 1e-15
    ):
        raise ValueError("observation-noise source is internally inconsistent")
    return standard_deviation


def _write_csv(path: Path, rows: list[dict], fieldnames: tuple[str, ...]) -> None:
    with path.open("x", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({name: row.get(name) for name in fieldnames})


def _daily_probability_rows(result) -> list[dict]:
    rows = []
    process_ids = tuple(result.process_ids.astype(str))
    for block in range(len(result.block_ids)):
        for trial in range(result.process_schedule.shape[0]):
            for day in range(result.process_schedule.shape[1]):
                stage = day // 180 + 1
                true_process_id = str(result.process_schedule[trial, day])
                for candidate, candidate_process_id in enumerate(process_ids):
                    rows.append(
                        {
                            "block_id": str(result.block_ids[block]),
                            "truth_trial": trial + 1,
                            "day_index": day,
                            "day_number": day + 1,
                            "stage": stage,
                            "true_process_id": true_process_id,
                            "candidate_process_id": candidate_process_id,
                            "posterior_probability": (
                                result.posterior_probabilities[
                                    block, trial, day, candidate
                                ]
                            ),
                        }
                    )
    return rows


def _write_process_covariances(
    path: Path,
    standard_deviations: dict[str, float],
) -> None:
    covariances = build_lower_groundwater_process_covariances(
        standard_deviations
    )
    rows = []
    for process_id, covariance in covariances.items():
        for state_index, variance in enumerate(np.diag(covariance)):
            rows.append(
                {
                    "process_id": process_id,
                    "state_index": state_index,
                    "variance_mm2_day2": variance,
                }
            )
    _write_csv(
        path,
        rows,
        ("process_id", "state_index", "variance_mm2_day2"),
    )


def _plot_probability_response(
    curve_rows: list[dict],
    response_summaries: list[dict],
    path: Path,
) -> None:
    matplotlib.rcParams["font.sans-serif"] = [
        "Microsoft YaHei",
        "SimHei",
        "Arial Unicode MS",
        "DejaVu Sans",
    ]
    matplotlib.rcParams["axes.unicode_minus"] = False
    colors = {
        PROCESS_IDS[0]: "#0072B2",
        PROCESS_IDS[1]: "#E69F00",
        PROCESS_IDS[2]: "#009E73",
    }
    candidate_names = {
        PROCESS_IDS[0]: "低过程噪声",
        PROCESS_IDS[1]: "中过程噪声",
        PROCESS_IDS[2]: "高过程噪声",
    }
    transition_names = {
        f"{PROCESS_IDS[0]}_to_{PROCESS_IDS[1]}": "低 → 中",
        f"{PROCESS_IDS[1]}_to_{PROCESS_IDS[2]}": "中 → 高",
        f"{PROCESS_IDS[2]}_to_{PROCESS_IDS[0]}": "高 → 低",
    }
    summary_by_transition = {
        row["transition_label"]: row for row in response_summaries
    }
    fig, axes = plt.subplots(3, 1, figsize=(10.5, 10.5), sharex=True)
    for axis, transition_label in zip(axes, transition_names):
        selected = [
            row
            for row in curve_rows
            if row["transition_label"] == transition_label
        ]
        for process_id in PROCESS_IDS:
            candidate_rows = [
                row
                for row in selected
                if row["candidate_process_id"] == process_id
            ]
            x = np.asarray(
                [row["relative_day"] for row in candidate_rows], dtype=float
            )
            median = np.asarray(
                [row["probability_median"] for row in candidate_rows]
            )
            lower = np.asarray(
                [row["probability_p10"] for row in candidate_rows]
            )
            upper = np.asarray(
                [row["probability_p90"] for row in candidate_rows]
            )
            axis.plot(
                x,
                median,
                color=colors[process_id],
                linewidth=2.1,
                label=candidate_names[process_id],
            )
            axis.fill_between(
                x, lower, upper, color=colors[process_id], alpha=0.14
            )
        summary = summary_by_transition[transition_label]
        axis.axvline(0.0, color="#333333", linestyle="--", linewidth=1.2)
        axis.set_ylim(0.0, 1.0)
        axis.set_ylabel("后验概率")
        axis.grid(alpha=0.22)
        axis.set_title(
            f"真实过程噪声切换：{transition_names[transition_label]}；"
            f"成功 {summary['successful_event_count']}/{summary['event_count']}；"
            f"95%精确区间 "
            f"[{summary['exact_interval_lower']:.3f}, "
            f"{summary['exact_interval_upper']:.3f}]"
        )
    axes[0].legend(ncol=3, loc="upper right")
    axes[-1].set_xlabel("相对切换日（0 为新噪声开始）")
    fig.suptitle(
        "固定真实水文参数下，三档下层地下水过程噪声的候选概率响应",
        fontsize=14,
    )
    fig.tight_layout(rect=(0.0, 0.0, 1.0, 0.97))
    fig.savefig(path, dpi=180, bbox_inches="tight")
    plt.close(fig)


def _plot_response_summary(
    response_summaries: list[dict],
    path: Path,
) -> None:
    matplotlib.rcParams["font.sans-serif"] = [
        "Microsoft YaHei",
        "SimHei",
        "Arial Unicode MS",
        "DejaVu Sans",
    ]
    names = ["低 → 中", "中 → 高", "高 → 低"]
    fractions = np.asarray(
        [row["response_fraction"] for row in response_summaries]
    )
    lower = np.asarray(
        [row["exact_interval_lower"] for row in response_summaries]
    )
    upper = np.asarray(
        [row["exact_interval_upper"] for row in response_summaries]
    )
    yerr = np.vstack((fractions - lower, upper - fractions))
    x = np.arange(3)
    fig, axis = plt.subplots(figsize=(8.8, 5.8))
    axis.errorbar(
        x,
        fractions,
        yerr=yerr,
        fmt="o",
        markersize=9,
        capsize=6,
        color="#0072B2",
        ecolor="#444444",
        linewidth=2,
    )
    threshold = 13.0 / 16.0
    axis.axhline(
        threshold,
        color="#D55E00",
        linestyle="--",
        linewidth=1.6,
        label="预先规定的最少成功比例 13/16",
    )
    axis.axhline(
        0.5,
        color="#777777",
        linestyle=":",
        linewidth=1.3,
        label="精确区间下限必须高于 0.5",
    )
    for index, row in enumerate(response_summaries):
        axis.text(
            index,
            min(1.03, upper[index] + 0.035),
            f"{row['successful_event_count']}/{row['event_count']}",
            ha="center",
            va="bottom",
        )
    axis.set_xticks(x, names)
    axis.set_ylim(0.0, 1.08)
    axis.set_ylabel("30 天内出现连续 5 天最高概率的事件比例")
    axis.set_title("三种真实过程噪声切换方向的响应判定")
    axis.grid(axis="y", alpha=0.24)
    axis.legend(loc="lower right")
    fig.tight_layout()
    fig.savefig(path, dpi=180, bbox_inches="tight")
    plt.close(fig)


def _decode_figure(path: Path) -> None:
    image = matplotlib_image.imread(path)
    if image.ndim not in (2, 3) or image.size == 0 or not np.all(
        np.isfinite(image)
    ):
        raise ValueError(f"generated figure cannot be decoded: {path}")


def _git_output(arguments: list[str]) -> str:
    result = subprocess.run(
        ["git", *arguments],
        cwd=PROJECT_ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def source_snapshot_entries() -> tuple[tuple[str, str], ...]:
    relative_paths = (
        "src/hbv_multilead_joint_uncertainty/state_domain_consistent_process_noise_switch.py",
        "src/hbv_multilead_joint_uncertainty/scripts/run_g3_state_domain_consistent_process_noise_switch.py",
        "src/hbv_multilead_joint_uncertainty/scripts/verify_g3_state_domain_consistent_process_noise_switch.py",
        "src/hbv_multilead_joint_uncertainty/methods.py",
        "src/hbv_multilead_joint_uncertainty/synthetic_truth.py",
        "src/hbv_joint_uncertainty/imm.py",
        "src/hbv_joint_uncertainty/sigma_filter.py",
        "src/hbv_joint_uncertainty/preflight.py",
        "test/test_hbv_state_domain_consistent_process_noise_switch.py",
        "test/test_hbv_state_domain_consistent_process_noise_switch_runner.py",
        "test/test_hbv_state_domain_consistent_process_noise_switch_verifier.py",
    )
    return tuple(
        (f"s{index:02d}.py", relative_path)
        for index, relative_path in enumerate(relative_paths)
    )


def _copy_source_snapshot(staging: Path) -> None:
    snapshot = staging / "srcsnap"
    snapshot.mkdir()
    manifest = []
    for alias, relative_path in source_snapshot_entries():
        source = PROJECT_ROOT / relative_path
        if not source.is_file():
            raise FileNotFoundError(f"source snapshot file is absent: {source}")
        destination = snapshot / alias
        shutil.copy2(source, destination)
        manifest.append(
            {
                "snapshot_path": f"srcsnap/{alias}",
                "project_relative_path": relative_path,
                "sha256": _sha256(destination),
            }
        )
    (staging / "source_snapshot_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _write_checksum_manifest(staging: Path) -> None:
    files = sorted(
        path
        for path in staging.rglob("*")
        if path.is_file() and path.name != "checksums.json"
    )
    manifest = {
        path.relative_to(staging).as_posix(): _sha256(path) for path in files
    }
    (staging / "checksums.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _write_evidence(
    path: Path,
    result,
    parameter_vectors: dict[str, dict[str, float]],
    standard_deviations: dict[str, float],
    observation_standard_deviation: float,
) -> None:
    covariances = build_lower_groundwater_process_covariances(
        standard_deviations
    )
    fixed_parameters = parameter_vectors["trained_center"]
    np.savez_compressed(
        path,
        block_ids=result.block_ids,
        process_ids=result.process_ids,
        parameter_names=np.asarray(PARAMETER_NAMES, dtype=np.str_),
        fixed_parameter_vector=np.asarray(
            [fixed_parameters[name] for name in PARAMETER_NAMES],
            dtype=np.float64,
        ),
        process_standard_deviations=np.asarray(
            [standard_deviations[identifier] for identifier in PROCESS_IDS],
            dtype=np.float64,
        ),
        process_covariances=np.stack(
            [covariances[identifier] for identifier in PROCESS_IDS]
        ),
        observation_standard_deviation=np.asarray(
            observation_standard_deviation, dtype=np.float64
        ),
        warmup_days=np.asarray(90, dtype=np.int64),
        stage_length_days=np.asarray(180, dtype=np.int64),
        forcing_blocks=result.forcing_blocks,
        process_schedule=result.process_schedule,
        process_standard_normals=result.process_standard_normals,
        observation_standard_normals=result.observation_standard_normals,
        initial_states=result.initial_states,
        initial_covariances=result.initial_covariances,
        deterministic_truth_states=result.deterministic_truth_states,
        truth_process_perturbations=result.truth_process_perturbations,
        truth_projection_adjustments=result.truth_projection_adjustments,
        truth_states=result.truth_states,
        truth_discharge=result.truth_discharge,
        observations=result.observations,
        posterior_probabilities=result.posterior_probabilities,
        global_posterior_states=result.global_posterior_states,
        forecast_executed=np.asarray(False, dtype=bool),
    )


def run(config_path: Path = DEFAULT_CONFIG) -> dict:
    config = load_and_validate_config(config_path)
    result_path = (PROJECT_ROOT / config["result_relative_path"]).resolve()
    verification_path = (
        PROJECT_ROOT / config["verification_relative_path"]
    ).resolve()
    if result_path != DEFAULT_OUTPUT.resolve() or verification_path != DEFAULT_VERIFICATION.resolve():
        raise ValueError("frozen result paths do not match the registered design")
    assert_output_paths_absent(result_path, verification_path)

    parameter_source = _verify_source(config, "parameter_source")
    observation_source = _verify_source(config, "observation_noise_source")
    parameter_vectors = _load_parameter_vectors(parameter_source)
    observation_standard_deviation = _load_observation_standard_deviation(
        observation_source
    )
    free_bytes = shutil.disk_usage(PROJECT_ROOT).free
    if free_bytes < 1_000_000_000:
        raise RuntimeError("less than one gigabyte of free disk is available")

    forcing = generate_forcing_blocks(config)
    standard_deviations = {
        row["process_id"]: float(row["standard_deviation_mm_day"])
        for row in config["process_noise_candidates"]
    }
    block_ids = [f"matched_block_{index + 1:02d}" for index in range(8)]
    result = run_state_domain_consistent_process_noise_switch(
        forcing_blocks=forcing,
        block_ids=block_ids,
        parameter_vectors=parameter_vectors,
        process_standard_deviations=standard_deviations,
        process_noise_seeds=config["seeds"]["process_noise"],
        observation_noise_seeds=config["seeds"]["observation_noise"],
        warmup_days=config["forcing"]["warmup_days"],
        stage_length_days=config["population"]["stage_length_days"],
        initial_covariance_fraction=config["filter"][
            "initial_covariance_fraction"
        ],
        observation_standard_deviation=observation_standard_deviation,
        factor_transition_stay_probability=config["filter"][
            "factor_transition_stay_probability"
        ],
    )
    response = config["response_rule"]
    events, response_summaries = summarize_switch_response(
        result.posterior_probabilities,
        result.process_schedule,
        result.process_ids,
        response_window_days=response["response_window_days"],
        consecutive_top_days=response["consecutive_top_ranked_days"],
        minimum_successful_events=response[
            "minimum_successful_events_per_directed_transition"
        ],
        minimum_interval_lower_bound=response[
            "minimum_exact_interval_lower_bound_exclusive"
        ],
    )
    curves = build_probability_response_curves(
        result.posterior_probabilities,
        result.process_schedule,
        result.process_ids,
    )
    stage_accuracy = summarize_full_stage_accuracy(
        result.posterior_probabilities,
        result.process_schedule,
        result.process_ids,
    )
    projection_event_count = int(
        np.count_nonzero(
            np.any(result.truth_projection_adjustments != 0.0, axis=-1)
        )
    )
    maximum_projection_adjustment = float(
        np.max(np.abs(result.truth_projection_adjustments))
    )
    if projection_event_count != 0 or maximum_projection_adjustment != 0.0:
        raise ValueError("truth state-domain gate failed after complete run")
    if len(events) != 48 or any(
        row["event_count"] != 16 for row in response_summaries
    ):
        raise ValueError("frozen event population was not preserved")
    decision = (
        "supported_under_clean_synthetic_condition"
        if all(row["criterion_passed"] for row in response_summaries)
        else "not_supported_under_clean_synthetic_condition"
    )

    staging = result_path.with_name(
        f"{result_path.name}.incomplete.{uuid4().hex}"
    )
    if staging.exists():
        raise FileExistsError(f"staging path already exists: {staging}")
    staging.mkdir(parents=False)

    shutil.copy2(parameter_source, staging / "parameter_vectors.csv")
    shutil.copy2(observation_source, staging / "observation_noise_low.csv")
    shutil.copy2(config_path, staging / "config_snapshot.json")
    _write_process_covariances(
        staging / "process_noise_covariances.csv", standard_deviations
    )
    _write_evidence(
        staging / "evidence.npz",
        result,
        parameter_vectors,
        standard_deviations,
        observation_standard_deviation,
    )
    _write_csv(
        staging / "switch_response_events.csv",
        events,
        (
            "event_id",
            "block_index",
            "trial_index",
            "switch_day_index",
            "switch_day_number",
            "old_process_id",
            "new_process_id",
            "transition_label",
            "success",
            "response_start_day",
            "new_candidate_top_ranked_days_in_window",
        ),
    )
    _write_csv(
        staging / "switch_response_summary.csv",
        response_summaries,
        (
            "old_process_id",
            "new_process_id",
            "transition_label",
            "event_count",
            "successful_event_count",
            "response_fraction",
            "exact_interval_lower",
            "exact_interval_upper",
            "median_response_start_day",
            "maximum_response_start_day",
            "criterion_passed",
        ),
    )
    _write_csv(
        staging / "daily_probabilities.csv",
        _daily_probability_rows(result),
        (
            "block_id",
            "truth_trial",
            "day_index",
            "day_number",
            "stage",
            "true_process_id",
            "candidate_process_id",
            "posterior_probability",
        ),
    )
    _plot_probability_response(
        curves,
        response_summaries,
        staging / "probability_response.png",
    )
    _plot_response_summary(
        response_summaries, staging / "response_summary.png"
    )
    _decode_figure(staging / "probability_response.png")
    _decode_figure(staging / "response_summary.png")

    summary = {
        "experiment_id": EXPERIMENT_ID,
        "status": "complete_pending_independent_verification",
        "decision": decision,
        "scientific_conclusion_withheld_until_independent_verification": True,
        "only_changed_factor": (
            "true and candidate lower-groundwater process-noise standard "
            "deviation: 1, 4, or 16 millimetres per day"
        ),
        "fixed_parameter_id": "trained_center",
        "candidate_parameter_ids": ["trained_center"] * 3,
        "candidate_process_ids": list(PROCESS_IDS),
        "process_noise_support": {
            "state_index": 4,
            "state_name": "SLZ",
            "plain_name": "lower groundwater storage",
            "all_other_fourteen_state_variances": 0.0,
        },
        "truth_population": {
            "matched_blocks": 8,
            "truth_trials": 3,
            "assimilation_days_per_trial": 540,
            "total_truth_transitions": 12960,
            "switch_events": 48,
            "events_per_directed_transition": 16,
        },
        "truth_state_domain_gate": {
            "projection_event_count": projection_event_count,
            "maximum_absolute_projection_adjustment": (
                maximum_projection_adjustment
            ),
            "passed": True,
        },
        "response_rule": response,
        "directed_transition_results": response_summaries,
        "full_stage_descriptive_accuracy": stage_accuracy,
        "probability_normalization_maximum_absolute_error": float(
            np.max(
                np.abs(
                    result.posterior_probabilities.sum(axis=-1) - 1.0
                )
            )
        ),
        "all_numeric_evidence_finite": True,
        "forbidden_scope_checks": {
            "forecast_imported": False,
            "forecast_executed": False,
            "future_observations_used": False,
            "parameter_switching": False,
            "parameter_estimation": False,
        },
        "evidence_boundary": (
            "warm-wet synthetic HBV-lite truth with process noise only on "
            "lower groundwater storage; this is not forecast evidence, not "
            "general process-noise evidence, not WALRUS evidence, and not "
            "real-catchment evidence"
        ),
    }
    (staging / "summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    environment = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "platform": platform.platform(),
        "python": sys.version,
        "numpy": np.__version__,
        "scipy": scipy.__version__,
        "matplotlib": matplotlib.__version__,
        "git_head": _git_output(["rev-parse", "HEAD"]),
        "git_status_short_before_result_seal": _git_output(
            ["status", "--short"]
        ).splitlines(),
        "free_disk_bytes_before_run": free_bytes,
    }
    (staging / "environment.json").write_text(
        json.dumps(environment, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    registry_entry = {
        "experiment_id": EXPERIMENT_ID,
        "experiment_type": "assimilation-only clean synthetic process-noise switch",
        "status": "complete_pending_independent_verification",
        "result_relative_path": config["result_relative_path"],
        "decision": decision,
        "forecast_executed": False,
        "scientific_boundary": summary["evidence_boundary"],
    }
    (staging / "registry_entry.json").write_text(
        json.dumps(registry_entry, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    _copy_source_snapshot(staging)

    required_without_manifest = set(config["required_result_files"]) - {
        "checksums.json"
    }
    actual_top_level = {
        path.name for path in staging.iterdir() if path.is_file()
    }
    if not required_without_manifest.issubset(actual_top_level):
        missing = sorted(required_without_manifest - actual_top_level)
        raise ValueError(f"result package is missing files: {missing}")
    _write_checksum_manifest(staging)
    if result_path.exists():
        raise FileExistsError(f"result path appeared during run: {result_path}")
    staging.rename(result_path)
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    args = parser.parse_args()
    summary = run(args.config)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
