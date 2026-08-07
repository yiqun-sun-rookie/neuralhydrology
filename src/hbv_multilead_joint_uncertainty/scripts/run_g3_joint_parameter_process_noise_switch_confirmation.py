"""Formal runner for joint parameter and process-noise switching confirmation.

Blind protocol: the runner seals all numeric response results into the result
directory but prints only physical gates, so the operator can hand the event
panels to the blinded human reviewer without seeing numeric verdicts.
"""

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

from hbv_multilead_joint_uncertainty.joint_parameter_process_noise_switch_confirmation import (  # noqa: E402
    run_joint_switch_confirmation,
    summarize_joint_descriptive_readouts,
    summarize_joint_switch_response,
)
from hbv_multilead_joint_uncertainty.state_domain_consistent_parameter_switch_confirmation import (  # noqa: E402
    audit_candidate_distinguishability,
    validate_parameter_candidates,
)

EXPERIMENT_ID = "g3_joint_parameter_process_noise_switch_confirmation_v04"
CONFIG_SHA256 = "2ca2c7cd288614f79d1a772c81148fa37742b9275820a2b561a78c70376e8763"
DEFAULT_CONFIG = (
    PROJECT_ROOT
    / "src"
    / "hbv_multilead_joint_uncertainty"
    / "configs"
    / f"{EXPERIMENT_ID}.json"
)
PARAMETER_NAMES = (
    "parTT", "parCFMAX", "parCFR", "parCWH", "parFC", "parBETA", "parLP",
    "parK0", "parK1", "parUZL", "parPERC", "parK2", "lag_time",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_and_validate_config(path: Path = DEFAULT_CONFIG) -> dict:
    if _sha256(path) != CONFIG_SHA256:
        raise ValueError("frozen configuration hash mismatch")
    config = json.loads(path.read_text(encoding="utf-8"))
    if config["experiment_id"] != EXPERIMENT_ID:
        raise ValueError("experiment identifier changed")
    if config["candidate_count"] != 9:
        raise ValueError("candidate count changed")
    return config


def _result_paths(config: dict) -> tuple[Path, Path, Path]:
    return (
        (PROJECT_ROOT / config["result_relative_path"]).resolve(),
        (PROJECT_ROOT / config["visual_review_relative_path"]).resolve(),
        (PROJECT_ROOT / config["verification_relative_path"]).resolve(),
    )


def assert_output_paths_absent(config: dict) -> None:
    for path in _result_paths(config):
        if path.exists():
            raise FileExistsError(f"protected output path already exists: {path}")


def _verify_parent_config(config: dict) -> dict:
    contract = config["parameter_source"]
    path = (PROJECT_ROOT / contract["frozen_config"]).resolve()
    if not path.is_file():
        raise FileNotFoundError(f"sealed parent config does not exist: {path}")
    if _sha256(path) != str(contract["sha256"]).lower():
        raise ValueError("sealed parent config hash mismatch")
    parent = json.loads(path.read_text(encoding="utf-8"))
    if config["parameter_candidates"] != parent["parameter_candidates"]:
        raise ValueError("parameter candidates differ from the sealed parent config")
    return parent


def _verify_observation_source(config: dict) -> float:
    contract = config["observation_noise_source"]
    path = (PROJECT_ROOT / contract["path"]).resolve()
    if not path.is_file():
        raise FileNotFoundError(f"sealed source does not exist: {path}")
    if _sha256(path) != str(contract["sha256"]).lower():
        raise ValueError("sealed observation-noise source hash mismatch")
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


def _parameter_vectors_from_config(config: dict) -> dict[str, dict[str, float]]:
    vectors = {
        str(row["parameter_id"]): {name: float(row[name]) for name in PARAMETER_NAMES}
        for row in config["parameter_candidates"]
    }
    validate_parameter_candidates(vectors)
    return vectors


def _process_standard_deviations(config: dict) -> dict[str, float]:
    rows = config["process_noise_candidates"]
    if len(rows) != 3:
        raise ValueError("process contract must contain three levels")
    result = {}
    for row in rows:
        standard_deviation = float(row["standard_deviation_mm_day"])
        if abs(float(row["variance_mm2_day2"]) - standard_deviation**2) > 1e-12:
            raise ValueError("process-noise variance is inconsistent")
        result[str(row["process_id"])] = standard_deviation
    return result


def _validate_seed_contract(config: dict) -> None:
    construction = set(int(v) for v in config["candidate_construction_seeds"]["forcing"])
    formal_groups = {
        key: set(int(v) for v in values)
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
    if not all(str(v).startswith("3805") for v in construction):
        raise ValueError("candidate-construction seed prefix changed")
    expected_prefixes = {"forcing": "3801", "process_noise": "3802", "observation_noise": "3803"}
    for key, values in formal_groups.items():
        if not all(str(v).startswith(expected_prefixes[key]) for v in values):
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
    if result.shape != (len(seeds), total_days, 3) or not np.all(np.isfinite(result)):
        raise FloatingPointError("forcing generation failed")
    return result


def _write_csv(path: Path, rows: list[dict], fieldnames: tuple[str, ...] | None = None) -> None:
    if not rows:
        raise ValueError(f"refusing to write empty CSV: {path}")
    names = tuple(rows[0]) if fieldnames is None else fieldnames
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=names)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def _margin_rows(result, attribute: str, identifier_attribute: str) -> list[dict]:
    margins = getattr(result, attribute)
    identifiers = [str(v) for v in getattr(result, identifier_attribute)]
    rows = []
    block_count, trial_count, day_count, _ = margins.shape
    for block in range(block_count):
        for trial in range(trial_count):
            for day in range(day_count):
                row = {
                    "block_id": str(result.block_ids[block]),
                    "trial_index": trial,
                    "day_number": day + 1,
                }
                for index, identifier in enumerate(identifiers):
                    row[identifier] = repr(float(margins[block, trial, day, index]))
                rows.append(row)
    return rows


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
        if start < 0 or stop > result.parameter_margin_probabilities.shape[2]:
            raise ValueError("visual-review window exceeds saved probabilities")
        relative_days = np.arange(relative_start, relative_end + 1)
        figure, axes = plt.subplots(2, 1, figsize=(9.6, 8.6), sharex=True)
        panels = (
            (
                axes[0],
                result.parameter_margin_probabilities[block, trial, start:stop],
                [str(v) for v in result.parameter_ids],
                str(event["new_parameter_id"]),
                "Parameter margin (posterior summed over noise levels)",
            ),
            (
                axes[1],
                result.noise_margin_probabilities[block, trial, start:stop],
                [str(v) for v in result.process_ids],
                str(event["new_process_id"]),
                "Noise margin (posterior summed over parameter candidates)",
            ),
        )
        for axis, margins, identifiers, new_identifier, title in panels:
            for index, identifier in enumerate(identifiers):
                is_new = identifier == new_identifier
                axis.plot(
                    relative_days,
                    margins[:, index],
                    color=colors[index],
                    linewidth=3.0 if is_new else 1.6,
                    alpha=1.0 if is_new else 0.78,
                    label=f"{identifier}{' (new true)' if is_new else ''}",
                )
            axis.axvline(0, color="black", linestyle="--", linewidth=1.2)
            axis.set_xlim(relative_start, relative_end)
            axis.set_ylim(0.0, 1.0)
            axis.set_ylabel("Posterior probability")
            axis.set_title(title, fontsize=10)
            axis.grid(alpha=0.2)
            axis.legend(loc="best", fontsize=8)
        axes[1].set_xlabel("Day relative to the simultaneous true switch")
        figure.suptitle(f"Blinded visual review item {review_index:03d}")
        figure.tight_layout(rect=(0, 0, 1, 0.97))
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
                "new_parameter_id": event["new_parameter_id"],
                "old_process_id": event["old_process_id"],
                "new_process_id": event["new_process_id"],
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
        "src/hbv_multilead_joint_uncertainty/joint_parameter_process_noise_switch_confirmation.py",
        "src/hbv_multilead_joint_uncertainty/scripts/run_g3_joint_parameter_process_noise_switch_confirmation.py",
        "src/hbv_multilead_joint_uncertainty/scripts/verify_g3_joint_parameter_process_noise_switch_confirmation.py",
        "test/test_hbv_joint_parameter_process_noise_switch_confirmation.py",
    )


def _source_manifest() -> dict:
    rows = {}
    for relative in _source_entries():
        path = PROJECT_ROOT / relative
        if not path.is_file():
            raise FileNotFoundError(f"required source snapshot input missing: {path}")
        rows[relative] = _sha256(path)
    return {"experiment_id": EXPERIMENT_ID, "config_sha256": CONFIG_SHA256, "files": rows}


def _git_output(arguments: list[str]) -> str:
    completed = subprocess.run(
        ["git", *arguments], cwd=PROJECT_ROOT, check=True, capture_output=True, text=True
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
    _verify_parent_config(config)
    observation_std = _verify_observation_source(config)
    vectors = _parameter_vectors_from_config(config)
    identifiers = tuple(vectors)
    standard_deviations = _process_standard_deviations(config)

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
    block_ids = tuple(f"formal_joint_block_{index + 1:02d}" for index in range(8))
    result = run_joint_switch_confirmation(
        formal_forcing,
        block_ids=block_ids,
        parameter_vectors=vectors,
        process_standard_deviations=standard_deviations,
        parameter_orders=config["truth_trial_stage_orders"]["parameter"],
        process_orders=config["truth_trial_stage_orders"]["process_noise"],
        process_noise_seeds=config["formal_confirmation_seeds"]["process_noise"],
        observation_noise_seeds=config["formal_confirmation_seeds"]["observation_noise"],
        warmup_days=int(config["forcing"]["warmup_days"]),
        stage_length_days=int(config["population"]["stage_length_days"]),
        initial_covariance_fraction=float(config["filter"]["initial_covariance_fraction"]),
        observation_standard_deviation=observation_std,
        factor_transition_stay_probability=float(
            config["filter"]["factor_transition_stay_probability"]
        ),
    )

    response = summarize_joint_switch_response(
        result.parameter_margin_probabilities,
        result.noise_margin_probabilities,
        result.parameter_schedule,
        result.process_schedule,
        [str(v) for v in result.parameter_ids],
        [str(v) for v in result.process_ids],
        config["parameter_margin_response_rule"],
        config["noise_margin_response_rule"],
    )
    events = response["events"]
    descriptive = summarize_joint_descriptive_readouts(
        result.posterior_probabilities,
        result.parameter_margin_probabilities,
        result.noise_margin_probabilities,
        result.parameter_schedule,
        result.process_schedule,
        [str(v) for v in result.parameter_ids],
        [str(v) for v in result.process_ids],
        [str(v) for v in result.candidate_parameter_ids],
        [str(v) for v in result.candidate_process_ids],
        int(config["population"]["stage_length_days"]),
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
        _write_csv(
            staging / "parameter_vectors.csv",
            [
                {"parameter_id": identifier, **{name: repr(vectors[identifier][name]) for name in PARAMETER_NAMES}}
                for identifier in identifiers
            ],
        )
        _write_csv(
            staging / "process_noise_covariances.csv",
            [
                {
                    "process_id": identifier,
                    "state_index": 4,
                    "state_name": "SLZ",
                    "standard_deviation_mm_day": repr(standard_deviations[identifier]),
                    "variance_mm2_day2": repr(standard_deviations[identifier] ** 2),
                }
                for identifier in standard_deviations
            ],
        )
        _write_csv(staging / "candidate_construction_audit.csv", construction_audit)
        _write_csv(
            staging / "daily_parameter_margin_probabilities.csv",
            _margin_rows(result, "parameter_margin_probabilities", "parameter_ids"),
        )
        _write_csv(
            staging / "daily_noise_margin_probabilities.csv",
            _margin_rows(result, "noise_margin_probabilities", "process_ids"),
        )
        event_rows = [
            {
                key: ("" if value is None else value)
                for key, value in event.items()
            }
            for event in events
        ]
        _write_csv(staging / "switch_response_events_numeric.csv", event_rows)
        summary_rows = [
            {"margin": "parameter", **row} for row in response["parameter_margin_summaries"]
        ] + [
            {"margin": "process_noise", **row} for row in response["noise_margin_summaries"]
        ]
        _write_csv(
            staging / "switch_response_summary_numeric.csv",
            [
                {key: ("" if value is None else value) for key, value in row.items()}
                for row in summary_rows
            ],
        )
        panel_manifest = _render_event_panels(staging, result, events, config)
        (staging / "event_panel_manifest.json").write_text(
            json.dumps(
                {
                    "display_order_seed": config["visual_review_rule"]["display_order_seed"],
                    "numeric_decisions_shown_in_panels": False,
                    "labels_per_event": config["visual_review_rule"]["labels_per_event"],
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
            process_ids=result.process_ids,
            candidate_parameter_ids=result.candidate_parameter_ids,
            candidate_process_ids=result.candidate_process_ids,
            parameter_vectors=np.asarray(
                [[vectors[identifier][name] for name in PARAMETER_NAMES] for identifier in identifiers],
                dtype=np.float64,
            ),
            parameter_names=np.asarray(PARAMETER_NAMES, dtype=np.str_),
            process_standard_deviations=result.process_standard_deviations,
            forcing_blocks=result.forcing_blocks,
            parameter_schedule=result.parameter_schedule,
            process_schedule=result.process_schedule,
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
            parameter_margin_probabilities=result.parameter_margin_probabilities,
            noise_margin_probabilities=result.noise_margin_probabilities,
            global_posterior_states=result.global_posterior_states,
            observation_standard_deviation=np.asarray(observation_std),
        )
        (staging / "source_manifest.json").write_text(
            json.dumps(_source_manifest(), indent=2, sort_keys=True) + "\n",
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
            json.dumps(environment, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        registry = {
            "exp_id": EXPERIMENT_ID,
            "type": "prospective_synthetic_joint_switch_confirmation",
            "hypothesis": config["scientific_question"],
            "base_config": config["parameter_source"],
            "changed_factor": "true parameter candidate and true lower-groundwater process-noise level switch together at days 181 and 361",
            "fixed_factors": [
                "fifteen-state HBV-lite implementation",
                "shared state-domain parameters parFC and parCWH",
                "fixed observation noise",
                "forcing distribution",
                "initial conditions",
                "nine-candidate bank",
                "factorized transition probabilities",
            ],
            "seeds": config["formal_confirmation_seeds"],
            "status": "complete_pending_blinded_visual_review_and_independent_verification",
            "run_dir": config["result_relative_path"],
            "metrics_path": f"{config['result_relative_path']}/switch_response_summary_numeric.csv",
            "paper_name": "not_assigned",
            "notes": "No forecast; margins judged separately; low-to-medium noise margin preregistered as expected not to pass; final event success also requires sealed blinded visual review.",
        }
        (staging / "registry_entry.json").write_text(
            json.dumps(registry, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        truth_projection_count = int(
            np.count_nonzero(np.any(result.truth_projection_adjustments != 0.0, axis=-1))
        )
        boundary_projection_count = int(
            np.count_nonzero(
                np.any(result.switch_boundary_projection_adjustments != 0.0, axis=-1)
            )
        )
        gates = {
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
            "truth_transition_count": int(np.prod(result.truth_states.shape[:3])),
            "switch_event_count": len(events),
        }
        summary = {
            "experiment_id": EXPERIMENT_ID,
            "status": "complete_pending_blinded_visual_review_and_independent_verification",
            "scientific_conclusion_withheld": True,
            "candidate_construction_audit": construction_audit,
            "parameter_ids": list(identifiers),
            "process_ids": list(standard_deviations),
            "shared_parFC": vectors[identifiers[0]]["parFC"],
            "shared_parCWH": vectors[identifiers[0]]["parCWH"],
            "switched_factors": "true parameter candidate and true process-noise level together",
            "physical_gates": gates,
            "parameter_margin_response_rule": config["parameter_margin_response_rule"],
            "noise_margin_response_rule": config["noise_margin_response_rule"],
            "preregistered_expectations": config["preregistered_expectations"],
            "parameter_margin_numeric_results": response["parameter_margin_summaries"],
            "noise_margin_numeric_results": response["noise_margin_summaries"],
            "descriptive_readouts": descriptive,
            "visual_review_required": True,
            "visual_review_status": "not_yet_performed",
            "forbidden_scope_checks": config["forbidden_scope"],
            "evidence_boundary": "warm-wet synthetic HBV-lite assimilation only; joint unique-combination readout is descriptive; not forecast, state-accuracy, WALRUS, or real-basin evidence",
        }
        (staging / "summary.json").write_text(
            json.dumps(summary, indent=2, sort_keys=True, default=_json_default) + "\n",
            encoding="utf-8",
        )
        required = set(config["required_result_files"])
        actual_top_level = {path.name for path in staging.iterdir() if path.is_file()}
        missing = required - {"checksums.json"} - actual_top_level
        if missing:
            raise FileNotFoundError(f"formal result is missing required files: {sorted(missing)}")
        if len(panel_manifest) != 48:
            raise ValueError("formal result must contain forty-eight visual panels")
        _write_checksums(staging)
        actual_top_level = {path.name for path in staging.iterdir() if path.is_file()}
        if required - actual_top_level:
            raise FileNotFoundError("formal result required-file gate failed")
        assert_output_paths_absent(config)
        os.replace(staging, output)
        return {"blind_safe_report": gates, "sealed_summary_path": str(output / "summary.json")}
    except Exception:
        if staging.exists() and not incomplete.exists():
            os.replace(staging, incomplete)
        raise


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    arguments = parser.parse_args()
    report = run(arguments.config)
    print(json.dumps(report, indent=2, sort_keys=True, default=_json_default))


if __name__ == "__main__":
    main()
