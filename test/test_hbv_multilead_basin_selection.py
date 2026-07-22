import hashlib
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.basins import (  # noqa: E402
    EXPECTED_FORMAL_BASINS,
    assign_static_strata,
    audit_temperature_pair,
    build_eligible_attribute_table,
    freeze_formal_selection,
    selection_list_sha256,
)
from hbv_multilead_joint_uncertainty.contracts import (  # noqa: E402
    TRAINING_PROJECTION_COLUMNS,
    csv_projection_sha256,
    load_base_config,
)
from hbv_multilead_joint_uncertainty.scripts.freeze_parameter_projection import (  # noqa: E402
    freeze_parameter_projection,
)
import hbv_multilead_joint_uncertainty.basins as basin_module  # noqa: E402


def _synthetic_attributes():
    rows = []
    climates = [
        ("snow", 0.5, 0.3),
        ("humid", 0.8, 0.0),
        ("semihumid", 1.2, 0.0),
        ("arid", 1.8, 0.0),
    ]
    for climate, aridity, snow in climates:
        for response_index, response in enumerate(("storage_infiltration", "fast_response")):
            for size_index, size in enumerate(("small", "large")):
                for replicate in range(2):
                    fast_value = 1.0 + 10.0 * response_index + replicate
                    area = 10.0 + 100.0 * size_index + replicate
                    rows.append(
                        {
                            "gauge_id": f"{len(rows) + 1:08d}",
                            "aridity": aridity,
                            "frac_snow": snow,
                            "slope_mean": fast_value,
                            "clay_frac": fast_value,
                            "high_prec_freq": fast_value,
                            "soil_depth_pelletier": 20.0 - fast_value,
                            "soil_porosity": 1.0 - 0.01 * fast_value,
                            "frac_forest": 1.0 - 0.01 * fast_value,
                            "area_gages2": area,
                            "expected_climate": climate,
                            "expected_response": response,
                            "expected_size": size,
                        }
                    )
    return pd.DataFrame(rows)


def test_static_strata_cross_four_climates_two_response_groups_and_two_area_groups():
    table = assign_static_strata(_synthetic_attributes())

    assert set(table["climate_stratum"]) == {"snow", "humid", "semihumid", "arid"}
    assert set(table["response_stratum"]) == {"storage_infiltration", "fast_response"}
    assert set(table["area_stratum"]) == {"small", "large"}
    assert set(zip(table["climate_stratum"], table["response_stratum"], table["area_stratum"])) == {
        (climate, response, size)
        for climate in ("snow", "humid", "semihumid", "arid")
        for response in ("storage_infiltration", "fast_response")
        for size in ("small", "large")
    }
    assert np.all(table["climate_stratum"] == table["expected_climate"])
    assert np.all(table["response_stratum"] == table["expected_response"])
    assert np.all(table["area_stratum"] == table["expected_size"])


def test_temperature_gate_rejects_the_confirmed_maurer_corruption():
    valid = audit_temperature_pair(
        maurer_tmean=np.array([-5.0, 0.0, 10.0]),
        daymet_tmean=np.array([-4.0, 1.0, 9.0]),
    )
    corrupt = audit_temperature_pair(
        maurer_tmean=np.array([-63.0, -50.0, -31.0]),
        daymet_tmean=np.array([5.0, 10.0, 15.0]),
    )

    assert valid["passed"] is True
    assert corrupt["passed"] is False
    assert "minimum_maurer_temperature" in corrupt["failed_checks"]
    assert "mean_product_bias" in corrupt["failed_checks"]


def test_real_static_candidate_pool_is_complete_and_does_not_read_result_metrics():
    table = build_eligible_attribute_table(REPO_ROOT)

    assert len(table) == 480
    assert not any(column.lower() in {"nse", "rmse", "mae", "kge"} for column in table.columns)
    assert table["area_relative_difference"].max() <= 0.05
    assert table["gauge_id"].is_unique
    assert np.all(np.isfinite(table["response_score"]))


def test_static_selector_never_loads_performance_columns_from_the_trained_table(monkeypatch):
    original = pd.read_csv

    def guarded_read_csv(path, *args, **kwargs):
        if str(path).endswith("trained_parameter_projection_531_v01.csv"):
            columns = set(kwargs.get("usecols") or ())
            assert columns == set(TRAINING_PROJECTION_COLUMNS)
        return original(path, *args, **kwargs)

    monkeypatch.setattr(basin_module.pd, "read_csv", guarded_read_csv)

    assert len(build_eligible_attribute_table(REPO_ROOT)) == 480


def test_training_projection_digest_is_unchanged_when_an_excluded_performance_value_changes(tmp_path):
    header = [*TRAINING_PROJECTION_COLUMNS, "nse"]
    selected = ["00000001", "success", *["1.0"] * (len(TRAINING_PROJECTION_COLUMNS) - 2)]
    first = tmp_path / "first.csv"
    second = tmp_path / "second.csv"
    first.write_text(",".join(header) + "\n" + ",".join([*selected, "0.1"]) + "\n", encoding="utf-8")
    second.write_text(",".join(header) + "\n" + ",".join([*selected, "0.9"]) + "\n", encoding="utf-8")

    assert csv_projection_sha256(first) == csv_projection_sha256(second)


def test_formal_selection_reproduces_the_independently_reviewed_sixteen_basin_list():
    selected = freeze_formal_selection(REPO_ROOT)
    basin_ids = selected["gauge_id"].tolist()

    assert basin_ids == list(EXPECTED_FORMAL_BASINS)
    assert len(selected) == 16
    assert len(set(zip(selected["climate_stratum"], selected["response_stratum"], selected["area_stratum"]))) == 16
    assert set(basin_ids).isdisjoint({"12375900", "09035800", "01580000", "11481200", "08109700", "04015330"})
    assert selection_list_sha256(basin_ids) == "cfc3d7e6f460cafe23c0cab9c370da7f3f48bf7d2ab1f7e7a69dc9a1b08ef0e8"
    assert hashlib.sha256(("\n".join(basin_ids) + "\n").encode("utf-8")).hexdigest() == selection_list_sha256(
        basin_ids
    )

    frozen = pd.read_csv(
        REPO_ROOT / "src/hbv_multilead_joint_uncertainty/configs/formal_sixteen_basins_v01.csv",
        dtype={"gauge_id": str, "huc_02": str},
        float_precision="round_trip",
    )
    for column in ("area_gages2", "aridity", "frac_snow"):
        assert np.array_equal(
            frozen[column].to_numpy(dtype=np.float64),
            selected[column].to_numpy(dtype=np.float64),
        )
    assert frozen["gauge_id"].str.zfill(8).tolist() == basin_ids


def test_parameter_projection_metadata_is_self_contained_in_the_versioned_package():
    config = load_base_config(REPO_ROOT)
    source = config["parameter_source"]

    assert source["metadata_path"] == (
        "src/hbv_multilead_joint_uncertainty/configs/"
        "trained_parameter_projection_531_v01.metadata.json"
    )
    metadata_path = REPO_ROOT / source["metadata_path"]
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    assert hashlib.sha256(metadata_path.read_bytes()).hexdigest() == source["metadata_sha256"]
    assert metadata["artifact_type"] == "frozen_trained_parameter_projection"
    assert metadata["columns"] == list(TRAINING_PROJECTION_COLUMNS)
    assert metadata["performance_columns_included"] is False


def test_parameter_projection_generator_reproduces_both_frozen_files_byte_for_byte(tmp_path):
    source = (
        REPO_ROOT
        / "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/"
        "hbv_lite_cma_FINAL_pt_v1_warmup_local_full.csv"
    )
    source_metadata = source.with_suffix(".metadata.json")
    generated_table = tmp_path / "trained_parameter_projection_531_v01.csv"
    generated_metadata = generated_table.with_suffix(".metadata.json")

    freeze_parameter_projection(source, source_metadata, generated_table)

    frozen_root = REPO_ROOT / "src/hbv_multilead_joint_uncertainty/configs"
    assert generated_table.read_bytes() == (
        frozen_root / "trained_parameter_projection_531_v01.csv"
    ).read_bytes()
    assert generated_metadata.read_bytes() == (
        frozen_root / "trained_parameter_projection_531_v01.metadata.json"
    ).read_bytes()
    with pytest.raises(FileExistsError):
        freeze_parameter_projection(source, source_metadata, generated_table)


def test_formal_selection_refuses_a_forbidden_development_overlap():
    with pytest.raises(ValueError, match="overlap"):
        freeze_formal_selection(REPO_ROOT, additional_development_ids=[EXPECTED_FORMAL_BASINS[0]])
