import json
import shutil
import sys
from dataclasses import replace
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.experiment import (  # noqa: E402
    BasinEvaluation,
    ResultPackageWriter,
    verify_contract_package,
    verify_result_package,
    write_contract_package,
)
import hbv_multilead_joint_uncertainty.experiment as experiment_module  # noqa: E402
from hbv_multilead_joint_uncertainty.methods import METHOD_ORDER  # noqa: E402
from hbv_multilead_joint_uncertainty.runner import MethodRunResult  # noqa: E402
from hbv_multilead_joint_uncertainty.selection import (  # noqa: E402
    generate_local_parameter_pool,
    generate_multiscale_parameter_pool,
    select_equifinal_parameters,
)
from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES, V1_PARAMETER_BOUNDS  # noqa: E402
from hbv_joint_uncertainty.candidates import sha256_file  # noqa: E402
from hbv_multilead_joint_uncertainty.contracts import (  # noqa: E402
    TRAINING_PROJECTION_COLUMNS,
    csv_projection_sha256,
    load_base_config,
)


def _basin_contract(basin_id="00000001"):
    parameters = {
        name: 0.5 * (V1_PARAMETER_BOUNDS[name][0] + V1_PARAMETER_BOUNDS[name][1])
        for name in PARAMETER_NAMES
    }
    process_rows = []
    for index, scale in enumerate((1e-8, 1e-7, 1e-6)):
        diagonal = np.zeros(15)
        diagonal[:5] = scale
        process_rows.append(
            {
                "process_id": f"process_{index}",
                "variance_scale": scale,
                "covariance_diagonal": diagonal.tolist(),
                "covariance_matrix": np.diag(diagonal).tolist(),
            }
        )
    return {
        "basin_id": basin_id,
        "preparation_data_boundary": {"uses_evaluation_discharge": False},
        "parameter_source": {"path": "synthetic.csv", "sha256": "0" * 64},
        "parameter_vectors": {
            "equifinal_low_flow": {
                "parameters": {**parameters, "parTT": parameters["parTT"] - 0.1},
                "development_nse": 0.8,
                "development_mean_discharge": 0.8,
            },
            "trained_center": {
                "parameters": parameters,
                "development_nse": 0.8,
                "development_mean_discharge": 1.0,
            },
            "equifinal_high_flow": {
                "parameters": {**parameters, "parTT": parameters["parTT"] + 0.1},
                "development_nse": 0.8,
                "development_mean_discharge": 1.2,
            },
        },
        "process_noise": {
            "selected_process_id": "process_1",
            "candidates": process_rows,
        },
        "observation_noise": {
            "selected_standard_deviation_mm_day": 0.2,
            "selected_variance_mm2_day2": 0.04,
        },
    }


def _diverse_basin_contract(basin_id="00000001"):
    contract = _basin_contract(basin_id)
    center = contract["parameter_vectors"]["trained_center"]["parameters"]
    pool = generate_local_parameter_pool(center, count=256, fraction=0.1, seed=1)
    scores = np.full(256, 0.79, dtype=np.float64)
    means = 2.0 + np.arange(256, dtype=np.float64) / 1000.0
    selected = select_equifinal_parameters(
        center=center,
        candidates=pool,
        center_nse=0.8,
        center_mean_discharge=1.0,
        candidate_nse=scores,
        candidate_mean_discharge=means,
        maximum_nse_drop=0.03,
    )
    selected_indices = [
        selected["equifinal_diverse_1"]["candidate_index"],
        selected["equifinal_diverse_2"]["candidate_index"],
    ]
    contract["parameter_vectors"] = selected
    contract["center_development_nse"] = 0.8
    contract["parameter_pool_audit"] = [
        {
            "candidate_index": index,
            "parameters": parameters,
            "development_nse": float(scores[index]),
            "development_mean_discharge": float(means[index]),
            "eligible": True,
        }
        for index, parameters in enumerate(pool)
    ]
    contract["parameter_selection"] = {
        "schema_version": 2,
        "strategy": "global_maximin_normalized_parameter_distance",
        "pool_generator": "scrambled_sobol",
        "pool_seed": 1,
        "pool_size": 256,
        "local_fraction": 0.1,
        "maximum_nse_drop": 0.03,
        "normalization": "frozen_physical_bound_span",
        "distance": "euclidean",
        "objective": "maximize_the_minimum_of_both_center_distances_and_the_pair_distance",
        "tie_break": "candidate_index_ascending_lexicographic",
        "eligible_distinct_candidate_count": 256,
        "selected_candidate_indices": selected_indices,
        "selected_pair_minimum_distance": selected["equifinal_diverse_1"][
            "selected_pair_minimum_distance"
        ],
        "mean_discharge_role": "diagnostic_only_not_a_selection_constraint",
    }
    return contract


def _diverse_config():
    return {
        "lead_days": [1, 3, 7],
        "random_seed": 1,
        "formal_interaction_mode": "full",
        "parameter_selection": {
            "schema_version": 2,
            "strategy": "global_maximin_normalized_parameter_distance",
            "pool_generator": "scrambled_sobol",
            "pool_size": 256,
            "local_fraction": 0.1,
            "maximum_nse_drop": 0.03,
            "normalization": "frozen_physical_bound_span",
            "distance": "euclidean",
            "objective": "maximize_the_minimum_of_both_center_distances_and_the_pair_distance",
            "tie_break": "candidate_index_ascending_lexicographic",
        },
    }


def _multiscale_config():
    return {
        "lead_days": [1, 3, 7],
        "random_seed": 1,
        "formal_interaction_mode": "full",
        "parameter_selection": {
            "schema_version": 3,
            "strategy": "multiscale_global_maximin_normalized_parameter_distance",
            "pool_generator": "scrambled_sobol_restarted_per_scale",
            "pool_size": 1024,
            "candidates_per_scale": 256,
            "local_fractions": [0.1, 0.05, 0.025, 0.0125],
            "candidate_order": "local_fraction_config_order_then_scale_candidate_index",
            "maximum_nse_drop": 0.03,
            "normalization": "frozen_physical_bound_span",
            "distance": "euclidean",
            "objective": "maximize_the_minimum_of_both_center_distances_and_the_pair_distance",
            "tie_break": "candidate_index_ascending_lexicographic",
        },
    }


def _multiscale_basin_contract(basin_id="00000001"):
    contract = _basin_contract(basin_id)
    center = contract["parameter_vectors"]["trained_center"]["parameters"]
    pool, provenance = generate_multiscale_parameter_pool(
        center,
        fractions=(0.1, 0.05, 0.025, 0.0125),
        count_per_scale=256,
        seed=1,
    )
    scores = np.full(len(pool), 0.79, dtype=np.float64)
    means = 2.0 + np.arange(len(pool), dtype=np.float64) / 1000.0
    selected = select_equifinal_parameters(
        center=center,
        candidates=pool,
        center_nse=0.8,
        center_mean_discharge=1.0,
        candidate_nse=scores,
        candidate_mean_discharge=means,
        maximum_nse_drop=0.03,
    )
    for parameter_id in ("equifinal_diverse_1", "equifinal_diverse_2"):
        source = provenance[selected[parameter_id]["candidate_index"]]
        selected[parameter_id].update(
            {
                key: source[key]
                for key in ("scale_index", "local_fraction", "scale_candidate_index")
            }
        )
    selected_indices = [
        selected["equifinal_diverse_1"]["candidate_index"],
        selected["equifinal_diverse_2"]["candidate_index"],
    ]
    contract["parameter_vectors"] = selected
    contract["center_development_nse"] = 0.8
    contract["parameter_pool_audit"] = [
        {
            **provenance[index],
            "parameters": parameters,
            "development_nse": float(scores[index]),
            "development_mean_discharge": float(means[index]),
            "eligible": True,
        }
        for index, parameters in enumerate(pool)
    ]
    contract["parameter_selection"] = {
        "schema_version": 3,
        "strategy": "multiscale_global_maximin_normalized_parameter_distance",
        "pool_generator": "scrambled_sobol_restarted_per_scale",
        "pool_seed": 1,
        "pool_size": 1024,
        "candidates_per_scale": 256,
        "local_fractions": [0.1, 0.05, 0.025, 0.0125],
        "scale_count": 4,
        "candidate_order": "local_fraction_config_order_then_scale_candidate_index",
        "maximum_nse_drop": 0.03,
        "normalization": "frozen_physical_bound_span",
        "distance": "euclidean",
        "objective": "maximize_the_minimum_of_both_center_distances_and_the_pair_distance",
        "tie_break": "candidate_index_ascending_lexicographic",
        "eligible_distinct_candidate_count": 1024,
        "selected_candidate_indices": selected_indices,
        "selected_pair_minimum_distance": selected["equifinal_diverse_1"][
            "selected_pair_minimum_distance"
        ],
        "mean_discharge_role": "diagnostic_only_not_a_selection_constraint",
    }
    return contract


def _stub_frozen_input_recalculation(monkeypatch):
    def recalculate(directory, basin_id, config, center_parameters, candidates):
        count = len(candidates)
        return {
            "center_nse": 0.8,
            "center_mean_discharge": 1.0,
            "candidate_nse": np.full(count, 0.79, dtype=np.float64),
            "candidate_mean_discharge": 2.0 + np.arange(count, dtype=np.float64) / 1000.0,
        }

    monkeypatch.setattr(
        experiment_module,
        "_recompute_parameter_pool_from_snapshot",
        recalculate,
        raising=False,
    )


def test_contract_verifier_accepts_and_reconstructs_current_multiscale_parameter_rule(
    tmp_path, monkeypatch
):
    _stub_frozen_input_recalculation(monkeypatch)
    output = write_contract_package(
        results_root=tmp_path,
        contract_id="multiscale_v01",
        config=_multiscale_config(),
        basin_table=pd.DataFrame([{"gauge_id": "00000001"}]),
        basin_contracts={"00000001": _multiscale_basin_contract()},
        input_audits={
            "00000001": {
                "basin_id": "00000001",
                "passed": True,
                "evaluation_discharge_values_parsed": False,
            }
        },
        resource_history=[],
        interaction_audit={"selected_mode": "full", "uses_evaluation_discharge": False},
        source_files=[],
        input_files=[],
        repo_root=REPO_ROOT,
    )

    assert verify_contract_package(output)["status"] == "verified"


def test_contract_verifier_rejects_changed_multiscale_provenance_with_updated_checksum(
    tmp_path, monkeypatch
):
    _stub_frozen_input_recalculation(monkeypatch)
    output = write_contract_package(
        results_root=tmp_path,
        contract_id="multiscale_provenance_attack_v01",
        config=_multiscale_config(),
        basin_table=pd.DataFrame([{"gauge_id": "00000001"}]),
        basin_contracts={"00000001": _multiscale_basin_contract()},
        input_audits={
            "00000001": {
                "basin_id": "00000001",
                "passed": True,
                "evaluation_discharge_values_parsed": False,
            }
        },
        resource_history=[],
        interaction_audit={"selected_mode": "full", "uses_evaluation_discharge": False},
        source_files=[],
        input_files=[],
        repo_root=REPO_ROOT,
    )
    contract_path = output / "basin_contracts" / "00000001.json"
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    contract["parameter_pool_audit"][256]["local_fraction"] = 0.1
    contract_path.write_text(
        json.dumps(contract, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    checksums_path = output / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    checksums["basin_contracts/00000001.json"] = sha256_file(contract_path)
    checksums_path.write_text(
        json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    with pytest.raises(ValueError, match="provenance"):
        verify_contract_package(output)


def test_contract_verifier_rejects_coordinated_multiscale_downgrade_to_legacy_vectors(
    tmp_path, monkeypatch
):
    _stub_frozen_input_recalculation(monkeypatch)
    output = write_contract_package(
        results_root=tmp_path,
        contract_id="multiscale_legacy_name_attack_v01",
        config=_multiscale_config(),
        basin_table=pd.DataFrame([{"gauge_id": "00000001"}]),
        basin_contracts={"00000001": _multiscale_basin_contract()},
        input_audits={
            "00000001": {
                "basin_id": "00000001",
                "passed": True,
                "evaluation_discharge_values_parsed": False,
            }
        },
        resource_history=[],
        interaction_audit={"selected_mode": "full", "uses_evaluation_discharge": False},
        source_files=[],
        input_files=[],
        repo_root=REPO_ROOT,
    )
    contract_path = output / "basin_contracts" / "00000001.json"
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    vectors = contract["parameter_vectors"]
    low = vectors.pop("equifinal_diverse_1")
    high = vectors.pop("equifinal_diverse_2")
    low["development_mean_discharge"] = 0.8
    high["development_mean_discharge"] = 1.2
    vectors["equifinal_low_flow"] = low
    vectors["equifinal_high_flow"] = high
    contract.pop("parameter_selection")
    contract.pop("parameter_pool_audit")
    contract_path.write_text(
        json.dumps(contract, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    config_path = output / "config_snapshot.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    config.pop("parameter_selection")
    config.pop("experiment_family", None)
    config_path.write_text(
        json.dumps(config, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    expected_tables = experiment_module._expected_flat_contract_tables(
        output, ["00000001"]
    )
    for name, table in expected_tables.items():
        table.to_csv(output / name, index=False)
    checksums_path = output / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    checksums["basin_contracts/00000001.json"] = sha256_file(contract_path)
    checksums["config_snapshot.json"] = sha256_file(config_path)
    for name in expected_tables:
        checksums[name] = sha256_file(output / name)
    checksums_path.write_text(
        json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    with pytest.raises(ValueError, match="external identity allowlist"):
        verify_contract_package(output)


def test_contract_verifier_accepts_and_reconstructs_current_global_parameter_diversity_rule(
    tmp_path, monkeypatch
):
    _stub_frozen_input_recalculation(monkeypatch)
    output = write_contract_package(
        results_root=tmp_path,
        contract_id="diverse_contract_v01",
        config=_diverse_config(),
        basin_table=pd.DataFrame([{"gauge_id": "00000001"}]),
        basin_contracts={"00000001": _diverse_basin_contract()},
        input_audits={
            "00000001": {
                "basin_id": "00000001",
                "passed": True,
                "evaluation_discharge_values_parsed": False,
            }
        },
        resource_history=[],
        interaction_audit={"selected_mode": "full", "uses_evaluation_discharge": False},
        source_files=[],
        input_files=[],
        repo_root=REPO_ROOT,
    )

    assert verify_contract_package(output)["status"] == "verified"


def test_contract_verifier_rejects_a_nonmaximal_current_parameter_pair_with_updated_checksum(
    tmp_path, monkeypatch
):
    _stub_frozen_input_recalculation(monkeypatch)
    output = write_contract_package(
        results_root=tmp_path,
        contract_id="diverse_contract_attack_v01",
        config=_diverse_config(),
        basin_table=pd.DataFrame([{"gauge_id": "00000001"}]),
        basin_contracts={"00000001": _diverse_basin_contract()},
        input_audits={
            "00000001": {
                "basin_id": "00000001",
                "passed": True,
                "evaluation_discharge_values_parsed": False,
            }
        },
        resource_history=[],
        interaction_audit={"selected_mode": "full", "uses_evaluation_discharge": False},
        source_files=[],
        input_files=[],
        repo_root=REPO_ROOT,
    )
    contract_path = output / "basin_contracts" / "00000001.json"
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    selected = contract["parameter_vectors"]["equifinal_diverse_1"]
    selected["candidate_index"] = (int(selected["candidate_index"]) + 1) % 256
    contract_path.write_text(
        json.dumps(contract, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    checksums_path = output / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    checksums["basin_contracts/00000001.json"] = sha256_file(contract_path)
    checksums_path.write_text(
        json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    with pytest.raises(ValueError, match="globally maximizing"):
        verify_contract_package(output)


def test_contract_verifier_rejects_changed_saved_development_score_after_frozen_input_recalculation(
    tmp_path, monkeypatch
):
    _stub_frozen_input_recalculation(monkeypatch)
    output = write_contract_package(
        results_root=tmp_path,
        contract_id="diverse_score_attack_v01",
        config=_diverse_config(),
        basin_table=pd.DataFrame([{"gauge_id": "00000001"}]),
        basin_contracts={"00000001": _diverse_basin_contract()},
        input_audits={
            "00000001": {
                "basin_id": "00000001",
                "passed": True,
                "evaluation_discharge_values_parsed": False,
            }
        },
        resource_history=[],
        interaction_audit={"selected_mode": "full", "uses_evaluation_discharge": False},
        source_files=[],
        input_files=[],
        repo_root=REPO_ROOT,
    )
    contract_path = output / "basin_contracts" / "00000001.json"
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    selected_indices = set(contract["parameter_selection"]["selected_candidate_indices"])
    attack_index = next(index for index in range(256) if index not in selected_indices)
    contract["parameter_pool_audit"][attack_index]["development_nse"] = -999.0
    contract["parameter_pool_audit"][attack_index]["eligible"] = False
    contract["parameter_selection"]["eligible_distinct_candidate_count"] = 255
    contract_path.write_text(
        json.dumps(contract, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    checksums_path = output / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    checksums["basin_contracts/00000001.json"] = sha256_file(contract_path)
    checksums_path.write_text(
        json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    with pytest.raises(ValueError, match="recomputed frozen-input"):
        verify_contract_package(output)


def test_contract_verifier_rejects_coordinated_change_from_full_to_no_interaction(
    tmp_path, monkeypatch
):
    _stub_frozen_input_recalculation(monkeypatch)
    output = write_contract_package(
        results_root=tmp_path,
        contract_id="diverse_interaction_attack_v01",
        config=_diverse_config(),
        basin_table=pd.DataFrame([{"gauge_id": "00000001"}]),
        basin_contracts={"00000001": _diverse_basin_contract()},
        input_audits={
            "00000001": {
                "basin_id": "00000001",
                "passed": True,
                "evaluation_discharge_values_parsed": False,
            }
        },
        resource_history=[],
        interaction_audit={"selected_mode": "full", "uses_evaluation_discharge": False},
        source_files=[],
        input_files=[],
        repo_root=REPO_ROOT,
    )
    changed_files = {
        "interaction_audit.json": ("selected_mode", "none"),
        "contract_manifest.json": ("selected_interaction_mode", "none"),
        "config_snapshot.json": ("formal_interaction_mode", "none"),
    }
    checksums_path = output / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    for relative, (field, value) in changed_files.items():
        path = output / relative
        content = json.loads(path.read_text(encoding="utf-8"))
        content[field] = value
        path.write_text(
            json.dumps(content, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        checksums[relative] = sha256_file(path)
    checksums_path.write_text(
        json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    with pytest.raises(ValueError, match="full interaction"):
        verify_contract_package(output)


@pytest.mark.parametrize("field", ["normalization", "distance", "objective", "tie_break"])
def test_contract_verifier_rejects_missing_frozen_selection_config_field(
    tmp_path, monkeypatch, field
):
    _stub_frozen_input_recalculation(monkeypatch)
    output = write_contract_package(
        results_root=tmp_path,
        contract_id=f"diverse_config_attack_{field}",
        config=_diverse_config(),
        basin_table=pd.DataFrame([{"gauge_id": "00000001"}]),
        basin_contracts={"00000001": _diverse_basin_contract()},
        input_audits={
            "00000001": {
                "basin_id": "00000001",
                "passed": True,
                "evaluation_discharge_values_parsed": False,
            }
        },
        resource_history=[],
        interaction_audit={"selected_mode": "full", "uses_evaluation_discharge": False},
        source_files=[],
        input_files=[],
        repo_root=REPO_ROOT,
    )
    config_path = output / "config_snapshot.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    del config["parameter_selection"][field]
    config_path.write_text(
        json.dumps(config, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    checksums_path = output / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    checksums["config_snapshot.json"] = sha256_file(config_path)
    checksums_path.write_text(
        json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    with pytest.raises(ValueError, match=f"config {field}"):
        verify_contract_package(output)


def test_contract_package_is_atomic_nonoverwriting_and_independently_verified(
    tmp_path, monkeypatch
):
    _stub_frozen_input_recalculation(monkeypatch)
    results_root = tmp_path / "results"
    basin_table = pd.DataFrame(
        [{"gauge_id": "00000001", "climate_stratum": "humid", "response_stratum": "fast_response"}]
    )
    output = write_contract_package(
        results_root=results_root,
        contract_id="contract_v01",
        config=_diverse_config(),
        basin_table=basin_table,
        basin_contracts={"00000001": _diverse_basin_contract()},
        input_audits={
            "00000001": {
                "basin_id": "00000001",
                "passed": True,
                "evaluation_discharge_values_parsed": False,
            }
        },
        resource_history=[{"event": "start", "timestamp": "2026-07-14T00:00:00+08:00"}],
        interaction_audit={"selected_mode": "full", "uses_evaluation_discharge": False},
        source_files=[REPO_ROOT / "src" / "hbv_multilead_joint_uncertainty" / "contracts.py"],
        input_files=[REPO_ROOT / "src" / "hbv_multilead_joint_uncertainty" / "configs" / "base_v01.json"],
        repo_root=REPO_ROOT,
    )

    verification = verify_contract_package(output)
    assert verification == {
        "status": "verified",
        "contract_id": "contract_v01",
        "basin_count": 1,
        "interaction_mode": "full",
    }
    assert (output / "checksums.json").is_file()
    assert (output / "source_snapshot" / "src" / "hbv_multilead_joint_uncertainty" / "contracts.py").is_file()
    input_snapshot = output / "input_snapshot" / "src" / "hbv_multilead_joint_uncertainty"
    assert (input_snapshot / "configs" / "base_v01.json").is_file()
    with pytest.raises(FileExistsError):
        write_contract_package(
            results_root=results_root,
            contract_id="contract_v01",
            config={},
            basin_table=basin_table,
            basin_contracts={"00000001": _basin_contract()},
            input_audits={
                "00000001": {"passed": True, "evaluation_discharge_values_parsed": False}
            },
            resource_history=[],
            interaction_audit={"selected_mode": "full"},
            source_files=[],
            input_files=[],
            repo_root=REPO_ROOT,
        )


def test_contract_verifier_rejects_coordinated_content_change_even_if_manifest_is_not_updated(
    tmp_path, monkeypatch
):
    _stub_frozen_input_recalculation(monkeypatch)
    output = write_contract_package(
        results_root=tmp_path,
        contract_id="contract_v02",
        config=_diverse_config(),
        basin_table=pd.DataFrame([{"gauge_id": "00000001"}]),
        basin_contracts={"00000001": _diverse_basin_contract()},
        input_audits={
            "00000001": {
                "basin_id": "00000001",
                "passed": True,
                "evaluation_discharge_values_parsed": False,
            }
        },
        resource_history=[],
        interaction_audit={"selected_mode": "full", "uses_evaluation_discharge": False},
        source_files=[],
        input_files=[],
        repo_root=REPO_ROOT,
    )
    contract_path = output / "basin_contracts" / "00000001.json"
    content = json.loads(contract_path.read_text(encoding="utf-8"))
    content["observation_noise"]["selected_variance_mm2_day2"] = 1.0
    contract_path.write_text(json.dumps(content), encoding="utf-8")

    with pytest.raises(ValueError, match="checksum"):
        verify_contract_package(output)


def test_contract_verifier_rebuilds_flat_tables_from_canonical_json_records(
    tmp_path, monkeypatch
):
    _stub_frozen_input_recalculation(monkeypatch)
    output = write_contract_package(
        results_root=tmp_path,
        contract_id="contract_flat_table_attack_v01",
        config=_diverse_config(),
        basin_table=pd.DataFrame([{"gauge_id": "00000001"}]),
        basin_contracts={"00000001": _diverse_basin_contract()},
        input_audits={
            "00000001": {
                "basin_id": "00000001",
                "passed": True,
                "evaluation_discharge_values_parsed": False,
            }
        },
        resource_history=[],
        interaction_audit={"selected_mode": "full", "uses_evaluation_discharge": False},
        source_files=[],
        input_files=[],
        repo_root=REPO_ROOT,
    )
    table_path = output / "parameter_vectors.csv"
    table = pd.read_csv(table_path)
    table.loc[0, "parTT"] += 1.0
    table.to_csv(table_path, index=False)
    checksums_path = output / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    checksums["parameter_vectors.csv"] = sha256_file(table_path)
    checksums_path.write_text(json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    with pytest.raises(ValueError, match="parameter_vectors.csv"):
        verify_contract_package(output)

    failed_name = tmp_path / "copied_contract.failed"
    shutil.copytree(output, failed_name)
    with pytest.raises(ValueError, match="failed"):
        verify_contract_package(failed_name)


def test_verified_execution_signature_recomputes_parameter_metadata_and_calibration_sources(
    tmp_path, monkeypatch
):
    _stub_frozen_input_recalculation(monkeypatch)
    config = load_base_config(REPO_ROOT)
    config.pop("resource")
    config["formal_interaction_mode"] = "full"
    basin_id = "04015330"
    basin_contract = _multiscale_basin_contract(basin_id)
    basin_contract["parameter_source"] = {
        "path": config["parameter_source"]["table_path"],
        "sha256": config["parameter_source"]["table_sha256"],
        "sha256_scope": "entire frozen twenty-column parameter table",
        "projection_columns": list(TRAINING_PROJECTION_COLUMNS),
        "metadata_path": config["parameter_source"]["metadata_path"],
        "metadata_sha256": config["parameter_source"]["metadata_sha256"],
    }
    metadata = json.loads(
        (REPO_ROOT / config["calibration_discharge_source"]["metadata_path"]).read_text(
            encoding="utf-8"
        )
    )
    input_audit = {
        "basin_id": basin_id,
        "passed": True,
        "evaluation_discharge_values_parsed": False,
        "variables": [
            {
                "variable_id": "streamflow",
                "source_sha256": config["calibration_discharge_source"]["table_sha256"],
                "raw_selected_source_lines_sha256": metadata["sources"][basin_id][
                    "selected_source_lines_sha256"
                ],
            }
        ],
    }
    source_files = [REPO_ROOT / "src/hbv_multilead_joint_uncertainty/contracts.py"]
    input_files = [
        REPO_ROOT / config["parameter_source"]["table_path"],
        REPO_ROOT / config["parameter_source"]["metadata_path"],
        REPO_ROOT / config["calibration_discharge_source"]["table_path"],
        REPO_ROOT / config["calibration_discharge_source"]["metadata_path"],
    ]
    signature_files = {
        path.relative_to(REPO_ROOT).as_posix(): sha256_file(path)
        for path in [*source_files, *input_files]
    }
    signature = {
        "files_sha256": signature_files,
        "environment": {
            "python": "test",
            "platform": "test",
            "packages": {},
            "process": {"create_time_unix_seconds": 2.0},
        },
        "source_process_freshness": {
            "process_create_time_unix_seconds": 2.0,
            "latest_source_mtime_unix_seconds": 1.0,
            "maximum_clock_tolerance_seconds": 0.0,
            "passed": True,
        },
        "parameter_table_sha256": config["parameter_source"]["table_sha256"],
        "parameter_projection_content_sha256": csv_projection_sha256(input_files[0]),
        "calibration_discharge_slice_sha256": {
            basin_id: metadata["sources"][basin_id]["selected_source_lines_sha256"]
        },
        "verified_unchanged_from_start_to_finish": True,
    }

    output = write_contract_package(
        results_root=tmp_path,
        contract_id="signed_contract_v01",
        config=config,
        basin_table=pd.DataFrame([{"gauge_id": basin_id}]),
        basin_contracts={basin_id: basin_contract},
        input_audits={basin_id: input_audit},
        resource_history=[],
        interaction_audit={"selected_mode": "full", "uses_evaluation_discharge": False},
        source_files=source_files,
        input_files=input_files,
        repo_root=REPO_ROOT,
        execution_signature=signature,
    )

    assert verify_contract_package(output)["status"] == "verified"


def test_result_package_saves_raw_arrays_and_recomputes_every_metric(tmp_path, monkeypatch):
    _stub_frozen_input_recalculation(monkeypatch)
    contract = write_contract_package(
        results_root=tmp_path / "contracts",
        contract_id="contract_v03",
        config=_diverse_config(),
        basin_table=pd.DataFrame([{"gauge_id": "00000001"}]),
        basin_contracts={"00000001": _diverse_basin_contract()},
        input_audits={
            "00000001": {
                "basin_id": "00000001",
                "passed": True,
                "evaluation_discharge_values_parsed": False,
            }
        },
        resource_history=[],
        interaction_audit={"selected_mode": "full", "uses_evaluation_discharge": False},
        source_files=[],
        input_files=[],
        repo_root=REPO_ROOT,
    )
    observations = np.linspace(0.1, 1.0, 10)
    origins = np.arange(3)
    leads = np.array([1, 3, 7])
    targets = origins[:, None] + leads[None, :]
    methods = {}
    expected_ids = {
        "open_loop": ("trained_center_open_loop",),
        "fixed_filter": ("trained_center__process_1",),
        "parameter_only": (
            "equifinal_diverse_1__process_1",
            "trained_center__process_1",
            "equifinal_diverse_2__process_1",
        ),
        "noise_only": (
            "trained_center__process_0",
            "trained_center__process_1",
            "trained_center__process_2",
        ),
        "joint": tuple(
            f"{parameter_id}__process_{process_index}"
            for parameter_id in ("equifinal_diverse_1", "trained_center", "equifinal_diverse_2")
            for process_index in range(3)
        ),
    }
    for method_index, method in enumerate(METHOD_ORDER):
        candidate_count = {"open_loop": 1, "fixed_filter": 1, "parameter_only": 3, "noise_only": 3, "joint": 9}[
            method
        ]
        predictions = observations[targets] + 0.01 * (method_index + 1)
        candidate_predictions = np.repeat(predictions[:, :, None], candidate_count, axis=2)
        probabilities = np.full(candidate_predictions.shape, 1.0 / candidate_count)
        candidate_covariance = None
        combined_covariance = None
        if method != "open_loop":
            candidate_covariance = np.ones((*predictions.shape, candidate_count, 15), dtype=np.float64)
            combined_covariance = np.ones((*predictions.shape, 15), dtype=np.float64)
        methods[method] = MethodRunResult(
            lead_days=leads,
            origin_indices=origins,
            target_indices=targets,
            predictions=predictions,
            target_observations=observations[targets],
            candidate_ids=expected_ids[method],
            candidate_predictions=candidate_predictions,
            probabilities=probabilities,
            candidate_covariance_diagonals=candidate_covariance,
            combined_covariance_diagonals=combined_covariance,
        )
    writer = ResultPackageWriter(
        results_root=tmp_path / "results",
        experiment_id="result_v01",
        contract_directory=contract,
        config={"lead_days": [1, 3, 7]},
    )
    writer.write_basin(
        BasinEvaluation(
            basin_id="00000001",
            dates=pd.date_range("1989-10-01", periods=10).strftime("%Y-%m-%d").to_numpy(),
            observations=observations,
            methods=methods,
        )
    )
    output = writer.finalize(resource_history=[], source_files=[], repo_root=REPO_ROOT)

    assert verify_result_package(output) == {
        "status": "verified",
        "experiment_id": "result_v01",
        "basin_count": 1,
        "method_count": 5,
        "lead_days": [1, 3, 7],
        "contract_id": "contract_v03",
    }
    contract_reference = json.loads(
        (output / "contract_reference.json").read_text(encoding="utf-8")
    )
    assert not Path(contract_reference["contract_directory"]).is_absolute()
    assert len(pd.read_csv(output / "metrics.csv")) == 15
    for name in (
        "paired_method_comparisons.csv",
        "candidate_probability_summary.csv",
        "joint_factor_probability_summary.csv",
        "lead_time_effects.png",
        "study_report.md",
    ):
        assert (output / name).is_file()
    for name in (
        "basins.csv",
        "parameter_vectors.csv",
        "parameter_dictionary.csv",
        "process_noise_covariances.csv",
        "observation_noise.csv",
        "input_variables.csv",
        "interaction_audit.json",
        "config_snapshot.json",
    ):
        assert (output / "contract_tables" / name).is_file()
    tampered = tmp_path / "results" / "tampered_result"
    shutil.copytree(output, tampered)
    Image.new("RGB", (1100, 600), color="white").save(tampered / "lead_time_effects.png")
    checksums_path = tampered / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    checksums["lead_time_effects.png"] = sha256_file(tampered / "lead_time_effects.png")
    checksums_path.write_text(json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="lead-time figure"):
        verify_result_package(tampered)
    tampered_report = tmp_path / "results" / "tampered_report"
    shutil.copytree(output, tampered_report)
    (tampered_report / "study_report.md").write_text("错误结论\n", encoding="utf-8")
    checksums_path = tampered_report / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    checksums["study_report.md"] = sha256_file(tampered_report / "study_report.md")
    checksums_path.write_text(json.dumps(checksums, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="study report"):
        verify_result_package(tampered_report)
    failed_result = tmp_path / "results" / "copied_result.failed"
    shutil.copytree(output, failed_result)
    with pytest.raises(ValueError, match="failed"):
        verify_result_package(failed_result)
    rooted_references = (
        str(contract),
        str(contract)[len(contract.drive) :],
        str(contract)[len(contract.drive) :].replace("\\", "/"),
        f"{contract.drive}../../contracts/contract_v03",
    )
    for index, rooted_reference in enumerate(rooted_references):
        rooted_result = tmp_path / "results" / f"rooted_reference_{index}"
        shutil.copytree(output, rooted_result)
        reference_path = rooted_result / "contract_reference.json"
        reference = json.loads(reference_path.read_text(encoding="utf-8"))
        reference["contract_directory"] = rooted_reference
        reference_path.write_text(
            json.dumps(reference, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        rooted_checksums_path = rooted_result / "checksums.json"
        rooted_checksums = json.loads(rooted_checksums_path.read_text(encoding="utf-8"))
        rooted_checksums["contract_reference.json"] = sha256_file(reference_path)
        rooted_checksums_path.write_text(
            json.dumps(rooted_checksums, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        with pytest.raises(ValueError, match="relative path"):
            verify_result_package(rooted_result)
    with pytest.raises(FileExistsError):
        ResultPackageWriter(tmp_path / "results", "result_v01", contract, {})

    bad_count = dict(methods)
    bad_count["parameter_only"] = replace(
        methods["parameter_only"],
        candidate_ids=methods["parameter_only"].candidate_ids[:2],
        candidate_predictions=methods["parameter_only"].candidate_predictions[:, :, :2],
        probabilities=np.full((*methods["parameter_only"].predictions.shape, 2), 0.5),
    )
    bad_writer = ResultPackageWriter(tmp_path / "results", "bad_count_v01", contract, {})
    with pytest.raises(ValueError, match="candidate count"):
        bad_writer.write_basin(
            BasinEvaluation(
                basin_id="00000001",
                dates=pd.date_range("1989-10-01", periods=10).strftime("%Y-%m-%d").to_numpy(),
                observations=observations,
                methods=bad_count,
            )
        )

    negative = dict(methods)
    negative_probabilities = methods["noise_only"].probabilities.copy()
    negative_probabilities[:, :, :] = np.array([-1.0, 2.0, 0.0])
    negative["noise_only"] = replace(methods["noise_only"], probabilities=negative_probabilities)
    negative_writer = ResultPackageWriter(tmp_path / "results", "negative_probability_v01", contract, {})
    with pytest.raises(ValueError, match="nonnegative"):
        negative_writer.write_basin(
            BasinEvaluation(
                basin_id="00000001",
                dates=pd.date_range("1989-10-01", periods=10).strftime("%Y-%m-%d").to_numpy(),
                observations=observations,
                methods=negative,
            )
        )

    mislabeled = dict(methods)
    mislabeled["fixed_filter"] = replace(
        methods["fixed_filter"],
        candidate_ids=("wrong_parameter__wrong_process",),
    )
    mislabeled_writer = ResultPackageWriter(tmp_path / "results", "mislabeled_v01", contract, {})
    with pytest.raises(ValueError, match="do not match the contract"):
        mislabeled_writer.write_basin(
            BasinEvaluation(
                basin_id="00000001",
                dates=pd.date_range("1989-10-01", periods=10).strftime("%Y-%m-%d").to_numpy(),
                observations=observations,
                methods=mislabeled,
            )
        )

    relocated = tmp_path / "relocated_archive"
    relocated.mkdir()
    shutil.move(str(tmp_path / "contracts"), str(relocated / "contracts"))
    shutil.move(str(tmp_path / "results"), str(relocated / "results"))
    relocated_output = relocated / "results" / "result_v01"
    assert verify_result_package(relocated_output)["status"] == "verified"


def test_result_writer_accepts_one_preverified_contract_without_repeating_expensive_verification(
    tmp_path, monkeypatch
):
    _stub_frozen_input_recalculation(monkeypatch)
    contract = write_contract_package(
        results_root=tmp_path / "contracts",
        contract_id="preverified_contract_v01",
        config=_diverse_config(),
        basin_table=pd.DataFrame([{"gauge_id": "00000001"}]),
        basin_contracts={"00000001": _diverse_basin_contract()},
        input_audits={
            "00000001": {
                "basin_id": "00000001",
                "passed": True,
                "evaluation_discharge_values_parsed": False,
            }
        },
        resource_history=[],
        interaction_audit={"selected_mode": "full", "uses_evaluation_discharge": False},
        source_files=[],
        input_files=[],
        repo_root=REPO_ROOT,
    )
    verified = verify_contract_package(contract)
    monkeypatch.setattr(
        experiment_module,
        "verify_contract_package",
        lambda _path: (_ for _ in ()).throw(AssertionError("unexpected repeated verification")),
    )

    writer = ResultPackageWriter(
        results_root=tmp_path / "results",
        experiment_id="preverified_result_v01",
        contract_directory=contract,
        config={"lead_days": [1, 3, 7]},
        verified_contract=verified,
    )

    assert writer.contract_id == "preverified_contract_v01"
