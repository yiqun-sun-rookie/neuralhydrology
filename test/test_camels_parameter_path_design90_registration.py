from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from camels_switch_confirmation.g1_precheck import PARAM_KEYS, STATE_NAMES
from camels_switch_confirmation.g2_switch_confirmation import _build_bank
from camels_switch_confirmation.bank import build_bank
from camels_switch_confirmation.register_parameter_path_design90 import (
    build_historical_stopped_run_evidence,
    build_mechanism_evidence,
    build_task_identities,
    independent_initial_moments,
)
from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds


def test_mechanism_evidence_requires_verified_go():
    summary = {
        "verification_status": "passed",
        "mechanism_gate_status": "HOLD",
        "task_count": 20,
        "source_task_count": 10,
    }
    with pytest.raises(ValueError, match="mechanism gate"):
        build_mechanism_evidence(
            summary=summary,
            result_collection={"count": 25, "bytes": 1, "sha256": "0" * 64},
            logs=[],
            config_sha256="0" * 64,
            paired_directions={},
        )


def test_task_identity_builder_uses_basin_order_then_seed_order():
    basins = [f"{index:08d}" for index in range(1, 91)]
    identities = build_task_identities(basins)
    assert len(identities) == 180
    assert identities[:4] == [
        ("00000001", 0),
        ("00000001", 1),
        ("00000002", 0),
        ("00000002", 1),
    ]
    assert identities[-1] == ("00000090", 1)


def test_historical_stopped_run_evidence_rejects_changed_collection():
    observed = {
        "version_03": {
            "entry_format": "relative_path,bytes,sha256",
            "count": 13,
            "bytes": 895677,
            "sha256_of_newline_joined_sorted_entries": (
                "495184901b82fb3ce8dad8d8b490b4831f599142ea9dbcf93429ee07f780b85b"
            ),
        },
        "version_03a": {
            "entry_format": "relative_path,bytes,sha256",
            "count": 13,
            "bytes": 896011,
            "sha256_of_newline_joined_sorted_entries": (
                "bfcfc14f178369e46d1cb934191b91d16f548465ec931690b525a91b93e01309"
            ),
        },
    }
    evidence = build_historical_stopped_run_evidence(observed)
    assert evidence["version_03"]["result_collection"]["count"] == 13
    changed = {key: dict(value) for key, value in observed.items()}
    changed["version_03a"]["bytes"] += 1
    with pytest.raises(ValueError, match="version_03a"):
        build_historical_stopped_run_evidence(changed)


def _parameter_row() -> dict[str, float]:
    root = Path(__file__).resolve().parents[1]
    parameters = pd.read_csv(
        root
        / "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/hbv_lite_cma_rising_local_full.csv",
        dtype={"basin_id": str},
    )
    row = parameters.iloc[0]
    return {name: row[name] for name in row.index}


def test_independent_initial_moments_bitwise_match_production_initializer():
    row = _parameter_row()
    params = {name: float(row[f"p_{name}"]) for name in PARAM_KEYS}
    params["lag_time"] = min(params["lag_time"], 10.0)
    initial_hydrologic = np.asarray(
        [float(row[f"state_{name}"]) for name in STATE_NAMES],
        dtype=np.float64,
    )
    bounds = resolve_hbv_bounds("v5")
    members, _ = build_bank(params, bounds["parFC"])
    probabilities, states, covariances = independent_initial_moments(
        members,
        initial_hydrologic,
    )
    estimator, _ = _build_bank(
        members,
        initial_hydrologic,
        sigma_obs=1.0,
        bounds=bounds,
        q_scale=3e-8,
        q_structure="lower_groundwater_state_only",
        q_mode="fixed",
        q_state_multiplier=1.0,
        filter_r_multiplier=1.0,
        interaction_mode="pairwise_path_postcollapse",
        parameter_state_mapping="conservative_parfc",
    )
    production_states = np.asarray([item.state for item in estimator.filters])
    production_covariances = np.asarray(
        [item.covariance for item in estimator.filters]
    )
    assert np.array_equal(probabilities, estimator.probabilities)
    assert np.array_equal(states, production_states)
    assert np.array_equal(covariances, production_covariances)
