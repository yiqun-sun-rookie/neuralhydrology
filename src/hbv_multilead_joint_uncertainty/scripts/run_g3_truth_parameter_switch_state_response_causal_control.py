"""Run the frozen true-parameter switch state-response causal control."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import platform
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable
from uuid import uuid4

import matplotlib
import matplotlib.image as matplotlib_image
import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SRC_ROOT = PROJECT_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from hbv_multilead_joint_uncertainty.truth_parameter_switch_state_response import (  # noqa: E402
    STATE_GROUP_NAMES,
    STATE_NAMES,
    build_switch_events,
    evaluate_physical_checks,
    summarize_state_response,
)
from hbv_multilead_joint_uncertainty.truth_parameter_switch_state_response_plotting import (  # noqa: E402
    plot_initial_new_parameter_domain_projection,
    plot_per_state_standardized_response,
    plot_state_group_standardized_response,
)


EXPERIMENT_ID = "g3_truth_parameter_switch_state_response_causal_control_v01"
BRANCH_NAMES = (
    "continue_old_true_parameters",
    "switch_to_new_true_parameters",
)
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
EXPECTED_ONLY_CHANGED_FACTOR = (
    "true parameter vector used for matched state propagation: "
    "continue old versus switch to new"
)
EXPECTED_FIXED_FACTORS = {
    "initial_state": "same saved fifteen-state truth vector from the day before the switch",
    "meteorological_forcing": "same saved daily rain potential evaporation and temperature",
    "process_perturbations": "same saved fifteen-state realized perturbation vector at every response lead",
    "response_window": "same thirty days",
    "state_projection_rule": "same parameter-specific reference truth projection",
    "observation_use": "none",
    "state_reset_or_manual_remapping": "none",
}
EXPECTED_POPULATION = {
    "matched_block_count": 8,
    "truth_trial_count": 3,
    "switch_count_per_trial": 2,
    "event_count": 48,
    "state_count": 15,
}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _require_unused_output(output_dir: Path) -> None:
    if output_dir.exists():
        raise FileExistsError(f"output directory already exists: {output_dir}")


def _validate_config(config: dict) -> None:
    if config.get("experiment_id") != EXPERIMENT_ID:
        raise ValueError("experiment identifier differs from the frozen contract")
    if config.get("status") != "frozen_before_run":
        raise ValueError("config status must be frozen_before_run")
    if tuple(config.get("branch_names", ())) != BRANCH_NAMES:
        raise ValueError("branch order differs from the frozen contract")
    if config.get("only_changed_factor") != EXPECTED_ONLY_CHANGED_FACTOR:
        raise ValueError("only changed factor differs from the frozen contract")
    if config.get("fixed_factors") != EXPECTED_FIXED_FACTORS:
        raise ValueError("fixed factors differ from the frozen contract")
    if config.get("population") != EXPECTED_POPULATION:
        raise ValueError("population differs from the frozen contract")
    if config.get("response_days") != 30:
        raise ValueError("response window differs from thirty days")
    if config.get("switch_boundaries_zero_based") != [180, 360]:
        raise ValueError("truth switch boundaries differ from the frozen contract")
    if any(
        config.get(name) is not False
        for name in (
            "observed_discharge_read",
            "forecast_executed",
            "assimilation_executed",
            "state_reset_at_switch",
        )
    ):
        raise ValueError("forbidden scope was enabled")
    if config.get("state_groups") != {
        "hydrologic_stores": [0, 1, 2, 3, 4],
        "routing_memory": [5, 6, 7, 8, 9, 10, 11, 12, 13, 14],
    }:
        raise ValueError("state groups differ from the complete fifteen-state contract")
    if config.get("numerical_tolerance") != 1e-12:
        raise ValueError("numerical tolerance differs from the frozen contract")
    for evidence_name in ("sealed_truth_evidence", "frozen_state_scale_evidence"):
        evidence = config.get(evidence_name, {})
        if not evidence.get("path") or len(str(evidence.get("sha256", ""))) != 64:
            raise ValueError(f"{evidence_name} identity is incomplete")
    source_groups = config.get("frozen_model_sources", {})
    if set(source_groups) != {"primary_reference", "independent_verifier"}:
        raise ValueError("frozen model-source groups are incomplete")
    if any(
        len(str(value)) != 64
        for group in source_groups.values()
        for value in group.values()
    ):
        raise ValueError("frozen model-source SHA-256 is incomplete")
    rule = config.get("decision_rule", {})
    if (
        rule.get(
            "clean_general_state_accuracy_truth_requires_zero_initial_new_parameter_domain_projection_events"
        )
        is not True
        or rule.get("if_projection_event_count_above_zero")
        != "requires_separate_fixed_parameter_state_jump_recovery_experiment"
        or rule.get("if_projection_event_count_equals_zero")
        != "suitable_as_clean_parameter_switch_truth_condition_for_state_accuracy"
    ):
        raise ValueError("decision rule differs from the frozen contract")


def _source_arrays(
    truth_path: Path,
    scale_path: Path,
    config: dict,
    *,
    on_read: Callable[[str], None] | None = None,
) -> tuple[dict[str, np.ndarray], dict[str, np.ndarray]]:
    """Read only the frozen state inputs named by the experiment contract."""
    truth_names = (
        "forcing_blocks",
        "warmup_days",
        "truth_states",
        "truth_process_perturbations",
        "truth_parameter_indices",
        "parameter_ids",
        "parameter_vectors",
    )
    scale_names = ("truth_standard_deviation", "state_names")

    def load(path: Path, names: tuple[str, ...]) -> dict[str, np.ndarray]:
        values: dict[str, np.ndarray] = {}
        with np.load(path, allow_pickle=False) as archive:
            missing = [name for name in names if name not in archive.files]
            if missing:
                raise KeyError(f"required arrays are missing from {path}: {missing}")
            for name in names:
                if on_read is not None:
                    on_read(name)
                values[name] = np.asarray(archive[name]).copy()
        return values

    truth = load(truth_path, truth_names)
    scale = load(scale_path, scale_names)
    for name, expected_shape in config["required_truth_arrays"].items():
        if truth[name].shape != tuple(expected_shape):
            raise ValueError(f"truth array {name} has shape {truth[name].shape}, expected {tuple(expected_shape)}")
    if truth["warmup_days"].shape != () or int(truth["warmup_days"].item()) < 0:
        raise ValueError("warmup_days must be one nonnegative scalar")
    for name, expected_shape in config["required_scale_arrays"].items():
        if scale[name].shape != tuple(expected_shape):
            raise ValueError(f"scale array {name} has shape {scale[name].shape}, expected {tuple(expected_shape)}")
    if tuple(scale["state_names"].astype(str)) != STATE_NAMES:
        raise ValueError("frozen state-scale names differ from the complete fifteen-state contract")
    scales = np.asarray(scale["truth_standard_deviation"], dtype=np.float64)
    if not np.all(np.isfinite(scales)) or np.any(scales <= 0.0):
        raise ValueError("frozen truth state standard deviations must be finite and positive")
    return truth, scale


def _verified_sources(config: dict) -> tuple[Path, Path, dict[str, str]]:
    identities: dict[str, str] = {}
    truth_path = (PROJECT_ROOT / config["sealed_truth_evidence"]["path"]).resolve()
    scale_path = (PROJECT_ROOT / config["frozen_state_scale_evidence"]["path"]).resolve()
    for label, path, expected in (
        ("sealed_truth_evidence", truth_path, config["sealed_truth_evidence"]["sha256"]),
        (
            "frozen_state_scale_evidence",
            scale_path,
            config["frozen_state_scale_evidence"]["sha256"],
        ),
    ):
        actual = _sha256(path)
        if actual != expected:
            raise ValueError(f"{label} SHA-256 changed: expected {expected}, got {actual}")
        identities[label] = actual
    for source_group, sources in config["frozen_model_sources"].items():
        for relative_path, expected in sources.items():
            source_path = (PROJECT_ROOT / relative_path).resolve()
            actual = _sha256(source_path)
            if actual != expected:
                raise ValueError(f"frozen model source changed: {relative_path}")
            identities[f"{source_group}:{relative_path}"] = actual
    return truth_path, scale_path, identities


def _state_group(state_index: int) -> str:
    return STATE_GROUP_NAMES[0] if state_index < 5 else STATE_GROUP_NAMES[1]


def _write_csv(path: Path, fieldnames: list[str], rows: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def _per_state_rows(summary: dict, state_scales: np.ndarray) -> list[dict]:
    rows = []
    for state_index, state_name in enumerate(STATE_NAMES):
        rows.append(
            {
                "state_index": state_index,
                "state_name": state_name,
                "state_group": _state_group(state_index),
                "frozen_state_standard_deviation": state_scales[state_index],
                "day_1_root_mean_square_raw_response": summary[
                    "per_state_day_1_root_mean_square_raw_response"
                ][state_index],
                "day_1_root_mean_square_standardized_response": summary[
                    "per_state_day_1_root_mean_square_standardized_response"
                ][state_index],
                "peak_root_mean_square_raw_response": summary[
                    "per_state_peak_root_mean_square_raw_response"
                ][state_index],
                "peak_root_mean_square_standardized_response": summary[
                    "per_state_peak_root_mean_square_standardized_response"
                ][state_index],
                "peak_lead_day": int(summary["per_state_peak_lead"][state_index]),
                "initial_new_domain_projection_event_count": int(
                    summary["initial_new_parameter_domain_projection_state_event_count"][state_index]
                ),
            }
        )
    return rows


def _transition_state_rows(summary: dict) -> list[dict]:
    labels = np.asarray(summary["transition_labels"]).astype(str)
    counts = np.asarray(summary["transition_event_count"], dtype=np.int64)
    raw = np.asarray(summary["transition_state_root_mean_square_raw_response"])
    standardized = np.asarray(summary["transition_state_root_mean_square_standardized_response"])
    rows = []
    for transition_index, label in enumerate(labels):
        for state_index, state_name in enumerate(STATE_NAMES):
            standardized_peak_lead = int(np.argmax(standardized[transition_index, :, state_index]))
            raw_peak_lead = int(np.argmax(raw[transition_index, :, state_index]))
            rows.append(
                {
                    "transition_label": label,
                    "event_count": int(counts[transition_index]),
                    "state_index": state_index,
                    "state_name": state_name,
                    "state_group": _state_group(state_index),
                    "day_1_root_mean_square_raw_response": raw[transition_index, 0, state_index],
                    "day_1_root_mean_square_standardized_response": standardized[
                        transition_index, 0, state_index
                    ],
                    "peak_root_mean_square_raw_response": raw[transition_index, raw_peak_lead, state_index],
                    "raw_peak_lead_day": raw_peak_lead + 1,
                    "peak_root_mean_square_standardized_response": standardized[
                        transition_index, standardized_peak_lead, state_index
                    ],
                    "standardized_peak_lead_day": standardized_peak_lead + 1,
                }
            )
    return rows


def _response_curve_rows(summary: dict) -> list[dict]:
    rows = []
    pooled_raw = np.asarray(summary["pooled_state_root_mean_square_raw_response"])
    pooled_standardized = np.asarray(summary["pooled_state_root_mean_square_standardized_response"])
    transition_raw = np.asarray(summary["transition_state_root_mean_square_raw_response"])
    transition_standardized = np.asarray(summary["transition_state_root_mean_square_standardized_response"])
    transition_groups = np.asarray(summary["transition_group_root_mean_square_standardized_response"])
    labels = np.asarray(summary["transition_labels"]).astype(str)
    group_values = np.asarray(summary["group_root_mean_square_standardized_response"])
    for lead in range(pooled_raw.shape[0]):
        for state_index, state_name in enumerate(STATE_NAMES):
            rows.append(
                {
                    "aggregation": "pooled",
                    "transition_label": "all_events",
                    "lead_day": lead + 1,
                    "object_type": "state",
                    "object_name": state_name,
                    "root_mean_square_raw_response": pooled_raw[lead, state_index],
                    "root_mean_square_standardized_response": pooled_standardized[lead, state_index],
                }
            )
        for group_index, group_name in enumerate(STATE_GROUP_NAMES):
            rows.append(
                {
                    "aggregation": "pooled",
                    "transition_label": "all_events",
                    "lead_day": lead + 1,
                    "object_type": "state_group",
                    "object_name": group_name,
                    "root_mean_square_raw_response": "",
                    "root_mean_square_standardized_response": group_values[lead, group_index],
                }
            )
        for transition_index, label in enumerate(labels):
            for state_index, state_name in enumerate(STATE_NAMES):
                rows.append(
                    {
                        "aggregation": "directed_transition",
                        "transition_label": label,
                        "lead_day": lead + 1,
                        "object_type": "state",
                        "object_name": state_name,
                        "root_mean_square_raw_response": transition_raw[transition_index, lead, state_index],
                        "root_mean_square_standardized_response": transition_standardized[
                            transition_index, lead, state_index
                        ],
                    }
                )
            for group_index, group_name in enumerate(STATE_GROUP_NAMES):
                rows.append(
                    {
                        "aggregation": "directed_transition",
                        "transition_label": label,
                        "lead_day": lead + 1,
                        "object_type": "state_group",
                        "object_name": group_name,
                        "root_mean_square_raw_response": "",
                        "root_mean_square_standardized_response": transition_groups[
                            transition_index, lead, group_index
                        ],
                    }
                )
    return rows


def _json_state_summary(summary: dict, scales: np.ndarray) -> list[dict]:
    rows = _per_state_rows(summary, scales)
    return [
        {
            key: (value.item() if isinstance(value, np.generic) else value)
            for key, value in row.items()
        }
        for row in rows
    ]


def _evidence_arrays(events: dict, summary: dict, scales: np.ndarray, physical_checks: dict) -> dict[str, np.ndarray]:
    event_array_names = (
        "event_indices",
        "block_indices",
        "truth_indices",
        "switch_boundaries",
        "old_parameter_indices",
        "new_parameter_indices",
        "branch_names",
        "parameter_names",
        "parameter_ids",
        "parameter_vectors",
        "warmup_days",
        "response_days",
        "initial_state",
        "forcing",
        "perturbations",
        "branch_parameters",
        "saved_truth",
        "initial_states",
        "shared_forcing",
        "shared_process_perturbations",
        "pretransition_projected_states",
        "pretransition_projection_adjustments",
        "deterministic_states",
        "postperturbation_projection_adjustments",
        "branch_states",
        "branch_state_difference",
        "new_branch_truth_reconstruction_maximum_absolute_error_by_event",
        "new_branch_truth_reconstruction_maximum_absolute_error",
        "routing_shift_maximum_absolute_error",
    )
    summary_array_names = (
        "state_names",
        "state_group_names",
        "transition_event_count",
        "standardized_response",
        "pooled_state_root_mean_square_raw_response",
        "pooled_state_root_mean_square_standardized_response",
        "transition_state_root_mean_square_raw_response",
        "transition_state_root_mean_square_standardized_response",
        "group_root_mean_square_standardized_response",
        "transition_group_root_mean_square_standardized_response",
        "per_state_day_1_root_mean_square_raw_response",
        "per_state_day_1_root_mean_square_standardized_response",
        "per_state_peak_root_mean_square_raw_response",
        "per_state_peak_root_mean_square_standardized_response",
        "per_state_peak_lead",
        "per_group_day_1_root_mean_square_standardized_response",
        "per_group_peak_root_mean_square_standardized_response",
        "per_group_peak_lead",
        "initial_new_parameter_domain_projection_adjustments",
        "initial_new_parameter_domain_projection_state_event_count",
    )
    arrays = {name: np.asarray(events[name]) for name in event_array_names}
    arrays["event_transition_labels"] = np.asarray(events["transition_labels"])
    arrays["unique_transition_labels"] = np.asarray(summary["transition_labels"])
    arrays.update({name: np.asarray(summary[name]) for name in summary_array_names})
    arrays["state_scales"] = np.asarray(scales, dtype=np.float64)
    arrays["lead_days"] = np.arange(1, int(np.asarray(events["response_days"]).item()) + 1, dtype=np.int64)
    arrays["initial_new_parameter_domain_projection_event_count"] = np.asarray(
        summary["initial_new_parameter_domain_projection_event_count"], dtype=np.int64
    )
    arrays["decision"] = np.asarray(summary["decision"])
    arrays["initial_new_parameter_domain_projection_standardized_adjustments"] = (
        np.asarray(summary["initial_new_parameter_domain_projection_adjustments"], dtype=np.float64)
        / scales[None, :]
    )
    check_names = tuple(name for name, value in physical_checks.items() if isinstance(value, bool) and name != "passed")
    value_names = tuple(name for name, value in physical_checks.items() if not isinstance(value, bool))
    arrays["physical_check_names"] = np.asarray(check_names)
    arrays["physical_check_passed"] = np.asarray([physical_checks[name] for name in check_names], dtype=bool)
    arrays["physical_value_names"] = np.asarray(value_names)
    arrays["physical_values"] = np.asarray([physical_checks[name] for name in value_names], dtype=np.float64)
    arrays["physical_checks_passed"] = np.asarray(physical_checks["passed"], dtype=bool)
    arrays["observed_discharge_read"] = np.asarray(False, dtype=bool)
    arrays["forecast_executed"] = np.asarray(False, dtype=bool)
    arrays["assimilation_executed"] = np.asarray(False, dtype=bool)
    arrays["state_reset_at_switch"] = np.asarray(False, dtype=bool)
    return arrays


def run(config_path: Path, output_dir: Path) -> dict:
    config_path = config_path.resolve()
    output_dir = output_dir.resolve()
    _require_unused_output(output_dir)
    config = json.loads(config_path.read_text(encoding="utf-8"))
    _validate_config(config)
    truth_path, scale_path, source_hashes = _verified_sources(config)
    requested_arrays: list[str] = []
    truth, scale = _source_arrays(truth_path, scale_path, config, on_read=requested_arrays.append)

    events = build_switch_events(
        **truth,
        switch_boundaries=config["switch_boundaries_zero_based"],
        response_days=config["response_days"],
    )
    expected_event_count = int(config["population"]["event_count"])
    if len(events["event_indices"]) != expected_event_count:
        raise ValueError("assembled switch-event count differs from the frozen contract")
    tolerance = float(config["numerical_tolerance"])
    physical_checks = evaluate_physical_checks(events, tolerance=tolerance)
    if not physical_checks["passed"]:
        raise ValueError(f"physical or reconstruction gate failed: {physical_checks}")
    scales = np.asarray(scale["truth_standard_deviation"], dtype=np.float64)
    summary = summarize_state_response(
        events["branch_state_difference"],
        scales,
        events["transition_labels"],
        events["pretransition_projection_adjustments"][:, 1, 0],
        tolerance=tolerance,
    )
    expected_decision = (
        config["decision_rule"]["if_projection_event_count_above_zero"]
        if summary["initial_new_parameter_domain_projection_event_count"] > 0
        else config["decision_rule"]["if_projection_event_count_equals_zero"]
    )
    if summary["decision"] != expected_decision:
        raise ValueError("computed decision differs from the frozen decision rule")

    evidence = _evidence_arrays(events, summary, scales, physical_checks)
    projection = np.asarray(summary["initial_new_parameter_domain_projection_adjustments"])
    event_labels = np.asarray(events["transition_labels"]).astype(str)
    unique_labels = np.asarray(summary["transition_labels"]).astype(str)
    projection_events_by_transition = {
        label: int(np.count_nonzero(np.any(np.abs(projection[event_labels == label]) > tolerance, axis=1)))
        for label in unique_labels
    }
    group_summary = []
    for group_index, group_name in enumerate(STATE_GROUP_NAMES):
        group_summary.append(
            {
                "state_group": group_name,
                "day_1_root_mean_square_standardized_response": float(
                    summary["per_group_day_1_root_mean_square_standardized_response"][group_index]
                ),
                "peak_root_mean_square_standardized_response": float(
                    summary["per_group_peak_root_mean_square_standardized_response"][group_index]
                ),
                "peak_lead_day": int(summary["per_group_peak_lead"][group_index]),
            }
        )
    result_summary = {
        "experiment_id": EXPERIMENT_ID,
        "status": "complete_pending_independent_verification",
        "scientific_conclusion_withheld_until_independent_verification": True,
        "decision": summary["decision"],
        "scope": config["scope_limit"],
        "evidence_boundary": (
            "HBV synthetic truth-generator state response only; no observation update, "
            "assimilation-method comparison, forecast evaluation, lowland-model claim, or real-basin claim."
        ),
        "only_changed_factor": config["only_changed_factor"],
        "event_count": expected_event_count,
        "response_days": config["response_days"],
        "state_count": config["population"]["state_count"],
        "directed_transition_event_counts": {
            label: int(count)
            for label, count in zip(summary["transition_labels"], summary["transition_event_count"])
        },
        "initial_new_parameter_domain_projection_event_count": int(
            summary["initial_new_parameter_domain_projection_event_count"]
        ),
        "initial_new_parameter_domain_projection_events_by_transition": projection_events_by_transition,
        "initial_new_parameter_domain_projection_state_event_count": {
            name: int(count)
            for name, count in zip(
                STATE_NAMES,
                summary["initial_new_parameter_domain_projection_state_event_count"],
            )
        },
        "new_branch_truth_reconstruction_maximum_absolute_error": float(
            events["new_branch_truth_reconstruction_maximum_absolute_error"]
        ),
        "physical_checks": physical_checks,
        "per_state_summary": _json_state_summary(summary, scales),
        "state_group_summary": group_summary,
        "forbidden_scope_checks": {
            "observed_discharge_read": False,
            "forecast_executed": False,
            "assimilation_executed": False,
            "state_reset_at_switch": False,
        },
        "source_hashes": source_hashes,
        "requested_source_arrays": requested_arrays,
    }

    output_dir.parent.mkdir(parents=True, exist_ok=True)
    staging = output_dir.with_name(f"{output_dir.name}.incomplete.{uuid4().hex}")
    staging.mkdir(exist_ok=False)
    (staging / "config_snapshot.json").write_text(
        json.dumps(config, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    environment = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "python": sys.version,
        "platform": platform.platform(),
        "numpy": np.__version__,
        "matplotlib": matplotlib.__version__,
        "config_path": str(config_path),
        "truth_source_path": str(truth_path),
        "state_scale_source_path": str(scale_path),
        "source_hashes": source_hashes,
        "requested_source_arrays": requested_arrays,
    }
    (staging / "environment.json").write_text(
        json.dumps(environment, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    np.savez_compressed(staging / "evidence.npz", **evidence)
    state_rows = _per_state_rows(summary, scales)
    _write_csv(staging / "per_state_summary.csv", list(state_rows[0]), state_rows)
    transition_rows = _transition_state_rows(summary)
    _write_csv(staging / "transition_state_summary.csv", list(transition_rows[0]), transition_rows)
    curve_rows = _response_curve_rows(summary)
    _write_csv(staging / "response_curves.csv", list(curve_rows[0]), curve_rows)
    (staging / "summary.json").write_text(
        json.dumps(result_summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    leads = evidence["lead_days"]
    plot_per_state_standardized_response(
        staging / "per_state_standardized_response.png",
        leads=leads,
        state_names=STATE_NAMES,
        transition_labels=summary["transition_labels"],
        transition_state_response=summary["transition_state_root_mean_square_standardized_response"],
    )
    plot_state_group_standardized_response(
        staging / "state_group_standardized_response.png",
        leads=leads,
        group_names=STATE_GROUP_NAMES,
        pooled_group_response=summary["group_root_mean_square_standardized_response"],
        transition_labels=summary["transition_labels"],
        transition_group_response=summary["transition_group_root_mean_square_standardized_response"],
    )
    plot_initial_new_parameter_domain_projection(
        staging / "initial_new_parameter_domain_projection.png",
        standardized_projection_adjustments=evidence[
            "initial_new_parameter_domain_projection_standardized_adjustments"
        ],
        state_names=STATE_NAMES,
        event_transition_labels=events["transition_labels"],
    )
    for figure_name in (
        "per_state_standardized_response.png",
        "state_group_standardized_response.png",
        "initial_new_parameter_domain_projection.png",
    ):
        image = matplotlib_image.imread(staging / figure_name)
        if image.ndim not in (2, 3) or image.size == 0 or not np.all(np.isfinite(image)):
            raise ValueError(f"generated figure failed decoding: {figure_name}")

    expected_files = set(config["output_files"])
    without_checksums = expected_files - {"checksums.json"}
    actual_without_checksums = {path.name for path in staging.iterdir()}
    if actual_without_checksums != without_checksums:
        raise ValueError(
            f"result file contract differs before checksums: expected {sorted(without_checksums)}, "
            f"got {sorted(actual_without_checksums)}"
        )
    checksums = {name: _sha256(staging / name) for name in sorted(without_checksums)}
    (staging / "checksums.json").write_text(
        json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    if {path.name for path in staging.iterdir()} != expected_files:
        raise ValueError("complete result file contract was not satisfied")
    if any(_sha256(staging / name) != digest for name, digest in checksums.items()):
        raise ValueError("artifact checksum self-check failed")

    _require_unused_output(output_dir)
    staging.rename(output_dir)
    return {**result_summary, "result_directory": str(output_dir)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    run(args.config, args.output_dir)


if __name__ == "__main__":
    main()
