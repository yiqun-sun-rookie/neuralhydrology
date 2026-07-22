import sys
from pathlib import Path

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.candidates import (  # noqa: E402
    build_candidate_definitions,
    derive_parameter_vectors,
    extract_center_parameters,
    extract_saved_warmup_state,
    load_preflight_config,
    load_trained_parameter_table,
    verify_source_artifacts,
)
from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES, V1_PARAMETER_BOUNDS  # noqa: E402
from hbv_joint_uncertainty.resource_monitor import (  # noqa: E402
    ResourceGateError,
    ResourceSnapshot,
    enforce_resource_gate,
    recommended_worker_count,
)
from hbv_joint_uncertainty.orchestrator import collect_reproducibility_files  # noqa: E402


def test_frozen_config_verifies_single_trained_source_and_metadata():
    config = load_preflight_config(REPO_ROOT)
    verified = verify_source_artifacts(config, REPO_ROOT)
    assert verified["parameter_table_sha256"] == "9fad3981a2593450fe02e9b7cd35e8830745a8d2dc3ed89f897f2fa3a083642c"
    assert verified["metadata_sha256"] == "4bb16c34f6461ddb5d9d6b4ab2c9685d8f7b390d5ff778f708b4ba11891983af"
    assert verified["forcing"] == "maurer"
    assert verified["pet_method"] == "priestley_taylor"
    assert verified["bounds_preset"] == "v1"
    assert verified["warmup_year"] is True


def test_trained_source_contains_all_rows_and_frozen_basins():
    config = load_preflight_config(REPO_ROOT)
    table = load_trained_parameter_table(config, REPO_ROOT)
    assert len(table) == 531
    assert set(table["run_status"]) == {"success"}
    basin_ids = set(config["basins"])
    assert basin_ids == {"12375900", "09035800", "01580000", "11481200", "08109700", "04213075"}
    assert basin_ids <= set(table["basin_id"])
    maximum_lag_row = table.loc[table["p_lag_time"].astype(float).idxmax()]
    assert maximum_lag_row["basin_id"] == "04213075"
    assert float(maximum_lag_row["p_lag_time"]) == pytest.approx(9.97233665946842)


def test_saved_center_warmup_state_has_explicit_1989_end_semantics():
    config = load_preflight_config(REPO_ROOT)
    table = load_trained_parameter_table(config, REPO_ROOT)
    state = extract_saved_warmup_state(table, "12375900")
    assert state == pytest.approx(
        {
            "SNOWPACK": 0.0,
            "MELTWATER": 0.0,
            "SM": 598.1627745759931,
            "SUZ": 0.0,
            "SLZ": 51.92714162566546,
        }
    )


def test_parameter_bank_is_center_plus_symmetric_bound_relative_stresses():
    config = load_preflight_config(REPO_ROOT)
    table = load_trained_parameter_table(config, REPO_ROOT)
    center = extract_center_parameters(table, "12375900")
    vectors = derive_parameter_vectors(center, fraction=0.1)

    assert tuple(vectors) == ("toward_lower_10pct", "trained_center", "toward_upper_10pct")
    assert vectors["trained_center"] == center
    for name in PARAMETER_NAMES:
        lower, upper = V1_PARAMETER_BOUNDS[name]
        assert vectors["toward_lower_10pct"][name] == pytest.approx(center[name] - 0.1 * (center[name] - lower))
        assert vectors["toward_upper_10pct"][name] == pytest.approx(center[name] + 0.1 * (upper - center[name]))
        assert lower <= vectors["toward_lower_10pct"][name] <= upper
        assert lower <= vectors["toward_upper_10pct"][name] <= upper


def test_candidate_bank_crosses_three_parameter_vectors_and_three_noise_levels():
    config = load_preflight_config(REPO_ROOT)
    table = load_trained_parameter_table(config, REPO_ROOT)
    center = extract_center_parameters(table, "12375900")
    candidates = build_candidate_definitions(center, config)

    assert len(candidates) == 9
    assert len({candidate.candidate_id for candidate in candidates}) == 9
    assert {candidate.noise_variance_scale for candidate in candidates} == {1e-5, 1e-4, 1e-3}
    assert len({candidate.parameter_group for candidate in candidates}) == 3
    assert all(len(candidate.parameter_group) == 13 for candidate in candidates)


def test_candidate_bank_rejects_stress_fraction_that_conflicts_with_frozen_names():
    config = load_preflight_config(REPO_ROOT)
    table = load_trained_parameter_table(config, REPO_ROOT)
    center = extract_center_parameters(table, "12375900")
    config["parameter_stress_fraction"] = 0.2
    with pytest.raises(ValueError, match="exactly 0.1"):
        build_candidate_definitions(center, config)


def _snapshot(available=16.0, fraction=0.5, disk=100.0, logical=32):
    return ResourceSnapshot(
        timestamp="2026-07-14T20:00:00+08:00",
        total_memory_gib=32.0,
        available_memory_gib=available,
        available_memory_fraction=fraction,
        cpu_load_percent=25.0,
        logical_processors=logical,
        disk_free_gib=disk,
        gpu_name="test-gpu",
        gpu_memory_total_mib=12000.0,
        gpu_memory_free_mib=10000.0,
        gpu_utilization_percent=0.0,
    )


def test_resource_gate_enforces_memory_disk_and_reserved_processor_thresholds():
    enforce_resource_gate(_snapshot(), estimated_peak_gib=10.0, estimated_output_gib=10.0)
    with pytest.raises(ResourceGateError, match="70%"):
        enforce_resource_gate(_snapshot(), estimated_peak_gib=12.0, estimated_output_gib=1.0)
    with pytest.raises(ResourceGateError, match="15%"):
        enforce_resource_gate(_snapshot(available=4.0, fraction=0.14), estimated_peak_gib=1.0, estimated_output_gib=1.0)
    with pytest.raises(ResourceGateError, match="disk"):
        enforce_resource_gate(_snapshot(disk=19.0), estimated_peak_gib=1.0, estimated_output_gib=1.0)
    with pytest.raises(ResourceGateError, match="logical processor"):
        enforce_resource_gate(_snapshot(logical=1), estimated_peak_gib=1.0, estimated_output_gib=1.0)


def test_worker_recommendation_keeps_one_processor_and_memory_headroom():
    assert recommended_worker_count(_snapshot(), requested=32, estimated_peak_per_worker_gib=1.0) == 11
    assert recommended_worker_count(_snapshot(), requested=4, estimated_peak_per_worker_gib=1.0) == 4
    with pytest.raises(ValueError):
        recommended_worker_count(_snapshot(), requested=0, estimated_peak_per_worker_gib=1.0)


def test_resource_gate_rejects_observed_process_peak_above_current_headroom():
    snapshot = _snapshot()
    snapshot = ResourceSnapshot(**{**snapshot.to_dict(), "process_peak_working_set_gib": 12.0})
    with pytest.raises(ResourceGateError, match="observed process peak"):
        enforce_resource_gate(snapshot, estimated_peak_gib=1.0, estimated_output_gib=1.0)


def test_reproducibility_snapshot_freezes_code_dependencies_and_thirteen_raw_inputs():
    config = load_preflight_config(REPO_ROOT)
    source_files, input_files = collect_reproducibility_files(REPO_ROOT, config["basins"], config)
    relative_sources = {path.relative_to(REPO_ROOT).as_posix() for path in source_files}
    relative_inputs = {path.relative_to(REPO_ROOT).as_posix() for path in input_files}

    assert "src/hbv_joint_uncertainty/preflight.py" in relative_sources
    assert "src/hbv_joint_uncertainty/scripts/run_preflight.py" in relative_sources
    assert "src/scl_hydro/hbv_lite_numpy.py" in relative_sources
    assert "src/hydroagent/data_loading.py" in relative_sources
    assert "test/test_hbv_joint_uncertainty_experiment.py" in relative_sources
    assert len(input_files) == 15
    assert "data/camels_us/camels_attributes_v2.0/camels_topo.txt" in relative_inputs
    for basin_id in config["basins"]:
        assert sum(basin_id in path for path in relative_inputs) == 2
    assert config["parameter_source"]["table_path"] in relative_inputs
    assert config["parameter_source"]["metadata_path"] in relative_inputs
