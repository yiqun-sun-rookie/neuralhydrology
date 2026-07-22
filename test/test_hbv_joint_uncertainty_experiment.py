import json
import sys
from dataclasses import replace
from pathlib import Path

import numpy as np
import pandas as pd
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.candidates import CandidateDefinition  # noqa: E402
from hbv_joint_uncertainty.experiment import (  # noqa: E402
    BasinPreflightResult,
    calculate_metrics,
    verify_experiment,
    write_experiment,
)
from hbv_joint_uncertainty.preflight import AssimilationResult, WarmupAudit  # noqa: E402
import hbv_joint_uncertainty.experiment as experiment_module  # noqa: E402


def _definitions():
    parameters = {
        "parTT": 0.0,
        "parCFMAX": 3.0,
        "parCFR": 0.05,
        "parCWH": 0.1,
        "parFC": 200.0,
        "parBETA": 2.0,
        "parLP": 0.8,
        "parK0": 0.2,
        "parK1": 0.1,
        "parUZL": 20.0,
        "parPERC": 1.0,
        "parK2": 0.05,
        "lag_time": 2.0,
    }
    return tuple(
        CandidateDefinition(
            candidate_id=f"candidate_{index}",
            parameter_id="trained_center",
            noise_variance_scale=scale,
            parameters=parameters.copy(),
            parameter_group=tuple(parameters.values()),
        )
        for index, scale in enumerate((1e-5, 1e-4, 1e-3))
    )


def _basin_result():
    observations = np.array([1.0, 2.0, 4.0])
    predicted = np.array([1.2, 1.8, 3.5])
    probabilities = np.array(
        [
            [0.2, 0.3, 0.5],
            [0.25, 0.25, 0.5],
            [0.4, 0.3, 0.3],
        ]
    )
    assimilation = AssimilationResult(
        prior_discharge=predicted,
        candidate_prior_discharge=np.tile(predicted[:, None], (1, 3)),
        prior_probabilities=probabilities,
        posterior_probabilities=probabilities,
        combined_states=np.ones((3, 15)),
    )
    return BasinPreflightResult(
        basin_id="12375900",
        dates=np.array(["1989-10-01", "1989-10-02", "1989-10-03"]),
        observations=observations,
        assimilation=assimilation,
        definitions=_definitions(),
        warmup_audits=(WarmupAudit("trained_center", 1e-12, 2e-12, 3e-12),),
    )


def _config(tmp_path):
    return {
        "experiment_family": "test-family",
        "results_root": str(tmp_path / "results"),
        "logs_root": str(tmp_path / "logs"),
    }


def test_metrics_are_computed_from_forecast_before_update_values():
    metrics = calculate_metrics(np.array([1.0, 2.0, 4.0]), np.array([1.2, 1.8, 3.5]))
    assert metrics["rmse"] == pytest.approx(np.sqrt((0.2**2 + 0.2**2 + 0.5**2) / 3.0))
    assert metrics["mae"] == pytest.approx(0.3)
    assert metrics["nse"] == pytest.approx(1.0 - 0.33 / (14.0 / 3.0))


def test_atomic_experiment_write_register_and_independent_verify(tmp_path):
    output = write_experiment(
        repo_root=REPO_ROOT,
        experiment_id="synthetic_audit_v01",
        config=_config(tmp_path),
        basin_results=[_basin_result()],
        resource_history=[{"timestamp": "2026-07-14T20:00:00+08:00", "available_memory_fraction": 0.5}],
        provenance={"git_commit": "test", "dirty": True},
    )

    assert output == tmp_path / "results" / "synthetic_audit_v01"
    assert (output / "checksums.json").is_file()
    assert (output / "config_snapshot.json").is_file()
    assert (output / "metrics.csv").is_file()
    assert (output / "basins" / "12375900.npz").is_file()
    assert (tmp_path / "logs" / "synthetic_audit_v01" / "run.log").is_file()
    registry = pd.read_csv(tmp_path / "results" / "experiment_registry.csv", dtype={"experiment_id": str})
    assert registry["experiment_id"].tolist() == ["synthetic_audit_v01"]
    assert registry["status"].tolist() == ["verified"]
    snapshot = json.loads((output / "config_snapshot.json").read_text(encoding="utf-8"))
    assert snapshot["execution"]["selected_basins"] == ["12375900"]
    assert snapshot["execution"]["actual_evaluation_windows"] == {
        "12375900": {
            "start": "1989-10-01",
            "end": "1989-10-03",
            "n_days": 3,
        }
    }

    report = verify_experiment(output)
    assert report["verified"] is True
    assert report["basin_count"] == 1
    assert report["maximum_probability_sum_error"] <= 1e-12

    with pytest.raises(FileExistsError):
        write_experiment(
            repo_root=REPO_ROOT,
            experiment_id="synthetic_audit_v01",
            config=_config(tmp_path),
            basin_results=[_basin_result()],
            resource_history=[],
            provenance={},
        )


def test_checksum_verifier_detects_post_write_tampering(tmp_path):
    output = write_experiment(
        repo_root=REPO_ROOT,
        experiment_id="tamper_v01",
        config=_config(tmp_path),
        basin_results=[_basin_result()],
        resource_history=[],
        provenance={},
    )
    metrics_path = output / "metrics.csv"
    metrics_path.write_text(metrics_path.read_text(encoding="utf-8") + "tampered\n", encoding="utf-8")
    with pytest.raises(ValueError, match="checksum"):
        verify_experiment(output)


def test_verifier_recomputes_metrics_even_if_checksums_are_regenerated(tmp_path):
    output = write_experiment(
        repo_root=REPO_ROOT,
        experiment_id="metric_recompute_v01",
        config=_config(tmp_path),
        basin_results=[_basin_result()],
        resource_history=[],
        provenance={},
    )
    metrics_path = output / "metrics.csv"
    table = pd.read_csv(metrics_path)
    table.loc[0, "rmse"] = 999.0
    table.to_csv(metrics_path, index=False)

    checksums_path = output / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    from hbv_joint_uncertainty.candidates import sha256_file

    checksums["metrics.csv"] = sha256_file(metrics_path)
    checksums_path.write_text(json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="metric recomputation"):
        verify_experiment(output)


def test_verifier_rejects_wrong_state_dimension_even_with_regenerated_checksum(tmp_path):
    output = write_experiment(
        repo_root=REPO_ROOT,
        experiment_id="shape_recompute_v01",
        config=_config(tmp_path),
        basin_results=[_basin_result()],
        resource_history=[],
        provenance={},
    )
    basin_path = output / "basins" / "12375900.npz"
    with np.load(basin_path, allow_pickle=False) as source:
        arrays = {name: source[name] for name in source.files}
    arrays["combined_states"] = arrays["combined_states"][:, :14]
    np.savez_compressed(basin_path, **arrays)

    checksums_path = output / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    from hbv_joint_uncertainty.candidates import sha256_file

    checksums["basins/12375900.npz"] = sha256_file(basin_path)
    checksums_path.write_text(json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="artifact structure"):
        verify_experiment(output)


def test_registry_commit_failure_rolls_back_official_output_and_allows_retry(tmp_path, monkeypatch):
    config = _config(tmp_path)
    real_replace = experiment_module.os.replace

    def fail_registry_commit(source, destination):
        if Path(destination).name == "experiment_registry.csv":
            raise OSError("injected registry commit failure")
        return real_replace(source, destination)

    with monkeypatch.context() as context:
        context.setattr(experiment_module.os, "replace", fail_registry_commit)
        with pytest.raises(OSError, match="registry commit"):
            write_experiment(
                repo_root=REPO_ROOT,
                experiment_id="atomic_retry_v01",
                config=config,
                basin_results=[_basin_result()],
                resource_history=[],
                provenance={},
            )

    assert not (tmp_path / "results" / "atomic_retry_v01").exists()
    assert not (tmp_path / "logs" / "atomic_retry_v01").exists()
    assert not (tmp_path / "results" / "experiment_registry.csv").exists()
    output = write_experiment(
        repo_root=REPO_ROOT,
        experiment_id="atomic_retry_v01",
        config=config,
        basin_results=[_basin_result()],
        resource_history=[],
        provenance={},
    )
    assert output.is_dir()


def test_verifier_crosschecks_execution_snapshot_against_basin_artifacts(tmp_path):
    output = write_experiment(
        repo_root=REPO_ROOT,
        experiment_id="execution_crosscheck_v01",
        config=_config(tmp_path),
        basin_results=[_basin_result()],
        resource_history=[],
        provenance={},
    )
    config_path = output / "config_snapshot.json"
    snapshot = json.loads(config_path.read_text(encoding="utf-8"))
    snapshot["execution"]["selected_basins"] = ["99999999"]
    config_path.write_text(json.dumps(snapshot, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    checksums_path = output / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    from hbv_joint_uncertainty.candidates import sha256_file

    checksums["config_snapshot.json"] = sha256_file(config_path)
    checksums_path.write_text(json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="execution snapshot"):
        verify_experiment(output)


def test_verifier_crosschecks_candidate_identifiers_against_candidate_table(tmp_path):
    output = write_experiment(
        repo_root=REPO_ROOT,
        experiment_id="candidate_crosscheck_v01",
        config=_config(tmp_path),
        basin_results=[_basin_result()],
        resource_history=[],
        provenance={},
    )
    basin_path = output / "basins" / "12375900.npz"
    with np.load(basin_path, allow_pickle=False) as source:
        arrays = {name: source[name] for name in source.files}
    arrays["candidate_ids"] = np.array(["wrong_0", "wrong_1", "wrong_2"])
    np.savez_compressed(basin_path, **arrays)
    checksums_path = output / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    from hbv_joint_uncertainty.candidates import sha256_file

    checksums["basins/12375900.npz"] = sha256_file(basin_path)
    checksums_path.write_text(json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="candidate correspondence"):
        verify_experiment(output)


def test_verifier_rechecks_resource_thresholds_after_checksum_validation(tmp_path):
    output = write_experiment(
        repo_root=REPO_ROOT,
        experiment_id="resource_crosscheck_v01",
        config=_config(tmp_path),
        basin_results=[_basin_result()],
        resource_history=[],
        provenance={},
    )
    config_path = output / "config_snapshot.json"
    snapshot = json.loads(config_path.read_text(encoding="utf-8"))
    snapshot["resource"] = {
        "minimum_available_fraction_of_total": 0.15,
        "maximum_peak_fraction_of_available": 0.7,
        "minimum_free_disk_gib": 20.0,
        "minimum_output_space_multiplier": 2.0,
        "monitor_interval_seconds": 60.0,
        "reserved_logical_processors": 1,
    }
    config_path.write_text(json.dumps(snapshot, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    resource_path = output / "resource_history.json"
    resource_path.write_text(
        json.dumps(
            [
                {
                    "event": "before_experiment",
                    "timestamp": "2026-07-14T20:00:00+08:00",
                    "available_memory_fraction": 0.10,
                    "available_memory_gib": 3.2,
                    "process_rss_gib": 0.2,
                    "process_peak_working_set_gib": 0.3,
                    "cpu_load_percent": 20.0,
                    "logical_processors": 32,
                    "disk_free_gib": 100.0,
                    "gpu_name": None,
                    "gpu_memory_total_mib": None,
                    "gpu_memory_free_mib": None,
                    "gpu_utilization_percent": None,
                }
            ],
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    checksums_path = output / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    from hbv_joint_uncertainty.candidates import sha256_file

    checksums["config_snapshot.json"] = sha256_file(config_path)
    checksums["resource_history.json"] = sha256_file(resource_path)
    checksums_path.write_text(json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="resource history"):
        verify_experiment(output)


def test_verifier_proves_forecast_is_weighted_before_same_day_update(tmp_path):
    output = write_experiment(
        repo_root=REPO_ROOT,
        experiment_id="forecast_semantics_v01",
        config=_config(tmp_path),
        basin_results=[_basin_result()],
        resource_history=[],
        provenance={},
    )
    basin_path = output / "basins" / "12375900.npz"
    with np.load(basin_path, allow_pickle=False) as source:
        arrays = {name: source[name] for name in source.files}
    arrays["prior_discharge"] = arrays["observations"].copy()
    np.savez_compressed(basin_path, **arrays)
    metrics_path = output / "metrics.csv"
    metrics = pd.read_csv(metrics_path)
    metrics.loc[0, ["rmse", "mae", "nse"]] = [0.0, 0.0, 1.0]
    metrics.to_csv(metrics_path, index=False)
    checksums_path = output / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    from hbv_joint_uncertainty.candidates import sha256_file

    checksums["basins/12375900.npz"] = sha256_file(basin_path)
    checksums["metrics.csv"] = sha256_file(metrics_path)
    checksums_path.write_text(json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="forecast-before-update"):
        verify_experiment(output)


def test_verifier_rechecks_all_warmup_equivalence_thresholds(tmp_path):
    output = write_experiment(
        repo_root=REPO_ROOT,
        experiment_id="warmup_crosscheck_v01",
        config=_config(tmp_path),
        basin_results=[_basin_result()],
        resource_history=[],
        provenance={},
    )
    warmup_path = output / "warmup_equivalence.csv"
    warmup = pd.read_csv(warmup_path)
    warmup.loc[0, ["maximum_discharge_error", "maximum_final_store_error", "maximum_saved_state_error"]] = 999.0
    warmup.to_csv(warmup_path, index=False)
    checksums_path = output / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    from hbv_joint_uncertainty.candidates import sha256_file

    checksums["warmup_equivalence.csv"] = sha256_file(warmup_path)
    checksums_path.write_text(json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="warmup equivalence"):
        verify_experiment(output)


def test_verifier_rejects_negative_warmup_errors_after_checksum_regeneration(tmp_path):
    output = write_experiment(
        repo_root=REPO_ROOT,
        experiment_id="negative_warmup_v01",
        config=_config(tmp_path),
        basin_results=[_basin_result()],
        resource_history=[],
        provenance={},
    )
    warmup_path = output / "warmup_equivalence.csv"
    warmup = pd.read_csv(warmup_path)
    warmup.loc[0, ["maximum_discharge_error", "maximum_final_store_error", "maximum_saved_state_error"]] = -999.0
    warmup.to_csv(warmup_path, index=False)
    checksums_path = output / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    from hbv_joint_uncertainty.candidates import sha256_file

    checksums["warmup_equivalence.csv"] = sha256_file(warmup_path)
    checksums_path.write_text(json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="warmup equivalence"):
        verify_experiment(output)


def test_verifier_reconstructs_prior_probability_chronology(tmp_path):
    config = _config(tmp_path)
    config["transition_diagonal"] = 0.98
    basin_result = _basin_result()
    transition = np.full((3, 3), 0.01)
    np.fill_diagonal(transition, 0.98)
    expected_prior = np.empty((3, 3))
    expected_prior[0] = np.full(3, 1.0 / 3.0) @ transition
    expected_prior[1:] = basin_result.assimilation.posterior_probabilities[:-1] @ transition
    basin_result = replace(
        basin_result,
        assimilation=replace(basin_result.assimilation, prior_probabilities=expected_prior),
    )
    output = write_experiment(
        repo_root=REPO_ROOT,
        experiment_id="prior_chronology_v01",
        config=config,
        basin_results=[basin_result],
        resource_history=[],
        provenance={},
    )
    basin_path = output / "basins" / "12375900.npz"
    with np.load(basin_path, allow_pickle=False) as source:
        arrays = {name: source[name] for name in source.files}
    arrays["prior_probabilities"] = np.eye(3)
    np.savez_compressed(basin_path, **arrays)
    checksums_path = output / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    from hbv_joint_uncertainty.candidates import sha256_file

    checksums["basins/12375900.npz"] = sha256_file(basin_path)
    checksums_path.write_text(json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="prior probability chronology"):
        verify_experiment(output)


def test_experiment_copies_and_verifies_exact_source_and_input_snapshots(tmp_path):
    source_file = REPO_ROOT / "src" / "hbv_joint_uncertainty" / "preflight.py"
    input_file = REPO_ROOT / "data" / "camels_us" / "camels_attributes_v2.0" / "camels_topo.txt"
    output = write_experiment(
        repo_root=REPO_ROOT,
        experiment_id="snapshot_v01",
        config=_config(tmp_path),
        basin_results=[_basin_result()],
        resource_history=[],
        provenance={},
        source_files=[source_file],
        input_files=[input_file],
    )
    manifest = json.loads((output / "reproducibility_manifest.json").read_text(encoding="utf-8"))
    assert len(manifest["source_files"]) == 1
    assert len(manifest["input_files"]) == 1
    assert (output / manifest["source_files"][0]["snapshot_path"]).is_file()
    assert (output / manifest["input_files"][0]["snapshot_path"]).is_file()
    assert verify_experiment(output)["verified"] is True
