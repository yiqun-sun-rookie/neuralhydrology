import sys
from pathlib import Path

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from camels_switch_confirmation.g2_switch_confirmation import _build_bank  # noqa: E402
from camels_switch_confirmation.run_student_t_fair_single_task import (  # noqa: E402
    _run_arm,
    _verify_common_source,
    _verify_full_arm,
    _verify_path_arm,
    run_diagnostic,
)
from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds  # noqa: E402


PARAMETER_NAMES = np.asarray(
    [
        "parTT",
        "parCFMAX",
        "parCFR",
        "parCWH",
        "parFC",
        "parBETA",
        "parLP",
        "parK0",
        "parK1",
        "parUZL",
        "parPERC",
        "parK2",
        "lag_time",
    ]
)


def _source_fixture():
    center = np.asarray(
        [0.0, 3.0, 0.05, 0.1, 200.0, 2.0, 0.7, 0.2, 0.1, 5.0, 1.0, 0.05, 3.0]
    )
    vectors = np.vstack(
        [
            center,
            np.where(PARAMETER_NAMES == "parFC", 100.0, center),
            np.where(PARAMETER_NAMES == "parFC", 400.0, center),
        ]
    )
    members = [
        dict(zip(PARAMETER_NAMES.tolist(), row.tolist()))
        for row in vectors
    ]
    initial_hydrology = np.array([0.0, 0.0, 160.0, 20.0, 30.0])
    estimator, _ = _build_bank(
        members,
        initial_hydrology,
        sigma_obs=0.1,
        bounds=resolve_hbv_bounds("v5"),
        q_scale=3e-8,
        q_structure="lower_groundwater_state_only",
        q_mode="fixed",
        q_state_multiplier=1.0,
        filter_r_multiplier=1.0,
        interaction_mode="pairwise_path_postcollapse",
        parameter_state_mapping="conservative_parfc",
    )
    n_days = 4
    return {
        "truth_q": np.array([0.2, 0.4, 0.1, 0.3]),
        "observations": np.array([0.25, 0.35, 0.15, 0.28]),
        "basin_id": np.array("07184000"),
        "seed": np.array(0, dtype=np.int64),
        "switch_days": np.array([], dtype=np.int32),
        "rotation": np.array([0], dtype=np.int64),
        "stage_days": np.array(180, dtype=np.int64),
        "true_candidate_indices": np.zeros(n_days, dtype=np.int64),
        "truth_parfc": np.full(n_days, 200.0),
        "candidate_parameter_names": PARAMETER_NAMES.copy(),
        "candidate_parameter_vectors": vectors,
        "observation_sigma": np.array(0.1),
        "rain": np.array([0.0, 2.0, 0.0, 1.0]),
        "pet": np.full(n_days, 0.1),
        "temperature": np.full(n_days, 5.0),
        "filter_process_variance_scale": np.array(3e-8),
        "filter_process_covariance_structure": np.array(
            "lower_groundwater_state_only"
        ),
        "filter_q_mode": np.array("fixed"),
        "filter_q_state_multiplier": np.array(1.0),
        "filter_observation_variance_multiplier": np.array(1.0),
        "path_initial_probabilities": estimator.probabilities.copy(),
        "path_initial_states": np.asarray(
            [candidate.state for candidate in estimator.filters]
        ),
        "path_initial_covariances": np.asarray(
            [candidate.covariance for candidate in estimator.filters]
        ),
    }


def test_two_online_arms_share_inputs_and_reconstruct_saved_student_t_evidence():
    source = _source_fixture()

    full = _run_arm(source, "C")
    path = _run_arm(source, "P")

    _verify_common_source(source, full)
    _verify_common_source(source, path)
    _verify_full_arm(full)
    _verify_path_arm(path)
    assert full["model_evidence_distribution"].item() == "student_t"
    assert path["model_evidence_distribution"].item() == "student_t"
    assert not np.array_equal(
        full["candidate_model_log_evidences"],
        full["candidate_gaussian_log_likelihoods"],
    )
    assert not np.array_equal(
        path["branch_model_log_evidences"],
        path["branch_gaussian_log_likelihoods"],
    )


def test_run_rejects_output_inside_frozen_evidence_before_writing(tmp_path):
    frozen_root = tmp_path / "frozen"
    frozen_root.mkdir()
    source_task = frozen_root / "source.npz"
    source_task.write_bytes(b"not-read-because-path-safety-must-fail-first")
    output_root = frozen_root / "new_diagnostic"

    with pytest.raises(ValueError, match="outside the frozen result root"):
        run_diagnostic(source_task, frozen_root, output_root)

    assert not output_root.exists()
