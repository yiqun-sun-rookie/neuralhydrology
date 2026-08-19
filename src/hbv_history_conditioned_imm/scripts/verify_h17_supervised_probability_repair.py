"""Independently verify one supervised probability repair artifact."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
from typing import Any, Mapping
import zipfile

import numpy as np
import torch

from hbv_history_conditioned_imm.causal_duration import (
    CausalSemiMarkovTransitionModule,
)
from hbv_history_conditioned_imm.filter import (
    DifferentiableInteractingMultipleModel,
)
from hbv_history_conditioned_imm.hbv import HBV15Model
from hbv_history_conditioned_imm.long_history import ObservableAssimilationBatch
from hbv_history_conditioned_imm.parameter_switch import build_parameter_candidates
from hbv_history_conditioned_imm.supervised_probability import (
    ActiveRowSupervision,
    rollout_semi_markov_probability,
)
from hbv_history_conditioned_imm.scripts.verify_h17_supervised_probability_upper_bound import (
    verify_h17_result,
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _is_explicit_duration(config: Mapping[str, Any]) -> bool:
    return (
        config.get("network", {}).get("transition_architecture")
        == "explicit_causal_duration"
    )


def _base_transition(config: Mapping[str, Any]) -> torch.Tensor:
    stay = float(config["filter"]["base_transition_stay_probability"])
    switch = (1.0 - stay) / 2.0
    return torch.tensor(
        [[stay, switch, switch], [switch, stay, switch], [switch, switch, stay]],
        dtype=torch.float64,
    )


def _duration_module(
    config: Mapping[str, Any],
) -> CausalSemiMarkovTransitionModule:
    duration = config["duration_contract"]
    return CausalSemiMarkovTransitionModule(
        base_transition=_base_transition(config),
        maximum_age=int(duration["maximum_age"]),
        hazard_hidden_size=int(duration["hazard_hidden_size"]),
        maximum_logit_correction=float(duration["maximum_logit_correction"]),
        minimum_differentiable_mode_probability=float(
            duration.get("minimum_differentiable_mode_probability", 1e-12)
        ),
        age_risk_representation=str(
            duration.get("age_risk_representation", "smooth_tanh_network")
        ),
        piecewise_knot_count=int(duration.get("piecewise_knot_count", 31)),
    )


def _close(left: Any, right: Any, *, tolerance: float = 1e-12) -> bool:
    if isinstance(left, Mapping) and isinstance(right, Mapping):
        return set(left) == set(right) and all(
            _close(left[name], right[name], tolerance=tolerance) for name in left
        )
    if isinstance(left, (list, tuple)) and isinstance(right, (list, tuple)):
        return len(left) == len(right) and all(
            _close(a, b, tolerance=tolerance) for a, b in zip(left, right)
        )
    if isinstance(left, (int, float)) and not isinstance(left, bool):
        return isinstance(right, (int, float)) and np.isclose(
            float(left), float(right), rtol=0.0, atol=tolerance
        )
    return left == right


def _resolved_project_root(result_root: Path, supplied: str | Path | None) -> Path:
    if supplied is not None:
        return Path(supplied).resolve()
    for candidate in (result_root, *result_root.parents):
        if (candidate / "src/hbv_history_conditioned_imm").is_dir():
            return candidate
    raise ValueError("project root could not be resolved")


def _live_registry_checks(
    project_root: Path,
    config: Mapping[str, Any],
    *,
    expected_repair_status: str,
) -> dict[str, bool]:
    registry_path = (
        project_root
        / "src/hbv_history_conditioned_imm/configs/experiment_registry.csv"
    )
    with registry_path.open("r", encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    experiment_rows = [
        row for row in rows if row.get("exp_id") == config["experiment_id"]
    ]
    h17_rows = [
        row
        for row in rows
        if row.get("exp_id")
        == "h17_supervised_active_row_probability_upper_bound_v01"
    ]
    h18_rows = [
        row
        for row in rows
        if str(row.get("exp_id", "")).lower().startswith("h18")
    ]
    return {
        "live_registry_contains_exactly_one_repair_row": len(experiment_rows) == 1,
        "live_registry_repair_row_matches_config": (
            len(experiment_rows) == 1
            and experiment_rows[0].get("run_dir") == config["result_relative_path"]
            and experiment_rows[0].get("status") == expected_repair_status
        ),
        "live_registry_preserves_exactly_one_h17_row": (
            len(h17_rows) == 1
            and h17_rows[0].get("status")
            == "completed_supervised_upper_bound_hold"
        ),
        "live_registry_contains_no_h18_row": len(h18_rows) == 0,
    }


def _weighting_audit_matches(
    root: Path,
    project_root: Path,
    config: Mapping[str, Any],
) -> bool:
    weighting = str(config["training"].get("sample_weighting", "uniform"))
    audit_path = root / "weighting_audit.json"
    if weighting == "uniform":
        return not audit_path.exists()
    if weighting != "sqrt_inverse_age_source_frequency" or not audit_path.is_file():
        return False
    audit = json.loads(audit_path.read_text("utf-8"))
    arrays_path = (
        project_root / str(config["source_h16_preflight_arrays"]["path"])
    ).resolve()
    with np.load(arrays_path, allow_pickle=False) as source:
        labels = np.asarray(source["split_labels"]).astype(str)
        selected_blocks = np.flatnonzero(labels == "training")[: int(
            config["data"]["training_blocks"]
        )]
        days = int(config["data"]["assimilation_days"])
        mask = np.asarray(source["transition_evaluation_mask"])[
            selected_blocks, :days
        ].astype(bool)
        sources = np.asarray(source["active_source_indices"])[
            selected_blocks, :days
        ][mask].astype(np.int64)
        ages = np.asarray(source["regime_age_before_transition"])[
            selected_blocks, :days
        ][mask].astype(np.int64)
    age_groups = np.where(ages < 30, 0, np.where(ages < 40, 1, 2))
    counts = np.zeros((3, 3), dtype=np.int64)
    for age_group in range(3):
        for source_index in range(3):
            counts[age_group, source_index] = np.count_nonzero(
                (age_groups == age_group) & (sources == source_index)
            )
    selected_counts = counts[age_groups, sources]
    weights = 1.0 / np.sqrt(selected_counts.astype(np.float64))
    weights = weights / weights.mean()
    means = np.zeros((3, 3), dtype=np.float64)
    for age_group in range(3):
        for source_index in range(3):
            selected = (age_groups == age_group) & (sources == source_index)
            if np.any(selected):
                means[age_group, source_index] = weights[selected].mean()
    return bool(
        audit.get("method") == weighting
        and audit.get("training_cell_counts") == counts.tolist()
        and np.allclose(
            np.asarray(audit.get("training_cell_mean_weights"), dtype=np.float64),
            means,
            rtol=0.0,
            atol=1e-12,
        )
        and int(audit.get("evaluated_training_day_count", -1)) == int(mask.sum())
        and np.isclose(
            float(audit.get("mean_evaluated_training_weight", np.nan)),
            1.0,
            rtol=0.0,
            atol=1e-12,
        )
        and audit.get("weights_computed_from_training_supervision_only") is True
        and int(audit.get("validation_read_count_for_weighting", -1)) == 0
        and int(audit.get("test_read_count_for_weighting", -1)) == 0
        and audit.get("validation_metrics_weighted") is False
        and audit.get("test_metrics_weighted") is False
    )


def _duration_artifacts_match(
    root: Path,
    config: Mapping[str, Any],
) -> bool:
    if not _is_explicit_duration(config):
        return all(
            not (root / name).exists()
            for name in (
                "duration_contract.json",
                "duration_causality_audit.json",
                "duration_state_audit.json",
            )
        )
    contract = json.loads((root / "duration_contract.json").read_text("utf-8"))
    causality = json.loads((root / "causality_audit.json").read_text("utf-8"))
    duration_causality = json.loads(
        (root / "duration_causality_audit.json").read_text("utf-8")
    )
    state_audit = json.loads(
        (root / "duration_state_audit.json").read_text("utf-8")
    )
    causality_copy = dict(duration_causality)
    causal_flags = {
        name: causality_copy.pop(name, None)
        for name in (
            "same_day_observation_used",
            "future_observation_used",
            "true_mode_used",
            "true_age_used",
            "hard_argmax_reset_used",
        )
    }
    if (
        contract != config.get("duration_contract")
        or causality_copy != causality
        or any(value is not False for value in causal_flags.values())
        or state_audit.get("true_mode_and_age_used_for_scoring_only") is not True
        or state_audit.get("true_mode_or_age_used_by_transition_module") is not False
    ):
        return False

    with np.load(root / "daily_arrays.npz", allow_pickle=False) as source:
        arrays = {name: source[name] for name in source.files}
    mask = np.asarray(arrays["transition_evaluation_mask"], dtype=np.bool_)
    sources = np.asarray(arrays["active_source_indices"], dtype=np.int64)[mask]
    ages = np.asarray(arrays["regime_age_before_transition"], dtype=np.int64)[mask]
    targets = np.asarray(
        arrays["oracle_active_row_probabilities"], dtype=np.float64
    )[mask]
    rows = np.arange(sources.size)
    oracle_hazards = 1.0 - targets[rows, sources]
    for seed_value in config["training"]["history_network_initialization_seeds"]:
        seed = str(int(seed_value))
        matrices = np.asarray(
            arrays[f"history_seed_{seed}_transition_matrices"], dtype=np.float64
        )
        hazards = np.asarray(
            arrays[f"history_seed_{seed}_duration_source_hazards"],
            dtype=np.float64,
        )
        expected_ages = np.asarray(
            arrays[f"history_seed_{seed}_duration_expected_ages"],
            dtype=np.float64,
        )
        posterior = np.asarray(
            arrays[f"history_seed_{seed}_posterior_mode_probabilities"],
            dtype=np.float64,
        )
        age_hazards = np.asarray(
            arrays[f"history_seed_{seed}_age_hazards"], dtype=np.float64
        )
        inferred_active = hazards[mask][rows, sources]
        expected_active = expected_ages[mask][rows, sources]
        posterior_active = posterior[mask][rows, sources]
        direct = age_hazards[np.minimum(ages - 1, age_hazards.size - 1)]
        recomputed = {
            "evaluated_day_count": int(np.count_nonzero(mask)),
            "direct_age_risk_mean_absolute_error": float(
                np.mean(np.abs(direct - oracle_hazards))
            ),
            "inferred_active_source_risk_mean_absolute_error": float(
                np.mean(np.abs(inferred_active - oracle_hazards))
            ),
            "active_source_expected_age_mean_absolute_error": float(
                np.mean(np.abs(expected_active - ages))
            ),
            "mean_posterior_probability_of_true_source": float(
                np.mean(posterior_active)
            ),
            "minimum_age_hazard": float(np.min(age_hazards)),
            "maximum_age_hazard": float(np.max(age_hazards)),
            "maximum_transition_hazard_diagnostic_mismatch": float(
                np.max(
                    np.abs(
                        1.0 - np.diagonal(matrices, axis1=-2, axis2=-1)
                        - hazards
                    )
                )
            ),
            "maximum_posterior_mode_sum_error": float(
                np.max(np.abs(np.sum(posterior, axis=-1) - 1.0))
            ),
            "minimum_expected_age": float(np.min(expected_ages)),
            "maximum_expected_age": float(np.max(expected_ages)),
        }
        if (
            config["duration_contract"].get("age_risk_representation")
            == "monotone_piecewise_linear"
        ):
            increments = np.diff(age_hazards)
            recomputed.update(
                {
                    "minimum_age_hazard_increment": float(np.min(increments)),
                    "age_hazard_nondecreasing": bool(
                        np.all(increments >= -1e-15)
                    ),
                }
            )
        if not _close(recomputed, state_audit["per_seed"][seed]):
            return False
    return True


def _duration_checkpoints_reproduce_arrays(
    root: Path,
    config: Mapping[str, Any],
) -> bool:
    if not _is_explicit_duration(config):
        return True
    with np.load(root / "daily_arrays.npz", allow_pickle=False) as source:
        arrays = {name: source[name] for name in source.files}
    observable = ObservableAssimilationBatch(
        forcing=torch.from_numpy(np.asarray(arrays["test_forcing"])).to(
            dtype=torch.float64
        ),
        observations=torch.from_numpy(
            np.asarray(arrays["test_observations"])
        ).to(dtype=torch.float64),
        initial_states=torch.from_numpy(
            np.asarray(arrays["test_initial_states"])
        ).to(dtype=torch.float64),
        initial_covariances=torch.from_numpy(
            np.asarray(arrays["test_initial_covariances"])
        ).to(dtype=torch.float64),
        assimilation_days=int(config["data"]["assimilation_days"]),
    )
    supervision = ActiveRowSupervision(
        source_indices=torch.from_numpy(
            np.asarray(arrays["active_source_indices"], dtype=np.int64)
        ),
        target_probabilities=torch.from_numpy(
            np.asarray(
                arrays["oracle_active_row_probabilities"], dtype=np.float64
            )
        ),
        evaluation_mask=torch.from_numpy(
            np.asarray(arrays["transition_evaluation_mask"], dtype=np.bool_)
        ),
        switch_event_mask=torch.from_numpy(
            np.asarray(arrays["switch_event_mask"], dtype=np.bool_)
        ),
        regime_age_before_transition=torch.from_numpy(
            np.asarray(arrays["regime_age_before_transition"], dtype=np.int64)
        ),
    )
    candidate_parameters = build_parameter_candidates(
        config["base_parameters"], config["parameter_candidates"]["values"]
    )
    covariance = torch.zeros((3, 15, 15), dtype=torch.float64)
    state_index = {"SUZ": 3, "SLZ": 4}[str(config["filter"]["process_state_name"])]
    covariance[:, state_index, state_index] = float(
        config["filter"]["common_process_standard_deviation"]
    ) ** 2

    def estimator() -> DifferentiableInteractingMultipleModel:
        return DifferentiableInteractingMultipleModel(
            models=tuple(
                HBV15Model(parameters)
                for parameters in candidate_parameters.values()
            ),
            process_covariances=covariance,
            observation_variance=float(
                config["filter"]["observation_standard_deviation"]
            )
            ** 2,
        )

    for seed_value in config["training"]["history_network_initialization_seeds"]:
        seed = str(int(seed_value))
        module = _duration_module(config)
        checkpoint = torch.load(
            root / f"history_seed_{seed}_best_checkpoint.pt",
            map_location="cpu",
            weights_only=False,
        )
        module.load_state_dict(checkpoint["network_state_dict"], strict=True)
        module.eval()
        with torch.no_grad():
            result = rollout_semi_markov_probability(
                observable,
                supervision,
                module,
                estimator(),
            )
        if not np.array_equal(
            result.transition_matrices.cpu().numpy(),
            np.asarray(arrays[f"history_seed_{seed}_transition_matrices"]),
        ):
            return False
        if not np.array_equal(
            result.posterior_mode_probabilities.cpu().numpy(),
            np.asarray(arrays[f"history_seed_{seed}_posterior_mode_probabilities"]),
        ):
            return False
    return True


def _stratified_metrics_match(root: Path, config: Mapping[str, Any]) -> bool:
    if not _is_explicit_duration(config):
        return not (root / "stratified_metrics.json").exists()
    saved = json.loads((root / "stratified_metrics.json").read_text("utf-8"))
    with np.load(root / "daily_arrays.npz", allow_pickle=False) as source:
        arrays = {name: source[name] for name in source.files}
    mask = np.asarray(arrays["transition_evaluation_mask"], dtype=np.bool_)
    sources = np.asarray(arrays["active_source_indices"], dtype=np.int64)
    ages = np.asarray(arrays["regime_age_before_transition"], dtype=np.int64)
    targets = np.asarray(
        arrays["oracle_active_row_probabilities"], dtype=np.float64
    )
    age_groups = {
        "age_1_29": (ages >= 1) & (ages <= 29),
        "age_30_39": (ages >= 30) & (ages <= 39),
        "age_40_49": (ages >= 40) & (ages <= 49),
        "age_50_plus": ages >= 50,
    }

    def selected_scores(matrices: np.ndarray, selected: np.ndarray) -> dict[str, Any]:
        block_index, day_index = np.nonzero(selected)
        count = int(block_index.size)
        if count == 0:
            return {
                "count": 0,
                "oracle_brier": None,
                "switch_hazard_mean_absolute_error": None,
            }
        selected_sources = sources[block_index, day_index]
        rows = matrices[block_index, day_index, selected_sources]
        selected_targets = targets[block_index, day_index]
        row_index = np.arange(count)
        return {
            "count": count,
            "oracle_brier": float(
                np.mean(np.square(rows - selected_targets).sum(axis=-1))
            ),
            "switch_hazard_mean_absolute_error": float(
                np.mean(
                    np.abs(
                        1.0 - rows[row_index, selected_sources]
                        - (1.0 - selected_targets[row_index, selected_sources])
                    )
                )
            ),
        }

    methods = {
        "learned_history_free_static_matrix": np.asarray(
            arrays["static_transition_matrices"], dtype=np.float64
        ),
        **{
            f"history_seed_{int(seed)}": np.asarray(
                arrays[f"history_seed_{int(seed)}_transition_matrices"],
                dtype=np.float64,
            )
            for seed in config["training"]["history_network_initialization_seeds"]
        },
    }
    expected: dict[str, Any] = {
        "age_bins": list(age_groups),
        "source_ids": [
            "slow_recession",
            "calibrated_recession",
            "fast_recession",
        ],
        "methods": {},
    }
    for name, matrices in methods.items():
        method: dict[str, Any] = {
            "by_source": {},
            "by_age_and_source": {},
            "by_block": {},
            "by_target_coordinate": {},
        }
        for source_index in range(3):
            method["by_source"][str(source_index)] = selected_scores(
                matrices, mask & (sources == source_index)
            )
        for age_name, age_mask in age_groups.items():
            method["by_age_and_source"][age_name] = {
                str(source_index): selected_scores(
                    matrices, mask & age_mask & (sources == source_index)
                )
                for source_index in range(3)
            }
        for block in range(mask.shape[0]):
            selected = np.zeros_like(mask)
            selected[block] = mask[block]
            method["by_block"][str(block)] = selected_scores(matrices, selected)
        block_index, day_index = np.nonzero(mask)
        active_sources = sources[block_index, day_index]
        rows = matrices[block_index, day_index, active_sources]
        selected_targets = targets[block_index, day_index]
        for target_index in range(3):
            error = rows[:, target_index] - selected_targets[:, target_index]
            method["by_target_coordinate"][str(target_index)] = {
                "count": int(rows.shape[0]),
                "mean_squared_probability_error": float(np.mean(np.square(error))),
                "mean_absolute_probability_error": float(np.mean(np.abs(error))),
            }
        expected["methods"][name] = method
    return _close(saved, expected)


def verify_supervised_probability_repair(
    result_directory: str | Path,
    *,
    verify_checksums: bool = True,
    project_root: str | Path | None = None,
) -> dict[str, Any]:
    """Recompute the original gates and audit repair-specific provenance."""

    root = Path(result_directory).resolve()
    resolved_project = _resolved_project_root(root, project_root)
    config = json.loads((root / "config_snapshot.json").read_text("utf-8"))
    core = verify_h17_result(
        root,
        verify_checksums=verify_checksums,
        project_root=resolved_project,
    )
    repair = json.loads((root / "repair_contract.json").read_text("utf-8"))
    evaluation = json.loads(
        (root / "evaluation_role_audit.json").read_text("utf-8")
    )
    static_reference = json.loads(
        (root / "static_reference.json").read_text("utf-8")
    )
    integrity = json.loads(
        (root / "source_integrity_audit.json").read_text("utf-8")
    )
    manifest = json.loads((root / "source_manifest.json").read_text("utf-8"))

    reference = config["source_h17_static_reference"]
    static_hashes_match = all(
        _sha256(root / destination) == str(reference[label]["sha256"])
        for label, destination in (
            ("checkpoint", "static_best_checkpoint.pt"),
            ("training_history", "static_training_history.csv"),
        )
    )
    h17_root = (resolved_project / str(reference["result_directory"])).resolve()
    h17_checksums_match = (
        _sha256(h17_root / "checksums.json")
        == str(reference["checksums_sha256"])
        == str(integrity["h17_checksums_sha256"])
        and integrity.get("h17_unchanged") is True
        and integrity.get("h17_independent_verification_passed") is True
    )

    explicit_duration = _is_explicit_duration(config)
    parameterization = str(config["network"]["output_parameterization"])
    expected_outputs = 1 if parameterization == "shared_hazard" else 9
    seeds = tuple(
        int(value)
        for value in config["training"]["history_network_initialization_seeds"]
    )
    output_shapes_match = True
    for seed in seeds:
        checkpoint = torch.load(
            root / f"history_seed_{seed}_best_checkpoint.pt",
            map_location="cpu",
            weights_only=False,
        )
        state = checkpoint["network_state_dict"]
        if explicit_duration:
            duration = config["duration_contract"]
            module = _duration_module(config)
            try:
                module.load_state_dict(state, strict=True)
            except (KeyError, RuntimeError, ValueError):
                output_shapes_match = False
            else:
                output_shapes_match = bool(
                    output_shapes_match
                    and checkpoint.get("method")
                    == "explicit_causal_duration_transition_matrix"
                    and checkpoint.get("transition_architecture")
                    == "explicit_causal_duration"
                    and checkpoint.get("duration_contract") == duration
                    and checkpoint.get("feature_statistics_used") is False
                    and checkpoint.get("warm_started") is False
                    and checkpoint.get("h17b_recurrent_checkpoint_loaded") is False
                )
        else:
            output_shapes_match = bool(
                output_shapes_match
                and tuple(state["output.weight"].shape)[0] == expected_outputs
                and tuple(state["output.bias"].shape) == (expected_outputs,)
            )

    snapshot_path = root / "source_snapshot.zip"
    manifest_files = manifest.get("files", {})
    with zipfile.ZipFile(snapshot_path, mode="r") as archive:
        snapshot_members_match = set(archive.namelist()) == {
            name.replace("\\", "/") for name in config["source_snapshot_files"]
        }
        manifest_hashes_match = bool(
            isinstance(manifest_files, Mapping)
            and set(manifest_files) == set(config["source_snapshot_files"])
            and all(
                hashlib.sha256(
                    archive.read(name.replace("\\", "/"))
                ).hexdigest()
                == digest
                for name, digest in manifest_files.items()
            )
            and _sha256(snapshot_path) == manifest.get("source_snapshot_sha256")
        )

    h17b_baseline_matches = True
    if explicit_duration:
        baseline = config.get("baseline_repair", {})
        baseline_integrity = integrity.get("h17b_baseline", {})
        baseline_root = (
            resolved_project / str(baseline.get("result_directory", ""))
        ).resolve()
        declaration_path = (
            resolved_project
            / str(baseline.get("declaration", {}).get("path", ""))
        ).resolve()
        h17b_baseline_matches = bool(
            baseline.get("experiment_id")
            == "h17b_active_row_cross_entropy_supervised_probability_v01"
            and declaration_path.is_file()
            and _sha256(declaration_path)
            == str(baseline.get("declaration", {}).get("sha256"))
            and _sha256(baseline_root / "checksums.json")
            == str(baseline.get("checksums_sha256"))
            and _sha256(baseline_root / "independent_verification.json")
            == str(baseline.get("independent_verification_sha256"))
            and baseline_integrity.get("all_hashes_verified") is True
        )

    h17d_baseline_matches = True
    baseline_duration = config.get("baseline_duration_repair")
    if isinstance(baseline_duration, Mapping):
        baseline_duration_integrity = integrity.get("h17d_baseline", {})
        baseline_duration_root = (
            resolved_project / str(baseline_duration.get("result_directory", ""))
        ).resolve()
        baseline_duration_declaration = (
            resolved_project
            / str(baseline_duration.get("declaration", {}).get("path", ""))
        ).resolve()
        h17d_baseline_matches = bool(
            baseline_duration.get("experiment_id")
            == "h17d_explicit_causal_duration_cross_entropy_supervised_probability_v02"
            and baseline_duration_declaration.is_file()
            and _sha256(baseline_duration_declaration)
            == str(baseline_duration.get("declaration", {}).get("sha256"))
            and _sha256(baseline_duration_root / "checksums.json")
            == str(baseline_duration.get("checksums_sha256"))
            and _sha256(
                baseline_duration_root / "independent_verification.json"
            )
            == str(baseline_duration.get("independent_verification_sha256"))
            and baseline_duration_integrity.get("all_hashes_verified") is True
        )

    h17e_baseline_matches = True
    baseline_age_risk = config.get("baseline_age_risk_repair")
    if isinstance(baseline_age_risk, Mapping):
        baseline_age_risk_integrity = integrity.get("h17e_baseline", {})
        baseline_age_risk_root = (
            resolved_project
            / str(baseline_age_risk.get("result_directory", ""))
        ).resolve()
        baseline_age_risk_declaration = (
            resolved_project
            / str(baseline_age_risk.get("declaration", {}).get("path", ""))
        ).resolve()
        baseline_age_risk_snapshot = (
            resolved_project
            / str(baseline_age_risk.get("config_snapshot", {}).get("path", ""))
        ).resolve()
        h17e_baseline_matches = bool(
            baseline_age_risk.get("experiment_id")
            == "h17e_monotone_piecewise_linear_age_risk_supervised_probability_v01"
            and baseline_age_risk_declaration.is_file()
            and _sha256(baseline_age_risk_declaration)
            == str(baseline_age_risk.get("declaration", {}).get("sha256"))
            and baseline_age_risk_snapshot.is_file()
            and _sha256(baseline_age_risk_snapshot)
            == str(baseline_age_risk.get("config_snapshot", {}).get("sha256"))
            and _sha256(baseline_age_risk_root / "checksums.json")
            == str(baseline_age_risk.get("checksums_sha256"))
            and _sha256(
                baseline_age_risk_root / "independent_verification.json"
            )
            == str(baseline_age_risk.get("independent_verification_sha256"))
            and baseline_age_risk_integrity.get("all_hashes_verified") is True
        )

    repair_checks = {
        "core_probability_verification": core.get("verified") is True,
        "experiment_is_registered_supervised_repair": (
            config.get("experiment_kind") == "supervised_probability_repair"
        ),
        "repair_contract_matches_config": repair == config.get("repair_contract"),
        "one_factor_change_is_declared": (
            isinstance(repair.get("changed_factors"), list)
            and len(repair["changed_factors"]) == 1
        ),
        "checkpoint_output_parameterization_matches": output_shapes_match,
        "frozen_static_reference_is_byte_identical": static_hashes_match,
        "frozen_h17_evidence_is_unchanged": h17_checksums_match,
        "frozen_h17b_baseline_is_unchanged": h17b_baseline_matches,
        "frozen_h17d_baseline_is_unchanged": h17d_baseline_matches,
        "frozen_h17e_baseline_is_unchanged": h17e_baseline_matches,
        "old_test_is_explicitly_development_diagnostic": (
            evaluation.get("current_evaluation_role") == "development_diagnostic"
            and evaluation.get("independent_generalization_evidence") is False
            and evaluation.get("passing_this_split_alone_establishes_solution")
            is False
            and evaluation.get("fresh_reserved_confirmation_required_after_diagnostic_pass")
            is True
            and evaluation.get("h18_authorized") is False
        ),
        "source_snapshot_hashes_match_manifest": manifest_hashes_match,
        "source_snapshot_members_match_manifest": snapshot_members_match,
        "training_weighting_audit_matches_frozen_training_split": (
            _weighting_audit_matches(root, resolved_project, config)
        ),
        "duration_artifacts_independently_match": _duration_artifacts_match(
            root, config
        ),
        "duration_checkpoints_reproduce_saved_arrays": (
            _duration_checkpoints_reproduce_arrays(root, config)
        ),
        "stratified_metrics_independently_match": _stratified_metrics_match(
            root, config
        ),
        **_live_registry_checks(
            resolved_project,
            config,
            expected_repair_status=(
                (
                    "completed_supervised_repair_diagnostic_pass"
                    if core["independent_values"]["all_capability_gates_passed"]
                    else "completed_supervised_repair_diagnostic_hold"
                )
                if explicit_duration
                else (
                    "completed_supervised_repair_go"
                    if core["independent_values"]["all_capability_gates_passed"]
                    else "completed_supervised_repair_hold"
                )
            ),
        ),
    }
    return {
        "experiment_id": config["experiment_id"],
        "verified": all(repair_checks.values()),
        "checksum_verification_requested": bool(verify_checksums),
        "checks": repair_checks,
        "core_checks": core.get("checks", {}),
        "independent_values": core.get("independent_values", {}),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result_directory")
    parser.add_argument("--project-root")
    arguments = parser.parse_args()
    result = verify_supervised_probability_repair(
        arguments.result_directory,
        project_root=arguments.project_root,
    )
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
