import hashlib
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from camels_switch_confirmation.verify_parameter_interaction_design import (  # noqa: E402
    compute_probability_metrics,
    evaluate_registered_decision_gates,
    evaluate_events_independently,
    expected_design_counts,
    verify_cross_arm_arrays,
    verify_design,
)


def test_uniform_probabilities_have_registered_uniform_scores():
    probabilities = np.full((1260, 3), 1.0 / 3.0)
    log_probabilities = np.full((1260, 3), -np.log(3.0))
    true_indices = np.repeat(np.array([0, 1, 2, 0, 2, 1, 0]), 180)

    metrics = compute_probability_metrics(
        probabilities,
        true_indices,
        log_probabilities=log_probabilities,
    )

    assert metrics["multiclass_brier"] == pytest.approx(2.0 / 3.0, abs=1e-15)
    assert metrics["true_negative_log_probability"] == pytest.approx(
        np.log(3.0), abs=1e-15
    )


def test_expected_design_counts_for_90_basins():
    counts = expected_design_counts(
        basin_count=90,
        seed_count=2,
        arm_count=3,
        events_per_task=6,
    )

    assert counts.total_tasks == 540
    assert counts.tasks_per_arm == 180
    assert counts.total_events == 3240
    assert counts.events_per_arm == 1080
    assert counts.events_per_direction_per_arm == 180


@pytest.mark.parametrize(
    "field",
    ["basin_count", "seed_count", "arm_count", "events_per_task"],
)
def test_expected_design_counts_rejects_nonpositive_fields(field):
    values = {
        "basin_count": 90,
        "seed_count": 2,
        "arm_count": 3,
        "events_per_task": 6,
    }
    values[field] = 0

    with pytest.raises(ValueError, match=f"{field} must be a positive integer"):
        expected_design_counts(**values)


def test_registered_decision_gates_separate_replication_from_freeze_eligibility():
    arms = pd.DataFrame(
        [
            {
                "arm_id": "A",
                "events_passed": 80,
                "multiclass_brier": 0.8,
                "true_negative_log_probability": 3.0,
            },
            {
                "arm_id": "B",
                "events_passed": 75,
                "multiclass_brier": 0.7,
                "true_negative_log_probability": 2.0,
            },
            {
                "arm_id": "C",
                "events_passed": 120,
                "multiclass_brier": 0.4,
                "true_negative_log_probability": 1.2,
            },
        ]
    )
    directions = pd.DataFrame(
        {
            "arm_id": ["C"] * 6,
            "events": [30] * 6,
            "passed": [20] * 6,
            "pass_rate": [2.0 / 3.0] * 6,
        }
    )
    gates = {
        "validation_freeze_eligibility": {
            "c_overall_event_pass_rate_min": 0.65,
            "c_minimum_direction_pass_rate_min": 0.50,
            "c_multiclass_brier_max": 2.0 / 3.0,
            "c_true_negative_log_probability_max": float(np.log(3.0)),
            "requires_scale_replication": True,
        }
    }

    result = evaluate_registered_decision_gates(arms, directions, gates)

    assert result["scale_replication_gate_passed"] is True
    assert result["validation_freeze_eligibility_gate_passed"] is False
    assert result["c_overall_event_pass_rate"] == pytest.approx(2.0 / 3.0)
    assert result["c_minimum_direction_pass_rate"] == pytest.approx(2.0 / 3.0)


def test_independent_event_recomputation_passes_immediate_one_hot_truth():
    true_indices = np.repeat(np.array([0, 1, 2, 0, 2, 1, 0]), 180)
    probabilities = np.eye(3)[true_indices]
    switch_days = np.arange(1, 7) * 180

    events = evaluate_events_independently(
        probabilities,
        switch_days,
        true_indices,
    )

    assert [event["passed"] for event in events] == [True] * 6
    assert [event["response_start"] for event in events] == [0] * 6


def _shared_contract_arrays():
    return {
        "truth_q": np.arange(4.0),
        "observations": np.arange(4.0) + 0.1,
        "switch_days": np.array([2]),
        "true_candidate_indices": np.array([0, 0, 1, 1]),
        "rotation": np.array([0, 1]),
        "stage_days": np.array(2),
        "basin_id": np.array("01022500"),
        "seed": np.array(0),
        "candidate_parameter_names": np.array(["parFC"]),
        "candidate_parameter_vectors": np.array([[100.0], [50.0], [200.0]]),
        "truth_slz_lognormal_sigma": np.array(0.02),
        "truth_clip_count": np.array(0),
        "observation_sigma": np.array(0.1),
        "rain": np.arange(4.0),
        "pet": np.arange(4.0) * 0.1,
        "temperature": np.arange(4.0) - 2.0,
        "filter_process_variance_scale": np.array(3e-8),
        "filter_process_covariance_structure": np.array(
            "lower_groundwater_state_only"
        ),
        "filter_q_mode": np.array("fixed"),
        "filter_q_state_multiplier": np.array(1.0),
        "filter_observation_variance_multiplier": np.array(1.0),
        "filter_process_lower_groundwater_variance": np.full(4, 3e-8),
    }


def _three_arms(shared):
    metadata = {
        "A": ("parameter_grouped", "legacy_projection"),
        "B": ("full", "legacy_projection"),
        "C": ("full", "conservative_parfc"),
    }
    arms = {}
    for arm_id, (interaction, mapping) in metadata.items():
        arrays = {key: value.copy() for key, value in shared.items()}
        arrays["arm_id"] = np.array(arm_id)
        arrays["state_interaction_mode"] = np.array(interaction)
        arrays["parameter_state_mapping"] = np.array(mapping)
        arms[arm_id] = arrays
    return arms


def test_cross_arm_verification_rejects_truth_change():
    shared = _shared_contract_arrays()
    arms = _three_arms(shared)
    arms["B"]["truth_q"][0] += 1.0

    with pytest.raises(ValueError, match="truth_q differs across arms"):
        verify_cross_arm_arrays(arms)


def test_cross_arm_verification_accepts_exact_shared_contract():
    shared = _shared_contract_arrays()
    arms = _three_arms(shared)

    verify_cross_arm_arrays(arms)


def test_cross_arm_verification_rejects_filter_noise_change():
    shared = _shared_contract_arrays()
    arms = _three_arms(shared)
    arms["C"]["filter_observation_variance_multiplier"] = np.array(2.0)

    with pytest.raises(
        ValueError,
        match="filter_observation_variance_multiplier differs across arms",
    ):
        verify_cross_arm_arrays(arms)


_BASIN_IDS = tuple(f"{index:08d}" for index in range(1, 13))
_SEEDS = (0, 1)
_ROTATION = np.array([0, 1, 2, 0, 2, 1, 0], dtype=np.int64)
_SWITCH_DAYS = np.arange(1, 7, dtype=np.int64) * 180
_TRUE_INDICES = np.repeat(_ROTATION, 180)
_ARM_METADATA = {
    "A": ("parameter_grouped", "legacy_projection"),
    "B": ("full", "legacy_projection"),
    "C": ("full", "conservative_parfc"),
}


def _sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _rewrite_npz(path, **changes):
    with np.load(path, allow_pickle=False) as archive:
        arrays = {name: archive[name].copy() for name in archive.files}
    arrays.update(changes)
    np.savez_compressed(path, **arrays)


def _probabilities_with_first_event(*, true_probability):
    probabilities = np.full((1260, 3), 1.0 / 3.0, dtype=np.float64)
    probabilities[180:185, 1] = true_probability
    other_probability = (1.0 - true_probability) / 2.0
    probabilities[180:185, 0] = other_probability
    probabilities[180:185, 2] = other_probability
    return probabilities


def _task_arrays(basin_id, seed, arm_id, probabilities, *, truth_clip_count=0):
    basin_offset = int(basin_id) * 1e-6 + int(seed) * 1e-3
    truth_q = np.arange(1260, dtype=np.float64) * 0.01 + basin_offset
    observations = truth_q + 0.05
    interaction_mode, mapping_mode = _ARM_METADATA[arm_id]
    parameter_names = np.array(
        [
            "parBETA",
            "parCET",
            "parFC",
            "parK0",
            "parK1",
            "parK2",
            "parLP",
            "parMAXBAS",
            "parPERC",
            "parTT",
            "parCFMAX",
            "parCFR",
            "parWHC",
        ]
    )
    parameter_vectors = np.tile(np.arange(1.0, 14.0), (3, 1))
    parameter_vectors[:, 2] = np.array([100.0, 50.0, 200.0])
    return {
        "probabilities": probabilities,
        "log_probabilities": np.log(probabilities),
        "truth_q": truth_q,
        "observations": observations,
        "basin_id": np.array(basin_id),
        "seed": np.array(seed, dtype=np.int64),
        "switch_days": _SWITCH_DAYS,
        "rotation": _ROTATION,
        "stage_days": np.array(180, dtype=np.int64),
        "true_candidate_indices": _TRUE_INDICES,
        "candidate_parameter_names": parameter_names,
        "candidate_parameter_vectors": parameter_vectors,
        "truth_slz_lognormal_sigma": np.array(0.02),
        "truth_clip_count": np.array(truth_clip_count, dtype=np.int64),
        "observation_sigma": np.array(0.1),
        "rain": np.arange(1260, dtype=np.float64) * 0.02,
        "pet": np.arange(1260, dtype=np.float64) * 0.001,
        "temperature": np.linspace(-5.0, 20.0, 1260),
        "filter_process_variance_scale": np.array(3e-8),
        "filter_process_covariance_structure": np.array(
            "lower_groundwater_state_only"
        ),
        "filter_q_mode": np.array("fixed"),
        "filter_q_state_multiplier": np.array(1.0),
        "filter_observation_variance_multiplier": np.array(1.0),
        "state_interaction_mode": np.array(interaction_mode),
        "parameter_state_mapping": np.array(mapping_mode),
        "arm_id": np.array(arm_id),
        "filter_process_lower_groundwater_variance": np.full(1260, 3e-8),
    }


def _build_complete_design(
    tmp_path,
    *,
    basin_count=12,
    design_seeds=(0, 1),
    legacy_event_mismatch=False,
    legacy_probability_mismatch=False,
):
    basin_ids = tuple(f"{index:08d}" for index in range(1, basin_count + 1))
    root = tmp_path
    inputs = root / "inputs"
    docs = root / "docs"
    implementation = root / "src" / "dummy_implementation.py"
    config_path = (
        root
        / "src"
        / "camels_switch_confirmation"
        / "configs"
        / "design.json"
    )
    output = root / "results" / f"design{basin_count}"
    legacy_root = root / "legacy"
    for directory in (inputs, docs, implementation.parent, legacy_root):
        directory.mkdir(parents=True, exist_ok=True)

    parameter_table = inputs / "parameters.csv"
    precheck_table = inputs / "g1.csv"
    coverage_table = inputs / "coverage.csv"
    raw_input = inputs / "forcing.txt"
    parameter_table.write_text("basin_id,value\n00000001,1\n", encoding="utf-8")
    precheck_table.write_text("basin_id,sigma_obs\n00000001,0.1\n", encoding="utf-8")
    coverage_table.write_text("basin_id,n_days\n00000001,1260\n", encoding="utf-8")
    raw_input.write_text("registered forcing input\n", encoding="utf-8")
    implementation.write_text("VALUE = 1\n", encoding="utf-8")

    basin_list = docs / "basins.csv"
    pd.DataFrame({"basin_id": basin_ids}).to_csv(basin_list, index=False)
    raw_manifest = docs / "raw_manifest.csv"
    pd.DataFrame(
        [
            {
                "relative_path": raw_input.relative_to(root).as_posix(),
                "bytes": raw_input.stat().st_size,
                "sha256": _sha256(raw_input),
            }
        ]
    ).to_csv(raw_manifest, index=False)

    uniform = np.full((1260, 3), 1.0 / 3.0, dtype=np.float64)
    legacy_rows = []
    legacy_probabilities_by_key = {}
    arm_a_probabilities_by_key = {}
    for basin_id in basin_ids:
        for seed in _SEEDS:
            key = (basin_id, seed)
            legacy_probabilities = uniform
            arm_a_probabilities = uniform
            if legacy_event_mismatch and key == (basin_ids[0], 0):
                legacy_probabilities = _probabilities_with_first_event(
                    true_probability=0.50000000000025
                )
                arm_a_probabilities = _probabilities_with_first_event(
                    true_probability=0.49999999999975
                )
            elif legacy_probability_mismatch and key == (basin_ids[0], 0):
                arm_a_probabilities = np.tile(
                    np.array([0.34, 0.33, 0.33]),
                    (1260, 1),
                )
            legacy_probabilities_by_key[key] = legacy_probabilities
            arm_a_probabilities_by_key[key] = arm_a_probabilities
            arrays = _task_arrays(
                basin_id,
                seed,
                "A",
                legacy_probabilities,
            )
            legacy_path = legacy_root / f"{basin_id}_s{seed}.npz"
            np.savez_compressed(
                legacy_path,
                probabilities=legacy_probabilities,
                truth_q=arrays["truth_q"],
                observations=arrays["observations"],
                switch_days=arrays["switch_days"],
            )
            legacy_rows.append(
                {
                    "basin_id": basin_id,
                    "seed": seed,
                    "relative_path": legacy_path.relative_to(root).as_posix(),
                    "bytes": legacy_path.stat().st_size,
                    "sha256": _sha256(legacy_path),
                }
            )
    legacy_manifest = docs / "legacy.csv"
    pd.DataFrame(legacy_rows).to_csv(legacy_manifest, index=False)

    config = {
        "experiment_id": "SYNTHETIC_PARAMETER_INTERACTION_DESIGN12",
        "configuration_status": "registered_exploratory_design_not_validation_frozen",
        "inputs": {
            "parameter_table": parameter_table.relative_to(root).as_posix(),
            "parameter_table_sha256": _sha256(parameter_table),
            "g1_precheck_table": precheck_table.relative_to(root).as_posix(),
            "g1_precheck_table_sha256": _sha256(precheck_table),
            "forcing_coverage_table": coverage_table.relative_to(root).as_posix(),
            "forcing_coverage_table_sha256": _sha256(coverage_table),
            "raw_input_manifest": raw_manifest.relative_to(root).as_posix(),
            "raw_input_manifest_sha256": _sha256(raw_manifest),
        },
        "design_selection": {
            "basin_list": basin_list.relative_to(root).as_posix(),
            "basin_list_sha256": _sha256(basin_list),
            "basin_count": basin_count,
        },
        "seeds": {"design": list(design_seeds)},
        "truth": {"rotation": _ROTATION.tolist(), "stage_days": 180},
        "arms": [
            {
                "arm_id": arm_id,
                "interaction_mode": interaction,
                "parameter_state_mapping": mapping,
            }
            for arm_id, (interaction, mapping) in _ARM_METADATA.items()
        ],
        "outputs": {"root": output.relative_to(root).as_posix()},
        "legacy_reference": {
            "manifest": legacy_manifest.relative_to(root).as_posix(),
            "manifest_sha256": _sha256(legacy_manifest),
            "probability_absolute_tolerance": 1e-12,
        },
        "implementation": {
            "dummy": {
                "path": implementation.relative_to(root).as_posix(),
                "sha256": _sha256(implementation),
            }
        },
    }
    _write_json(config_path, config)
    config_hash = _sha256(config_path)

    output.mkdir(parents=True)
    _write_json(
        output / "runner_summary.json",
        {
            "experiment_id": config["experiment_id"],
            "config_sha256": config_hash,
            "execution_status": "complete",
            "n_arms_started": 3,
            "n_tasks_planned": basin_count * len(_SEEDS) * len(_ARM_METADATA),
        },
    )
    for arm_id, (interaction, mapping) in _ARM_METADATA.items():
        arm_root = output / "arms" / arm_id
        probability_root = arm_root / "probs"
        probability_root.mkdir(parents=True)
        _write_json(
            arm_root / "g2_summary.json",
            {
                "execution_status": "complete",
                "config_sha256": config_hash,
                "arm_id": arm_id,
                "n_tasks": basin_count * len(_SEEDS),
                "n_success": basin_count * len(_SEEDS),
                "n_failed": 0,
                "state_interaction_mode": interaction,
                "parameter_state_mapping": mapping,
            },
        )
        runner_rows = []
        for basin_id in basin_ids:
            for seed in _SEEDS:
                key = (basin_id, seed)
                probabilities = (
                    arm_a_probabilities_by_key[key]
                    if arm_id == "A"
                    else uniform
                )
                np.savez_compressed(
                    probability_root / f"{basin_id}_s{seed}.npz",
                    **_task_arrays(basin_id, seed, arm_id, probabilities),
                )
                runner_rows.append(
                    {
                        "basin_id": basin_id,
                        "seed": seed,
                        "run_status": "success",
                        "truth_clip_count": 0,
                    }
                )
        pd.DataFrame(runner_rows).to_csv(arm_root / "g2_events.csv", index=False)

    return {
        "root": root,
        "output": output,
        "config_path": config_path,
        "config_hash": config_hash,
        "basin_ids": basin_ids,
    }


@pytest.fixture
def complete_design(tmp_path):
    return _build_complete_design(tmp_path)


def test_verify_design_accepts_complete_72_task_evidence(complete_design):
    report = verify_design(
        complete_design["output"],
        complete_design["config_path"],
        complete_design["config_hash"],
    )

    assert report["verification_status"] == "passed"
    assert report["task_count"] == 72
    assert report["event_count"] == 432
    verification = complete_design["output"] / "verification"
    assert verification.is_dir()
    assert not (complete_design["output"] / "verification.tmp").exists()
    assert {
        path.name for path in verification.iterdir()
    } == {
        "task_metrics.csv",
        "event_metrics.csv",
        "arm_metrics.csv",
        "direction_metrics.csv",
        "comparison_summary.json",
    }


def test_verify_design_accepts_configuration_derived_two_basin_counts(tmp_path):
    design = _build_complete_design(tmp_path, basin_count=2)

    report = verify_design(
        design["output"],
        design["config_path"],
        design["config_hash"],
    )

    assert report["task_count"] == 12
    assert report["event_count"] == 72


def test_verify_design_rejects_shared_wrong_truth_labels(complete_design):
    wrong_truth = _TRUE_INDICES.copy()
    wrong_truth[0] = 1
    for arm_id in _ARM_METADATA:
        path = (
            complete_design["output"]
            / "arms"
            / arm_id
            / "probs"
            / f"{_BASIN_IDS[0]}_s0.npz"
        )
        _rewrite_npz(path, true_candidate_indices=wrong_truth)

    with pytest.raises(
        ValueError,
        match="true-candidate indices differ from registered rotation",
    ):
        verify_design(
            complete_design["output"],
            complete_design["config_path"],
            complete_design["config_hash"],
        )


def test_verify_design_rejects_cross_arm_filter_noise_difference(complete_design):
    path = (
        complete_design["output"]
        / "arms"
        / "C"
        / "probs"
        / f"{_BASIN_IDS[0]}_s0.npz"
    )
    _rewrite_npz(path, filter_observation_variance_multiplier=np.array(2.0))

    with pytest.raises(
        ValueError,
        match="filter_observation_variance_multiplier differs across arms",
    ):
        verify_design(
            complete_design["output"],
            complete_design["config_path"],
            complete_design["config_hash"],
        )


def test_verify_design_rejects_legacy_probability_difference(tmp_path):
    design = _build_complete_design(tmp_path, legacy_probability_mismatch=True)

    with pytest.raises(
        ValueError,
        match="arm A probabilities differ from legacy reference",
    ):
        verify_design(design["output"], design["config_path"], design["config_hash"])


def test_verify_design_rejects_legacy_event_difference_within_tolerance(tmp_path):
    design = _build_complete_design(tmp_path, legacy_event_mismatch=True)

    with pytest.raises(
        ValueError,
        match="arm A event decisions differ from legacy reference",
    ):
        verify_design(design["output"], design["config_path"], design["config_hash"])


def test_verify_design_rejects_duplicate_design_seed(tmp_path):
    design = _build_complete_design(tmp_path, design_seeds=(0, 0))

    with pytest.raises(
        ValueError,
        match=r"basin count, unique basins, or seeds \[0,1\] changed",
    ):
        verify_design(design["output"], design["config_path"], design["config_hash"])


def test_verify_design_rejects_nonzero_truth_clip_count(complete_design):
    for arm_id in _ARM_METADATA:
        path = (
            complete_design["output"]
            / "arms"
            / arm_id
            / "probs"
            / f"{_BASIN_IDS[0]}_s0.npz"
        )
        _rewrite_npz(path, truth_clip_count=np.array(1, dtype=np.int64))

    with pytest.raises(ValueError, match="truth clipping occurred"):
        verify_design(
            complete_design["output"],
            complete_design["config_path"],
            complete_design["config_hash"],
        )


def test_verify_design_keeps_partial_report_in_temporary_directory(
    complete_design,
    monkeypatch,
):
    def fail_csv_write(*_args, **_kwargs):
        raise OSError("simulated verification write failure")

    monkeypatch.setattr(pd.DataFrame, "to_csv", fail_csv_write)

    with pytest.raises(OSError, match="simulated verification write failure"):
        verify_design(
            complete_design["output"],
            complete_design["config_path"],
            complete_design["config_hash"],
        )

    assert not (complete_design["output"] / "verification").exists()
    assert (complete_design["output"] / "verification.tmp").is_dir()
