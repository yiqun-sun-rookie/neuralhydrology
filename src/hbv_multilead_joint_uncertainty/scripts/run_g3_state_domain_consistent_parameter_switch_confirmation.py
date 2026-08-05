"""Run the frozen parameter-switch confirmation without truth-state clipping."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import platform
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SRC_ROOT = PROJECT_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from hbv_multilead_joint_uncertainty.state_domain_consistent_parameter_switch_confirmation import (  # noqa: E402
    PARAMETER_NAMES,
    audit_candidate_distinguishability,
    build_fixed_lower_groundwater_covariance,
    build_rotating_parameter_schedule,
    run_parameter_switch_confirmation,
    summarize_full_stage_accuracy,
    summarize_parameter_switch_response,
    validate_parameter_candidates,
)


EXPERIMENT_ID = "g3_state_domain_consistent_parameter_switch_confirmation_v01"
CONFIG_SHA256 = "a7c974608a647f7eade14a7fa0ee443f6148950cf7175103b21d91c6bb344059"
DEFAULT_CONFIG = (
    PROJECT_ROOT
    / "src"
    / "hbv_multilead_joint_uncertainty"
    / "configs"
    / f"{EXPERIMENT_ID}.json"
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _read_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"JSON root must be an object: {path}")
    return value


def load_and_validate_config(path: Path = DEFAULT_CONFIG) -> dict:
    """Load the exact frozen config and validate its non-negotiable contracts."""
    resolved = path.resolve()
    if not resolved.is_file():
        raise FileNotFoundError(f"frozen config does not exist: {resolved}")
    if _sha256(resolved) != CONFIG_SHA256:
        raise ValueError("frozen config hash mismatch")
    config = _read_json(resolved)
    if config.get("experiment_id") != EXPERIMENT_ID:
        raise ValueError("experiment ID changed")
    if config.get("status") != "frozen_before_run":
        raise ValueError("config status changed")
    if int(config["population"]["matched_block_count"]) != 8:
        raise ValueError("matched block count changed")
    if int(config["population"]["events_per_directed_transition"]) != 16:
        raise ValueError("directed event count changed")
    if int(config["forcing"]["warmup_days"]) != 45:
        raise ValueError("warmup changed")
    if int(config["population"]["stage_length_days"]) != 180:
        raise ValueError("stage length changed")
    if config["filter"]["interaction_mode"] != "full":
        raise ValueError("interaction mode changed")
    if config["forbidden_scope"] != {
        "forecast_imported": False,
        "forecast_executed": False,
        "future_observations_used": False,
        "process_noise_switching": False,
        "joint_parameter_process_noise_switching": False,
        "state_interaction_attribution": False,
        "state_accuracy_claim": False,
        "real_basin_claim": False,
        "walrus_claim": False,
    }:
        raise ValueError("forbidden scope changed")
    return config


def _result_paths(config: dict) -> tuple[Path, Path, Path]:
    result = (PROJECT_ROOT / config["result_relative_path"]).resolve()
    visual = (PROJECT_ROOT / config["visual_review_relative_path"]).resolve()
    verification = (PROJECT_ROOT / config["verification_relative_path"]).resolve()
    return result, visual, verification


def assert_output_paths_absent(config: dict) -> None:
    for path in _result_paths(config):
        if path.exists():
            raise FileExistsError(f"protected output path already exists: {path}")


def _verify_source(config: dict, key: str) -> Path:
    contract = config[key]
    path = (PROJECT_ROOT / contract["path"]).resolve()
    if not path.is_file():
        raise FileNotFoundError(f"sealed source does not exist: {path}")
    if _sha256(path) != str(contract["sha256"]).lower():
        raise ValueError(f"sealed source hash mismatch: {path}")
    return path


def _load_source_parameter_rows(path: Path) -> dict[str, dict[str, float]]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 3:
        raise ValueError("sealed parameter source must contain three rows")
    result: dict[str, dict[str, float]] = {}
    for row in rows:
        identifier = str(row["parameter_id"])
        result[identifier] = {name: float(row[name]) for name in PARAMETER_NAMES}
    if set(result) != {
        "equifinal_diverse_1",
        "trained_center",
        "equifinal_diverse_2",
    }:
        raise ValueError("sealed parameter identifiers changed")
    return result


def _parameter_vectors_from_config(config: dict, source_path: Path) -> dict[str, dict[str, float]]:
    source = _load_source_parameter_rows(source_path)
    center = source["trained_center"]
    vectors: dict[str, dict[str, float]] = {}
    for row in config["parameter_candidates"]:
        identifier = str(row["parameter_id"])
        source_identifier = str(row["source_parameter_id"])
        expected = source[source_identifier].copy()
        expected["parFC"] = center["parFC"]
        expected["parCWH"] = center["parCWH"]
        actual = {name: float(row[name]) for name in PARAMETER_NAMES}
        if any(actual[name] != expected[name] for name in PARAMETER_NAMES):
            raise ValueError(f"candidate transformation mismatch: {identifier}")
        vectors[identifier] = actual
    validate_parameter_candidates(vectors)
    return vectors


def _load_observation_standard_deviation(path: Path) -> float:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 1:
        raise ValueError("observation-noise source must contain one row")
    standard_deviation = float(rows[0]["standard_deviation_mm_day"])
    variance = float(rows[0]["variance_mm2_day2"])
    if (
        not np.isfinite(standard_deviation)
        or standard_deviation <= 0.0
        or abs(variance - standard_deviation**2) > 1e-15
    ):
        raise ValueError("observation-noise source is inconsistent")
    return standard_deviation


def _validate_seed_contract(config: dict) -> None:
    construction = set(int(value) for value in config["candidate_construction_seeds"]["forcing"])
    formal_groups = {
        key: set(int(value) for value in values)
        for key, values in config["formal_confirmation_seeds"].items()
    }
    all_groups = {"construction": construction, **formal_groups}
    for label, values in all_groups.items():
        if len(values) != 8:
            raise ValueError(f"seed group {label} must contain eight unique values")
    labels = tuple(all_groups)
    for left_index, left in enumerate(labels):
        for right in labels[left_index + 1 :]:
            if all_groups[left] & all_groups[right]:
                raise ValueError(f"seed groups overlap: {left} and {right}")
    if not all(str(value).startswith("360") for value in construction):
        raise ValueError("candidate-construction seed prefix changed")
    for key, values in formal_groups.items():
        if not all(str(value).startswith("370") for value in values):
            raise ValueError(f"formal seed prefix changed for {key}")


def generate_forcing_blocks(config: dict, seeds: list[int]) -> np.ndarray:
    forcing = config["forcing"]
    total_days = int(forcing["warmup_days"]) + int(forcing["assimilation_days"])
    if not seeds or len(seeds) > int(config["population"]["matched_block_count"]):
        raise ValueError("forcing seeds must contain between one and eight values")
    blocks = []
    for seed in seeds:
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
                    np.full(total_days, float(forcing["potential_evaporation_mm_day"])),
                    np.full(total_days, float(forcing["temperature_celsius"])),
                )
            )
        )
    result = np.asarray(blocks, dtype=np.float64)
    expected = (len(seeds), total_days, 3)
    if result.shape != expected or not np.all(np.isfinite(result)):
        raise FloatingPointError("forcing generation failed")
    return result


def run_preflight(config_path: Path = DEFAULT_CONFIG, block_limit: int = 1) -> dict:
    """Run development separation and a bounded formal truth/filter resource check."""
    config = load_and_validate_config(config_path)
    assert_output_paths_absent(config)
    _validate_seed_contract(config)
    parameter_source = _verify_source(config, "parameter_source")
    observation_source = _verify_source(config, "observation_noise_source")
    vectors = _parameter_vectors_from_config(config, parameter_source)
    observation_std = _load_observation_standard_deviation(observation_source)
    construction_forcing = generate_forcing_blocks(
        config, config["candidate_construction_seeds"]["forcing"]
    )
    gate = config["candidate_distinguishability_gate"]
    audit = audit_candidate_distinguishability(
        construction_forcing,
        vectors,
        warmup_days=int(config["forcing"]["warmup_days"]),
        observation_standard_deviation=observation_std,
        minimum_observation_standard_deviation_multiple=float(
            gate["minimum_pairwise_rmse_in_observation_standard_deviations"]
        ),
        minimum_center_standard_deviation_multiple=float(
            gate["minimum_pairwise_rmse_as_trained_center_discharge_standard_deviation"]
        ),
    )
    if not all(bool(row["passed"]) for row in audit):
        raise ValueError("candidate distinguishability gate failed")

    limit = int(block_limit)
    if limit <= 0 or limit > 8:
        raise ValueError("block_limit must be between one and eight")
    formal_forcing = generate_forcing_blocks(
        config, config["formal_confirmation_seeds"]["forcing"][:limit]
    )
    result = run_parameter_switch_confirmation(
        formal_forcing,
        block_ids=tuple(f"formal_parameter_block_{index + 1:02d}" for index in range(limit)),
        parameter_vectors=vectors,
        process_noise_seeds=config["formal_confirmation_seeds"]["process_noise"][:limit],
        observation_noise_seeds=config["formal_confirmation_seeds"]["observation_noise"][:limit],
        warmup_days=int(config["forcing"]["warmup_days"]),
        stage_length_days=int(config["population"]["stage_length_days"]),
        initial_covariance_fraction=float(config["filter"]["initial_covariance_fraction"]),
        process_standard_deviation_mm_day=float(
            config["fixed_process_noise"]["standard_deviation_mm_day"]
        ),
        observation_standard_deviation=observation_std,
        factor_transition_stay_probability=float(
            config["filter"]["factor_transition_stay_probability"]
        ),
    )
    return {
        "candidate_audit": audit,
        "formal_block_count": limit,
        "truth_transition_count": int(np.prod(result.truth_states.shape[:3])),
        "truth_projection_event_count": int(
            np.count_nonzero(np.any(result.truth_projection_adjustments != 0.0, axis=-1))
        ),
        "switch_boundary_projection_event_count": int(
            np.count_nonzero(
                np.any(result.switch_boundary_projection_adjustments != 0.0, axis=-1)
            )
        ),
        "maximum_projection_adjustment": float(
            np.max(np.abs(result.truth_projection_adjustments))
        ),
        "maximum_switch_boundary_projection_adjustment": float(
            np.max(np.abs(result.switch_boundary_projection_adjustments))
        ),
        "probability_normalization_maximum_absolute_error": float(
            np.max(np.abs(result.posterior_probabilities.sum(axis=-1) - 1.0))
        ),
    }


def _write_csv(path: Path, rows: list[dict], fieldnames: tuple[str, ...] | None = None) -> None:
    if not rows:
        raise ValueError(f"refusing to write empty CSV: {path}")
    names = tuple(rows[0]) if fieldnames is None else fieldnames
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=names)
        writer.writeheader()
        writer.writerows(rows)


def _daily_probability_rows(result) -> list[dict]:
    candidate_index = {
        str(identifier): index for index, identifier in enumerate(result.parameter_ids)
    }
    rows: list[dict] = []
    for block in range(len(result.block_ids)):
        for trial in range(result.parameter_schedule.shape[0]):
            for day in range(result.parameter_schedule.shape[1]):
                true_identifier = str(result.parameter_schedule[trial, day])
                probabilities = result.posterior_probabilities[block, trial, day]
                row = {
                    "block_index": block,
                    "block_id": str(result.block_ids[block]),
                    "trial_index": trial,
                    "day_index": day,
                    "day_number": day + 1,
                    "true_parameter_id": true_identifier,
                    "true_candidate_probability": float(
                        probabilities[candidate_index[true_identifier]]
                    ),
                    "top_ranked_parameter_id": str(
                        result.parameter_ids[int(np.argmax(probabilities))]
                    ),
                }
                for index, identifier in enumerate(result.parameter_ids):
                    row[f"probability_{identifier}"] = float(probabilities[index])
                rows.append(row)
    return rows


def _parameter_rows(config: dict) -> list[dict]:
    rows = []
    for candidate in config["parameter_candidates"]:
        rows.append(
            {
                "parameter_id": candidate["parameter_id"],
                "source_parameter_id": candidate["source_parameter_id"],
                **{name: candidate[name] for name in PARAMETER_NAMES},
            }
        )
    return rows


def _covariance_rows(config: dict) -> list[dict]:
    covariance = build_fixed_lower_groundwater_covariance(
        config["fixed_process_noise"]["standard_deviation_mm_day"]
    )
    return [
        {
            "state_index": index,
            "variance": float(covariance[index, index]),
        }
        for index in range(15)
    ]


def _plot_numeric_summary(path: Path, summaries: list[dict]) -> None:
    labels = [row["transition_label"] for row in summaries]
    counts = [row["numerically_successful_event_count"] for row in summaries]
    figure, axis = plt.subplots(figsize=(11, 5.5))
    colors = ["#2b8cbe" if row["numerical_criterion_passed"] else "#d95f0e" for row in summaries]
    axis.bar(np.arange(3), counts, color=colors)
    axis.axhline(13, color="black", linestyle="--", linewidth=1.2, label="minimum 13 of 16")
    axis.set_xticks(np.arange(3), labels, rotation=12, ha="right")
    axis.set_ylim(0, 17)
    axis.set_ylabel("Numerically successful events")
    axis.set_title("Frozen numerical response before blinded visual review")
    axis.legend(loc="upper right")
    figure.tight_layout()
    figure.savefig(path, dpi=180)
    plt.close(figure)


def _render_event_panels(staging: Path, result, events: list[dict], config: dict) -> list[dict]:
    panel_dir = staging / "event_panels"
    panel_dir.mkdir()
    seed = int(config["visual_review_rule"]["display_order_seed"])
    order = np.random.default_rng(seed).permutation(len(events))
    relative_start = int(config["visual_review_rule"]["relative_day_start"])
    relative_end = int(config["visual_review_rule"]["relative_day_end"])
    colors = ("#1b9e77", "#d95f02", "#7570b3")
    rows: list[dict] = []
    for review_index, event_position in enumerate(order, start=1):
        event = events[int(event_position)]
        block = int(event["block_index"])
        trial = int(event["trial_index"])
        boundary = int(event["switch_day_index"])
        start = boundary + relative_start
        stop = boundary + relative_end + 1
        if start < 0 or stop > result.posterior_probabilities.shape[2]:
            raise ValueError("visual-review window exceeds saved probabilities")
        probabilities = result.posterior_probabilities[block, trial, start:stop]
        relative_days = np.arange(relative_start, relative_end + 1)
        new_identifier = str(event["new_parameter_id"])
        figure, axis = plt.subplots(figsize=(9.6, 5.4))
        for candidate_index, identifier in enumerate(result.parameter_ids):
            identifier = str(identifier)
            is_new = identifier == new_identifier
            axis.plot(
                relative_days,
                probabilities[:, candidate_index],
                color=colors[candidate_index],
                linewidth=3.0 if is_new else 1.6,
                alpha=1.0 if is_new else 0.78,
                label=f"{identifier}{' (new true candidate)' if is_new else ''}",
            )
        axis.axvline(0, color="black", linestyle="--", linewidth=1.2, label="true parameter switch")
        axis.set_xlim(relative_start, relative_end)
        axis.set_ylim(0.0, 1.0)
        axis.set_xlabel("Day relative to true parameter switch")
        axis.set_ylabel("Posterior probability")
        axis.set_title(f"Blinded visual review item {review_index:03d}")
        axis.grid(alpha=0.2)
        axis.legend(loc="best", fontsize=8)
        figure.tight_layout()
        filename = f"review_{review_index:03d}.png"
        path = panel_dir / filename
        figure.savefig(path, dpi=180)
        plt.close(figure)
        with Image.open(path) as image:
            image.verify()
        rows.append(
            {
                "review_id": f"review_{review_index:03d}",
                "panel_relative_path": f"event_panels/{filename}",
                "panel_sha256": _sha256(path),
                "event_id": event["event_id"],
                "block_index": block,
                "trial_index": trial,
                "switch_day_index": boundary,
                "old_parameter_id": event["old_parameter_id"],
                "new_parameter_id": new_identifier,
            }
        )
    return rows


def _source_entries() -> tuple[str, ...]:
    return (
        "src/hbv_joint_uncertainty/hbv_adapter.py",
        "src/hbv_joint_uncertainty/imm.py",
        "src/hbv_joint_uncertainty/preflight.py",
        "src/hbv_joint_uncertainty/sigma_filter.py",
        "src/hbv_multilead_joint_uncertainty/methods.py",
        "src/hbv_multilead_joint_uncertainty/synthetic_truth.py",
        "src/hbv_multilead_joint_uncertainty/state_domain_consistent_parameter_switch_confirmation.py",
        "src/hbv_multilead_joint_uncertainty/scripts/run_g3_state_domain_consistent_parameter_switch_confirmation.py",
        "src/hbv_multilead_joint_uncertainty/scripts/verify_g3_state_domain_consistent_parameter_switch_confirmation.py",
        "test/test_hbv_state_domain_consistent_parameter_switch_confirmation.py",
        "test/test_hbv_state_domain_consistent_parameter_switch_confirmation_runner.py",
        "test/test_hbv_state_domain_consistent_parameter_switch_confirmation_verifier.py",
    )


def _source_manifest() -> dict:
    rows = {}
    for relative in _source_entries():
        path = PROJECT_ROOT / relative
        if not path.is_file():
            raise FileNotFoundError(f"required source snapshot input missing: {path}")
        rows[relative] = _sha256(path)
    return {
        "experiment_id": EXPERIMENT_ID,
        "config_sha256": CONFIG_SHA256,
        "files": rows,
    }


def _git_output(arguments: list[str]) -> str:
    completed = subprocess.run(
        ["git", *arguments],
        cwd=PROJECT_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip()


def _write_checksums(staging: Path) -> None:
    mapping = {}
    for path in sorted(staging.rglob("*")):
        if path.is_file() and path.name != "checksums.json":
            mapping[path.relative_to(staging).as_posix()] = _sha256(path)
    (staging / "checksums.json").write_text(
        json.dumps(mapping, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def _json_default(value):
    if isinstance(value, (np.integer,)):
        return int(value)
    if isinstance(value, (np.floating,)):
        return float(value)
    if isinstance(value, np.ndarray):
        return value.tolist()
    raise TypeError(f"cannot serialize {type(value)!r}")


def run(config_path: Path = DEFAULT_CONFIG) -> dict:
    config = load_and_validate_config(config_path)
    assert_output_paths_absent(config)
    _validate_seed_contract(config)
    parameter_source = _verify_source(config, "parameter_source")
    observation_source = _verify_source(config, "observation_noise_source")
    vectors = _parameter_vectors_from_config(config, parameter_source)
    identifiers = tuple(vectors)
    observation_std = _load_observation_standard_deviation(observation_source)

    construction_forcing = generate_forcing_blocks(
        config, config["candidate_construction_seeds"]["forcing"]
    )
    gate = config["candidate_distinguishability_gate"]
    construction_audit = audit_candidate_distinguishability(
        construction_forcing,
        vectors,
        warmup_days=int(config["forcing"]["warmup_days"]),
        observation_standard_deviation=observation_std,
        minimum_observation_standard_deviation_multiple=float(
            gate["minimum_pairwise_rmse_in_observation_standard_deviations"]
        ),
        minimum_center_standard_deviation_multiple=float(
            gate["minimum_pairwise_rmse_as_trained_center_discharge_standard_deviation"]
        ),
    )
    if not all(bool(row["passed"]) for row in construction_audit):
        raise ValueError("candidate distinguishability gate failed")

    formal_forcing = generate_forcing_blocks(
        config, config["formal_confirmation_seeds"]["forcing"]
    )
    block_ids = tuple(f"formal_parameter_block_{index + 1:02d}" for index in range(8))
    result = run_parameter_switch_confirmation(
        formal_forcing,
        block_ids=block_ids,
        parameter_vectors=vectors,
        process_noise_seeds=config["formal_confirmation_seeds"]["process_noise"],
        observation_noise_seeds=config["formal_confirmation_seeds"]["observation_noise"],
        warmup_days=int(config["forcing"]["warmup_days"]),
        stage_length_days=int(config["population"]["stage_length_days"]),
        initial_covariance_fraction=float(config["filter"]["initial_covariance_fraction"]),
        process_standard_deviation_mm_day=float(
            config["fixed_process_noise"]["standard_deviation_mm_day"]
        ),
        observation_standard_deviation=observation_std,
        factor_transition_stay_probability=float(
            config["filter"]["factor_transition_stay_probability"]
        ),
    )
    expected_schedule = np.asarray(config["truth_trial_stage_orders"], dtype=np.str_)
    expanded = np.asarray(
        [[identifier for identifier in order for _ in range(180)] for order in expected_schedule],
        dtype=np.str_,
    )
    if not np.array_equal(result.parameter_schedule, expanded):
        raise ValueError("formal parameter schedule differs from frozen config")

    rule = config["numerical_response_rule"]
    events, numeric_summaries = summarize_parameter_switch_response(
        result.posterior_probabilities,
        result.parameter_schedule,
        identifiers,
        response_window_days=int(rule["response_window_days"]),
        consecutive_clear_days=int(rule["consecutive_clear_dominance_days"]),
        minimum_probability_exclusive=float(
            rule["minimum_new_true_candidate_probability_exclusive"]
        ),
        minimum_margin_inclusive=float(
            rule["minimum_probability_margin_over_runner_up_inclusive"]
        ),
        minimum_successful_events=int(
            rule["minimum_successful_events_per_directed_transition"]
        ),
        minimum_interval_lower_bound=float(
            rule["minimum_exact_interval_lower_bound_exclusive"]
        ),
    )
    full_stage = summarize_full_stage_accuracy(
        result.posterior_probabilities, result.parameter_schedule, identifiers
    )

    output, _, _ = _result_paths(config)
    output.parent.mkdir(parents=True, exist_ok=True)
    token = uuid.uuid4().hex
    staging = output.with_name(f"{output.name}.staging.{token}")
    incomplete = output.with_name(f"{output.name}.incomplete.{token}")
    staging.mkdir()
    try:
        (staging / "config_snapshot.json").write_text(
            json.dumps(config, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        _write_csv(staging / "parameter_vectors.csv", _parameter_rows(config))
        _write_csv(staging / "fixed_process_covariance.csv", _covariance_rows(config))
        _write_csv(staging / "candidate_construction_audit.csv", construction_audit)
        _write_csv(staging / "daily_probabilities.csv", _daily_probability_rows(result))
        _write_csv(staging / "switch_response_events_numeric.csv", events)
        _write_csv(staging / "switch_response_summary_numeric.csv", numeric_summaries)
        _plot_numeric_summary(staging / "numeric_response_summary.png", numeric_summaries)
        panel_manifest = _render_event_panels(staging, result, events, config)
        (staging / "event_panel_manifest.json").write_text(
            json.dumps(
                {
                    "display_order_seed": config["visual_review_rule"]["display_order_seed"],
                    "numeric_decisions_shown_in_panels": False,
                    "panel_count": len(panel_manifest),
                    "panels": panel_manifest,
                },
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        np.savez_compressed(
            staging / "evidence.npz",
            block_ids=result.block_ids,
            parameter_ids=result.parameter_ids,
            parameter_vectors=np.asarray(
                [[vectors[identifier][name] for name in PARAMETER_NAMES] for identifier in identifiers],
                dtype=np.float64,
            ),
            forcing_blocks=result.forcing_blocks,
            parameter_schedule=result.parameter_schedule,
            process_standard_normals=result.process_standard_normals,
            observation_standard_normals=result.observation_standard_normals,
            initial_states=result.initial_states,
            initial_covariances=result.initial_covariances,
            deterministic_truth_states=result.deterministic_truth_states,
            truth_process_perturbations=result.truth_process_perturbations,
            truth_projection_adjustments=result.truth_projection_adjustments,
            switch_boundary_projection_adjustments=result.switch_boundary_projection_adjustments,
            truth_states=result.truth_states,
            truth_discharge=result.truth_discharge,
            observations=result.observations,
            posterior_probabilities=result.posterior_probabilities,
            global_posterior_states=result.global_posterior_states,
            observation_standard_deviation=np.asarray(observation_std),
            fixed_process_standard_deviation=np.asarray(
                config["fixed_process_noise"]["standard_deviation_mm_day"]
            ),
        )
        source_manifest = _source_manifest()
        (staging / "source_manifest.json").write_text(
            json.dumps(source_manifest, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        environment = {
            "created_utc": datetime.now(timezone.utc).isoformat(),
            "python": sys.version,
            "platform": platform.platform(),
            "numpy": np.__version__,
            "git_head": _git_output(["rev-parse", "HEAD"]),
            "git_branch": _git_output(["branch", "--show-current"]),
            "config_sha256": CONFIG_SHA256,
        }
        (staging / "environment.json").write_text(
            json.dumps(environment, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        registry = {
            "exp_id": EXPERIMENT_ID,
            "type": "prospective_synthetic_parameter_switch_confirmation",
            "hypothesis": config["scientific_question"],
            "base_config": config["parameter_source"],
            "changed_factor": "true fixed parameter candidate at days 181 and 361",
            "fixed_factors": [
                "fifteen-state HBV-lite implementation",
                "fixed lower-groundwater process noise",
                "fixed observation noise",
                "forcing distribution",
                "initial conditions",
                "candidate bank",
                "transition probabilities",
            ],
            "seeds": config["formal_confirmation_seeds"],
            "status": "complete_pending_blinded_visual_review_and_independent_verification",
            "run_dir": config["result_relative_path"],
            "metrics_path": f"{config['result_relative_path']}/switch_response_summary_numeric.csv",
            "paper_name": "not_assigned",
            "notes": "No forecast; final event success also requires sealed blinded visual review.",
        }
        (staging / "registry_entry.json").write_text(
            json.dumps(registry, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        truth_projection_count = int(
            np.count_nonzero(np.any(result.truth_projection_adjustments != 0.0, axis=-1))
        )
        boundary_projection_count = int(
            np.count_nonzero(
                np.any(result.switch_boundary_projection_adjustments != 0.0, axis=-1)
            )
        )
        summary = {
            "experiment_id": EXPERIMENT_ID,
            "status": "complete_pending_blinded_visual_review_and_independent_verification",
            "scientific_conclusion_withheld": True,
            "candidate_construction_audit": construction_audit,
            "parameter_ids": list(identifiers),
            "parameters_setting_truth_state_limits": config[
                "parameters_that_set_truth_state_limits"
            ],
            "shared_parFC": vectors[identifiers[0]]["parFC"],
            "shared_parCWH": vectors[identifiers[0]]["parCWH"],
            "only_switched_factor": "true fixed parameter candidate",
            "fixed_process_noise": config["fixed_process_noise"],
            "truth_population": {
                "matched_blocks": 8,
                "truth_trials": 3,
                "assimilation_days_per_trial": 540,
                "switch_events": len(events),
                "events_per_directed_transition": 16,
                "truth_transition_count": int(np.prod(result.truth_states.shape[:3])),
            },
            "truth_projection_gate": {
                "projection_event_count": truth_projection_count,
                "maximum_absolute_projection_adjustment": float(
                    np.max(np.abs(result.truth_projection_adjustments))
                ),
                "passed": truth_projection_count == 0,
            },
            "switch_boundary_projection_gate": {
                "projection_event_count": boundary_projection_count,
                "maximum_absolute_projection_adjustment": float(
                    np.max(np.abs(result.switch_boundary_projection_adjustments))
                ),
                "passed": boundary_projection_count == 0,
            },
            "probability_normalization_maximum_absolute_error": float(
                np.max(np.abs(result.posterior_probabilities.sum(axis=-1) - 1.0))
            ),
            "numerical_response_rule": config["numerical_response_rule"],
            "directed_transition_numeric_results": numeric_summaries,
            "full_stage_descriptive_accuracy": full_stage,
            "visual_review_required": True,
            "visual_review_status": "not_yet_performed",
            "forbidden_scope_checks": config["forbidden_scope"],
            "evidence_boundary": "warm-wet synthetic HBV-lite assimilation only; not forecast, state-accuracy, process-noise-switch, joint-identification, WALRUS, or real-basin evidence",
        }
        (staging / "summary.json").write_text(
            json.dumps(summary, indent=2, sort_keys=True, default=_json_default) + "\n",
            encoding="utf-8",
        )
        required = set(config["required_result_files"])
        actual_top_level = {path.name for path in staging.iterdir() if path.is_file()}
        missing_before_checksums = required - {"checksums.json"} - actual_top_level
        if missing_before_checksums:
            raise FileNotFoundError(
                f"formal result is missing required files: {sorted(missing_before_checksums)}"
            )
        if len(panel_manifest) != 48:
            raise ValueError("formal result must contain forty-eight visual panels")
        _write_checksums(staging)
        actual_top_level = {path.name for path in staging.iterdir() if path.is_file()}
        if required - actual_top_level:
            raise FileNotFoundError("formal result required-file gate failed")
        assert_output_paths_absent(config)
        os.replace(staging, output)
        return summary
    except Exception:
        if staging.exists() and not incomplete.exists():
            os.replace(staging, incomplete)
        raise


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--preflight", action="store_true")
    parser.add_argument("--preflight-blocks", type=int, default=1)
    arguments = parser.parse_args()
    if arguments.preflight:
        report = run_preflight(arguments.config, block_limit=arguments.preflight_blocks)
    else:
        report = run(arguments.config)
    print(json.dumps(report, indent=2, sort_keys=True, default=_json_default))


if __name__ == "__main__":
    main()
